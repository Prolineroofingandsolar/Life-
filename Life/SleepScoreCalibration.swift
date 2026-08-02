import Foundation

// MARK: - Personal calibration

/// Learns how this person's Google Health scores differ from Life's estimates,
/// and applies that correction to future nights.
///
/// **The base score is never overwritten.** Calibration produces a separate
/// correction; both are stored, and the adjustment is always reversible and
/// inspectable. The model also never applies itself on the strength of one
/// night — it stays out of the way until there's enough evidence to be worth
/// trusting, and falls back the moment the learned version does worse than the
/// simple one.
enum SleepScoreCalibration {

    /// Bumped when the calibration maths changes, so stored corrections can be
    /// told apart from ones made under different rules.
    static let modelVersion = "calibration-1"

    /// Comparisons needed before any personal adjustment is applied.
    static let minimumForBias = 14
    /// Comparisons needed before the residual model is attempted.
    static let minimumForRidge = 30
    /// Only the most recent pairs are kept — older ones describe a different
    /// person's habits and a possibly different device.
    static let maximumRetained = 60
    /// Corrections are bounded in both directions. A calibration that wants to
    /// move a score by more than this is not calibrating, it's overriding.
    static let maximumCorrection: Double = 15
    /// Ridge penalty. Large enough to keep coefficients small on the tens of
    /// examples this will realistically ever see.
    static let ridgeLambda: Double = 10

    static let featureNames = [
        "duration", "continuity", "stages", "latency", "consistency",
        "sleepingHeartRate", "hrv", "respiratoryRate", "oxygenSaturation", "temperature",
        "fullAwakenings", "interruptionMinutes",
        "missingHeartRate", "missingHrv", "missingBaseline"
    ]

    // MARK: Stages

    enum Stage: Equatable {
        /// Fewer than 14 comparisons: observe only.
        case collecting(count: Int)
        /// 14–29: a single personal bias.
        case bias(count: Int, bias: Double)
        /// 30+: a fitted residual model.
        case model(count: Int, validation: Validation)

        var comparisonCount: Int {
            switch self {
            case .collecting(let count):   return count
            case .bias(let count, _):      return count
            case .model(let count, _):     return count
            }
        }

        var isPersonalised: Bool {
            if case .collecting = self { return false }
            return true
        }
    }

    // MARK: Model

    struct Model: Equatable {
        var stage: Stage
        /// Mean signed difference (base − google) across the training set.
        var bias: Double = 0
        /// Ridge coefficients, aligned with `featureNames`. Empty in bias mode.
        var weights: [Double] = []
        var intercept: Double = 0
        var modelVersion: String = SleepScoreCalibration.modelVersion
        var scoringModelVersion: String = SleepScore.modelVersion
        /// Held-out performance, kept whichever model won so the diagnostics can
        /// show why the simpler one was preferred.
        var validation: Validation? = nil

        /// The correction to add to a base score for a given night.
        func correction(for comparison: SleepScoreComparison) -> Double {
            switch stage {
            case .collecting:
                return 0
            case .bias:
                // difference = base − google, so subtracting the mean difference
                // moves our estimate toward theirs.
                return clampCorrection(-bias)
            case .model:
                guard !weights.isEmpty else { return clampCorrection(-bias) }
                let features = comparison.featureVector
                guard features.count == weights.count else { return clampCorrection(-bias) }
                let predicted = zip(features, weights).reduce(intercept) { $0 + $1.0 * $1.1 }
                return clampCorrection(predicted)
            }
        }

        private func clampCorrection(_ value: Double) -> Double {
            min(SleepScoreCalibration.maximumCorrection,
                max(-SleepScoreCalibration.maximumCorrection, value))
        }
    }

    // MARK: Validation

    struct Validation: Equatable {
        var meanError: Double = 0
        var meanAbsoluteError: Double = 0
        var medianAbsoluteError: Double = 0
        /// Share of validation nights landing in the same category as Google.
        var categoryAgreement: Double = 0
        var pairedNights: Int = 0
        var averagePersonalCorrection: Double = 0
        /// True when the ridge model beat the simple bias on held-out nights.
        var learnedModelUsed: Bool = false
    }

