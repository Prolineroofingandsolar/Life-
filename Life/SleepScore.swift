import Foundation

// MARK: - Sleep Score

/// Life's estimated sleep score.
///
/// **This is not Google's or Fitbit's Sleep Score and does not claim to be.**
/// Google doesn't publish its complete formula and doesn't expose its private
/// movement, heart-rate-stability and personalisation inputs — verified against
/// the v4 discovery document, which carries no score field on any sleep type.
/// If a source ever supplies an official score it is displayed unchanged; this
/// model is only ever used in its absence.
///
/// The score is a 0–100 figure, **not a percentage**. It is never rendered with
/// a percent sign.
enum SleepScore {

    // MARK: Categories

    enum Category: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"

        init(score: Int) {
            switch score {
            case 90...:   self = .excellent
            case 80..<90: self = .good
            case 60..<80: self = .fair
            default:      self = .poor
            }
        }
    }

    enum Confidence: String {
        case high, medium, low
    }

    // MARK: Result

    struct Components: Equatable {
        var duration: Double = 0
        var continuity: Double = 0
        var restorative: Double = 0
        var latency: Double = 0
        var consistency: Double = 0
    }

    /// A scored night, with everything needed to explain and debug it.
    struct Result: Equatable {
        var score: Int
        var category: Category
        var components: Components
        var confidence: Confidence
        var weightedScoreBeforeCeilings: Double
        /// Human-readable ceilings that were applicable, for diagnostics.
        var appliedCeilings: [String]
        var missingFields: [String]

        var isEstimate: Bool { true }
        var title: String { "Estimated Sleep Score" }
    }

    /// The measurements a night must supply to be scored. Deliberately a plain
    /// value type rather than `HealthDay`, so the model can be tested without
    /// any of the app's storage.
    struct Night {
        var minutesAsleep: Int
        var timeInBed: Int
        var lightMinutes: Int?
        var deepMinutes: Int?
        var remMinutes: Int?
        var genericSleepMinutes: Int = 0
        var fullAwakeningCount: Int = 0
        var interruptionMinutes: Int = 0
        var restlessMinutes: Int = 0
        var sleepLatencyMinutes: Int?
        /// Clock minutes past midnight.
        var bedtimeClockMinutes: Double?
        var wakeClockMinutes: Double?
        var heartRateAvailable: Bool = false
        var movementAvailable: Bool = false

        var sleepEfficiency: Double? {
            guard timeInBed > 0 else { return nil }
            return min(1, Double(minutesAsleep) / Double(timeInBed))
        }

        /// Stage detail is required. Without it there is no score at all.
        var hasStages: Bool { deepMinutes != nil || remMinutes != nil }
    }

    /// The 14-day rolling baseline the consistency component scores against.
    struct Baseline {
        var medianBedtimeClockMinutes: Double?
        var medianWakeClockMinutes: Double?
        var validNights: Int = 0

        /// Fewer than seven nights isn't a baseline worth scoring against.
        var isSufficient: Bool {
            validNights >= 7 && medianBedtimeClockMinutes != nil && medianWakeClockMinutes != nil
        }
    }

    // MARK: Constants

    /// Substituted for any component whose inputs are missing. Deliberately
    /// neutral: missing data must never be scored as perfect, and must never
    /// raise the score.
    static let neutralComponentValue: Double = 70

    // MARK: Entry point

    /// Scores a night, or returns nil when there isn't enough data to try.
    ///
    /// Returns nil only when sleep stages are unavailable — every other gap is
    /// handled with a neutral component and a confidence downgrade.
    static func calculate(night: Night, baseline: Baseline) -> Result? {
        guard night.hasStages, night.minutesAsleep > 0 else { return nil }

        var missing: [String] = []

        let duration = durationScore(minutesAsleep: night.minutesAsleep)
        let continuity = continuityScore(night: night)

        guard let restorative = restorativeScore(night: night) else { return nil }

        let latency: Double
        if let latencyMinutes = night.sleepLatencyMinutes {
            latency = latencyScore(minutes: Double(latencyMinutes))
        } else {
            latency = neutralComponentValue
            missing.append("latency")
        }

        let consistency: Double
        if baseline.isSufficient,
           let bedtime = night.bedtimeClockMinutes,
           let wake = night.wakeClockMinutes,
           let medianBedtime = baseline.medianBedtimeClockMinutes,
           let medianWake = baseline.medianWakeClockMinutes {
            let bedtimeDeviation = circularClockDifference(bedtime, medianBedtime)
            let wakeDeviation = circularClockDifference(wake, medianWake)
            consistency = consistencyScore(averageDeviation: (bedtimeDeviation + wakeDeviation) / 2)
        } else {
            consistency = neutralComponentValue
            missing.append("consistencyBaseline")
        }

        if !night.heartRateAvailable { missing.append("heartRate") }
        if !night.movementAvailable { missing.append("movement") }

        let components = Components(
            duration: duration,
            continuity: continuity,
            restorative: restorative,
            latency: latency,
            consistency: consistency
        )

        let weighted =
            duration * 0.30
            + continuity * 0.30
            + restorative * 0.20
            + latency * 0.10
            + consistency * 0.10

        let ceilings = applicableCeilings(night: night)
        // The lowest applicable ceiling wins.
        let cap = ceilings.map(\.limit).min() ?? 100
        // Rounded once, after every calculation and ceiling.
        let final = Int(min(weighted, Double(cap)).rounded())

        return Result(
            score: max(0, min(100, final)),
            category: Category(score: final),
            components: components,
            confidence: confidence(night: night, missing: missing),
            weightedScoreBeforeCeilings: (weighted * 10).rounded() / 10,
            appliedCeilings: ceilings.map(\.reason),
            missingFields: missing
        )
    }

    // MARK: Components

    static func durationScore(minutesAsleep: Int) -> Double {
        // Rises to a peak at eight hours then falls away: sleeping ever longer
        // is not indefinitely better, and often signals the opposite.
        interpolate(Double(minutesAsleep), [
            (0, 0), (240, 20), (300, 40), (360, 60),
            (420, 82), (480, 100), (540, 95), (600, 80), (660, 65)
        ])
    }

    static func continuityScore(night: Night) -> Double {
        let efficiency = (night.sleepEfficiency ?? 0) * 100
        let efficiencyScore = interpolate(efficiency, [
            (60, 20), (70, 35), (75, 50), (80, 65),
            (85, 78), (90, 88), (95, 95), (100, 98)
        ])

        let penalised = efficiencyScore
            - (Double(night.fullAwakeningCount) * 6)
            - (Double(night.interruptionMinutes) * 0.35)
            - min(10, Double(night.restlessMinutes) * 0.10)

        return clamp(penalised)
    }

    /// Deep and REM against their healthy ranges, weighted equally.
    ///
    /// Named *restorative*, never "sound sleep": Google's sound-sleep figure
    /// also draws on movement and heart-rate-stability data that isn't
    /// available here, so the two are not equivalent.
    ///
    /// Nil when stages are unavailable — the night then gets no score at all
    /// rather than a guess.
    static func restorativeScore(night: Night) -> Double? {
        guard night.hasStages, night.minutesAsleep > 0 else { return nil }

        let asleep = Double(night.minutesAsleep)
        let deepRatio = Double(night.deepMinutes ?? 0) / asleep * 100
        let remRatio = Double(night.remMinutes ?? 0) / asleep * 100

        let deepScore = interpolate(deepRatio, [
            (0, 20), (5, 40), (10, 70), (15, 95),
            (20, 100), (25, 95), (30, 80), (40, 60)
        ])
        let remScore = interpolate(remRatio, [
            (0, 20), (10, 45), (15, 75), (20, 95),
            (25, 100), (30, 95), (35, 80), (45, 60)
        ])

        return clamp(deepScore * 0.50 + remScore * 0.50)
    }

    static func latencyScore(minutes: Double) -> Double {
        // Dropping off instantly scores below the sweet spot — it can indicate
        // sleep deprivation rather than good sleep.
        interpolate(minutes, [
            (0, 80), (5, 95), (10, 100), (20, 100),
            (30, 82), (45, 60), (60, 40), (90, 20)
        ])
    }

    static func consistencyScore(averageDeviation: Double) -> Double {
        interpolate(averageDeviation, [
            (0, 100), (15, 98), (30, 90), (60, 70),
            (90, 50), (120, 30), (180, 10)
        ])
    }

    // MARK: Ceilings

    struct Ceiling: Equatable {
        var limit: Int
        var reason: String
    }

    /// Every ceiling that applies to a night. The caller takes the lowest.
    static func applicableCeilings(night: Night) -> [Ceiling] {
        var out: [Ceiling] = []

        // Ordered most severe first; only the tightest matching band is added
        // so diagnostics don't list three overlapping duration ceilings.
        switch night.minutesAsleep {
        case ..<240: out.append(.init(limit: 49, reason: "under 4h asleep: max 49"))
        case ..<300: out.append(.init(limit: 59, reason: "under 5h asleep: max 59"))
        case ..<360: out.append(.init(limit: 69, reason: "under 6h asleep: max 69"))
        case ..<420: out.append(.init(limit: 84, reason: "under 7h asleep: max 84"))
        default: break
        }

        if let efficiency = night.sleepEfficiency {
            if efficiency < 0.75 { out.append(.init(limit: 59, reason: "efficiency under 75%: max 59")) }
            else if efficiency < 0.80 { out.append(.init(limit: 69, reason: "efficiency under 80%: max 69")) }
            else if efficiency < 0.85 { out.append(.init(limit: 79, reason: "efficiency under 85%: max 79")) }
        }

        if night.interruptionMinutes > 60 {
            out.append(.init(limit: 69, reason: "over 60 interruption minutes: max 69"))
        } else if night.interruptionMinutes > 45 {
            out.append(.init(limit: 74, reason: "over 45 interruption minutes: max 74"))
        } else if night.interruptionMinutes > 30 {
            out.append(.init(limit: 82, reason: "over 30 interruption minutes: max 82"))
        }

        if night.fullAwakeningCount >= 4 {
            out.append(.init(limit: 69, reason: "four or more full awakenings: max 69"))
        } else if night.fullAwakeningCount >= 3 {
            out.append(.init(limit: 76, reason: "three full awakenings: max 76"))
        } else if night.fullAwakeningCount == 2 {
            out.append(.init(limit: 84, reason: "two full awakenings: max 84"))
        }

        if let latency = night.sleepLatencyMinutes, latency > 60 {
            out.append(.init(limit: 79, reason: "over 60 minutes to fall asleep: max 79"))
        }

        if !night.heartRateAvailable || !night.movementAvailable {
            out.append(.init(limit: 88, reason: "heart-rate or movement unavailable: max 88"))
        }

        return out
    }

    // MARK: Confidence

    /// Confidence is reported separately and never alters the score. A night
    /// with poor data does not get a higher number to compensate.
    static func confidence(night: Night, missing: [String]) -> Confidence {
        if missing.contains("latency") || missing.contains("consistencyBaseline") { return .low }
        if !night.heartRateAvailable || !night.movementAvailable { return .medium }
        return .high
    }

    // MARK: Maths

    /// Piecewise linear interpolation across a table of (input, score) points.
    /// Values outside the table clamp to the nearest end, so sleeping twelve
    /// hours can't score better than the last point allows.
    static func interpolate(_ value: Double, _ points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if value <= first.0 { return first.1 }
        if value >= last.0 { return last.1 }

        for index in 1..<points.count {
            let (upperX, upperY) = points[index]
            guard value <= upperX else { continue }
            let (lowerX, lowerY) = points[index - 1]
            let span = upperX - lowerX
            guard span > 0 else { return upperY }
            return lowerY + (upperY - lowerY) * ((value - lowerX) / span)
        }
        return last.1
    }

    /// Shortest distance between two times on a 24-hour clock, in minutes.
    /// 23:50 and 00:10 are twenty minutes apart, not 1,420.
    static func circularClockDifference(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 1440)
        return min(raw, 1440 - raw)
    }

    static func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
        min(upper, max(lower, value))
    }

    /// Median of clock times, computed around noon so that bedtimes either side
    /// of midnight cluster instead of averaging to the middle of the day.
    static func medianClockMinutes(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let shifted = values.map { ($0 + 720).truncatingRemainder(dividingBy: 1440) }.sorted()
        let middle: Double
        if shifted.count % 2 == 1 {
            middle = shifted[shifted.count / 2]
        } else {
            middle = (shifted[shifted.count / 2 - 1] + shifted[shifted.count / 2]) / 2
        }
        return (middle + 720).truncatingRemainder(dividingBy: 1440)
    }
}

