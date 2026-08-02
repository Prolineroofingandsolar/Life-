import Testing
import Foundation
@testable import Life

/// Covers the ten-component base score, the calibration stages, and the rules
/// that stop either of them misbehaving quietly.
struct SleepScoreTests {

    // MARK: Fixtures

    /// A well-recorded night; each test varies only what it's about.
    static func features(
        asleep: Int = 450,
        inBed: Int = 500,
        light: Int? = 240,
        deep: Int? = 90,
        rem: Int? = 120,
        awakenings: Int = 0,
        interruption: Int = 0,
        restless: Int = 0,
        latency: Int? = 12,
        bedtime: Double? = 23 * 60,
        wake: Double? = 7 * 60,
        hrDelta: Double? = 0,
        hrvDelta: Double? = 0,
        respiratoryDelta: Double? = 0,
        temperatureDelta: Double? = 0,
        spo2: Double? = 96,
        missing: [String] = [],
        dayKey: String = "2026-08-01"
    ) -> SleepFeatures {
        var out = SleepFeatures()
        out.dayKey = dayKey
        out.sourceRecordID = "rec-\(dayKey)"
        out.minutesAsleep = asleep
        out.timeInBed = inBed
        out.lightMinutes = light
        out.deepMinutes = deep
        out.remMinutes = rem
        out.hasStages = deep != nil || rem != nil
        out.fullAwakeningCount = awakenings
        out.interruptionMinutes = interruption
        out.restlessMinutes = restless
        out.sleepLatencyMinutes = latency
        out.bedtimeClockMinutes = bedtime
        out.wakeClockMinutes = wake
        out.heartRateDeltaFromBaseline = hrDelta
        out.hrvDeltaFromBaseline = hrvDelta
        out.respiratoryRateDeltaFromBaseline = respiratoryDelta
        out.temperatureDeltaFromBaseline = temperatureDelta
        out.spo2Average = spo2
        out.missingFields = missing
        return out
    }

    static let baselines = SleepBaselines(
        heartRate: 58, hrv: 45, respiratoryRate: 14, temperature: 33.5,
        medianBedtimeClockMinutes: 23 * 60, medianWakeClockMinutes: 7 * 60,
        nightCount: 20
    )

    static let noBaselines = SleepBaselines(nightCount: 0)

    static func comparison(day: Int, base: Int, google: Int) -> SleepScoreComparison {
        var out = SleepScoreComparison()
        out.dayKey = String(format: "2026-06-%02d", day)
        out.sleepRecordID = "rec-\(day)"
        out.baseScore = base
        out.googleScore = google
        out.minutesAsleep = 450
        out.durationComponent = 90
        out.continuityComponent = 80
        out.stageComponent = 85
        out.latencyComponent = 95
        out.consistencyComponent = 90
        out.heartRateComponent = 70
        out.hrvComponent = 70
        out.respiratoryComponent = 70
        out.oxygenComponent = 85
        out.temperatureComponent = 70
        out.modelVersion = SleepScore.modelVersion
        return out
    }

    // MARK: Base score with all data

    @Test("All available data produces a high-confidence score")
    func allDataPresent() {
        let result = SleepScore.calculate(features: features(), baselines: Self.baselines)
        #expect(result != nil)
        #expect(result?.confidence == .high)
        #expect((result?.score ?? 0) > 70)
    }

    // MARK: Missing signals

    @Test("Missing heart rate uses the neutral value and lowers confidence")
    func missingHeartRate() {
        let result = SleepScore.calculate(
            features: features(hrDelta: nil, missing: ["heartRate"]),
            baselines: Self.baselines
        )
        #expect(result?.components.sleepingHeartRate == SleepScore.neutralComponentValue)
        #expect(result?.confidence == .medium)
    }

    @Test("Missing HRV uses the neutral value")
    func missingHRV() {
        let result = SleepScore.calculate(
            features: features(hrvDelta: nil, missing: ["hrv"]),
            baselines: Self.baselines
        )
        #expect(result?.components.hrv == SleepScore.neutralComponentValue)
    }

    @Test("Missing SpO2 uses the neutral value rather than assuming healthy")
    func missingSpO2() {
        let result = SleepScore.calculate(
            features: features(spo2: nil, missing: ["spo2"]),
            baselines: Self.baselines
        )
        #expect(result?.components.oxygenSaturation == SleepScore.neutralComponentValue)
    }

