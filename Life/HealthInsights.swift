import Foundation
import SwiftUI

// MARK: - Shared Range

/// Time window for the Health charts. Mirrors `WeightTab.ChartRange` in
/// `BodyView`, which stays private to that file.
enum HealthRange: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "1M"
    case threeMonth = "3M"
    case all = "All"

    var id: String { rawValue }

    /// Nil means "everything on file".
    var days: Int? {
        switch self {
        case .week:       return 7
        case .month:      return 30
        case .threeMonth: return 90
        case .all:        return nil
        }
    }

    var label: String {
        switch self {
        case .week:       return "last 7 days"
        case .month:      return "last 30 days"
        case .threeMonth: return "last 90 days"
        case .all:        return "all time"
        }
    }
}

// MARK: - Recovery Metrics

/// The overnight measurements. All of these live on `HealthDay` and are read
/// straight out of Apple Health.
enum RecoveryMetric: String, CaseIterable, Identifiable {
    case restingHr = "Resting HR"
    case hrv = "HRV"
    case breathing = "Breathing"
    case spo2 = "SpO₂"
    case wristTemp = "Wrist Temp"
    case vo2Max = "VO₂ Max"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .restingHr: return "bpm"
        case .hrv:       return "ms"
        case .breathing: return "br/min"
        case .spo2:      return "%"
        case .wristTemp: return "°C"
        case .vo2Max:    return "ml/kg·min"
        }
    }

    var icon: String {
        switch self {
        case .restingHr: return "heart.fill"
        case .hrv:       return "waveform.path.ecg"
        case .breathing: return "lungs.fill"
        case .spo2:      return "drop.fill"
        case .wristTemp: return "thermometer.medium"
        case .vo2Max:    return "figure.run"
        }
    }

    var colour: Color {
        switch self {
        case .restingHr: return .pink
        case .hrv:       return AppTheme.primary
        case .breathing: return .teal
        case .spo2:      return .cyan
        case .wristTemp: return .orange
        case .vo2Max:    return .green
        }
    }

    func value(from day: HealthDay) -> Double? {
        switch self {
        case .restingHr: return day.restingHr
        case .hrv:       return day.hrvMs
        case .breathing: return day.respiratoryRate
        case .spo2:      return day.spo2Pct
        case .wristTemp: return day.wristTempC
        case .vo2Max:    return day.vo2Max
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .restingHr, .hrv: return String(format: "%.0f", value)
        default:               return String(format: "%.1f", value)
        }
    }

    /// For most of these a rise is worse (resting HR climbing, temperature up).
    /// HRV, SpO2 and VO2 max are the other way round. Used to colour trends, so
    /// "up" isn't blindly shown as good.
    var higherIsBetter: Bool {
        switch self {
        case .hrv, .spo2, .vo2Max: return true
        default:                   return false
        }
    }

    /// Charts start at zero only where zero is meaningful. A resting-heart-rate
    /// axis running from 0 flattens the variation that matters.
    var includesZero: Bool { false }
}

// MARK: - Activity Metrics

/// One day of activity. Steps live on `CareDay` (they drive Today's Move ring)
/// while the rest live on `HealthDay`, so the Activity tab stitches the two
/// together into this.
struct ActivityDay: Identifiable {
    let dayKey: String
    var steps: Int? = nil
    var activeEnergyKcal: Double? = nil
    var exerciseMinutes: Int? = nil
    var distanceKm: Double? = nil
    var flights: Int? = nil

    var id: String { dayKey }
    var date: Date? { _dayKeyFormatter.date(from: dayKey) }
}

