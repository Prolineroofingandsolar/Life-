import Foundation

// MARK: - Coach Context Builder

/// Turns the app's stored state into the compact summary the coach is sent.
///
/// The rule this file exists to enforce: **read the trusted figures, never
/// recompute them.** Every number here comes from `HealthInsights`,
/// `HealthSync` or the stored models, because those are what the Health tab
/// shows. A second implementation of "how many steps today" that disagreed with
/// the screen next to it would make the coach worse than useless — the user
/// would have no way to tell which of the two was lying.
///
/// It follows that the cleaning the brief asks for happens *before* this runs,
/// not in it: deduplication in `GoogleHealthService`, source selection in
/// `HealthSync`, baselines in `HealthInsights`. This assembles their output.
@MainActor
enum CoachContextBuilder {

    /// What the coach may be told about.
    ///
    /// Task and habit titles are user-written text and can name real people —
    /// "Reply to Mrs Hargreaves about the roof". They're included because the
    /// coach can't recommend a specific task without naming it, but they're a
    /// separate switch from the health figures so that choice stays the user's.
    struct Permissions: Equatable, Sendable {
        var health: Bool = true
        var activity: Bool = true
        var training: Bool = true
        var tasks: Bool = true
        var habits: Bool = true
        /// When false, tasks and habits are counted but never named.
        ///
        /// Defaults to false, matching `CoachSettings.shareTitles`. Two
        /// cautious defaults that disagree are one cautious default and one
        /// trap: any caller taking the default would have started sending the
        /// words while the settings screen showed the switch as off.
        var includeTitles: Bool = false

        /// Categories the user has asked not to be nudged about.
        var mutedCategories: [String] = []

        /// Everything, titles included. Explicit rather than `Permissions()`,
        /// so it stays true to its name if a default changes.
        static let all: Permissions = {
            var permissions = Permissions()
            permissions.includeTitles = true
            return permissions
        }()

        /// The user's settings, expressed as what may be sent.
        ///
        /// One translation, in one place. The alternative — each call site
        /// reading `settings.allowTasks` and remembering to check it — is how a
        /// category ends up being sent by the one path that forgot.
        init(_ settings: CoachSettings) {
            health = settings.allowHealth
            activity = settings.allowActivity
            training = settings.allowTraining
            tasks = settings.allowTasks
            habits = settings.allowHabits
            includeTitles = settings.shareTitles
            mutedCategories = settings.mutedCategories
        }

        init() {}
    }

    /// The most candidates worth sending.
    ///
    /// The coach picks one action, so this is a shortlist, not an inventory.
    /// Sending the whole task list would cost tokens on every request to
    /// transmit items that cannot be chosen.
    private static let maximumCandidates = 5

    /// Exercises worth reporting progress on.
    ///
    /// Six, because the context has a byte ceiling and because nobody asks
    /// "how am I doing on my seventh most-trained lift".
    private static let maximumExercises = 6

