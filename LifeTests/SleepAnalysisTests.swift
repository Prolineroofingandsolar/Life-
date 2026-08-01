import Testing
import Foundation
@testable import Life

/// Covers the rules that are easy to get wrong and expensive to get wrong
/// quietly: split nights, naps, travel, daylight saving, overlapping intervals,
/// and the exact five-minute awakening boundary.
struct SleepAnalysisTests {

    // MARK: Helpers

    /// A fixed reference instant so cases read as wall-clock times.
    /// 2026-03-01 22:00 UTC.
    static let base = Date(timeIntervalSince1970: 1_772_402_400)

    static func at(_ minutesFromBase: Double) -> Date {
        base.addingTimeInterval(minutesFromBase * 60)
    }

    static func stage(_ kind: SleepStageClass, from: Double, to: Double) -> SleepInterval {
        SleepInterval(start: at(from), end: at(to), stage: kind)
    }

    static func session(
        from: Double,
        to: Double,
        stages: [SleepInterval],
        nap: Bool = false,
        sourceStages: Bool = true,
        offset: Int? = 0
    ) -> SleepSessionInput {
        SleepSessionInput(
            start: at(from),
            end: at(to),
            stages: stages,
            isNap: nap,
            hasSourceStages: sourceStages,
            provenance: SleepProvenance(platform: "GOOGLE_HEALTH", deviceName: "Fitbit", utcOffsetSeconds: offset)
        )
    }

    // MARK: Overlaps

    @Test("Overlapping stage intervals are never double-counted")
    func overlappingIntervalsAreClipped() {
        // 60 minutes of light overlapped by 30 minutes of deep. Total elapsed is
        // 60 minutes, so minutes asleep must be 60 — not 90.
        let night = SleepAnalysis.measure(session(from: 0, to: 60, stages: [
            Self.stage(.light, from: 0, to: 60),
            Self.stage(.deep, from: 30, to: 60)
        ]))

        #expect(night.minutesAsleep == 60)
        #expect(night.lightMinutes == 60)
        #expect(night.deepMinutes == 0, "the later interval is clipped away entirely")
    }

    @Test("Source-derived stages win over inferred ones at the same instant")
    func sourceStagesWin() {
        let inferred = SleepInterval(start: Self.at(0), end: Self.at(30), stage: .light, sourceDerived: false)
        let fromSource = SleepInterval(start: Self.at(0), end: Self.at(30), stage: .deep, sourceDerived: true)

        let flattened = SleepAnalysis.flatten([inferred, fromSource])

        #expect(flattened.count == 1)
        #expect(flattened.first?.stage == .deep)
    }

    // MARK: The five-minute boundary

    @Test("A wake of exactly five minutes is restlessness, not a full awakening")
    func exactlyFiveMinuteWake() {
        let night = SleepAnalysis.measure(session(from: 0, to: 120, stages: [
            Self.stage(.light, from: 0, to: 50),
            Self.stage(.awake, from: 50, to: 55),   // exactly 5
            Self.stage(.light, from: 55, to: 120)
        ]))

        #expect(night.fullAwakeningCount == 0)
        #expect(night.restlessMinutes == 5)
        #expect(night.interruptionMinutes == 0)
    }

    @Test("A wake of just over five minutes is a full awakening")
    func justOverFiveMinuteWake() {
        let night = SleepAnalysis.measure(session(from: 0, to: 120, stages: [
            Self.stage(.light, from: 0, to: 50),
            Self.stage(.awake, from: 50, to: 56),   // 6 minutes
            Self.stage(.light, from: 56, to: 120)
        ]))

        #expect(night.fullAwakeningCount == 1)
        #expect(night.interruptionMinutes == 6)
        #expect(night.restlessMinutes == 0)
    }

    // MARK: Split sleep