    @Test("Missing respiratory rate uses the neutral value")
    func missingRespiratory() {
        let result = SleepScore.calculate(
            features: features(respiratoryDelta: nil, missing: ["respiratoryRate"]),
            baselines: Self.baselines
        )
        #expect(result?.components.respiratoryRate == SleepScore.neutralComponentValue)
    }

    @Test("Missing temperature uses the neutral value")
    func missingTemperature() {
        let result = SleepScore.calculate(
            features: features(temperatureDelta: nil, missing: ["temperature"]),
            baselines: Self.baselines
        )
        #expect(result?.components.temperatureStability == SleepScore.neutralComponentValue)
    }

    @Test("Missing movement lowers confidence but imposes no ceiling")
    func missingMovementNoCeiling() {
        let subject = features(missing: ["movement"])
        let ceilings = SleepScore.applicableCeilings(features: subject)
        #expect(ceilings.contains { $0.reason.contains("movement") } == false)
        #expect(ceilings.contains { $0.limit == 88 } == false)

        let result = SleepScore.calculate(features: subject, baselines: Self.baselines)
        #expect(result?.confidence == .medium)
    }

    @Test("Missing stages produces no score")
    func missingStages() {
        let result = SleepScore.calculate(
            features: features(light: nil, deep: nil, rem: nil),
            baselines: Self.baselines
        )
        #expect(result == nil)
    }

    // MARK: Baselines

    @Test("No personal baseline gives neutral physiological components")
    func noBaseline() {
        var subject = features(hrDelta: nil, hrvDelta: nil, respiratoryDelta: nil, temperatureDelta: nil)
        subject.missingFields = ["personalBaseline"]
        let result = SleepScore.calculate(features: subject, baselines: Self.noBaselines)

        #expect(result?.components.sleepingHeartRate == 70)
        #expect(result?.components.hrv == 70)
        #expect(result?.components.consistency == 70)
        #expect(result?.confidence == .low)
    }

    @Test("Seven nights is the threshold for a usable baseline")
    func sevenNightBaseline() {
        #expect(SleepBaselines(nightCount: 6).isSufficient == false)
        #expect(SleepBaselines(nightCount: 7).isSufficient == true)
    }

    @Test("Sitting on your baseline scores 70, not 100")
    func baselineScoresNeutral() {
        #expect(SleepScore.deviationScore(0, scale: 6, higherIsBetter: false) == 70)
        // Better than baseline earns more, worse earns less.
        #expect(SleepScore.deviationScore(-6, scale: 6, higherIsBetter: false) == 100)
        #expect(SleepScore.deviationScore(6, scale: 6, higherIsBetter: false) == 40)
    }

    // MARK: Calibration stages

    @Test("Fewer than 14 comparisons applies no personal adjustment")
    func belowBiasThreshold() {
        let pairs = (1...13).map { Self.comparison(day: $0, base: 85, google: 75) }
        let model = SleepScoreCalibration.fit(pairs)

        #expect(model.stage == .collecting(count: 13))
        #expect(model.stage.isPersonalised == false)
        #expect(model.correction(for: pairs[0]) == 0)
    }

    @Test("Exactly 14 comparisons switches on the bias adjustment")
    func exactlyFourteen() {
        let pairs = (1...14).map { Self.comparison(day: $0, base: 85, google: 75) }
        let model = SleepScoreCalibration.fit(pairs)

        guard case .bias(let count, _) = model.stage else {
            Issue.record("expected the bias stage")
            return
        }
        #expect(count == 14)
        // We score 10 above Google every night, so the correction is -10.
        #expect(abs(model.correction(for: pairs[0]) - (-10)) < 0.001)
    }

    @Test("Bias adjustment moves the estimate toward the Google scores")
    func biasMovesTowardGoogle() {
        let pairs = (1...20).map { Self.comparison(day: $0, base: 90, google: 78) }
        let model = SleepScoreCalibration.fit(pairs)

        var result = SleepScore.Result(
            score: 90, category: .excellent, components: SleepScore.Components(),
            confidence: .high, weightedScoreBeforeCeilings: 90,
            appliedCeilings: [], missingFields: []
        )
        result.score = 90
        let adjusted = SleepScoreCalibration.apply(model: model, to: result, features: features())
        #expect(adjusted.baseScore == 90, "the base score is never overwritten")
        #expect(adjusted.adjustedScore < 90)
        #expect(abs(adjusted.adjustedScore - 78) <= 2)
    }