    static func build(
        appState: AppState,
        permissions: Permissions = Permissions(),
        now: Date = Date(),
        calendar: Calendar = .current,
        snapshot: HealthSnapshot? = nil
    ) -> CoachContext {
        var warnings: [String] = []

        // One snapshot for every health figure below. Passed in wherever the
        // caller already holds one — the card, the briefing and Ask Coach all
        // render from the same instance, so a figure cannot differ between them
        // because one of them rebuilt half a second later. The fallback builds
        // against the `now` that was passed rather than the wall clock, so a
        // test can pin the moment and get a context and a snapshot describing it.
        let health = snapshot ?? HealthSnapshotBuilder.build(appState: appState, now: now)

        let sleep = permissions.health
            ? sleepSection(health, warnings: &warnings)
            : nil
        let recovery = permissions.health
            ? recoverySection(health, warnings: &warnings)
            : nil
        let activity = permissions.activity
            ? activitySection(health, appState: appState, warnings: &warnings)
            : nil
        let training = permissions.training
            ? trainingSection(appState: appState, permissions: permissions, now: now, calendar: calendar)
            : nil
        let tasks = permissions.tasks
            ? tasksSection(appState: appState, permissions: permissions, now: now, calendar: calendar)
            : nil
        let habits = permissions.habits
            ? habitsSection(appState: appState, permissions: permissions, dayKey: health.dayKey)
            : nil

        if !health.isFresh && health.hasConnectedSource {
            warnings.append(
                "Health data hasn't refreshed recently — \(health.freshnessStatement)."
            )
        }
        if !health.hasConnectedSource {
            warnings.append("No tracker is connected, so there are no health measurements at all.")
        }
        for failure in health.syncFailures {
            warnings.append("\(failure) didn't come through on the last sync.")
        }

        var context = CoachContext(
            generatedAt: now,
            timeOfDay: .from(now, calendar: calendar),
            goals: goals(appState: appState),
            sleep: sleep,
            recovery: recovery,
            activity: activity,
            training: training,
            tasks: tasks,
            habits: habits,
            dataWarnings: warnings,
            mutedCategories: permissions.mutedCategories
        )

        context.dayKey = health.dayKey
        context.timeZoneIdentifier = health.timeZoneIdentifier
        context.dataSource = permissions.health || permissions.activity ? health.source : nil
        context.dataUpdatedAt = permissions.health || permissions.activity ? health.lastSyncedAt : nil
        context.dataIsFresh = health.isFresh
        context.comparisons = comparisons(
            health, appState: appState, permissions: permissions, now: now, calendar: calendar
        )

        // The parts that make this a coach rather than a readout: where the
        // figures have been going over weeks, what the body has been doing, and
        // which parts of their life move together. All gated by the same health
        // permission as the figures they are derived from.
        if permissions.health {
            context.body = bodySection(appState: appState, now: now, calendar: calendar)
            context.trends = trendsSection(appState: appState, now: now, calendar: calendar)
            context.patterns = CoachPatterns.patterns(appState: appState, now: now, calendar: calendar)
        }
        if permissions.activity {
            context.hydration = hydrationSection(appState: appState, now: now, calendar: calendar)
        }

        return context
    }

    // MARK: Body