enum ActivityMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case energy = "Energy"
    case exercise = "Active Min"
    case distance = "Distance"
    case flights = "Floors"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .steps:    return "steps"
        case .energy:   return "kcal"
        case .exercise: return "min"
        case .distance: return "km"
        case .flights:  return "floors"
        }
    }

    var icon: String {
        switch self {
        case .steps:    return "figure.walk"
        case .energy:   return "flame.fill"
        case .exercise: return "timer"
        case .distance: return "location.fill"
        case .flights:  return "stairs"
        }
    }

    var colour: Color {
        switch self {
        case .steps:    return AppTheme.primary
        case .energy:   return .orange
        case .exercise: return .green
        case .distance: return .blue
        case .flights:  return .purple
        }
    }

    func value(from day: ActivityDay) -> Double? {
        switch self {
        case .steps:    return day.steps.map(Double.init)
        case .energy:   return day.activeEnergyKcal
        case .exercise: return day.exerciseMinutes.map(Double.init)
        case .distance: return day.distanceKm
        case .flights:  return day.flights.map(Double.init)
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .steps, .energy, .flights: return Int(value.rounded()).formatted()
        case .exercise:                 return String(format: "%.0f", value)
        case .distance:                 return String(format: "%.1f", value)
        }
    }
}

// MARK: - Health Insights

/// Derived statistics over health history. Deliberately free of SwiftUI so the
/// arithmetic can be reasoned about (and the type-checker never has to wade
/// through it inside a view body).
///
/// The governing rule throughout: **say nothing rather than something wrong.**
/// Every function returns nil or an empty result below its minimum sample
/// count. A trend computed from three readings is noise dressed up as insight,
/// and health data invites people to act on it.
enum HealthInsights {

    /// Readings needed before a metric is compared against its own baseline.
    /// Roughly a fortnight of nights, allowing for a few the tracker missed.
    static let minimumSamples = 10

    /// A change smaller than this is within normal day-to-day variation and is
    /// not worth remarking on.
    static let meaningfulChangePercent = 5.0

    // MARK: Trend

    struct Trend {
        let current: Double
        let baseline: Double
        let sampleCount: Int

        var delta: Double { current - baseline }

        var deltaPercent: Double {
            guard baseline != 0 else { return 0 }
            return (current - baseline) / baseline * 100
        }

        var isMeaningful: Bool { abs(deltaPercent) >= meaningfulChangePercent }
    }

    /// Latest reading for a metric, and how it compares with the mean of the
    /// preceding `window` days. Nil until there are enough readings.
    ///
    /// The baseline excludes the reading being compared, so a value is never
    /// measured against a mean it is itself part of.
    static func trend(
        _ days: [HealthDay],
        metric: (HealthDay) -> Double?,
        window: Int = 30
    ) -> Trend? {
        let readings = days.compactMap { day -> Double? in metric(day) }
        guard let current = readings.last else { return nil }

        let history = readings.dropLast().suffix(window)
        guard history.count >= minimumSamples else { return nil }

        let baseline = history.reduce(0, +) / Double(history.count)
        return Trend(current: current, baseline: baseline, sampleCount: history.count)
    }