    // MARK: Fitting

    /// Fits the best calibration the available comparisons support.
    ///
    /// Chronological split — oldest 80% trains, newest 20% validates. Random
    /// splitting would leak future nights into training and flatter the model.
    static func fit(_ comparisons: [SleepScoreComparison]) -> Model {
        let ordered = comparisons.sorted { $0.dayKey < $1.dayKey }.suffix(maximumRetained)
        let all = Array(ordered)

        guard all.count >= minimumForBias else {
            return Model(stage: .collecting(count: all.count))
        }

        let bias = mean(all.map(\.residual).map { -$0 })

        guard all.count >= minimumForRidge else {
            return Model(stage: .bias(count: all.count, bias: bias), bias: bias)
        }

        let splitIndex = max(1, Int(Double(all.count) * 0.8))
        let training = Array(all[..<splitIndex])
        let testing = Array(all[splitIndex...])

        guard !testing.isEmpty else {
            return Model(stage: .bias(count: all.count, bias: bias), bias: bias)
        }

        let trainingBias = mean(training.map(\.residual).map { -$0 })
        let biasModel = Model(stage: .bias(count: all.count, bias: trainingBias), bias: trainingBias)

        var ridgeModel = Model(stage: .bias(count: all.count, bias: trainingBias), bias: trainingBias)
        if let fitted = ridge(training: training) {
            ridgeModel.weights = fitted.weights
            ridgeModel.intercept = fitted.intercept
            ridgeModel.stage = .model(count: all.count, validation: Validation())
        }

        let biasValidation = validate(model: biasModel, on: testing)
        let ridgeValidation = validate(model: ridgeModel, on: testing)

        // Never deploy a learned model that makes held-out error worse.
        guard !ridgeModel.weights.isEmpty,
              ridgeValidation.meanAbsoluteError < biasValidation.meanAbsoluteError else {
            // The learned model didn't beat the simple bias on held-out nights,
            // so it isn't deployed. Keeping its validation alongside makes that
            // decision auditable rather than invisible.
            var out = biasModel
            var validation = biasValidation
            validation.learnedModelUsed = false
            out.validation = validation
            return out
        }

        var out = ridgeModel
        var validation = ridgeValidation
        validation.learnedModelUsed = true
        out.stage = .model(count: all.count, validation: validation)
        out.validation = validation
        return out
    }

    /// Held-out performance for a model.
    static func validate(model: Model, on comparisons: [SleepScoreComparison]) -> Validation {
        guard !comparisons.isEmpty else { return Validation() }

        var errors: [Double] = []
        var corrections: [Double] = []
        var agreements = 0

        for comparison in comparisons {
            let correction = model.correction(for: comparison)
            let adjusted = clampScore(Double(comparison.baseScore) + correction)
            errors.append(adjusted - Double(comparison.googleScore))
            corrections.append(correction)
            if SleepScore.Category(score: Int(adjusted.rounded()))
                == SleepScore.Category(score: comparison.googleScore) {
                agreements += 1
            }
        }

        let absolute = errors.map(abs)
        return Validation(
            meanError: round1(mean(errors)),
            meanAbsoluteError: round1(mean(absolute)),
            medianAbsoluteError: round1(median(absolute)),
            categoryAgreement: round1(Double(agreements) / Double(comparisons.count) * 100),
            pairedNights: comparisons.count,
            averagePersonalCorrection: round1(mean(corrections)),
            learnedModelUsed: !model.weights.isEmpty
        )
    }

    // MARK: Ridge regression