    /// Weight as movement, never as a bare number.
    ///
    /// One weigh-in invites comment on a figure that swings two kilos with a
    /// salty dinner. The direction over a month is the part worth coaching, and
    /// `readings` is sent so a two-entry "trend" reads as what it is.
    private static func bodySection(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Body? {
        let entries = appState.weightEntries.sorted { $0.date < $1.date }
        guard let latest = entries.last else { return nil }

        func weight(daysAgo days: Int) -> Double? {
            guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
            // The last reading at or before the cutoff, so the comparison is
            // against a real weigh-in rather than an interpolation.
            return entries.last { $0.date <= cutoff }?.valueKg
        }

        let bodyFat = appState.bodyCompEntries
            .sorted { $0.date < $1.date }
            .last?.bodyFatPct

        return CoachContext.Body(
            weightKg: latest.valueKg,
            changeOver30DaysKg: weight(daysAgo: 30).map { latest.valueKg - $0 },
            changeOver90DaysKg: weight(daysAgo: 90).map { latest.valueKg - $0 },
            targetKg: appState.workoutSettings.goalWeightKg,
            bodyFatPercent: bodyFat,
            readings: entries.count,
            // Two readings is a pair of numbers, not a trend, and the model is
            // told which it has.
            state: entries.count >= 3 ? .ready : .insufficientHistory
        )
    }

    // MARK: Hydration

    private static func hydrationSection(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Hydration? {
        let todayKey = DayKey.string(for: now, calendar: calendar)
        let today = appState.careDays[todayKey]?.waterGlasses ?? 0

        var recent: [Int] = []
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DayKey.string(for: day, calendar: calendar)
            guard let glasses = appState.careDays[key]?.waterGlasses, glasses > 0 else { continue }
            recent.append(glasses)
        }

        guard today > 0 || !recent.isEmpty else { return nil }

        return CoachContext.Hydration(
            glassesToday: today,
            // Their own usual, not a number off a poster — "four glasses" means
            // nothing until you know whether they normally drink three or ten.
            typicalGlasses: recent.isEmpty ? nil : recent.reduce(0, +) / recent.count,
            state: recent.count >= 5 ? .ready : .insufficientHistory
        )
    }

    // MARK: Trends

    /// Seven days against twenty-eight, with the direction named.
    ///
    /// Directions rather than raw deltas: the model doesn't have to subtract,
    /// and therefore can't subtract wrongly. "Your sleep has been drifting down
    /// for a few weeks" is a sentence it simply could not produce before,
    /// because it was only ever shown today and yesterday.
    private static func trendsSection(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Trends? {
        func average(_ values: [Int]) -> Int? {
            values.isEmpty ? nil : values.reduce(0, +) / values.count
        }
        func averageDouble(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
        }

        var sleep7: [Int] = [], sleep28: [Int] = []
        var steps7: [Int] = [], steps28: [Int] = []
        var rhr7: [Double] = [], rhr28: [Double] = []
        var bedtimes: [Int] = []
        var days = 0

        for offset in 1...28 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DayKey.string(for: day, calendar: calendar)
            let health = appState.healthDays[key]
            let care = appState.careDays[key]

            if health?.sleepMin != nil || care?.steps ?? 0 > 0 { days += 1 }

            if let minutes = health?.sleepMin, minutes > 0 {
                sleep28.append(minutes)
                if offset <= 7 { sleep7.append(minutes) }
            }
            if let steps = care?.steps, steps > 0 {
                steps28.append(steps)
                if offset <= 7 { steps7.append(steps) }
            }
            if let rate = health?.restingHr, rate > 0 {
                rhr28.append(rate)
                if offset <= 7 { rhr7.append(rate) }
            }
            if let bedtime = health?.bedtime {
                let components = calendar.dateComponents([.hour, .minute], from: bedtime)
                let raw = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                // Midnight-crossing: 23:40 and 00:20 are forty minutes apart,
                // not twenty-three hours, and averaging them naively puts
                // someone's typical bedtime at lunchtime.
                bedtimes.append(raw < 12 * 60 ? raw + 24 * 60 : raw)
            }
        }

        guard days >= 3 else { return nil }

        let weekStart = WeeklyReview.startOfWeek(containing: now, calendar: calendar)
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: weekStart) ?? weekStart
        let recentSessions = appState.completedWorkouts.filter {
            ($0.finishedAt ?? .distantPast) >= fourWeeksAgo
        }

        return CoachContext.Trends(
            sleepMinutes7Day: average(sleep7),
            sleepMinutes28Day: average(sleep28),
            stepsDaily7Day: average(steps7),
            stepsDaily28Day: average(steps28),
            restingHeartRate7Day: averageDouble(rhr7),
            restingHeartRate28Day: averageDouble(rhr28),
            sessionsPerWeek4Week: recentSessions.isEmpty ? nil : recentSessions.count / 4,
            typicalBedtimeMinutes: average(bedtimes).map { $0 % (24 * 60) },
            bedtimeVariationMinutes: spread(bedtimes),
            daysRecorded: days,
            sleepDirection: direction(recent: average(sleep7), baseline: average(sleep28), tolerance: 0.05),
            stepsDirection: direction(recent: average(steps7), baseline: average(steps28), tolerance: 0.08),
            restingHeartRateDirection: direction(
                recent: averageDouble(rhr7).map { Int($0) },
                baseline: averageDouble(rhr28).map { Int($0) },
                tolerance: 0.03
            )
        )
    }

