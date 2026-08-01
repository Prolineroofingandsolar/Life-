import Testing
import Foundation
@testable import Life

/// Covers the scoring model: components, ceilings, confidence, and the rule
/// that missing data is never scored as perfect.
struct SleepScoreTests {

    // MARK: Helpers

    /// A well-recorded night by default; each test varies only what it's about.
    static func night(
        asleep: Int = 480,
        inBed: Int = 500,
        light: Int? = 250,
        deep: Int? = 96,
        rem: Int? = 134,
        awakenings: Int = 0,
        interruption: Int = 0,
        restless: Int = 0,
        latency: Int? = 12,
        bedtime: Double? = 23 * 60,
        wake: Double? = 7 * 60,
        heartRate: Bool = true,
        movement: Bool = true
    ) -> SleepScore.Night {
        SleepScore.Night(
            minutesAsleep: asleep,
            timeInBed: inBed,
            lightMinutes: light,
            deepMinutes: deep,
            remMinutes: rem,
            fullAwakeningCount: awakenings,
            interruptionMinutes: interruption,
            restlessMinutes: restless,
            sleepLatencyMinutes: latency,
            bedtimeClockMinutes: bedtime,
            wakeClockMinutes: wake,
            heartRateAvailable: heartRate,
            movementAvailable: movement
        )
    }

    /// A settled 14-night baseline centred on 23:00 / 07:00.
    static let baseline = SleepScore.Baseline(
        medianBedtimeClockMinutes: 23 * 60,
        medianWakeClockMinutes: 7 * 60,
        validNights: 14
    )

    static let noBaseline = SleepScore.Baseline(validNights: 0)

    // MARK: 1–4, core nights

    @Test("1. An excellent eight-hour uninterrupted night scores well")
    func excellentNight() {
        let result = SleepScore.calculate(night: night(), baseline: Self.baseline)
        #expect(result != nil)
        #expect((result?.score ?? 0) >= 85)
        #expect(result?.category == .good || result?.category == .excellent)
        #expect(result?.confidence == .high)
    }

    @Test("2. Eight hours broken by several long awakenings is capped")
    func brokenNight() {
        let result = SleepScore.calculate(
            night: night(asleep: 480, inBed: 580, awakenings: 4, interruption: 70, restless: 20),
            baseline: Self.baseline
        )
        // Four awakenings caps at 69; over 60 interruption minutes also caps at
        // 69; efficiency ~83% caps at 79. The lowest wins.
        #expect((result?.score ?? 100) <= 69)
        #expect(result?.appliedCeilings.contains { $0.contains("four or more") } == true)
    }

    @Test("3. A five-hour uninterrupted night can't score above 59")
    func shortNight() {
        let result = SleepScore.calculate(
            night: night(asleep: 300, inBed: 315, light: 160, deep: 60, rem: 80),
            baseline: Self.baseline
        )
        #expect((result?.score ?? 100) <= 59)
        #expect(result?.category == .poor)
    }

    @Test("4. Nine hours with poor efficiency is capped by efficiency, not rewarded for length")
    func longButInefficient() {
        // 540 asleep in 780 in bed = 69% efficiency.
        let result = SleepScore.calculate(
            night: night(asleep: 540, inBed: 780, light: 300, deep: 100, rem: 140,
                         awakenings: 3, interruption: 90),
            baseline: Self.baseline
        )
        #expect((result?.score ?? 100) <= 59, "efficiency under 75% caps at 59")
    }

    // MARK: 7–8, the five-minute boundary