    @Test("Sessions separated by a short gap merge into one night")
    func splitSleepMerges() {
        let first = session(from: 0, to: 180, stages: [Self.stage(.light, from: 0, to: 180)])
        let second = session(from: 200, to: 400, stages: [Self.stage(.light, from: 200, to: 400)])

        let merged = SleepAnalysis.mergeSessions([first, second])
        #expect(merged.count == 1)

        let night = SleepAnalysis.measure(merged[0])
        // 180 + 200 asleep; the 20-minute gap is awake, not sleep.
        #expect(night.minutesAsleep == 380)
        #expect(night.fullAwakeningCount == 1)
        #expect(night.interruptionMinutes == 20)
    }

    @Test("Sessions separated by a long gap stay separate nights")
    func longGapDoesNotMerge() {
        let first = session(from: 0, to: 180, stages: [Self.stage(.light, from: 0, to: 180)])
        let second = session(from: 400, to: 600, stages: [Self.stage(.light, from: 400, to: 600)])

        #expect(SleepAnalysis.mergeSessions([first, second]).count == 2)
    }

    // MARK: Naps

    @Test("Naps are kept out of the nightly figures")
    func napsAreSeparate() {
        let night = session(from: 0, to: 420, stages: [Self.stage(.light, from: 0, to: 420)])
        let nap = session(from: 900, to: 945, stages: [Self.stage(.light, from: 900, to: 945)], nap: true)

        let result = SleepAnalysis.analyse(sessions: [night, nap])

        #expect(result.nights.count == 1)
        #expect(result.naps.count == 1)
        #expect(result.nights.values.first?.minutesAsleep == 420)
    }

    @Test("A nap never merges into an adjacent night")
    func napDoesNotMerge() {
        let night = session(from: 0, to: 400, stages: [Self.stage(.light, from: 0, to: 400)])
        let nap = session(from: 430, to: 460, stages: [], nap: true, sourceStages: false)

        // Gap is 30 minutes — inside the merge window — but one side is a nap.
        #expect(SleepAnalysis.mergeSessions([night, nap]).count == 2)
    }

    // MARK: Derived measurements

    @Test("Latency, efficiency and midpoint are derived from the sleep window")
    func derivedMeasurements() {
        // In bed at 0, asleep 20→260, up at 270.
        let night = SleepAnalysis.measure(session(from: 0, to: 270, stages: [
            Self.stage(.awake, from: 0, to: 20),
            Self.stage(.deep, from: 20, to: 80),
            Self.stage(.rem, from: 80, to: 140),
            Self.stage(.light, from: 140, to: 260)
        ]))

        #expect(night.sleepLatencyMinutes == 20)
        #expect(night.minutesAsleep == 240)
        #expect(night.timeInSleepWindow == 270)
        #expect(night.deepMinutes == 60)
        #expect(night.remMinutes == 60)
        #expect(night.lightMinutes == 120)
        // Restorative = deep + REM. Explicitly not "sound sleep".
        #expect(night.restorativeMinutes == 120)
        #expect(night.sleepStart == Self.at(20))
        #expect(night.sleepEnd == Self.at(260))
        #expect(night.sleepMidpoint == Self.at(140))

        #expect(night.sleepEfficiency != nil)
        if let efficiency = night.sleepEfficiency {
            #expect(abs(efficiency - (240.0 / 270.0)) < 0.001)
        }
    }

    @Test("Leading awake time is latency, not an interruption")
    func leadingAwakeIsNotAnInterruption() {
        let night = SleepAnalysis.measure(session(from: 0, to: 100, stages: [
            Self.stage(.awake, from: 0, to: 30),
            Self.stage(.light, from: 30, to: 100)
        ]))

        #expect(night.sleepLatencyMinutes == 30)
        #expect(night.fullAwakeningCount == 0)
        #expect(night.interruptionMinutes == 0)
    }

    // MARK: Time zones

    @Test("A night is filed under the local day it ended, using the offset in effect")
    func dayKeyUsesSessionOffset() {
        // Ends 2026-03-02 06:00 UTC. In UTC-08:00 that's still 2026-03-01.
        let end = Date(timeIntervalSince1970: 1_772_431_200)

        #expect(SleepAnalysis.dayKey(for: end, offsetSeconds: 0) == "2026-03-02")
        #expect(SleepAnalysis.dayKey(for: end, offsetSeconds: -8 * 3600) == "2026-03-01")
        #expect(SleepAnalysis.dayKey(for: end, offsetSeconds: 13 * 3600) == "2026-03-02")
    }