// MARK: - Bridging from stored records

extension SleepScore {

    /// Builds a scoreable night from a stored `HealthDay`.
    ///
    /// Movement is reported as **unavailable**, and that is not an oversight.
    /// The API supplies stage classifications, not the epoch-level movement and
    /// restlessness data Google's own scoring uses. Stage-derived awake
    /// intervals are a weaker proxy, and treating them as the real thing would
    /// let nights reach scores the underlying data can't justify — which is
    /// exactly how the earlier model produced 95s. So the 88 ceiling applies,
    /// "movement" appears in `missingFields`, and confidence caps at medium.
    static func night(from day: HealthDay) -> Night {
        Night(
            minutesAsleep: day.sleepMin ?? 0,
            timeInBed: day.timeInBedMin ?? day.sleepMin ?? 0,
            lightMinutes: day.lightMin,
            deepMinutes: day.deepMin,
            remMinutes: day.remMin,
            genericSleepMinutes: 0,
            fullAwakeningCount: day.awakenings ?? 0,
            interruptionMinutes: day.interruptionMinutes ?? 0,
            restlessMinutes: day.restlessMinutes ?? 0,
            sleepLatencyMinutes: day.latencyMin,
            bedtimeClockMinutes: day.bedtime.map(clockMinutes),
            wakeClockMinutes: day.wakeTime.map(clockMinutes),
            heartRateAvailable: day.restingHr != nil || day.hrvMs != nil || day.deepSleepHrvMs != nil,
            movementAvailable: false
        )
    }