    /// Mean of a metric across the given days, or nil if nothing was recorded.
    static func average(_ days: [HealthDay], metric: (HealthDay) -> Double?) -> Double? {
        let values = days.compactMap { day -> Double? in metric(day) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: Sleep

    /// How much bedtime and wake time wander, in minutes, over the last `lastN`
    /// nights. Consistency is the most actionable thing in sleep data and
    /// nothing else in the app surfaces it.
    ///
    /// Nil until there are enough nights to be worth reporting.
    static func sleepConsistency(
        _ days: [HealthDay],
        lastN: Int = 14
    ) -> (bedtimeSD: Double, wakeSD: Double)? {
        let nights = days.filter { $0.bedtime != nil && $0.wakeTime != nil }.suffix(lastN)
        guard nights.count >= 5 else { return nil }

        // Bedtimes straddle midnight, so minutes-since-midnight would put 23:40
        // and 00:10 thirty minutes apart in reality but 1,410 apart on paper.
        // Measuring from noon instead keeps an evening's bedtimes adjacent.
        let bedtimes = nights.compactMap { $0.bedtime.map { minutesFromNoon($0) } }
        let wakes = nights.compactMap { $0.wakeTime.map { minutesFromMidnight($0) } }

        return (standardDeviation(bedtimes), standardDeviation(wakes))
    }

    /// Consecutive most-recent nights meeting the sleep goal.
    static func sleepGoalStreak(_ days: [HealthDay], goalMinutes: Int) -> Int {
        var streak = 0
        for day in days.reversed() {
            guard let minutes = day.sleepMin else { break }
            guard minutes >= goalMinutes else { break }
            streak += 1
        }
        return streak
    }

    /// Consecutive most-recent nights that fell short of the goal.
    static func sleepShortfallRun(_ days: [HealthDay], goalMinutes: Int) -> Int {
        var run = 0
        for day in days.reversed() {
            guard let minutes = day.sleepMin else { break }
            guard minutes < goalMinutes else { break }
            run += 1
        }
        return run
    }

    /// Mean share of each stage across nights that reported a breakdown, as
    /// fractions of total time asleep.
    static func averageStageSplit(
        _ days: [HealthDay]
    ) -> (deep: Double, rem: Double, light: Double)? {
        let staged = days.filter { $0.deepMin != nil || $0.remMin != nil || $0.lightMin != nil }
        guard !staged.isEmpty else { return nil }

        var deep = 0.0, rem = 0.0, light = 0.0, total = 0.0
        for day in staged {
            let d = Double(day.deepMin ?? 0)
            let r = Double(day.remMin ?? 0)
            let l = Double(day.lightMin ?? 0)
            deep += d; rem += r; light += l; total += d + r + l
        }
        guard total > 0 else { return nil }
        return (deep / total, rem / total, light / total)
    }

    // MARK: Activity

    struct WeekTotal: Identifiable {
        let weekStart: Date
        let total: Double
        var id: Date { weekStart }
    }

    /// Totals per calendar week, oldest first, for the last `weeks` weeks.
    /// Weeks with no readings at all are omitted rather than shown as zero.
    static func weeklyTotals(
        _ days: [ActivityDay],
        metric: ActivityMetric,
        weeks: Int = 8
    ) -> [WeekTotal] {
        let calendar = Calendar.current
        var totals: [Date: Double] = [:]

        for day in days {
            guard let value = metric.value(from: day), let date = day.date else { continue }
            guard let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            totals[week, default: 0] += value
        }

        return totals
            .map { WeekTotal(weekStart: $0.key, total: $0.value) }
            .sorted { $0.weekStart < $1.weekStart }
            .suffix(weeks)
            .map { $0 }
    }

    /// Days in the last week where active minutes met the goal.
    static func exerciseGoalDays(_ days: [ActivityDay], goalMinutes: Int) -> Int {
        days.suffix(7).filter { ($0.exerciseMinutes ?? 0) >= goalMinutes }.count
    }

    // MARK: Callouts

    enum Tone {
        case good, neutral, watch

        var colour: Color {
            switch self {
            case .good:    return .green
            case .neutral: return .secondary
            case .watch:   return .orange
            }
        }
    }

    struct Callout: Identifiable {
        let id: String
        let text: String
        let tone: Tone
        let icon: String
    }

    /// Plain-English observations, most useful first.
    ///
    /// Returns empty rather than padding with weak statements — an empty list
    /// means "nothing worth saying yet", which the UI shows as a note about
    /// needing more history.
    static func callouts(
        health: [HealthDay],
        activity: [ActivityDay],
        settings: HealthSettings
    ) -> [Callout] {
        var out: [Callout] = []

        // Recovery drift against personal baselines.
        if let hrv = trend(health, metric: { $0.hrvMs }), hrv.isMeaningful {
            let pct = abs(Int(hrv.deltaPercent.rounded()))
            out.append(hrv.deltaPercent < 0
                ? Callout(id: "hrv-down",
                          text: "HRV is \(pct)% below your 30-day average. Often a sign of fatigue, illness or a late night — worth an easier day.",
                          tone: .watch, icon: "waveform.path.ecg")
                : Callout(id: "hrv-up",
                          text: "HRV is \(pct)% above your 30-day average — a good day to train hard.",
                          tone: .good, icon: "waveform.path.ecg"))
        }

        if let hr = trend(health, metric: { $0.restingHr }), hr.isMeaningful, hr.deltaPercent > 0 {
            let beats = abs(Int(hr.delta.rounded()))
            out.append(Callout(
                id: "rhr-up",
                text: "Resting heart rate is \(beats) bpm above your usual. Common after poor sleep, alcohol or a hard session.",
                tone: .watch, icon: "heart.fill"))
        }

        // Sleep quantity.
        let shortfall = sleepShortfallRun(health, goalMinutes: settings.sleepGoalMinutes)
        let streak = sleepGoalStreak(health, goalMinutes: settings.sleepGoalMinutes)
        if shortfall >= 3 {
            out.append(Callout(
                id: "sleep-short",
                text: "\(shortfall) nights running under your \(formatHours(settings.sleepGoalMinutes)) goal.",
                tone: .watch, icon: "bed.double.fill"))
        } else if streak >= 3 {
            out.append(Callout(
                id: "sleep-streak",
                text: "\(streak) nights running at or above your sleep goal.",
                tone: .good, icon: "bed.double.fill"))
        }

        // Sleep timing.
        if let consistency = sleepConsistency(health), consistency.bedtimeSD >= 60 {
            let swing = Int((consistency.bedtimeSD / 15).rounded() * 15)
            out.append(Callout(
                id: "bedtime-swing",
                text: "Your bedtime swings by about \(swing) minutes night to night. Consistent timing tends to help more than extra hours.",
                tone: .watch, icon: "clock.fill"))
        }

        // Activity — the positive one, so the list isn't all warnings.
        let goalDays = exerciseGoalDays(activity, goalMinutes: settings.exerciseGoalMinutes)
        if goalDays >= 5 {
            out.append(Callout(
                id: "active-week",
                text: "You hit your active-minutes goal on \(goalDays) of the last 7 days.",
                tone: .good, icon: "flame.fill"))
        }

        return out
    }

    // MARK: Scores

    /// A 0–100 score with a word for it.
    ///
    /// These are **Life's own composites, not clinical measures**. Each one is
    /// documented with its formula below so the number can be argued with
    /// rather than taken on faith, and every score returns nil when the inputs
    /// aren't there — a readiness score invented from two nights would be worse
    /// than no score at all.
    struct Score {
        let value: Int
        let label: String
        let tone: Tone
    }

    /// Fitbit's own bands, so a score close to theirs also gets the same word
    /// next to it. Life previously called 85+ "Excellent" where Fitbit starts
    /// that at 80, which guaranteed the labels disagreed even when the numbers
    /// didn't.
    static func describe(_ value: Int) -> (String, Tone) {
        switch value {
        case 90...:   return ("Excellent", .good)
        case 80..<90: return ("Very good", .good)
        case 60..<80: return ("Good", .neutral)
        case 40..<60: return ("Fair", .watch)
        default:      return ("Poor", .watch)
        }
    }

    /// A sleep score and, when it's Life's own, the components behind it.
    ///
    /// `origin` is the important field. A score supplied by the source is passed
    /// through untouched; anything Life computes is an **estimate** and must be
    /// labelled as one everywhere it appears. The two are never averaged,
    /// normalised or blended.
    struct SleepScoreBreakdown {
        enum Origin: Equatable {
            /// Provided by the source and stored verbatim.
            case official(source: String)
            /// Computed by Life from the underlying measurements.
            case estimated
        }

        var origin: Origin = .estimated
        var duration: Double        // out of 50
        var quality: Double         // out of 25
        var restoration: Double     // out of 25
        var total: Int
        var label: String
        var tone: Tone
        /// Device that measured the night, where the source said.
        var device: String? = nil
        /// The night this score is for.
        var dayKey: String = ""
        /// True while restoration is still working from a short or absent
        /// baseline. The score is usable but will move as history builds, and
        /// the UI says so rather than presenting it as settled.
        var isProvisional: Bool = false

        var isEstimate: Bool { origin == .estimated }

        /// What to call it on screen. Never "Google Health Score" or "Fitbit
        /// Sleep Score" unless the source actually gave us that value.
        var title: String {
            switch origin {
            case .official(let source):
                return source.replacingOccurrences(of: "_", with: " ").capitalized + " Sleep Score"
            case .estimated:
                return "Estimated Sleep Score"
            }
        }

        var score: Score { Score(value: total, label: label, tone: tone) }
    }

    /// Sleep quality for a night, 0–100, built to track Fitbit's score.
    ///
    /// Fitbit's number isn't exposed anywhere in the Google Health API — there's
    /// no score field on any sleep schema — so it has to be recomputed from the
    /// same underlying data. This mirrors their published composition:
    ///
    /// - **Duration, 50 points** — how much you slept.
    /// - **Quality, 25 points** — time in deep and REM.
    /// - **Restoration, 25 points** — how relaxed you were: resting heart rate,
    ///   SpO₂ and HRV during sleep, each against your own baseline.
    ///
    /// Calibration matters as much as the shape. Fitbit says most people score
    /// **72–83**, so an ordinary night — around seven hours, ~32% deep+REM,
    /// resting heart rate at baseline — needs to land there rather than in the
    /// nineties. Reaching 90+ should take genuinely excellent sleep. An earlier
    /// version scored a duration hit as full marks and read raw efficiency
    /// (which never leaves an 88–95% band) as a fraction, so almost every night
    /// came out at 99 and the number said nothing.
    ///
    /// It still won't match to the point — Fitbit's weightings aren't published.
    /// If it's consistently out in one direction across a week, the breakdown
    /// shows which term to adjust.
    ///
    /// Where a component's data is missing its weight is redistributed across
    /// the others, rather than penalising a tracker that reports less detail.
    static func sleepScoreBreakdown(
        for night: HealthDay,
        history: [HealthDay],
        settings: HealthSettings
    ) -> SleepScoreBreakdown? {
        // An official score from the source is displayed exactly as given —
        // never recalculated, averaged, normalised or blended with the estimate
        // below. Nothing populates this today; see `HealthDay.officialSleepScore`.
        if let official = night.officialSleepScore {
            let (label, tone) = describe(official)
            return SleepScoreBreakdown(
                origin: .official(source: night.officialSleepScoreSource ?? "Source"),
                duration: 0, quality: 0, restoration: 0,
                total: official, label: label, tone: tone,
                device: night.sleepSourceDevice, dayKey: night.dayKey
            )
        }

        guard let minutes = night.sleepMin, minutes > 0, settings.sleepGoalMinutes > 0 else { return nil }

        // Nights described by too little stage data aren't scored at all. A
        // number derived from an hour of a nine-hour night would look just as
        // confident as a real one. The rule lives in `SleepAnalysis` so the
        // tests exercise the same thresholds the app applies.
        guard SleepAnalysis.isScoreable(night) else { return nil }

        // Duration. Full marks need the goal met; below that it falls away
        // faster than linearly, because the gap between six and seven hours
        // matters more than between eight and nine.
        let ratio = min(1.0, Double(minutes) / Double(settings.sleepGoalMinutes))
        let duration = pow(ratio, 1.3) * 50
        var available = 50.0

        // Quality — deep + REM share. 20% or less earns nothing; full marks need
        // ~44% combined, which is a genuinely strong night for an adult.
        var quality = 0.0
        if let restorative = night.restorativeShare {
            quality = clamp((restorative - 0.20) / 0.24) * 25
            available += 25
        }

        // Restoration — how settled the body was, measured against its own
        // baselines.
        //
        // This term *requires* a baseline-backed cardiac signal. It used to fall
        // back to whatever was available, which produced nonsense: SpO2 alone
        // would score 25/25, because 97% is unremarkable and scored as if it
        // were exceptional. Combined with duration at 50/50 for simply hitting
        // the goal, ordinary nights came out at 98. A term meaning "how
        // recovered were you" cannot be answered by a number that reads the same
        // for everyone every night.
        var parts: [Double] = []
        var samples = 0
        if let hr = night.restingHr,
           let hrBaseline = baseline(history, { $0.restingHr }, minimum: provisionalMinimumSamples) {
            // Sitting at your baseline scores 0.6, not full marks — the top of
            // the scale is reserved for a night better than your normal.
            parts.append(clamp(0.6 - (hr - hrBaseline) / 11))
            samples = max(samples, sampleCount(history) { $0.restingHr })
        }
        if let hrv = night.deepSleepHrvMs ?? night.hrvMs,
           let hrvBaseline = baseline(history, { $0.deepSleepHrvMs ?? $0.hrvMs }, minimum: provisionalMinimumSamples),
           hrvBaseline > 0 {
            parts.append(clamp(0.6 + (hrv - hrvBaseline) / (hrvBaseline * 0.7)))
            samples = max(samples, sampleCount(history) { $0.deepSleepHrvMs ?? $0.hrvMs })
        }

        // With no baseline at all, assume *typical* rather than excellent — the
        // same 0.6 a night sitting exactly on your baseline would earn. Refusing
        // to score leaves the screen blank on day one; scoring it from whatever
        // single signal happens to exist is what produced 98s. Assuming average
        // in the absence of evidence does neither.
        var isProvisional = false
        if parts.isEmpty {
            parts.append(0.6)
            isProvisional = true
        } else if samples < minimumSamples {
            isProvisional = true
        }

        var restoration = (parts.reduce(0, +) / Double(parts.count)) * 25
        available += 25

        // SpO2 only ever subtracts. Desaturation is worth flagging; a normal
        // reading is not an achievement and must not earn points.
        if let spo2 = night.spo2Pct, spo2 < 92 {
            restoration *= clamp(0.5 + (spo2 - 88) / 8)
        }

        let total = Int(((duration + quality + restoration) / available * 100).rounded())
        let (label, tone) = describe(total)
        return SleepScoreBreakdown(
            origin: .estimated,
            duration: duration,
            quality: quality,
            restoration: restoration,
            total: total,
            label: label,
            tone: tone,
            device: night.sleepSourceDevice,
            dayKey: night.dayKey,
            isProvisional: isProvisional
        )
    }

    // MARK: Ranking and comparison
    //
    // These are the honest half of the sleep screen. Every figure below comes
    // straight from measured data with no invented weighting, so unlike the
    // estimated score they can't be "wrong" — only more or less useful.

    /// Where a night sits among recent nights, best first.
    ///
    /// A rank can't disagree with itself the way an absolute score can: if a
    /// night really was poor, it cannot come out near the top, whatever the
    /// formula thinks. Shown next to the score so a misbehaving score is
    /// immediately visible rather than quietly believed.
    static func nightRank(
        for night: HealthDay,
        in history: [HealthDay],
        settings: HealthSettings,
        window: Int = 14
    ) -> (rank: Int, of: Int)? {
        let recent = history.suffix(window).filter { $0.sleepMin != nil }
        guard recent.count >= 3 else { return nil }

        let scored = recent.compactMap { day -> (String, Int)? in
            guard let breakdown = sleepScoreBreakdown(for: day, history: history, settings: settings)
            else { return nil }
            return (day.dayKey, breakdown.total)
        }
        guard scored.count >= 3,
              let mine = scored.first(where: { $0.0 == night.dayKey })?.1 else { return nil }

        let better = scored.filter { $0.1 > mine }.count
        return (better + 1, scored.count)
    }

    /// Mean of a sleep metric across recent nights, for "versus your usual".
    static func recentAverage(
        _ history: [HealthDay],
        window: Int = 14,
        metric: (HealthDay) -> Double?
    ) -> Double? {
        let values = history.suffix(window).compactMap { day -> Double? in metric(day) }
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// "42m more than usual" / "in line with your usual". Nil when there's not
    /// enough history, or the difference is too small to be worth saying.
    static func comparison(
        _ value: Double?,
        against average: Double?,
        formatter: (Double) -> String,
        threshold: Double
    ) -> String? {
        guard let value, let average else { return nil }
        let delta = value - average
        guard abs(delta) >= threshold else { return "in line with your usual" }
        return "\(formatter(abs(delta))) \(delta > 0 ? "more" : "less") than usual"
    }

    /// Convenience for callers that only want the number for the latest night.
    static func sleepScore(_ days: [HealthDay], settings: HealthSettings) -> Score? {
        guard let night = days.last(where: { $0.sleepMin != nil }) else { return nil }
        return sleepScoreBreakdown(for: night, history: days, settings: settings)?.score
    }

    /// Readings needed before a baseline is treated as settled rather than
    /// provisional. Three nights is enough to be better than assuming average,
    /// while `minimumSamples` (ten) is where it stops being marked provisional.
    static let provisionalMinimumSamples = 3

    /// Mean of a metric over recent history, for scoring against. Separate from
    /// `trend` because scoring wants a plain baseline, not a comparison.
    private static func baseline(
        _ days: [HealthDay],
        _ metric: (HealthDay) -> Double?,
        window: Int = 30,
        minimum: Int = minimumSamples
    ) -> Double? {
        let values = days.compactMap { day -> Double? in metric(day) }.suffix(window)
        guard values.count >= minimum else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// How many readings of a metric exist, for deciding whether a baseline is
    /// settled or still provisional.
    private static func sampleCount(_ days: [HealthDay], _ metric: (HealthDay) -> Double?) -> Int {
        days.compactMap { day -> Double? in metric(day) }.suffix(30).count
    }

    /// How ready the body looks for hard work today.
    ///
    /// HRV and resting heart rate measured against their own 30-day baselines,
    /// plus last night's sleep. Nil until both baselines exist — this is the
    /// score most likely to be acted on, so it holds itself to the strictest
    /// data requirement.
    static func readinessScore(_ days: [HealthDay], settings: HealthSettings) -> Score? {
        let hrv = trend(days, metric: { $0.hrvMs })
        let rhr = trend(days, metric: { $0.restingHr })
        guard hrv != nil || rhr != nil else { return nil }

        var total = 0.0
        var weight = 0.0

        // HRV above baseline is good; ±25% spans the full range.
        if let hrv = hrv {
            total += clamp(0.5 + hrv.deltaPercent / 50) * 0.4
            weight += 0.4
        }
        // Resting HR above baseline is bad, so the sign flips. It moves in a
        // much narrower band than HRV, hence ±10%.
        if let rhr = rhr {
            total += clamp(0.5 - rhr.deltaPercent / 20) * 0.3
            weight += 0.3
        }
        if let sleep = sleepScore(days, settings: settings) {
            total += Double(sleep.value) / 100 * 0.3
            weight += 0.3
        }

        guard weight > 0 else { return nil }
        let value = Int((total / weight * 100).rounded())
        let (label, tone) = describe(value)
        return Score(value: value, label: label, tone: tone)
    }

    /// Today's movement against the daily goals.
    static func activityScore(
        _ days: [ActivityDay],
        settings: HealthSettings,
        stepGoal: Int
    ) -> Score? {
        guard let today = days.last else { return nil }

        var total = 0.0
        var weight = 0.0

        if let minutes = today.exerciseMinutes, settings.exerciseGoalMinutes > 0 {
            total += min(1.0, Double(minutes) / Double(settings.exerciseGoalMinutes)) * 0.5
            weight += 0.5
        }
        if let steps = today.steps, stepGoal > 0 {
            total += min(1.0, Double(steps) / Double(stepGoal)) * 0.3
            weight += 0.3
        }
        if let energy = today.activeEnergyKcal {
            let recent = days.dropLast().suffix(14).compactMap(\.activeEnergyKcal)
            if !recent.isEmpty {
                let average = recent.reduce(0, +) / Double(recent.count)
                if average > 0 {
                    total += min(1.0, energy / average) * 0.2
                    weight += 0.2
                }
            }
        }

        guard weight > 0 else { return nil }
        let value = Int((total / weight * 100).rounded())
        let (label, tone) = describe(value)
        return Score(value: value, label: label, tone: tone)
    }

    /// Exertion for today on a 0–10 scale.
    ///
    /// Note this is **not** WHOOP-style strain: that's built from continuous
    /// heart-rate data, which Life doesn't collect. This is active energy and
    /// exercise minutes measured against your own recent ceiling — a reasonable
    /// proxy for how hard a day has been, and honest about being one.
    static func exertion(_ days: [ActivityDay]) -> Double? {
        guard let today = days.last else { return nil }
        let history = days.dropLast().suffix(30)
        guard history.count >= 5 else { return nil }

        let energies = history.compactMap(\.activeEnergyKcal)
        guard let peak = energies.max(), peak > 0,
              let energy = today.activeEnergyKcal else { return nil }

        let energyShare = min(1.0, energy / peak)
        let minutes = Double(today.exerciseMinutes ?? 0)
        let minuteShare = min(1.0, minutes / 90)

        return ((energyShare * 0.7 + minuteShare * 0.3) * 10 * 10).rounded() / 10
    }

    static func exertionLabel(_ value: Double) -> (String, Tone) {
        switch value {
        case ..<4:   return ("Low", .neutral)
        case 4..<7:  return ("Moderate", .good)
        default:     return ("High", .watch)
        }
    }

    // MARK: Guidance

    struct Guidance {
        let headline: String
        let detail: String
        let tone: Tone
    }

    /// The one-line training steer on the overview. Deliberately hedged where
    /// the data is thin — it says what it saw, not what you should do with your
    /// body.
    static func guidance(
        readiness: Score?,
        health: [HealthDay],
        settings: HealthSettings
    ) -> Guidance {
        guard let readiness = readiness else {
            return Guidance(
                headline: "Still learning your baseline",
                detail: "Wear your tracker for about two weeks and readiness guidance will appear here.",
                tone: .neutral)
        }

        let shortfall = sleepShortfallRun(health, goalMinutes: settings.sleepGoalMinutes)
        if shortfall >= 3 {
            return Guidance(
                headline: "Prioritise sleep today",
                detail: "\(shortfall) nights running under your goal — recovery lags behind sleep debt.",
                tone: .watch)
        }

        switch readiness.value {
        case 75...:
            return Guidance(headline: "Good day to push",
                            detail: "Recovery is above your 30-day average.",
                            tone: .good)
        case 55..<75:
            return Guidance(headline: "Good day for moderate training",
                            detail: "Recovery is around your usual level.",
                            tone: .good)
        case 40..<55:
            return Guidance(headline: "Keep it light",
                            detail: "Recovery is below your 30-day average.",
                            tone: .neutral)
        default:
            return Guidance(headline: "Rest or go easy",
                            detail: "Recovery is well below your usual — often illness, poor sleep or accumulated fatigue.",
                            tone: .watch)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    // MARK: Day-over-day

    /// Change from the previous recorded day, for the "vs yesterday" figures.
    /// Compares the two most recent days that both have the metric, so a day
    /// the tracker missed doesn't blank the comparison.
    static func changeFromPrevious(
        _ days: [HealthDay],
        metric: (HealthDay) -> Double?
    ) -> Double? {
        let values = days.compactMap { day -> Double? in metric(day) }
        guard values.count >= 2 else { return nil }
        return values[values.count - 1] - values[values.count - 2]
    }

    // MARK: Formatting

    /// "7h 30m", or "8h" on the hour.
    static func formatDuration(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static func formatHours(_ minutes: Int) -> String { formatDuration(minutes) }

    // MARK: Private

    private static func minutesFromMidnight(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Minutes since noon, wrapping. Puts late-evening and after-midnight
    /// bedtimes next to each other on the same scale.
    private static func minutesFromNoon(_ date: Date) -> Double {
        (minutesFromMidnight(date) + 720).truncatingRemainder(dividingBy: 1440)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