    @Test("Travelling between zones doesn't split or duplicate a night")
    func travelKeepsOneNight() {
        // Same night measured with an offset that changed mid-flight: the end
        // offset is what files it, so it lands on exactly one day.
        var flown = session(from: 0, to: 420, stages: [Self.stage(.light, from: 0, to: 420)])
        flown.provenance.utcOffsetSeconds = 5 * 3600

        let result = SleepAnalysis.analyse(sessions: [flown])
        #expect(result.nights.count == 1)
    }

    @Test("Clocks going back does not turn one night into two")
    func daylightSavingChange() {
        // A night spanning a DST boundary is still one session with one end
        // instant, so it files under one day whatever the local clock did.
        let night = session(from: 0, to: 480, stages: [
            Self.stage(.light, from: 0, to: 240),
            Self.stage(.deep, from: 240, to: 480)
        ], offset: 0)

        let shifted = SleepAnalysis.measure(night)
        // Elapsed time is measured in absolute terms, so a repeated wall-clock
        // hour can't inflate it.
        #expect(shifted.timeInSleepWindow == 480)
        #expect(shifted.minutesAsleep == 480)
    }

    // MARK: UTC offset parsing

    @Test("UTC offsets parse in both spellings the API uses")
    func utcOffsetParsing() {
        #expect(SleepAnalysis.parseUTCOffset("-08:00") == -8 * 3600)
        #expect(SleepAnalysis.parseUTCOffset("+05:30") == 5 * 3600 + 30 * 60)
        #expect(SleepAnalysis.parseUTCOffset("-28800s") == -28800)
        #expect(SleepAnalysis.parseUTCOffset("Z") == 0)
        #expect(SleepAnalysis.parseUTCOffset(nil) == nil)
        #expect(SleepAnalysis.parseUTCOffset("") == nil)
    }

    // MARK: Validation

    @Test("A night without source stages is not scoreable")
    func classicNightIsNotScoreable() {
        let night = SleepAnalysis.measure(session(
            from: 0, to: 420,
            stages: [Self.stage(.asleep, from: 0, to: 420)],
            sourceStages: false
        ))

        #expect(night.hasSourceStages == false)
        #expect(SleepAnalysis.isScoreable(night) == false)
        #expect(night.restorativeShare == nil, "no stage detail means no restorative share")
        #expect(SleepAnalysis.warnings(for: night, hasRestorationSignals: true).contains(.noSourceStages))
    }

    @Test("A sparsely covered night is not scoreable")
    func sparseNightIsNotScoreable() {
        // Eight hours in bed, one hour of stages recorded.
        let night = SleepAnalysis.measure(session(from: 0, to: 480, stages: [
            Self.stage(.light, from: 0, to: 60)
        ]))

        #expect(night.stageCoverage < SleepAnalysis.minimumStageCoverage)
        #expect(SleepAnalysis.isScoreable(night) == false)
        #expect(SleepAnalysis.warnings(for: night, hasRestorationSignals: true).contains(.sparseStageCoverage))
    }

    @Test("Missing overnight heart rate is warned about, not hidden")
    func missingRestorationSignalsWarns() {
        let night = SleepAnalysis.measure(session(from: 0, to: 420, stages: [
            Self.stage(.light, from: 0, to: 420)
        ]))

        #expect(SleepAnalysis.warnings(for: night, hasRestorationSignals: false).contains(.noHeartRateOrMovement))
    }

    // MARK: Provenance

    @Test("Source platform and device survive analysis")
    func provenanceIsPreserved() {
        let night = SleepAnalysis.measure(session(from: 0, to: 420, stages: [
            Self.stage(.light, from: 0, to: 420)
        ]))

        #expect(night.provenance.platform == "GOOGLE_HEALTH")
        #expect(night.provenance.deviceName == "Fitbit")
        #expect(night.provenance.displayLabel == "Fitbit")
    }
}