    /// Closed-form ridge: w = (XᵀX + λI)⁻¹ Xᵀy, with a column of ones for the
    /// intercept (left unpenalised).
    ///
    /// Fifteen features on thirty-odd examples would overfit badly unpenalised,
    /// which is the whole reason for the ridge term.
    static func ridge(training: [SleepScoreComparison]) -> (weights: [Double], intercept: Double)? {
        guard training.count >= 2 else { return nil }

        let rawFeatures = training.map(\.featureVector)
        guard let width = rawFeatures.first?.count, width > 0 else { return nil }

        // Standardise so features on wildly different scales (a 0–100 component
        // against an awakening count of 0–5) get comparable penalisation.
        var means = [Double](repeating: 0, count: width)
        var deviations = [Double](repeating: 1, count: width)
        for column in 0..<width {
            let values = rawFeatures.map { $0[column] }
            means[column] = mean(values)
            let variance = mean(values.map { pow($0 - means[column], 2) })
            deviations[column] = variance > 1e-9 ? sqrt(variance) : 1
        }

        let x = rawFeatures.map { row in
            [1.0] + (0..<width).map { (row[$0] - means[$0]) / deviations[$0] }
        }
        let y = training.map(\.residual)
        let columns = width + 1

        // XᵀX + λI, leaving the intercept unpenalised.
        var normal = [[Double]](repeating: [Double](repeating: 0, count: columns), count: columns)
        for i in 0..<columns {
            for j in 0..<columns {
                normal[i][j] = x.reduce(0) { $0 + $1[i] * $1[j] }
            }
            if i > 0 { normal[i][i] += ridgeLambda }
        }
        var target = [Double](repeating: 0, count: columns)
        for i in 0..<columns {
            target[i] = zip(x, y).reduce(0) { $0 + $1.0[i] * $1.1 }
        }

        guard let solution = solve(normal, target) else { return nil }

        // Undo standardisation so the weights apply to raw feature values.
        var weights = [Double](repeating: 0, count: width)
        var intercept = solution[0]
        for column in 0..<width {
            let scaled = solution[column + 1] / deviations[column]
            weights[column] = scaled
            intercept -= scaled * means[column]
        }
        return (weights, intercept)
    }

    /// Gaussian elimination with partial pivoting. Nil when singular.
    static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        var a = matrix
        var b = vector
        let n = b.count

        for pivot in 0..<n {
            var maxRow = pivot
            for row in (pivot + 1)..<n where abs(a[row][pivot]) > abs(a[maxRow][pivot]) {
                maxRow = row
            }
            guard abs(a[maxRow][pivot]) > 1e-10 else { return nil }
            a.swapAt(pivot, maxRow)
            b.swapAt(pivot, maxRow)

            for row in (pivot + 1)..<n {
                let factor = a[row][pivot] / a[pivot][pivot]
                guard factor != 0 else { continue }
                for column in pivot..<n { a[row][column] -= factor * a[pivot][column] }
                b[row] -= factor * b[pivot]
            }
        }

        var solution = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for column in (row + 1)..<n { sum -= a[row][column] * solution[column] }
            solution[row] = sum / a[row][row]
        }
        return solution.allSatisfy { $0.isFinite } ? solution : nil
    }

    // MARK: Applying

    struct Adjusted: Equatable {
        var baseScore: Int
        var correction: Double
        var adjustedScore: Int
        var stage: Stage
        var modelVersion: String

        var isPersonalised: Bool { stage.isPersonalised }
        var category: SleepScore.Category { SleepScore.Category(score: adjustedScore) }
    }

    /// Applies a model to a scored night. The base score is carried through
    /// untouched alongside the adjustment.
    static func apply(model: Model, to result: SleepScore.Result, features: SleepFeatures) -> Adjusted {
        var probe = SleepScoreComparison(features: features, result: result, googleScore: 0)
        probe.baseScore = result.score

        let correction = model.correction(for: probe)
        let adjusted = Int(clampScore(Double(result.score) + correction).rounded())

        return Adjusted(
            baseScore: result.score,
            correction: round1(correction),
            adjustedScore: adjusted,
            stage: model.stage,
            modelVersion: model.modelVersion
        )
    }

    // MARK: Maths

    static func clampScore(_ value: Double) -> Double { min(100, max(0, value)) }

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
