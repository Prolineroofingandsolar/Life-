import Foundation

// MARK: - Comparison record

/// One night where the user told us what Google Health scored it, paired with
/// what Life estimated and every input behind that estimate.
///
/// This is the training data for personal calibration. It stores the feature
/// vector alongside the scores so the model can be refitted later without
/// re-deriving anything, and so a record made under an older scoring model can
/// be identified rather than silently mixed in.
struct SleepScoreComparison: Codable, Identifiable, Equatable {

    var dayKey: String = ""
    /// The exact sleep session this was entered against. If the night is
    /// re-imported and the session changes, the comparison is no longer valid.
    var sleepRecordID: String? = nil
    /// What Life estimated before any personal adjustment. Never overwritten.
    var baseScore: Int = 0
    /// What the user read off Google Health. 0–100.
    var googleScore: Int = 0

    // The inputs behind `baseScore`, kept for refitting.
    var durationComponent: Double = 0
    var continuityComponent: Double = 0
    var stageComponent: Double = 0
    var latencyComponent: Double = 0
    var consistencyComponent: Double = 0
    var heartRateComponent: Double = 0
    var hrvComponent: Double = 0
    var respiratoryComponent: Double = 0
    var oxygenComponent: Double = 0
    var temperatureComponent: Double = 0

    var fullAwakeningCount: Int = 0
    var interruptionMinutes: Int = 0
    var minutesAsleep: Int = 0
    var missingFields: [String] = []
    var confidence: String = ""
    /// Scoring model in force when this was recorded.
    var modelVersion: String = ""
    var recordedAt: Date = Date()

    var id: String { dayKey }

    /// What the calibration model is trying to predict.
    var residual: Double { Double(googleScore - baseScore) }

    /// Feature vector for the ridge model. Order is fixed and must match
    /// `SleepScoreCalibration.featureNames`.
    var featureVector: [Double] {
        [
            durationComponent, continuityComponent, stageComponent,
            latencyComponent, consistencyComponent,
            heartRateComponent, hrvComponent, respiratoryComponent,
            oxygenComponent, temperatureComponent,
            Double(fullAwakeningCount),
            Double(interruptionMinutes),
            // Missing-data flags, so the model can learn that nights with gaps
            // deviate differently from complete ones.
            missingFields.contains("heartRate") ? 1 : 0,
            missingFields.contains("hrv") ? 1 : 0,
            missingFields.contains("personalBaseline") ? 1 : 0
        ]
    }

    init() {}

    /// Builds a comparison from a scored night plus the user's entered value.
    init(features: SleepFeatures, result: SleepScore.Result, googleScore: Int) {
        self.dayKey = features.dayKey
        self.sleepRecordID = features.sourceRecordID
        self.baseScore = result.score
        self.googleScore = googleScore
        self.durationComponent = result.components.duration
        self.continuityComponent = result.components.continuity
        self.stageComponent = result.components.stages
        self.latencyComponent = result.components.latency
        self.consistencyComponent = result.components.consistency
        self.heartRateComponent = result.components.sleepingHeartRate
        self.hrvComponent = result.components.hrv
        self.respiratoryComponent = result.components.respiratoryRate
        self.oxygenComponent = result.components.oxygenSaturation
        self.temperatureComponent = result.components.temperatureStability
        self.fullAwakeningCount = features.fullAwakeningCount
        self.interruptionMinutes = features.interruptionMinutes
        self.minutesAsleep = features.minutesAsleep
        self.missingFields = features.missingFields
        self.confidence = result.confidence.rawValue
        self.modelVersion = SleepScore.modelVersion
        self.recordedAt = Date()
    }
}

// MARK: - Validation

enum SleepComparisonValidator {

    enum Rejection: String, CaseIterable {
        case scoreOutOfRange
        case missingStages
        case isNap
        case duplicate
        case sessionChanged
        case durationMismatch
        case incompleteRecord

        var message: String {
            switch self {
            case .scoreOutOfRange:  return "A Google Health score must be between 0 and 100."
            case .missingStages:    return "This night has no sleep stages, so it can't be compared."
            case .isNap:            return "Naps aren't scored, so they can't be compared."
            case .duplicate:        return "There's already a comparison saved for this night."
            case .sessionChanged:   return "The sleep session for this night has changed since the score was entered."
            case .durationMismatch: return "The imported sleep duration no longer matches the night this score was entered against."
            case .incompleteRecord: return "This night is still being processed by the source."
            }
        }
    }

    /// Sleep duration may drift slightly on re-import; beyond this the record
    /// is a different night in all but name and the comparison is discarded.
    static let durationToleranceMinutes = 30

    /// Whether a score can be saved for this night.
    static func validateEntry(
        googleScore: Int,
        features: SleepFeatures,
        existing: [String: SleepScoreComparison]
    ) -> Rejection? {
        guard (0...100).contains(googleScore) else { return .scoreOutOfRange }
        guard features.hasStages else { return .missingStages }
        guard !features.isNap else { return .isNap }
        guard features.processingComplete else { return .incompleteRecord }
        if existing[features.dayKey] != nil { return .duplicate }
        return nil
    }

    /// Whether a stored comparison is still usable for training.
    ///
    /// Re-checked on every fit rather than only at entry: the underlying night
    /// can change after the fact when a source reprocesses it, and training on
    /// a stale pairing teaches the model the wrong correction.
    static func validateForTraining(
        _ comparison: SleepScoreComparison,
        against features: SleepFeatures?
    ) -> Rejection? {
        guard (0...100).contains(comparison.googleScore) else { return .scoreOutOfRange }
        guard let features else { return .sessionChanged }
        guard features.hasStages else { return .missingStages }
        guard !features.isNap else { return .isNap }

        if let recordID = comparison.sleepRecordID,
           let currentID = features.sourceRecordID,
           recordID != currentID {
            return .sessionChanged
        }
        if abs(features.minutesAsleep - comparison.minutesAsleep) > durationToleranceMinutes {
            return .durationMismatch
        }
        return nil
    }

    /// Filters stored comparisons down to those still safe to train on.
    static func validTrainingSet(
        _ comparisons: [SleepScoreComparison],
        featuresByDay: [String: SleepFeatures]
    ) -> [SleepScoreComparison] {
        comparisons
            .filter { validateForTraining($0, against: featuresByDay[$0.dayKey]) == nil }
            .sorted { $0.dayKey < $1.dayKey }
    }
}