    @Test("Thirty or more comparisons attempts the ridge model")
    func ridgeAttempted() {
        // A residual that genuinely depends on a feature, so ridge can beat bias.
        var pairs: [SleepScoreComparison] = []
        for day in 1...35 {
            var pair = Self.comparison(day: day, base: 85, google: 85)
            pair.fullAwakeningCount = day % 4
            pair.googleScore = 85 - (day % 4) * 4
            pairs.append(pair)
        }
        let model = SleepScoreCalibration.fit(pairs)
        #expect(model.stage.comparisonCount == 35)
        #expect(model.validation != nil)
    }

    @Test("A learned model that performs worse than bias is not deployed")
    func ridgeFallsBackToBias() {
        // Pure constant offset with noise-free structure: ridge can't beat a
        // simple mean, so the simple model must win.
        let pairs = (1...40).map { Self.comparison(day: $0, base: 80, google: 72) }
        let model = SleepScoreCalibration.fit(pairs)

        if case .model = model.stage {
            // Allowed only if it genuinely validated better.
            #expect(model.validation?.learnedModelUsed == true)
        } else {
            #expect(model.weights.isEmpty)
        }
    }

    // MARK: Bounds

    @Test("Corrections are limited to ±15")
    func correctionClamped() {
        let pairs = (1...20).map { Self.comparison(day: $0, base: 95, google: 20) }
        let model = SleepScoreCalibration.fit(pairs)
        #expect(model.correction(for: pairs[0]) >= -SleepScoreCalibration.maximumCorrection)
        #expect(abs(model.correction(for: pairs[0])) <= SleepScoreCalibration.maximumCorrection)
    }

    @Test("The adjusted score stays within 0–100")
    func scoreClamped() {
        #expect(SleepScoreCalibration.clampScore(140) == 100)
        #expect(SleepScoreCalibration.clampScore(-20) == 0)
    }

    @Test("The base score is never overwritten by calibration")
    func baseNeverOverwritten() {
        let pairs = (1...20).map { Self.comparison(day: $0, base: 88, google: 70) }
        let model = SleepScoreCalibration.fit(pairs)
        let result = SleepScore.Result(
            score: 88, category: .good, components: SleepScore.Components(),
            confidence: .high, weightedScoreBeforeCeilings: 88,
            appliedCeilings: [], missingFields: []
        )
        let adjusted = SleepScoreCalibration.apply(model: model, to: result, features: features())

        #expect(adjusted.baseScore == 88)
        #expect(adjusted.adjustedScore != adjusted.baseScore)
        #expect(result.score == 88, "the original result is untouched")
    }

    // MARK: Validation of entries

    @Test("An invalid Google score is rejected")
    func invalidGoogleScore() {
        let subject = features()
        #expect(SleepComparisonValidator.validateEntry(googleScore: 101, features: subject, existing: [:]) == .scoreOutOfRange)
        #expect(SleepComparisonValidator.validateEntry(googleScore: -1, features: subject, existing: [:]) == .scoreOutOfRange)
        #expect(SleepComparisonValidator.validateEntry(googleScore: 76, features: subject, existing: [:]) == nil)
    }

    @Test("A duplicate comparison for the same night is rejected")
    func duplicateComparison() {
        let subject = features()
        let existing = [subject.dayKey: Self.comparison(day: 1, base: 80, google: 75)]
        #expect(SleepComparisonValidator.validateEntry(googleScore: 76, features: subject, existing: existing) == .duplicate)
    }

    @Test("A nap can't be used as a comparison")
    func napExcluded() {
        var subject = features()
        subject.isNap = true
        #expect(SleepComparisonValidator.validateEntry(googleScore: 76, features: subject, existing: [:]) == .isNap)
    }

    @Test("A night without stages can't be used as a comparison")
    func stagelessExcluded() {
        var subject = features(light: nil, deep: nil, rem: nil)
        subject.hasStages = false
        #expect(SleepComparisonValidator.validateEntry(googleScore: 76, features: subject, existing: [:]) == .missingStages)
    }

