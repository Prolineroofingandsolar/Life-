import Foundation

// MARK: - Sleep Score Features

/// Everything the scoring model reads about one night, derived once and passed
/// around as a value.
///
/// Separated from both storage and scoring so the derivation can be tested on
/// its own, and so the calibration model has a stable feature vector to learn
/// from. Every optional is genuinely optional — `nil` means the metric wasn't
/// available, and is recorded in `missingFields` rather than being filled in
/// with something flattering.
struct SleepFeatures: Equatable {

    var dayKey: String = ""
    var sourceRecordID: String? = nil

    // Duration and continuity
    var minutesAsleep: Int = 0
    var timeInBed: Int = 0
    var awakeMinutes: Int = 0
    var fullAwakeningCount: Int = 0
    var interruptionMinutes: Int = 0
    var restlessMinutes: Int = 0
    var stageTransitionCount: Int = 0
    var sleepLatencyMinutes: Int? = nil

    // Stages
    var lightMinutes: Int? = nil
    var deepMinutes: Int? = nil
    var remMinutes: Int? = nil

    // Schedule
    var bedtimeClockMinutes: Double? = nil
    var wakeClockMinutes: Double? = nil

    // Overnight physiology, absolute values
    var sleepingHeartRateAverage: Double? = nil
    var sleepingHeartRateMinimum: Double? = nil
    /// Standard deviation of overnight heart rate — lower is steadier.
    var sleepingHeartRateStability: Double? = nil
    var restingHeartRate: Double? = nil
    var hrvMs: Double? = nil
    var spo2Average: Double? = nil
    var spo2MinutesBelowExpected: Int? = nil
    var respiratoryRate: Double? = nil
    var skinTemperatureC: Double? = nil

    // Deviations from the user's own rolling baseline. Nil until a baseline
    // exists — these are what the physiological components actually score.
    var heartRateDeltaFromBaseline: Double? = nil
    var hrvDeltaFromBaseline: Double? = nil
    var respiratoryRateDeltaFromBaseline: Double? = nil
    var temperatureDeltaFromBaseline: Double? = nil

    // Data quality
    var hasStages: Bool = false
    var isNap: Bool = false
    var isMainSession: Bool = true
    var processingComplete: Bool = true
    var missingFields: [String] = []

    var sleepEfficiency: Double? {
        guard timeInBed > 0 else { return nil }
        return min(1, Double(minutesAsleep) / Double(timeInBed))
    }

    var deepPercentage: Double? {
        guard minutesAsleep > 0, let deepMinutes else { return nil }
        return Double(deepMinutes) / Double(minutesAsleep) * 100
    }

    var remPercentage: Double? {
        guard minutesAsleep > 0, let remMinutes else { return nil }
        return Double(remMinutes) / Double(minutesAsleep) * 100
    }

    var lightPercentage: Double? {
        guard minutesAsleep > 0, let lightMinutes else { return nil }
        return Double(lightMinutes) / Double(minutesAsleep) * 100
    }
}

// MARK: - Personal baselines

/// The user's own rolling baselines. Physiological components are scored
/// against these rather than universal thresholds — a resting heart rate of 58
/// means nothing without knowing whether that's high or low for this person.
struct SleepBaselines: Equatable {

    /// Nights required before a baseline is trusted. Below this, components
    /// that depend on one take the neutral value and confidence drops.
    static let minimumNights = 7

    var heartRate: Double? = nil
    var hrv: Double? = nil
    var respiratoryRate: Double? = nil
    var temperature: Double? = nil
    var medianBedtimeClockMinutes: Double? = nil
    var medianWakeClockMinutes: Double? = nil
    var nightCount: Int = 0

    var isSufficient: Bool { nightCount >= Self.minimumNights }

    /// Schedule consistency needs its own check: it can be present when the
    /// physiological baselines aren't, and vice versa.
    var hasSchedule: Bool {
        isSufficient && medianBedtimeClockMinutes != nil && medianWakeClockMinutes != nil
    }
}

// MARK: - Derivation

enum SleepFeatureBuilder {

