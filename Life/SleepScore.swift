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

    /// The ten weighted parts of the base score. Each is 0–100.
    struct Components: Equatable {
        var duration: Double = 0            // 25%
        var continuity: Double = 0          // 25%
        var stages: Double = 0              // 15%
        var latency: Double = 0             // 10%
        var consistency: Double = 0         // 10%
        var sleepingHeartRate: Double = 0   // 5%
        var hrv: Double = 0                 // 4%
        var respiratoryRate: Double = 0     // 2%
        var oxygenSaturation: Double = 0    // 2%
        var temperatureStability: Double = 0 // 2%

        /// Weights sum to 1.0. Sleep architecture dominates deliberately; the
        /// physiological signals refine rather than drive the number.
        var weighted: Double {
            duration * 0.25
            + continuity * 0.25
            + stages * 0.15
            + latency * 0.10
            + consistency * 0.10
            + sleepingHeartRate * 0.05
            + hrv * 0.04
            + respiratoryRate * 0.02
            + oxygenSaturation * 0.02
            + temperatureStability * 0.02
        }
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

    // MARK: Constants

    /// Substituted for any component whose inputs are missing. Deliberately
    /// neutral: missing data must never be scored as perfect, and must never
    /// raise the score.
    static let neutralComponentValue: Double = 70

    /// Bumped whenever the scoring rules change, so calibration records made
    /// against an older model can be identified rather than silently mixed in.
    static let modelVersion = "base-2"

    // MARK: Entry point

    /// Scores a night from its derived features.
    ///
    /// Returns nil only when sleep stages are unavailable — every other gap is
    /// handled with a neutral component and a lowered confidence, never by
    /// assuming the best.
    static func calculate(features: SleepFeatures, baselines: SleepBaselines) -> Result? {
        guard features.hasStages, features.minutesAsleep > 0 else { return nil }

        var components = Components()
        components.duration = durationScore(minutesAsleep: features.minutesAsleep)
        components.continuity = continuityScore(features: features)

        guard let stages = stageScore(features: features) else { return nil }
        components.stages = stages

        if let latency = features.sleepLatencyMinutes {
            components.latency = latencyScore(minutes: Double(latency))
        } else {
            components.latency = neutralComponentValue
        }

        if baselines.hasSchedule,
           let bedtime = features.bedtimeClockMinutes,
           let wake = features.wakeClockMinutes,
           let medianBedtime = baselines.medianBedtimeClockMinutes,
           let medianWake = baselines.medianWakeClockMinutes {
            let deviation = (circularClockDifference(bedtime, medianBedtime)
                             + circularClockDifference(wake, medianWake)) / 2
            components.consistency = consistencyScore(averageDeviation: deviation)
        } else {
            components.consistency = neutralComponentValue
        }

        // Physiological components score the *deviation from this person's own
        // baseline*, not an absolute value. A resting heart rate of 58 says
        // nothing without knowing whether that is high or low for them.
        components.sleepingHeartRate = deviationScore(
            features.heartRateDeltaFromBaseline, scale: 6, higherIsBetter: false)
        components.hrv = deviationScore(
            features.hrvDeltaFromBaseline, scale: baselines.hrv.map { max(5, $0 * 0.25) } ?? 12,
            higherIsBetter: true)
        components.respiratoryRate = deviationScore(
            features.respiratoryRateDeltaFromBaseline, scale: 1.5, higherIsBetter: false)
        components.temperatureStability = deviationScore(
            features.temperatureDeltaFromBaseline, scale: 0.5, higherIsBetter: false, symmetric: true)
        components.oxygenSaturation = oxygenScore(features.spo2Average)

        let weighted = components.weighted
        let ceilings = applicableCeilings(features: features)
        let cap = ceilings.map(\.limit).min() ?? 100
        // Rounded once, after every calculation and ceiling.
        let final = Int(min(weighted, Double(cap)).rounded())

        return Result(
            score: max(0, min(100, final)),
            category: Category(score: final),
            components: components,
            confidence: confidence(features: features),
            weightedScoreBeforeCeilings: (weighted * 10).rounded() / 10,
            appliedCeilings: ceilings.map(\.reason),
            missingFields: features.missingFields
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

    static func continuityScore(features: SleepFeatures) -> Double {
        let efficiency = (features.sleepEfficiency ?? 0) * 100
        let efficiencyScore = interpolate(efficiency, [
            (60, 20), (70, 35), (75, 50), (80, 65),
            (85, 78), (90, 88), (95, 95), (100, 98)
        ])

        let penalised = efficiencyScore
            - (Double(features.fullAwakeningCount) * 6)
            - (Double(features.interruptionMinutes) * 0.35)
            - min(10, Double(features.restlessMinutes) * 0.10)

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
    static func stageScore(features: SleepFeatures) -> Double? {
        guard features.hasStages, features.minutesAsleep > 0 else { return nil }

        let deepRatio = features.deepPercentage ?? 0
        let remRatio = features.remPercentage ?? 0

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
    static func applicableCeilings(features: SleepFeatures) -> [Ceiling] {
        var out: [Ceiling] = []

        // Ordered most severe first; only the tightest matching band is added
        // so diagnostics don't list three overlapping duration ceilings.
        switch features.minutesAsleep {
        case ..<240: out.append(.init(limit: 49, reason: "under 4h asleep: max 49"))
        case ..<300: out.append(.init(limit: 59, reason: "under 5h asleep: max 59"))
        case ..<360: out.append(.init(limit: 69, reason: "under 6h asleep: max 69"))
        case ..<420: out.append(.init(limit: 84, reason: "under 7h asleep: max 84"))
        default: break
        }

        if let efficiency = features.sleepEfficiency {
            if efficiency < 0.75 { out.append(.init(limit: 59, reason: "efficiency under 75%: max 59")) }
            else if efficiency < 0.80 { out.append(.init(limit: 69, reason: "efficiency under 80%: max 69")) }
            else if efficiency < 0.85 { out.append(.init(limit: 79, reason: "efficiency under 85%: max 79")) }
        }

        if features.interruptionMinutes > 60 {
            out.append(.init(limit: 69, reason: "over 60 interruption minutes: max 69"))
        } else if features.interruptionMinutes > 45 {
            out.append(.init(limit: 74, reason: "over 45 interruption minutes: max 74"))
        } else if features.interruptionMinutes > 30 {
            out.append(.init(limit: 82, reason: "over 30 interruption minutes: max 82"))
        }

        if features.fullAwakeningCount >= 4 {
            out.append(.init(limit: 69, reason: "four or more full awakenings: max 69"))
        } else if features.fullAwakeningCount >= 3 {
            out.append(.init(limit: 76, reason: "three full awakenings: max 76"))
        } else if features.fullAwakeningCount == 2 {
            out.append(.init(limit: 84, reason: "two full awakenings: max 84"))
        }

        if let latency = features.sleepLatencyMinutes, latency > 60 {
            out.append(.init(limit: 79, reason: "over 60 minutes to fall asleep: max 79"))
        }

        // Deliberately no ceiling for missing movement or heart rate. Those
        // gaps are a statement about how much is known, not about how well the
        // night went, so they reduce *confidence* instead. Capping the score
        // for them would penalise the user for their device's limitations.

        return out
    }

    // MARK: Confidence

    /// Confidence is reported separately and never alters the score. A night
    /// with poor data does not get a higher number to compensate.
    static func confidence(features: SleepFeatures) -> Confidence {
        let missing = Set(features.missingFields)
        if missing.contains("latency") || missing.contains("personalBaseline") || missing.contains("stages") {
            return .low
        }
        if !missing.isEmpty { return .medium }
        return .high
    }

    // MARK: Physiological components

    /// Scores a deviation from the user's own baseline on a 0–100 scale.
    ///
    /// Sitting on the baseline scores 70, not 100 — the top of the range is for
    /// a night measurably better than this person's normal, which is what stops
    /// unremarkable nights accumulating full marks across five components.
    ///
    /// Returns the neutral value when there's no baseline to compare against.
    static func deviationScore(
        _ delta: Double?,
        scale: Double,
        higherIsBetter: Bool,
        symmetric: Bool = false
    ) -> Double {
        guard let delta, scale > 0 else { return neutralComponentValue }
        // Temperature is symmetric: drifting either way from baseline is a
        // signal, so the magnitude is what matters.
        let signed = symmetric ? -abs(delta) : (higherIsBetter ? delta : -delta)
        return clamp(70 + (signed / scale) * 30)
    }

    /// Blood oxygen as a general wellness signal only — deliberately not a
    /// medical interpretation. Neutral when unavailable.
    static func oxygenScore(_ average: Double?) -> Double {
        guard let average else { return neutralComponentValue }
        return interpolate(average, [(88, 40), (92, 65), (95, 85), (97, 95), (99, 100)])
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

    /// Scores a stored night, deriving its features and baselines first.
    static func calculate(day: HealthDay, history: [HealthDay]) -> Result? {
        let baselines = SleepFeatureBuilder.baselines(from: history, excluding: day.dayKey)
        let features = SleepFeatureBuilder.features(for: day, history: history, baselines: baselines)
        return calculate(features: features, baselines: baselines)
    }
}

// MARK: - Diagnostics

extension SleepScore {

    /// Per-night structured diagnostics, for working out *why* a night scored
    /// what it did without reverse-engineering it from the screen.
    struct Diagnostics: Codable {
        var dayKey: String
        var minutesAsleep: Int
        var timeInBed: Int
        var sleepEfficiency: Double
        var fullAwakeningCount: Int
        var interruptionMinutes: Int
        var restlessMinutes: Int
        var deepMinutes: Int
        var remMinutes: Int
        var lightMinutes: Int
        var stageTransitionCount: Int
        var sleepLatency: Int?
        var durationScore: Int
        var continuityScore: Int
        var stageScore: Int
        var latencyScore: Int
        var consistencyScore: Int
        var sleepingHeartRateScore: Int
        var hrvScore: Int
        var respiratoryRateScore: Int
        var oxygenSaturationScore: Int
        var temperatureScore: Int
        var baseScore: Int
        var weightedScoreBeforeCeilings: Double
        var appliedCeilings: [String]
        var confidence: String
        var missingFields: [String]
        var modelVersion: String
    }

    static func diagnostics(features: SleepFeatures, result: Result) -> Diagnostics {
        Diagnostics(
            dayKey: features.dayKey,
            minutesAsleep: features.minutesAsleep,
            timeInBed: features.timeInBed,
            sleepEfficiency: ((features.sleepEfficiency ?? 0) * 1000).rounded() / 1000,
            fullAwakeningCount: features.fullAwakeningCount,
            interruptionMinutes: features.interruptionMinutes,
            restlessMinutes: features.restlessMinutes,
            deepMinutes: features.deepMinutes ?? 0,
            remMinutes: features.remMinutes ?? 0,
            lightMinutes: features.lightMinutes ?? 0,
            stageTransitionCount: features.stageTransitionCount,
            sleepLatency: features.sleepLatencyMinutes,
            durationScore: Int(result.components.duration.rounded()),
            continuityScore: Int(result.components.continuity.rounded()),
            stageScore: Int(result.components.stages.rounded()),
            latencyScore: Int(result.components.latency.rounded()),
            consistencyScore: Int(result.components.consistency.rounded()),
            sleepingHeartRateScore: Int(result.components.sleepingHeartRate.rounded()),
            hrvScore: Int(result.components.hrv.rounded()),
            respiratoryRateScore: Int(result.components.respiratoryRate.rounded()),
            oxygenSaturationScore: Int(result.components.oxygenSaturation.rounded()),
            temperatureScore: Int(result.components.temperatureStability.rounded()),
            baseScore: result.score,
            weightedScoreBeforeCeilings: result.weightedScoreBeforeCeilings,
            appliedCeilings: result.appliedCeilings,
            confidence: result.confidence.rawValue,
            missingFields: result.missingFields,
            modelVersion: modelVersion
        )
    }
}