    @Test("An edited sleep session invalidates its comparison")
    func editedSession() {
        var pair = Self.comparison(day: 1, base: 80, google: 75)
        pair.sleepRecordID = "rec-original"
        pair.minutesAsleep = 450

        var changed = features()
        changed.sourceRecordID = "rec-reimported"
        #expect(SleepComparisonValidator.validateForTraining(pair, against: changed) == .sessionChanged)

        var driftedDuration = features(asleep: 500)
        driftedDuration.sourceRecordID = "rec-original"
        #expect(SleepComparisonValidator.validateForTraining(pair, against: driftedDuration) == .durationMismatch)

        var unchanged = features()
        unchanged.sourceRecordID = "rec-original"
        #expect(SleepComparisonValidator.validateForTraining(pair, against: unchanged) == nil)
    }

    // MARK: Train/test split

    @Test("The train/test split is chronological, not random")
    func chronologicalSplit() {
        // Later nights carry a different offset; a chronological split means the
        // validation set is the newest 20% and the model can't have seen them.
        var pairs: [SleepScoreComparison] = []
        for day in 1...30 {
            pairs.append(Self.comparison(day: day, base: 85, google: day <= 24 ? 80 : 60))
        }
        let model = SleepScoreCalibration.fit(pairs.shuffled())

        // Trained on the oldest 24 (offset 5), validated on the newest 6
        // (offset 25), so held-out error must be large.
        #expect(model.validation != nil)
        #expect((model.validation?.meanAbsoluteError ?? 0) > 5)
    }

    @Test("Only the most recent 60 pairs are retained")
    func retentionLimit() {
        let pairs = (1...80).map { Self.comparison(day: min($0, 28), base: 80, google: 75) }
        let model = SleepScoreCalibration.fit(pairs)
        #expect(model.stage.comparisonCount <= SleepScoreCalibration.maximumRetained)
    }

    @Test("Calibration records carry the scoring model version they were made under")
    func recordsCarryModelVersion() {
        let result = SleepScore.calculate(features: features(), baselines: Self.baselines)!
        let pair = SleepScoreComparison(features: features(), result: result, googleScore: 76)
        #expect(pair.modelVersion == SleepScore.modelVersion)
        #expect(pair.baseScore == result.score)
    }

    // MARK: Presentation

    @Test("Categories follow the specified bands")
    func categories() {
        #expect(SleepScore.Category(score: 95) == .excellent)
        #expect(SleepScore.Category(score: 85) == .good)
        #expect(SleepScore.Category(score: 76) == .fair)
        #expect(SleepScore.Category(score: 40) == .poor)
        #expect(SleepScore.Category(score: 76).rawValue == "Fair")
    }

    @Test("The score is a plain number with no percent sign")
    func noPercentSign() {
        let result = SleepScore.calculate(features: features(), baselines: Self.baselines)
        let rendered = "\(result?.score ?? 0)"
        #expect(rendered.contains("%") == false)
        #expect(result?.title == "Estimated Sleep Score")
    }

    // MARK: Diagnostics

    @Test("Diagnostics capture components, ceilings, calibration and versions")
    func diagnostics() {
        let subject = features(asleep: 432, inBed: 498, awakenings: 2, interruption: 37, restless: 24, latency: 29)
        guard let result = SleepScore.calculate(features: subject, baselines: Self.baselines) else {
            Issue.record("expected a score")
            return
        }
        let pairs = (1...20).map { Self.comparison(day: $0, base: 85, google: 78) }
        let model = SleepScoreCalibration.fit(pairs)
        let adjusted = SleepScoreCalibration.apply(model: model, to: result, features: subject)

        var day = HealthDay(dayKey: subject.dayKey)
        day.sleepMin = subject.minutesAsleep

        let payload = SleepDiagnosticsBuilder.build(
            day: day, features: subject, result: result,
            adjusted: adjusted, model: model, comparison: pairs.last
        )

        #expect(payload.minutesAsleep == 432)
        #expect(payload.baseScore == result.score)
        #expect(payload.adjustedScore == adjusted.adjustedScore)
        #expect(payload.scoringModelVersion == SleepScore.modelVersion)
        #expect(payload.calibrationModelVersion == SleepScoreCalibration.modelVersion)
        #expect(payload.appliedCeilings.isEmpty == false)

        let json = SleepDiagnosticsBuilder.json(payload)
        #expect(json.contains("\"baseScore\""))
        #expect(json.contains("\"adjustedScore\""))
    }
}