    /// How much a set of figures moves about — consistency, which is most of
    /// sleep quality and is invisible in an average.
    private static func spread(_ values: [Int]) -> Int? {
        guard values.count >= 3 else { return nil }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count)
        return Int(variance.squareRoot().rounded())
    }

    /// Rising, steady or falling — with a tolerance, so ordinary week-to-week
    /// noise isn't reported as a direction.
    private static func direction(
        recent: Int?,
        baseline: Int?,
        tolerance: Double
    ) -> CoachContext.Trends.Direction? {
        guard let recent, let baseline, baseline > 0 else { return nil }
        let change = Double(recent - baseline) / Double(baseline)
        if change > tolerance { return .rising }
        if change < -tolerance { return .falling }
        return .steady
    }

    // MARK: Comparisons

    /// Today against yesterday, this week against last, as a few integers.
    ///
    /// Gated by the same permissions as the figures they compare — a delta is
    /// still the data, just arithmetic away.
    private static func comparisons(
        _ health: HealthSnapshot,
        appState: AppState,
        permissions: Permissions,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Comparisons? {
        var out = CoachContext.Comparisons()

        if permissions.health {
            out.sleepVsYesterdayMinutes = health.sleepChangeSinceYesterdayMinutes
            out.restingHeartRateVsYesterday = health.restingHeartRateChangeSinceYesterday
        }
        if permissions.activity {
            out.stepsVsYesterday = health.stepsChangeSinceYesterday
        }
        if permissions.training {
            let finished = appState.completedWorkouts.compactMap(\.finishedAt)
            if let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
               let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) {
                out.workoutsThisWeek = finished.filter { $0 >= thisWeekStart }.count
                out.workoutsLastWeek = finished.filter { $0 >= lastWeekStart && $0 < thisWeekStart }.count
            }
        }

        return out == CoachContext.Comparisons() ? nil : out
    }

    // MARK: Goals

    /// Life has no goals feature, so these are assembled from the targets the
    /// user has actually set. Nothing is invented: a target that hasn't been
    /// set produces no goal rather than a default one, because "your goal is
    /// 10,000 steps" is a lie if they never chose it.
    private static func goals(appState: AppState) -> [CoachContext.Goal] {
        var out: [CoachContext.Goal] = []
        let care = appState.careSettings
        let healthSettings = appState.healthSettings

        if let goalWeight = appState.workoutSettings.goalWeightKg {
            out.append(.init(
                id: "goal-weight",
                category: "body",
                summary: "Reach a body weight of \(goalWeight.weightDisplay) kg"
            ))
        }

        if care.stepGoal > 0 {
            out.append(.init(
                id: "goal-steps",
                category: "activity",
                summary: "Walk \(care.stepGoal.formatted()) steps a day"
            ))
        }

        out.append(.init(
            id: "goal-sleep",
            category: "sleep",
            summary: "Sleep \(HealthInsights.formatDuration(healthSettings.sleepGoalMinutes)) a night"
        ))

        out.append(.init(
            id: "goal-active-minutes",
            category: "fitness",
            summary: "\(healthSettings.exerciseGoalMinutes) active minutes a day"
        ))

        return out
    }

    // MARK: Sleep

    private static func sleepSection(
        _ health: HealthSnapshot,
        warnings: inout [String]
    ) -> CoachContext.Sleep? {
        let duration = health.sleepMinutes
        guard duration.state.hasValue, let minutes = duration.value else {
            warnings.append(
                health.hasConnectedSource
                    ? "No sleep recorded for last night."
                    : "No sleep recorded — no tracker is connected."
            )
            return nil
        }

        if duration.state == .stale, let day = duration.dayKey {
            warnings.append("The most recent sleep on file is from \(day), not last night.")
        }
        switch duration.confidence {
        case .low:
            warnings.append("Last night's sleep is poorly recorded, so treat the figure as approximate.")
        case .medium where duration.state == .partial:
            warnings.append("Last night's sleep stages are only partly covered.")
        default:
            break
        }

        let vsBaseline = health.sleepVsBaselineMinutes
        if vsBaseline.state == .insufficientHistory {
            warnings.append(
                "Not enough sleep history yet to compare last night against your usual — "
                + "\(vsBaseline.sampleCount) of \(vsBaseline.requiredSamples) nights recorded."
            )
        }

        return CoachContext.Sleep(
            score: health.sleepScore.value,
            durationMinutes: minutes,
            // Formatted once, here, from the same helper the Today screen uses.
            durationText: HealthInsights.formatDuration(minutes),
            vsBaselineMinutes: vsBaseline.value,
            efficiencyPercent: health.sleepEfficiencyPercent.value,
            confidence: duration.confidence.asContextConfidence,
            quality: duration.state.asDataQuality,
            state: duration.state
        )
    }

    // MARK: Recovery

    /// Recovery, whenever a measurement exists.
    ///
    /// The old version returned nil unless a baseline could be computed, and the
    /// warning it emitted in that case said "No recovery data". So the coach
    /// denied readings the Health tab was displaying at that exact moment. A
    /// measurement without a baseline is now sent, marked
    /// `insufficientHistory`, and the sentence that goes with it comes from
    /// `HealthSnapshot.recoveryStatement` so the coach and the screen say the
    /// same thing.
    private static func recoverySection(
        _ health: HealthSnapshot,
        warnings: inout [String]
    ) -> CoachContext.Recovery? {
        let hrv = health.hrvMs
        let rhr = health.restingHeartRate

        guard hrv.state.hasValue || rhr.state.hasValue else {
            warnings.append(health.recoveryStatement)
            return nil
        }

        let readiness = health.readiness
        if readiness.state == .insufficientHistory || readiness.state == .missing {
            warnings.append(health.recoveryStatement)
        }
        if hrv.state == .stale || rhr.state == .stale {
            warnings.append("Recovery figures are not from today.")
        }

        // The section's own state is the weaker of the two readings: advice can
        // be no surer than the shakier half of what it rests on.
        let state = [hrv.state, rhr.state]
            .filter { $0.hasValue }
            .min(by: { rank($0) < rank($1) }) ?? .missing

        let bothInterpretable = hrv.state == .ready && rhr.state == .ready

        return CoachContext.Recovery(
            hrvStatus: status(for: health.hrvBaseline),
            restingHeartRateStatus: status(for: health.restingHeartRateBaseline),
            readinessScore: readiness.value,
            confidence: bothInterpretable ? .high : .medium,
            quality: state.asDataQuality,
            state: state,
            hasHrvMeasurement: hrv.state.hasValue,
            hasRestingHeartRateMeasurement: rhr.state.hasValue,
            baselineNightsRecorded: max(hrv.sampleCount, rhr.sampleCount),
            baselineNightsRequired: HealthSnapshot.baselineSampleRequirement
        )
    }

    /// Orders states worst-first, so "the weaker of the two" has a definition.
    private static func rank(_ state: MetricState) -> Int {
        switch state {
        case .missing:              return 0
        case .stale:                return 1
        case .insufficientHistory:  return 2
        case .partial:              return 3
        case .ready:                return 4
        }
    }

    /// Turns a baseline comparison into a word.
    ///
    /// `isMeaningful` is what stops a 1% wobble being reported as a change —
    /// the brief's "avoid dramatic conclusions from one reading", enforced here
    /// rather than left to the model's judgement.
    private static func status(
        for comparison: BaselineComparison?
    ) -> CoachContext.Recovery.BaselineStatus? {
        guard let comparison else { return nil }
        guard comparison.isMeaningful else { return .normal }
        return comparison.direction == .above ? .aboveBaseline : .belowBaseline
    }

    // MARK: Activity

    private static func activitySection(
        _ health: HealthSnapshot,
        appState: AppState,
        warnings: inout [String]
    ) -> CoachContext.Activity? {
        let steps = health.steps

        if !steps.state.hasValue {
            warnings.append(
                health.hasConnectedSource
                    ? "No steps recorded today yet — the tracker may not have synced."
                    : "No steps recorded — no tracker is connected."
            )
        }

        return CoachContext.Activity(
            steps: steps.value,
            stepGoal: appState.careSettings.stepGoal > 0 ? appState.careSettings.stepGoal : nil,
            activeMinutes: health.activeMinutes.value,
            activeMinutesGoal: appState.healthSettings.exerciseGoalMinutes,
            // Any figure for today is still accumulating, by definition.
            isPartialDay: true,
            source: health.source,
            quality: steps.state.asDataQuality,
            state: steps.state
        )
    }

    // MARK: Training

    private static func trainingSection(
        appState: AppState,
        permissions: Permissions,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Training? {
        let finished = appState.completedWorkouts
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }

        let planned = appState.plannedSessions.first {
            calendar.isDateInToday($0.date) && !$0.completed
        }

        let lastDaysAgo = finished.first?.finishedAt.flatMap {
            calendar.dateComponents([.day], from: $0, to: now).day
        }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        let thisWeek = finished.filter { session in
            guard let start = weekStart, let finishedAt = session.finishedAt else { return false }
            return finishedAt >= start
        }

        let library = librarySection(appState: appState)

        // Nothing at all to say only when there is *nothing* — no session done,
        // none planned, no routine, and an empty library.
        //
        // The old guard required a finished or planned workout, so a brand-new
        // user asking for their first programme was described to the coach as
        // having no training data whatsoever: not even which muscles the app
        // could build for. That is precisely the moment the training context
        // matters most.
        let hasAnything = planned != nil
            || !finished.isEmpty
            || !appState.routines.isEmpty
            || library != nil
        guard hasAnything else { return nil }

        return CoachContext.Training(
            plannedWorkout: planned?.routineName,
            routines: appState.routines.prefix(maximumCandidates).map {
                CoachContext.Named(id: $0.id, name: $0.name)
            },
            lastWorkoutDaysAgo: lastDaysAgo,
            recentLoad: load(sessionsThisWeek: thisWeek.count),
            sessionsThisWeek: thisWeek.count,
            library: library,
            recovery: recoverySection(appState: appState),
            trainingReadiness: finished.isEmpty
                ? nil
                : MuscleRecoveryEngine.readiness(from: MuscleRecoveryEngine.statuses(appState: appState)),
            topExercises: exerciseProgress(
                appState: appState,
                permissions: permissions,
                now: now,
                calendar: calendar
            )
        )
    }

    /// Fatigue per muscle, in the blueprint's vocabulary.
    ///
    /// The map works in finer-grained groups — lats, traps and lower back are
    /// three regions of one `Back`. They are folded together on the *worst*
    /// fatigue rather than the average, because a session that hammered the lats
    /// and left the traps alone has still left the back needing a day. Weekly
    /// sets are taken once per muscle, never summed, since all three groups read
    /// the same underlying figure and adding them would treble it.
    private static func recoverySection(appState: AppState) -> [CoachContext.Training.MuscleRecovery] {
        var byMuscle: [BlueprintMuscle: CoachContext.Training.MuscleRecovery] = [:]

        for status in MuscleRecoveryEngine.statuses(appState: appState) {
            guard let muscle = status.blueprintMuscle else { continue }
            let entry = CoachContext.Training.MuscleRecovery(
                muscle: muscle.rawValue,
                fatigue: status.fatigue,
                band: status.band.rawValue,
                setsThisWeek: status.weeklySets,
                weeklyTargetMin: status.weeklyTarget.lowerBound,
                weeklyTargetMax: status.weeklyTarget.upperBound,
                hasHistory: status.hasTrainingHistory
            )
            if let existing = byMuscle[muscle], existing.fatigue >= entry.fatigue {
                // Keep the worst, but never lose the fact that some part of this
                // muscle has been trained.
                if entry.hasHistory { byMuscle[muscle]?.hasHistory = true }
                continue
            }
            byMuscle[muscle] = entry
        }

        return byMuscle.values.sorted { $0.muscle < $1.muscle }
    }

    /// The exercises with enough history to say anything about.
    ///
    /// Ranked by how much they have actually been done, not by weight — the
    /// question this answers is "am I progressing", and the lift someone does
    /// once a month is the one they know least about anyway.
    private static func exerciseProgress(
        appState: AppState,
        permissions: Permissions,
        now: Date,
        calendar: Calendar
    ) -> [CoachContext.Training.ExerciseProgress] {
        /// Below this, a change is noise: two sessions can differ by a warm-up
        /// that was marked as working, or by a day's sleep.
        let minimumSessions = 3

        struct Entry {
            var sessions: Int = 0
            /// Heaviest working set per session, most recent first.
            var recent: [(date: Date, weight: Double)] = []
        }

        var entries: [String: Entry] = [:]

        for session in appState.completedWorkouts {
            guard let finishedAt = session.finishedAt else { continue }
            for exercise in session.exercises {
                let working = exercise.sets
                    .filter { $0.done && !$0.isWarmup && $0.weight > 0 }
                    .map(\.weight)
                guard let heaviest = working.max() else { continue }
                var entry = entries[exercise.exerciseId] ?? Entry()
                entry.sessions += 1
                entry.recent.append((date: finishedAt, weight: heaviest))
                entries[exercise.exerciseId] = entry
            }
        }

        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now

        let ranked = entries
            .sorted { lhs, rhs in
                if lhs.value.sessions != rhs.value.sessions {
                    return lhs.value.sessions > rhs.value.sessions
                }
                // A stable tie-break, so the same data produces the same context
                // and the cache isn't defeated by dictionary ordering.
                return lhs.key < rhs.key
            }
            .prefix(maximumExercises)

        var progress: [CoachContext.Training.ExerciseProgress] = []
        for (id, entry) in ranked {
            let sorted = entry.recent.sorted { $0.date > $1.date }
            let latest = sorted.first?.weight
            // The last figure at or before four weeks ago, so the comparison is
            // against a session that happened rather than an interpolation.
            let baseline = sorted.first { $0.date <= fourWeeksAgo }?.weight

            var change: Double?
            if let latest, let baseline { change = latest - baseline }

            var name: String?
            if permissions.includeTitles {
                name = appState.exercises.first { $0.id == id }?.name
            }

            progress.append(
                CoachContext.Training.ExerciseProgress(
                    exerciseId: id,
                    name: name,
                    recentWorkingWeightKg: latest,
                    changeOverFourWeeksKg: change,
                    sessionsRecorded: entry.sessions,
                    state: entry.sessions >= minimumSessions ? .ready : .insufficientHistory
                )
            )
        }
        return progress
    }

    /// What the library can build, counted rather than listed.
    ///
    /// Muscle names are normalised through `BlueprintMuscle` so the counts use
    /// the same ten words as the response schema. `Exercise.muscle` is a free
    /// `String` — a custom exercise can carry anything — and a count filed under
    /// "Upper back" would tell the coach a muscle exists that it cannot then ask
    /// for. Unrecognised muscles are counted in the total and nowhere else.
    private static func librarySection(appState: AppState) -> CoachContext.Training.Library? {
        let exercises = appState.exercises
        guard !exercises.isEmpty else { return nil }

        var byMuscle: [String: Int] = [:]
        var equipment = Set<String>()
        var custom = 0

        for exercise in exercises {
            if let muscle = BlueprintMuscle(appMuscle: exercise.muscle) {
                byMuscle[muscle.rawValue, default: 0] += 1
            }
            equipment.insert(exercise.equipment.rawValue)
            if exercise.isCustom { custom += 1 }
        }

        return CoachContext.Training.Library(
            exercisesByMuscle: byMuscle,
            equipment: equipment.sorted(),
            totalExercises: exercises.count,
            customExercises: custom
        )
    }

    /// Load by session count rather than volume.
    ///
    /// Volume in kilograms isn't comparable across a leg day and an arm day, so
    /// totalling it and calling the result "heavy" would say more about which
    /// muscles were trained than about how hard the week was.
    private static func load(sessionsThisWeek: Int) -> CoachContext.Training.Load {
        switch sessionsThisWeek {
        case ...1: return .light
        case 2...3: return .moderate
        default:   return .heavy
        }
    }

    // MARK: Tasks

    private static func tasksSection(
        appState: AppState,
        permissions: Permissions,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Tasks? {
        let outstanding = appState.tasks.filter { !$0.done }
        guard !outstanding.isEmpty else {
            return CoachContext.Tasks(
                lists: taskLists(appState: appState, permissions: permissions),
                importantRemaining: 0,
                totalRemainingToday: 0,
                nextDeadline: nil,
                topCandidates: []
            )
        }

        let dueToday = outstanding.filter { task in
            guard let date = task.resolvedDate else { return false }
            return calendar.isDateInToday(date)
        }

        let important = outstanding.filter { $0.priority == .high }

        let nextDeadline = outstanding
            .compactMap(\.resolvedDate)
            .filter { $0 >= calendar.startOfDay(for: now) }
            .min()

        // Ordered the way the app itself would: high priority first, then by
        // due date. The coach picks from the top of a shortlist rather than
        // being handed everything and asked to sort.
        let ranked = outstanding.sorted { a, b in
            if a.priority != b.priority { return a.priority.rank > b.priority.rank }
            switch (a.resolvedDate, b.resolvedDate) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return false
            }
        }

        let candidates = ranked.prefix(maximumCandidates).map { task in
            CoachContext.Tasks.Candidate(
                id: task.id,
                title: permissions.includeTitles ? task.title : "A task",
                priority: task.priority.contextLabel,
                estimatedMinutes: task.estimatedMinutes,
                dueToday: task.resolvedDate.map { calendar.isDateInToday($0) } ?? false
            )
        }

        return CoachContext.Tasks(
            lists: taskLists(appState: appState, permissions: permissions),
            importantRemaining: important.count,
            totalRemainingToday: dueToday.count,
            nextDeadline: nextDeadline,
            topCandidates: Array(candidates)
        )
    }

    private static func taskLists(
        appState: AppState, permissions: Permissions
    ) -> [CoachContext.Named] {
        guard permissions.includeTitles else { return [] }
        return appState.taskLists.map { CoachContext.Named(id: $0.id, name: $0.name) }
    }

    // MARK: Habits

    private static func habitsSection(
        appState: AppState,
        permissions: Permissions,
        dayKey todayKey: String
    ) -> CoachContext.Habits? {
        let active = appState.habits.filter { !$0.isArchived }
        guard !active.isEmpty else { return nil }

        // The day key comes from the snapshot rather than being recomputed. A
        // context built either side of midnight would otherwise count habits
        // against one day and sleep against another.
        func isComplete(_ habit: Habit) -> Bool {
            let log = habit.logs.first { $0.dayKey == todayKey }
            let slipped = log?.slipped == true
            if habit.kind == .break { return !slipped }
            return !slipped && (log?.count ?? 0) >= habit.targetCount
        }

        let outstanding = active.filter { !isComplete($0) }

        // A streak is what makes an unfinished habit worth mentioning today
        // rather than tomorrow, so the shortlist is the longest streaks at
        // risk — those are the ones with something to lose.
        let atRisk = outstanding
            .map { (habit: $0, streak: appState.streakFor($0)) }
            .sorted { $0.streak > $1.streak }
            .prefix(maximumCandidates)
            .map { entry in
                CoachContext.Habits.Candidate(
                    id: entry.habit.id,
                    title: permissions.includeTitles ? entry.habit.name : "A habit",
                    streak: entry.streak
                )
            }

        return CoachContext.Habits(
            remaining: outstanding.count,
            completedToday: active.count - outstanding.count,
            atRisk: Array(atRisk),
            // "You missed today" and "you've kept this four times in thirty
            // days" are the same fact about today and completely different
            // advice. Only the second is coaching.
            thirtyDayCompletionPercent: completionRate(active, days: 30),
            longestCurrentStreak: active.map { appState.streakFor($0) }.max()
        )
    }
}

