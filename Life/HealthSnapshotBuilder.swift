import Foundation

// MARK: - Health Snapshot Builder

/// Assembles the canonical `HealthSnapshot` from stored state.
///
/// The rule this file enforces is the one `CoachContextBuilder` was written to
/// enforce and then only half kept: **read the trusted figures, never recompute
/// them.** Everything here comes from `HealthInsights`, `HealthSync` or the
/// stored models. What it adds is the classification — missing, stale, no
/// baseline yet, partial, ready — which is exactly the part each consumer used
/// to invent for itself, and exactly where they disagreed.
///
/// Built in one place and read by Today, Health, the briefings, the
/// recommendation card and Ask Coach. That is the whole design: a second
/// implementation of "do we have HRV?" is how "No recovery data" came to be
/// printed under a visible HRV reading.
@MainActor
enum HealthSnapshotBuilder {

    /// How far back an overnight reading may be and still describe "now".
    ///
    /// Sleep, HRV and resting heart rate are recorded while asleep and filed
    /// under the morning. Before the first sync of the day the newest reading
    /// is yesterday's, and calling that stale at 7am would flag every morning
    /// as a problem. Two days is the point at which it genuinely is one.
    static let overnightFreshnessDays = 1

    /// Daytime figures are only current for the day they belong to. Yesterday's
    /// step count is not a partial version of today's.
    static let daytimeFreshnessDays = 0

    static func build(
        appState: AppState,
        now: Date = Date(),
        calendar: Calendar = DayKey.calendar
    ) -> HealthSnapshot {

        let todayKey = DayKey.string(for: now, calendar: calendar)
        let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: now)
            .map { DayKey.string(for: $0, calendar: calendar) }

        let settings = appState.healthSettings
        let history = appState.healthHistory
        let source = HealthSync.source(for: settings)