    /// Rolling 14-day median bedtime and wake time, excluding the night being
    /// scored so a night is never measured against itself.
    static func baseline(from history: [HealthDay], excluding dayKey: String) -> Baseline {
        let recent = history
            .filter { $0.dayKey != dayKey && $0.bedtime != nil && $0.wakeTime != nil }
            .suffix(14)

        return Baseline(
            medianBedtimeClockMinutes: medianClockMinutes(recent.compactMap { $0.bedtime.map(clockMinutes) }),
            medianWakeClockMinutes: medianClockMinutes(recent.compactMap { $0.wakeTime.map(clockMinutes) }),
            validNights: recent.count
        )
    }

    static func calculate(day: HealthDay, history: [HealthDay]) -> Result? {
        calculate(night: night(from: day), baseline: baseline(from: history, excluding: day.dayKey))
    }

    private static func clockMinutes(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}

// MARK: - Diagnostics

extension SleepScore {

    /// Per-night structured diagnostics, for working out *why* a night scored
    /// what it did without reverse-engineering it from the UI.
    struct Diagnostics: Codable {
        var minutesAsleep: Int
        var timeInBed: Int
        var sleepEfficiency: Double
        var fullAwakeningCount: Int
        var interruptionMinutes: Int
        var restlessMinutes: Int
        var deepMinutes: Int
        var remMinutes: Int
        var sleepLatency: Int?
        var durationScore: Int
        var continuityScore: Int
        var restorativeScore: Int
        var latencyScore: Int
        var consistencyScore: Int
        var weightedScoreBeforeCeilings: Double
        var appliedCeilings: [String]
        var finalScore: Int
        var confidence: String
        var missingFields: [String]
    }