    /// Builds the feature vector for one night from stored records.
    static func features(
        for day: HealthDay,
        history: [HealthDay],
        baselines: SleepBaselines
    ) -> SleepFeatures {
        var out = SleepFeatures()
        out.dayKey = day.dayKey
        out.sourceRecordID = day.sleepRecordID

        out.minutesAsleep = day.sleepMin ?? 0
        out.timeInBed = day.timeInBedMin ?? day.sleepMin ?? 0
        out.awakeMinutes = day.awakeMin ?? 0
        out.fullAwakeningCount = day.awakenings ?? 0
        out.interruptionMinutes = day.interruptionMinutes ?? 0
        out.restlessMinutes = day.restlessMinutes ?? 0
        out.stageTransitionCount = day.stageTransitions ?? 0
        out.sleepLatencyMinutes = day.latencyMin

        out.lightMinutes = day.lightMin
        out.deepMinutes = day.deepMin
        out.remMinutes = day.remMin
        out.hasStages = day.deepMin != nil || day.remMin != nil

        out.bedtimeClockMinutes = day.bedtime.map(clockMinutes)
        out.wakeClockMinutes = day.wakeTime.map(clockMinutes)

        out.sleepingHeartRateAverage = day.sleepingHrAverage
        out.sleepingHeartRateMinimum = day.sleepingHrMinimum
        out.sleepingHeartRateStability = day.sleepingHrStability
        out.restingHeartRate = day.restingHr
        out.hrvMs = day.deepSleepHrvMs ?? day.hrvMs
        out.spo2Average = day.spo2Pct
        out.respiratoryRate = day.respiratoryRate
        out.skinTemperatureC = day.wristTempC

        // Deviations only exist once there's a baseline to deviate from.
        if baselines.isSufficient {
            let heartRate = out.sleepingHeartRateAverage ?? out.restingHeartRate
            out.heartRateDeltaFromBaseline = delta(heartRate, baselines.heartRate)
            out.hrvDeltaFromBaseline = delta(out.hrvMs, baselines.hrv)
            out.respiratoryRateDeltaFromBaseline = delta(out.respiratoryRate, baselines.respiratoryRate)
            out.temperatureDeltaFromBaseline = delta(out.skinTemperatureC, baselines.temperature)
        }

        out.isNap = false
        out.missingFields = missingFields(for: out, baselines: baselines)
        return out
    }

    /// Names every metric that wasn't available, so nothing is silently
    /// substituted and the diagnostics can say what was absent.
    static func missingFields(for features: SleepFeatures, baselines: SleepBaselines) -> [String] {
        var out: [String] = []
        if !features.hasStages { out.append("stages") }
        if features.sleepLatencyMinutes == nil { out.append("latency") }
        if features.sleepingHeartRateAverage == nil && features.restingHeartRate == nil {
            out.append("heartRate")
        }
        if features.hrvMs == nil { out.append("hrv") }
        if features.spo2Average == nil { out.append("spo2") }
        if features.respiratoryRate == nil { out.append("respiratoryRate") }
        if features.skinTemperatureC == nil { out.append("temperature") }
        if features.sleepingHeartRateStability == nil { out.append("movement") }
        if !baselines.isSufficient { out.append("personalBaseline") }
        return out
    }

    /// Rolling baselines from recent nights, excluding the night being scored
    /// so it is never measured against itself.
    static func baselines(from history: [HealthDay], excluding dayKey: String, window: Int = 30) -> SleepBaselines {
        let recent = history.filter { $0.dayKey != dayKey }.suffix(window)

        func mean(_ metric: (HealthDay) -> Double?) -> Double? {
            let values = recent.compactMap { day -> Double? in metric(day) }
            guard values.count >= SleepBaselines.minimumNights else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        let scheduleNights = recent.filter { $0.bedtime != nil && $0.wakeTime != nil }

        var out = SleepBaselines()
        out.heartRate = mean { $0.sleepingHrAverage ?? $0.restingHr }
        out.hrv = mean { $0.deepSleepHrvMs ?? $0.hrvMs }
        out.respiratoryRate = mean { $0.respiratoryRate }
        out.temperature = mean { $0.wristTempC }
        out.medianBedtimeClockMinutes = SleepScore.medianClockMinutes(
            scheduleNights.suffix(14).compactMap { $0.bedtime.map(clockMinutes) }
        )
        out.medianWakeClockMinutes = SleepScore.medianClockMinutes(
            scheduleNights.suffix(14).compactMap { $0.wakeTime.map(clockMinutes) }
        )
        // Nights that carry a sleep duration are what count toward "enough
        // history", regardless of which individual metrics were recorded.
        out.nightCount = recent.filter { $0.sleepMin != nil }.count
        return out
    }

    private static func delta(_ value: Double?, _ baseline: Double?) -> Double? {
        guard let value, let baseline else { return nil }
        return value - baseline
    }

    static func clockMinutes(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}