        var snapshot = HealthSnapshot(
            dayKey: todayKey,
            generatedAt: now,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        snapshot.source = source.provider?.detailedName
        snapshot.lastSyncedAt = settings.lastSyncedAt
        snapshot.syncFailures = settings.lastSyncFailures
        snapshot.hasConnectedSource = source != .none

        // MARK: Sleep

        let night = history.last { $0.sleepMin != nil }
        if let night, let minutes = night.sleepMin {
            let freshness = state(
                forDayKey: night.dayKey,
                todayKey: todayKey,
                calendar: calendar,
                allowedDaysBehind: overnightFreshnessDays
            )
            // Stage coverage is the honest measure of whether a night was
            // properly recorded. A band that lost contact for three hours still
            // reports a duration; it just isn't one to be confident about.
            let coverage = night.stageCoverage
            let confidence: DataConfidence
            var quality: MetricState
            switch coverage {
            case .some(let value) where value >= 0.8:
                confidence = .high
                quality = .ready
            case .some(let value) where value >= 0.5:
                confidence = .medium
                quality = .partial
            case .some:
                confidence = .low
                quality = .partial
            case nil:
                // No stage breakdown at all. A total duration is still useful,
                // and is what the Sleep screen shows, so it isn't withheld.
                confidence = .medium
                quality = .partial
            }
            // Staleness outranks completeness: a fully recorded night from
            // Tuesday is still not last night.
            if freshness == .stale { quality = .stale }

            snapshot.sleepMinutes = HealthMetric(
                value: minutes,
                state: quality,
                confidence: confidence,
                dayKey: night.dayKey,
                measuredAt: night.wakeTime ?? DayKey.date(from: night.dayKey, calendar: calendar),
                source: night.sleepSourceDevice ?? snapshot.source
            )

            if let efficiency = night.sleepEfficiency {
                snapshot.sleepEfficiencyPercent = HealthMetric(
                    value: Int((efficiency * 100).rounded()),
                    state: quality,
                    confidence: confidence,
                    dayKey: night.dayKey,
                    source: snapshot.source
                )
            }

            // The user's own recent average, never a population figure. Nil
            // until there are enough nights for an average to mean anything —
            // which is `insufficientHistory`, not missing: the night itself is
            // right there above.
            let baseline = appState.healthBaseline({ $0.sleepMin.map(Double.init) })
            let sleepSamples = samples(history, { $0.sleepMin.map(Double.init) })
            if let baseline {
                snapshot.sleepVsBaselineMinutes = HealthMetric(
                    value: Int((Double(minutes) - baseline).rounded()),
                    state: quality == .stale ? .stale : .ready,
                    confidence: confidence,
                    dayKey: night.dayKey,
                    source: snapshot.source,
                    sampleCount: sleepSamples,
                    requiredSamples: 3
                )
            } else {
                snapshot.sleepVsBaselineMinutes = HealthMetric(
                    value: nil,
                    state: .insufficientHistory,
                    confidence: .low,
                    sampleCount: sleepSamples,
                    requiredSamples: 3
                )
            }
        }

        // Read, don't recompute. This is the same score the Sleep screen shows.
        if let score = HealthInsights.sleepScore(history, settings: settings) {
            snapshot.sleepScore = HealthMetric(
                value: score.value,
                state: snapshot.sleepMinutes.state == .stale ? .stale : .ready,
                confidence: snapshot.sleepMinutes.confidence,
                dayKey: night?.dayKey,
                source: snapshot.source
            )
        } else if snapshot.sleepMinutes.state.hasValue {
            // A duration with no score means the night couldn't be scored —
            // usually too little stage coverage. Say that, rather than letting
            // a consumer read the absence as "you didn't sleep".
            snapshot.sleepScore = HealthMetric(
                value: nil,
                state: .insufficientHistory,
                confidence: .low,
                requiredSamples: HealthSnapshot.baselineSampleRequirement
            )
        }

        // MARK: Recovery

        snapshot.hrvMs = overnightMetric(
            history: history,
            todayKey: todayKey,
            calendar: calendar,
            source: snapshot.source,
            metric: { $0.hrvMs }
        )
        snapshot.restingHeartRate = overnightMetric(
            history: history,
            todayKey: todayKey,
            calendar: calendar,
            source: snapshot.source,
            metric: { $0.restingHr }
        )

        snapshot.hrvBaseline = comparison(
            HealthInsights.trend(history, metric: { $0.hrvMs })
        )
        snapshot.restingHeartRateBaseline = comparison(
            HealthInsights.trend(history, metric: { $0.restingHr })
        )

        // Readiness needs a baseline, not just a reading. When it can't be
        // computed but the readings exist, that is `insufficientHistory` — the
        // distinction that turns "No recovery data" into "Not enough history to
        // assess recovery".
        if let readiness = HealthInsights.readinessScore(history, settings: settings) {
            let stale = snapshot.hrvMs.state == .stale && snapshot.restingHeartRate.state == .stale
            snapshot.readiness = HealthMetric(
                value: readiness.value,
                state: stale ? .stale : .ready,
                confidence: (snapshot.hrvMs.state == .ready && snapshot.restingHeartRate.state == .ready)
                    ? .high : .medium,
                dayKey: todayKey,
                source: snapshot.source,
                sampleCount: max(snapshot.hrvMs.sampleCount, snapshot.restingHeartRate.sampleCount),
                requiredSamples: HealthSnapshot.baselineSampleRequirement
            )
        } else if snapshot.hrvMs.state.hasValue || snapshot.restingHeartRate.state.hasValue {
            snapshot.readiness = HealthMetric(
                value: nil,
                state: .insufficientHistory,
                confidence: .low,
                sampleCount: max(snapshot.hrvMs.sampleCount, snapshot.restingHeartRate.sampleCount),
                requiredSamples: HealthSnapshot.baselineSampleRequirement
            )
        }

        // MARK: Activity

        // `CareDay.steps` is non-optional and defaults to 0, so absence has to
        // be inferred from the record. Zero steps stored is not the same as no
        // steps recorded, and the difference decides whether the right advice is
        // "get moving" or "your tracker hasn't synced".
        let careToday = appState.careDays[todayKey]
        if let care = careToday, care.steps > 0 {
            snapshot.steps = HealthMetric(
                value: care.steps,
                // Today is by definition still accumulating, so a figure below
                // goal isn't a failure at ten in the morning.
                state: .partial,
                confidence: .high,
                dayKey: todayKey,
                measuredAt: settings.lastSyncedAt,
                source: snapshot.source
            )
        }

        let healthToday = appState.healthDays[todayKey]

        if let minutes = healthToday?.exerciseMinutes {
            snapshot.activeMinutes = HealthMetric(
                value: minutes,
                state: .partial,
                confidence: .high,
                dayKey: todayKey,
                measuredAt: settings.lastSyncedAt,
                source: snapshot.source
            )
        }

        // Zero is a real reading for these two — a day with no walking really
        // does have 0 km — so unlike steps, presence of the figure is the test
        // rather than its being above zero.
        if let distance = healthToday?.distanceKm {
            snapshot.distanceKm = HealthMetric(
                value: distance,
                state: .partial,
                confidence: .high,
                dayKey: todayKey,
                measuredAt: settings.lastSyncedAt,
                source: snapshot.source
            )
        }

        if let energy = healthToday?.activeEnergyKcal {
            snapshot.activeEnergyKcal = HealthMetric(
                value: energy,
                state: .partial,
                confidence: .high,
                dayKey: todayKey,
                measuredAt: settings.lastSyncedAt,
                source: snapshot.source
            )
        }

        // MARK: Yesterday comparisons

        if let yesterdayKey {
            // Derived here rather than sent as two nights of raw history: the
            // coach can answer "which figure changed most since yesterday?"
            // from a single number, and a single number is all it needs.
            snapshot.sleepChangeSinceYesterdayMinutes = HealthInsights
                .changeFromPrevious(history, metric: { $0.sleepMin.map(Double.init) })
                .map { Int($0.rounded()) }

            if let today = careToday?.steps, today > 0,
               let yesterday = appState.careDays[yesterdayKey]?.steps, yesterday > 0 {
                snapshot.stepsChangeSinceYesterday = today - yesterday
            }

            snapshot.restingHeartRateChangeSinceYesterday = HealthInsights.changeFromPrevious(
                history, metric: { $0.restingHr }
            )
        }

        return snapshot
    }