    static func diagnostics(night: Night, result: Result) -> Diagnostics {
        Diagnostics(
            minutesAsleep: night.minutesAsleep,
            timeInBed: night.timeInBed,
            sleepEfficiency: ((night.sleepEfficiency ?? 0) * 1000).rounded() / 1000,
            fullAwakeningCount: night.fullAwakeningCount,
            interruptionMinutes: night.interruptionMinutes,
            restlessMinutes: night.restlessMinutes,
            deepMinutes: night.deepMinutes ?? 0,
            remMinutes: night.remMinutes ?? 0,
            sleepLatency: night.sleepLatencyMinutes,
            durationScore: Int(result.components.duration.rounded()),
            continuityScore: Int(result.components.continuity.rounded()),
            restorativeScore: Int(result.components.restorative.rounded()),
            latencyScore: Int(result.components.latency.rounded()),
            consistencyScore: Int(result.components.consistency.rounded()),
            weightedScoreBeforeCeilings: result.weightedScoreBeforeCeilings,
            appliedCeilings: result.appliedCeilings,
            finalScore: result.score,
            confidence: result.confidence.rawValue,
            missingFields: result.missingFields
        )
    }

    /// Pretty-printed JSON for the debug sheet and for pasting into a bug report.
    static func diagnosticsJSON(night: Night, result: Result) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(diagnostics(night: night, result: result)),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