    @Test("7. An awake interval of exactly five minutes is not a full awakening")
    func exactlyFiveMinutes() {
        let interval = SleepInterval(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 300),
            stage: .awake
        )
        #expect(interval.minutes == 5)
        #expect(interval.minutes > SleepAnalysis.fullAwakeningThresholdMinutes == false)
    }

    @Test("8. An awake interval longer than five minutes is a full awakening and costs points")
    func longerThanFiveMinutes() {
        let clean = SleepScore.calculate(night: night(), baseline: Self.baseline)
        let broken = SleepScore.calculate(
            night: night(awakenings: 1, interruption: 6),
            baseline: Self.baseline
        )
        #expect((broken?.score ?? 0) < (clean?.score ?? 0))
    }

    // MARK: 9–12, missing data

    @Test("9. Missing heart-rate data caps the score at 88 and lowers confidence")
    func missingHeartRate() {
        let result = SleepScore.calculate(night: night(heartRate: false), baseline: Self.baseline)
        #expect((result?.score ?? 100) <= 88)
        #expect(result?.missingFields.contains("heartRate") == true)
        #expect(result?.confidence == .medium)
    }

    @Test("10. Missing movement data caps the score at 88")
    func missingMovement() {
        let result = SleepScore.calculate(night: night(movement: false), baseline: Self.baseline)
        #expect((result?.score ?? 100) <= 88)
        #expect(result?.missingFields.contains("movement") == true)
    }

    @Test("11. Missing latency uses the neutral value, not a perfect one")
    func missingLatency() {
        let result = SleepScore.calculate(night: night(latency: nil), baseline: Self.baseline)
        #expect(result?.components.latency == SleepScore.neutralComponentValue)
        #expect(result?.missingFields.contains("latency") == true)
        #expect(result?.confidence == .low)
    }

    @Test("12. Missing stages produces no score at all")
    func missingStages() {
        let result = SleepScore.calculate(
            night: night(light: nil, deep: nil, rem: nil),
            baseline: Self.baseline
        )
        #expect(result == nil)
    }

    // MARK: 18–20

    @Test("18. A new user without a baseline gets a neutral consistency score")
    func newUserNoBaseline() {
        let result = SleepScore.calculate(night: night(), baseline: Self.noBaseline)
        #expect(result?.components.consistency == SleepScore.neutralComponentValue)
        #expect(result?.missingFields.contains("consistencyBaseline") == true)
        #expect(result?.confidence == .low)
    }

    @Test("19. Excessively long sleep is not rewarded indefinitely")
    func excessiveSleep() {
        let eight = SleepScore.durationScore(minutesAsleep: 480)
        let eleven = SleepScore.durationScore(minutesAsleep: 660)
        let fourteen = SleepScore.durationScore(minutesAsleep: 840)

        #expect(eight == 100)
        #expect(eleven < eight)
        #expect(fourteen <= eleven, "beyond the table it clamps rather than climbing")
    }

    @Test("20. No missing value ever defaults to 100")
    func missingNeverScoresPerfect() {
        #expect(SleepScore.neutralComponentValue == 70)

        let everythingMissing = SleepScore.calculate(
            night: night(latency: nil, heartRate: false, movement: false),
            baseline: Self.noBaseline
        )
        #expect(everythingMissing?.components.latency == 70)
        #expect(everythingMissing?.components.consistency == 70)
        #expect((everythingMissing?.score ?? 100) <= 88)
        #expect(everythingMissing?.confidence == .low)
    }

    // MARK: Component tables

    @Test("Duration interpolates between the specified points")
    func durationTable() {
        #expect(SleepScore.durationScore(minutesAsleep: 0) == 0)
        #expect(SleepScore.durationScore(minutesAsleep: 240) == 20)
        #expect(SleepScore.durationScore(minutesAsleep: 420) == 82)
        #expect(SleepScore.durationScore(minutesAsleep: 480) == 100)
        #expect(SleepScore.durationScore(minutesAsleep: 540) == 95)
        // Midpoint of 420→480 is (82+100)/2 = 91.
        #expect(abs(SleepScore.durationScore(minutesAsleep: 450) - 91) < 0.001)
    }

    @Test("Latency peaks in the 10–20 minute band, not at zero")
    func latencyTable() {
        #expect(SleepScore.latencyScore(minutes: 0) == 80)
        #expect(SleepScore.latencyScore(minutes: 10) == 100)
        #expect(SleepScore.latencyScore(minutes: 20) == 100)
        #expect(SleepScore.latencyScore(minutes: 60) == 40)
        #expect(SleepScore.latencyScore(minutes: 0) < SleepScore.latencyScore(minutes: 10))
    }

    @Test("Continuity subtracts awakenings, interruptions and restlessness")
    func continuityPenalties() {
        let clean = SleepScore.continuityScore(night: night(asleep: 480, inBed: 500))
        let penalised = SleepScore.continuityScore(
            night: night(asleep: 480, inBed: 500, awakenings: 2, interruption: 40, restless: 30)
        )
        // 2 awakenings = -12, 40 interruption minutes = -14, restless capped at -3.
        #expect(abs((clean - penalised) - 29) < 0.5)
    }

    @Test("Restorative sleep peaks at healthy deep and REM shares and falls away either side")
    func restorativeCurve() {
        let low = SleepScore.restorativeScore(night: night(asleep: 480, deep: 10, rem: 20))
        let healthy = SleepScore.restorativeScore(night: night(asleep: 480, deep: 96, rem: 115))
        let excessive = SleepScore.restorativeScore(night: night(asleep: 480, deep: 200, rem: 220))

        #expect((low ?? 0) < (healthy ?? 0))
        #expect((excessive ?? 0) < (healthy ?? 0))
    }

    @Test("Consistency scores the deviation from the rolling median, wrapping midnight")
    func consistencyWrapsMidnight() {
        // 23:50 and 00:10 are twenty minutes apart, not 1,420.
        #expect(SleepScore.circularClockDifference(23 * 60 + 50, 10) == 20)
        #expect(SleepScore.consistencyScore(averageDeviation: 0) == 100)
        #expect(SleepScore.consistencyScore(averageDeviation: 60) == 70)
        #expect(SleepScore.consistencyScore(averageDeviation: 240) == 10)
    }

    @Test("Median bedtime is computed around midnight, not the middle of the day")
    func medianAcrossMidnight() {
        // 23:00, 23:30 and 00:30 — the median is 23:30, not midday.
        let median = SleepScore.medianClockMinutes([23 * 60, 23 * 60 + 30, 30])
        #expect(median == 23 * 60 + 30)
    }

    // MARK: Ceilings and rounding

    @Test("The lowest applicable ceiling wins")
    func lowestCeilingWins() {
        let ceilings = SleepScore.applicableCeilings(
            night: night(asleep: 300, inBed: 450, awakenings: 4, interruption: 80)
        )
        #expect(ceilings.map(\.limit).min() == 49 || ceilings.map(\.limit).min() == 59)
        #expect(ceilings.count >= 3, "duration, efficiency, interruptions and awakenings all apply")
    }

    @Test("Ceilings can only lower a score, never raise it")
    func ceilingsOnlyLower() {
        let poor = SleepScore.calculate(
            night: night(asleep: 200, inBed: 400, light: 100, deep: 40, rem: 60,
                         awakenings: 5, interruption: 120),
            baseline: Self.baseline
        )
        #expect((poor?.score ?? 100) <= 49)
    }

    @Test("A score is a 0–100 number and never a percentage")
    func scoreIsNotAPercentage() {
        let result = SleepScore.calculate(night: night(), baseline: Self.baseline)
        let score = result?.score ?? -1
        #expect(score >= 0 && score <= 100)
        // The category vocabulary is the specified one.
        #expect(SleepScore.Category(score: 95) == .excellent)
        #expect(SleepScore.Category(score: 85) == .good)
        #expect(SleepScore.Category(score: 76) == .fair)
        #expect(SleepScore.Category(score: 40) == .poor)
    }

    // MARK: Diagnostics

    @Test("Diagnostics report the components, ceilings and confidence for a night")
    func diagnosticsOutput() {
        let subject = night(asleep: 432, inBed: 498, light: 288, deep: 61, rem: 83,
                            awakenings: 2, interruption: 37, restless: 24, latency: 29)
        guard let result = SleepScore.calculate(night: subject, baseline: Self.baseline) else {
            Issue.record("expected a score")
            return
        }
        let diagnostics = SleepScore.diagnostics(night: subject, result: result)

        #expect(diagnostics.minutesAsleep == 432)
        #expect(diagnostics.timeInBed == 498)
        #expect(abs(diagnostics.sleepEfficiency - 0.867) < 0.002)
        #expect(diagnostics.fullAwakeningCount == 2)
        #expect(diagnostics.finalScore == result.score)
        #expect(diagnostics.appliedCeilings.isEmpty == false)

        let json = SleepScore.diagnosticsJSON(night: subject, result: result)
        #expect(json.contains("\"finalScore\""))
        #expect(json.contains("\"appliedCeilings\""))
    }
}