// MARK: - Habit arithmetic

extension CoachContextBuilder {

    /// How much of the last month's habit work actually happened.
    ///
    /// Counted against each habit's own cadence rather than against every
    /// calendar day, so a twice-a-week habit isn't reported as 29% kept.
    static func completionRate(_ habits: [Habit], days: Int, now: Date = Date()) -> Int? {
        guard !habits.isEmpty else { return nil }
        let calendar = Calendar.current

        var expected = 0
        var kept = 0

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DayKey.string(for: day, calendar: calendar)
            let weekday = calendar.component(.weekday, from: day)

            for habit in habits {
                // A habit scheduled for particular weekdays is only owed on
                // those days.
                if !habit.weekdays.isEmpty, !habit.weekdays.contains(weekday) { continue }
                expected += 1
                let done = habit.logs.contains {
                    $0.dayKey == key && !$0.slipped && $0.count >= habit.targetCount
                }
                if done { kept += 1 }
            }
        }

        guard expected > 0 else { return nil }
        return Int((Double(kept) / Double(expected) * 100).rounded())
    }
}

// MARK: - Supporting

/// Bridges the snapshot's vocabulary to the coach's.
///
/// Two enums rather than one because they answer different questions and are
/// consumed by different things — `MetricState` is what the app holds, and
/// `DataQuality` is what the model is told. The mapping lives here, once, so a
/// new state can't reach the wire as an unconsidered default.
extension MetricState {
    var asDataQuality: CoachContext.DataQuality {
        switch self {
        case .missing:             return .missing
        case .stale:               return .suspect
        case .insufficientHistory: return .partial
        case .partial:             return .partial
        case .ready:               return .verified
        }
    }
}

extension DataConfidence {
    var asContextConfidence: CoachContext.Confidence {
        switch self {
        case .low:    return .low
        case .medium: return .medium
        case .high:   return .high
        }
    }
}

private extension TaskPriority {
    /// Ordering weight. `TaskPriority` is a display type, so the ranking lives
    /// here rather than being read off the enum's declaration order.
    var rank: Int {
        switch self {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        case .none:   return 0
        }
    }

    /// The word sent to the coach — lowercase and stable, independent of
    /// whatever the UI happens to call it.
    var contextLabel: String {
        switch self {
        case .high:   return "high"
        case .medium: return "medium"
        case .low:    return "low"
        case .none:   return "none"
        }
    }
}
