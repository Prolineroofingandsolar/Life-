import Foundation

// MARK: - Diagnostics

/// The full picture for one night: what was imported, what was derived, what
/// each component scored, which ceilings bit, what the user said Google
/// reported, and what calibration did about it.
///
/// Codable so it can be copied out of the debug screen and pasted into a bug
/// report — reproducing a scoring complaint from a screenshot is guesswork.
struct SleepNightDiagnostics: Codable {

    // Imported source data
    var dayKey: String
    var sourceRecordID: String?
    var sourcePlatform: String?
    var sourceDevice: String?
    var bedtime: Date?
    var wakeTime: Date?
    var isMainSession: Bool
    var isNap: Bool
    var processingComplete: Bool

    // Derived features
    var minutesAsleep: Int
    var timeInBed: Int
    var sleepEfficiency: Double
    var awakeMinutes: Int
    var fullAwakeningCount: Int
    var interruptionMinutes: Int
    var restlessMinutes: Int
    var lightMinutes: Int
    var deepMinutes: Int
    var remMinutes: Int
    var stageTransitionCount: Int
    var sleepLatency: Int?
    var sleepingHeartRateAverage: Double?
    var sleepingHeartRateMinimum: Double?
    var sleepingHeartRateStability: Double?
    var hrvMs: Double?
    var spo2Average: Double?
    var respiratoryRate: Double?
    var skinTemperatureC: Double?
    var heartRateDeltaFromBaseline: Double?
    var hrvDeltaFromBaseline: Double?

    // Component scores
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

    // Scores
    var weightedScoreBeforeCeilings: Double
    var appliedCeilings: [String]
    var baseScore: Int
    var googleScore: Int?
    var nightlyDifference: Int?
    var personalBias: Double?
    var learnedCorrection: Double?
    var adjustedScore: Int

    // Meta
    var confidence: String
    var missingFields: [String]
    var scoringModelVersion: String
    var calibrationModelVersion: String
    var calibrationStage: String
    var comparisonCount: Int
    var validationMeanAbsoluteError: Double?
    var validationCategoryAgreement: Double?
    var learnedModelUsed: Bool
}

enum SleepDiagnosticsBuilder {

    /// Assembles diagnostics for a night from everything the app knows about it.
    static func build(
        day: HealthDay,
        features: SleepFeatures,
        result: SleepScore.Result,
        adjusted: SleepScoreCalibration.Adjusted,
        model: SleepScoreCalibration.Model,
        comparison: SleepScoreComparison?
    ) -> SleepNightDiagnostics {

        let stageLabel: String
        switch model.stage {
        case .collecting: stageLabel = "collecting"
        case .bias:       stageLabel = "bias"
        case .model:      stageLabel = "ridge"
        }

        return SleepNightDiagnostics(
            dayKey: features.dayKey,
            sourceRecordID: features.sourceRecordID,
            sourcePlatform: day.sleepSourceDevice,
            sourceDevice: day.sleepSourceDevice,
            bedtime: day.bedtime,
            wakeTime: day.wakeTime,
            isMainSession: features.isMainSession,
            isNap: features.isNap,
            processingComplete: features.processingComplete,

            minutesAsleep: features.minutesAsleep,
            timeInBed: features.timeInBed,
            sleepEfficiency: round3(features.sleepEfficiency ?? 0),
            awakeMinutes: features.awakeMinutes,
            fullAwakeningCount: features.fullAwakeningCount,
            interruptionMinutes: features.interruptionMinutes,
            restlessMinutes: features.restlessMinutes,
            lightMinutes: features.lightMinutes ?? 0,
            deepMinutes: features.deepMinutes ?? 0,
            remMinutes: features.remMinutes ?? 0,
            stageTransitionCount: features.stageTransitionCount,
            sleepLatency: features.sleepLatencyMinutes,
            sleepingHeartRateAverage: features.sleepingHeartRateAverage,
            sleepingHeartRateMinimum: features.sleepingHeartRateMinimum,
            sleepingHeartRateStability: features.sleepingHeartRateStability,
            hrvMs: features.hrvMs,
            spo2Average: features.spo2Average,
            respiratoryRate: features.respiratoryRate,
            skinTemperatureC: features.skinTemperatureC,
            heartRateDeltaFromBaseline: features.heartRateDeltaFromBaseline.map(round1),
            hrvDeltaFromBaseline: features.hrvDeltaFromBaseline.map(round1),

            durationScore: rounded(result.components.duration),
            continuityScore: rounded(result.components.continuity),
            stageScore: rounded(result.components.stages),
            latencyScore: rounded(result.components.latency),
            consistencyScore: rounded(result.components.consistency),
            sleepingHeartRateScore: rounded(result.components.sleepingHeartRate),
            hrvScore: rounded(result.components.hrv),
            respiratoryRateScore: rounded(result.components.respiratoryRate),
            oxygenSaturationScore: rounded(result.components.oxygenSaturation),
            temperatureScore: rounded(result.components.temperatureStability),

            weightedScoreBeforeCeilings: result.weightedScoreBeforeCeilings,
            appliedCeilings: result.appliedCeilings,
            baseScore: result.score,
            googleScore: comparison?.googleScore,
            nightlyDifference: comparison.map { $0.baseScore - $0.googleScore },
            personalBias: round1(model.bias),
            learnedCorrection: adjusted.correction,
            adjustedScore: adjusted.adjustedScore,

            confidence: result.confidence.rawValue,
            missingFields: result.missingFields,
            scoringModelVersion: SleepScore.modelVersion,
            calibrationModelVersion: model.modelVersion,
            calibrationStage: stageLabel,
            comparisonCount: model.stage.comparisonCount,
            validationMeanAbsoluteError: model.validation?.meanAbsoluteError,
            validationCategoryAgreement: model.validation?.categoryAgreement,
            learnedModelUsed: model.validation?.learnedModelUsed ?? false
        )
    }

    /// Pretty-printed JSON, for copying out of the debug screen.
    static func json(_ diagnostics: SleepNightDiagnostics) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(diagnostics),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func rounded(_ value: Double) -> Int { Int(value.rounded()) }
    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    private static func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
}