    // MARK: Helpers

    /// The newest reading of an overnight metric, classified.
    ///
    /// The three outcomes are the point. A reading with a baseline is `.ready`;
    /// a reading without one is `.insufficientHistory` and still carries its
    /// value; no reading at all is `.missing`. Folding the middle case into
    /// either of the outer two is what produced contradictory screens.
    private static func overnightMetric(
        history: [HealthDay],
        todayKey: String,
        calendar: Calendar,
        source: String?,
        metric: (HealthDay) -> Double?
    ) -> HealthMetric<Double> {
        guard let day = history.last(where: { metric($0) != nil }),
              let value = metric(day) else {
            return .missing
        }

        let sampleCount = samples(history, metric)
        let hasBaseline = HealthInsights.trend(history, metric: metric) != nil
        let freshness = state(
            forDayKey: day.dayKey,
            todayKey: todayKey,
            calendar: calendar,
            allowedDaysBehind: overnightFreshnessDays
        )

        let resolved: MetricState
        if freshness == .stale {
            resolved = .stale
        } else if hasBaseline {
            resolved = .ready
        } else {
            resolved = .insufficientHistory
        }

        return HealthMetric(
            value: value,
            state: resolved,
            confidence: hasBaseline ? .high : .medium,
            dayKey: day.dayKey,
            measuredAt: DayKey.date(from: day.dayKey, calendar: calendar),
            source: source,
            sampleCount: sampleCount,
            requiredSamples: HealthSnapshot.baselineSampleRequirement
        )
    }

    /// Whether a reading filed under `dayKey` still describes now.
    ///
    /// Returns `.stale` or `.ready` only — the caller decides what a fresh
    /// reading's real state is, since freshness and completeness are different
    /// questions and a reading can fail either.
    static func state(
        forDayKey dayKey: String,
        todayKey: String,
        calendar: Calendar,
        allowedDaysBehind: Int
    ) -> MetricState {
        guard let readingDay = DayKey.date(from: dayKey, calendar: calendar),
              let today = DayKey.date(from: todayKey, calendar: calendar),
              // Whole calendar days, not elapsed seconds: across a DST change
              // one of these "days" is 23 or 25 hours, and dividing by 86,400
              // rounds a same-day reading into yesterday.
              let daysBehind = calendar.dateComponents([.day], from: readingDay, to: today).day
        else { return .stale }

        return daysBehind <= allowedDaysBehind ? .ready : .stale
    }

    /// How many readings of a metric exist in the window a baseline is drawn
    /// from. Used to say "3 of 10 nights" rather than refusing without saying
    /// why.
    private static func samples(_ history: [HealthDay], _ metric: (HealthDay) -> Double?) -> Int {
        history.compactMap { metric($0) }.suffix(30).count
    }

    private static func comparison(_ trend: HealthInsights.Trend?) -> BaselineComparison? {
        guard let trend else { return nil }
        let direction: BaselineDirection
        if !trend.isMeaningful {
            direction = .normal
        } else {
            direction = trend.delta > 0 ? .above : .below
        }
        return BaselineComparison(
            direction: direction,
            deltaPercent: trend.deltaPercent,
            isMeaningful: trend.isMeaningful
        )
    }
}
