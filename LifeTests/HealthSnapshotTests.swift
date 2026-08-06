import Testing
import Foundation
@testable import Life

/// The canonical snapshot, and the five states it has to keep apart.
///
/// These are written against four specific contradictions that were on screen at
/// the same time:
///
/// - Today: "10h 17m slept". Ask Coach: "471 minutes".
/// - Today: no recovery data. Health: HRV 79 ms, resting HR 59 bpm.
/// - Today: no steps. Ask Coach: steps and active minutes, both populated.
/// - A measurement visibly present, and a coach saying "no recovery data".
///
/// Every one of them came from a consumer applying its own rule for whether a
/// figure existed. The assertions below are mostly about *which* absence the
/// snapshot reports, because that is the distinction each of those bugs lost.
@MainActor
struct HealthSnapshotTests {

    // MARK: Fixtures

    static func emptyState() -> AppState {
        let state = AppState()
        state.tasks = []
        state.habits = []
        state.sessions = []
        state.healthDays = [:]
        state.careDays = [:]
        state.weightEntries = []
        state.plannedSessions = []
        state.healthSettings = HealthSettings()
        state.careSettings = CareSettings()
        state.workoutSettings = WorkoutSettings()
        return state
    }

    static func key(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return date.dayKey
    }

    static func day(
        _ key: String,
        sleepMin: Int? = nil,
        stageCoverage: Double? = nil,
        restingHr: Double? = nil,
        hrvMs: Double? = nil,
        exerciseMinutes: Int? = nil
    ) -> HealthDay {
        var d = HealthDay(dayKey: key)
        d.sleepMin = sleepMin
        d.stageCoverage = stageCoverage
        d.restingHr = restingHr
        d.hrvMs = hrvMs
        d.exerciseMinutes = exerciseMinutes
        return d
    }

    /// A state with enough nights behind it for a baseline to exist.
    static func stateWithHistory(nights: Int, hrv: Double = 60, rhr: Double = 60) -> AppState {
        let state = emptyState()
        for offset in stride(from: nights, through: 1, by: -1) {
            let key = Self.key(daysAgo: offset)
            state.healthDays[key] = day(key, sleepMin: 450, stageCoverage: 0.9, restingHr: rhr, hrvMs: hrv)
        }
        return state
    }

    // MARK: Missing against insufficient history

    @Test("Nothing recorded is missing, and says there is no data")
    func nothingRecordedIsMissing() {
        let snapshot = HealthSnapshotBuilder.build(appState: Self.emptyState())

        #expect(snapshot.hrvMs.state == .missing)
        #expect(snapshot.hrvMs.value == nil)
        #expect(snapshot.restingHeartRate.state == .missing)
        #expect(snapshot.readiness.state == .missing)
        #expect(snapshot.recoveryStatement.contains("No recovery data"))
        #expect(snapshot.hasAnyMeasurement == false)
    }

    @Test("A reading with too little history keeps its value and says why it can't be read")
    func readingWithoutBaselineIsNotMissing() {
        // Four nights. Real measurements, no baseline — the exact situation that
        // produced "No recovery data" underneath a visible HRV of 79.
        let state = Self.stateWithHistory(nights: 4, hrv: 79, rhr: 59)
        let snapshot = HealthSnapshotBuilder.build(appState: state)

        #expect(snapshot.hrvMs.state == .insufficientHistory)
        #expect(snapshot.hrvMs.value == 79)
        #expect(snapshot.restingHeartRate.state == .insufficientHistory)
        #expect(snapshot.restingHeartRate.value == 59)

        // The sentence itself, because this is the one users read.
        #expect(snapshot.recoveryStatement.contains("Not enough history"))
        #expect(!snapshot.recoveryStatement.contains("No recovery data"))
        #expect(snapshot.hasAnyMeasurement)
    }

    @Test("The insufficient-history statement says how far along the baseline is")
    func insufficientHistoryReportsProgress() {
        let state = Self.stateWithHistory(nights: 4, hrv: 79, rhr: 59)
        let snapshot = HealthSnapshotBuilder.build(appState: state)

        #expect(snapshot.hrvMs.sampleCount == 4)
        #expect(snapshot.hrvMs.requiredSamples == HealthSnapshot.baselineSampleRequirement)
        #expect(snapshot.recoveryStatement.contains("4 of \(HealthSnapshot.baselineSampleRequirement)"))
    }

    @Test("Enough history makes a reading interpretable")
    func enoughHistoryIsReady() {
        let state = Self.stateWithHistory(nights: 20, hrv: 79, rhr: 59)
        let snapshot = HealthSnapshotBuilder.build(appState: state)

        #expect(snapshot.hrvMs.state == .ready)
        #expect(snapshot.restingHeartRate.state == .ready)
        #expect(snapshot.readiness.state == .ready)
        #expect(snapshot.readiness.value != nil)
    }

    // MARK: Staleness

    @Test("An overnight reading from a week ago is stale, not current")
    func oldOvernightReadingIsStale() {
        let state = Self.emptyState()
        for offset in stride(from: 20, through: 7, by: -1) {
            let key = Self.key(daysAgo: offset)
            state.healthDays[key] = Self.day(key, sleepMin: 450, stageCoverage: 0.9, restingHr: 59, hrvMs: 79)
        }

        let snapshot = HealthSnapshotBuilder.build(appState: state)

        #expect(snapshot.hrvMs.state == .stale)
        // The value is kept. A stale reading is still the most recent thing
        // known, and hiding it leaves the screen looking like nothing was ever
        // recorded — which is a different problem with a different fix.
        #expect(snapshot.hrvMs.value == 79)
        #expect(snapshot.sleepMinutes.state == .stale)
    }

    @Test("Last night's reading is current even before this morning's sync")
    func yesterdaysOvernightReadingIsCurrent() {
        let state = Self.stateWithHistory(nights: 15)
        // Nothing filed under today yet: the tracker hasn't synced since waking.
        state.healthDays[Date().dayKey] = nil

        let snapshot = HealthSnapshotBuilder.build(appState: state)

        // Calling this stale would flag every morning as a problem.
        #expect(snapshot.hrvMs.state != .stale)
        #expect(snapshot.sleepMinutes.state != .stale)
    }

    // MARK: Steps

    @Test("No step record is missing, not zero")
    func missingStepsAreNotZero() {
        let snapshot = HealthSnapshotBuilder.build(appState: Self.emptyState())

        #expect(snapshot.steps.state == .missing)
        #expect(snapshot.steps.value == nil)
    }

    @Test("Today's steps are partial, because the day is not over")
    func todaysStepsArePartial() {
        let state = Self.emptyState()
        var care = CareDay(dayKey: state.todayKey)
        care.steps = 6969
        state.careDays[state.todayKey] = care

        let snapshot = HealthSnapshotBuilder.build(appState: state)

        #expect(snapshot.steps.value == 6969)
        #expect(snapshot.steps.state == .partial)
    }

    @Test("Yesterday's steps do not stand in for today's")
    func yesterdaysStepsAreNotTodays() {
        let state = Self.emptyState()
        var care = CareDay(dayKey: Self.key(daysAgo: 1))
        care.steps = 12_000
        state.careDays[Self.key(daysAgo: 1)] = care

        let snapshot = HealthSnapshotBuilder.build(appState: state)

        // A step count is a property of a day, not a rolling figure. Showing
        // yesterday's under today's heading is the "no steps" contradiction in
        // reverse.
        #expect(snapshot.steps.state == .missing)
    }

    // MARK: One formatting, one figure

    @Test("Sleep is carried as minutes and formatted once, the same way everywhere")
    func sleepIsFormattedConsistently() {
        let state = Self.stateWithHistory(nights: 12)
        let key = Date().dayKey
        state.healthDays[key] = Self.day(key, sleepMin: 471, stageCoverage: 0.9, restingHr: 59, hrvMs: 79)

        let snapshot = HealthSnapshotBuilder.build(appState: state)
        let context = CoachContextBuilder.build(appState: state, snapshot: snapshot)

        #expect(snapshot.sleepMinutes.value == 471)
        // Today reads the minutes and formats them; the coach is handed the
        // formatted string. Both go through `HealthInsights.formatDuration`, so
        // "471 minutes" cannot reappear on one screen while "7h 51m" is on the
        // other.
        #expect(HealthInsights.formatDuration(471) == "7h 51m")
        #expect(context.sleep?.durationText == "7h 51m")
        #expect(context.sleep?.durationMinutes == 471)
    }

    // MARK: The coach agrees with the screen

    @Test("A measurement without a baseline reaches the coach as a measurement")
    func coachIsToldTheMeasurementExists() {
        let state = Self.stateWithHistory(nights: 4, hrv: 79, rhr: 59)
        let snapshot = HealthSnapshotBuilder.build(appState: state)
        let context = CoachContextBuilder.build(appState: state, snapshot: snapshot)

        // The old builder returned nil here and warned "No recovery data",
        // which is what the coach then repeated back over a visible reading.
        #expect(context.recovery != nil)
        #expect(context.recovery?.hasHrvMeasurement == true)
        #expect(context.recovery?.hasRestingHeartRateMeasurement == true)
        #expect(context.recovery?.state == .insufficientHistory)
        #expect(context.recovery?.readinessScore == nil)
        #expect(context.dataWarnings.contains { $0.contains("Not enough history") })
        #expect(!context.dataWarnings.contains { $0.contains("No recovery data") })
    }

    @Test("The context and the screen quote the same day")
    func contextAndSnapshotShareADay() {
        let state = Self.stateWithHistory(nights: 12)
        let snapshot = HealthSnapshotBuilder.build(appState: state)
        let context = CoachContextBuilder.build(appState: state, snapshot: snapshot)

        #expect(context.dayKey == snapshot.dayKey)
        #expect(context.timeZoneIdentifier == snapshot.timeZoneIdentifier)
    }

    // MARK: Hashing

    @Test("Timestamps alone do not change the material hash")
    func timestampsDoNotChangeTheHash() {
        let state = Self.stateWithHistory(nights: 12)
        var first = HealthSnapshotBuilder.build(appState: state, now: Date())
        var second = first
        second.generatedAt = first.generatedAt.addingTimeInterval(3600)
        second.lastSyncedAt = Date()
        first.lastSyncedAt = Date().addingTimeInterval(-9000)

        // This is what stops a two-minute foreground poll costing a model call
        // every two minutes: a sync that brought nothing new must produce the
        // same key it did before.
        #expect(first.materialHash == second.materialHash)
    }

    @Test("A changed figure changes the material hash")
    func changedFiguresChangeTheHash() {
        let before = HealthSnapshotBuilder.build(appState: Self.stateWithHistory(nights: 12, hrv: 60))
        let after = HealthSnapshotBuilder.build(appState: Self.stateWithHistory(nights: 12, hrv: 90))

        #expect(before.materialHash != after.materialHash)
    }

    @Test("A state change alone changes the material hash")
    func changedStateChangesTheHash() {
        // Same HRV reading in both. The only difference is whether there is
        // enough history to interpret it — which changes the advice completely,
        // and which a hash built from values alone would miss.
        let thin = HealthSnapshotBuilder.build(appState: Self.stateWithHistory(nights: 4, hrv: 70))
        let thick = HealthSnapshotBuilder.build(appState: Self.stateWithHistory(nights: 20, hrv: 70))

        #expect(thin.hrvMs.value == thick.hrvMs.value)
        #expect(thin.hrvMs.state != thick.hrvMs.state)
        #expect(thin.materialHash != thick.materialHash)
    }

    @Test("Steps do not disturb the overnight hash")
    func stepsDoNotInvalidateBriefings() {
        let state = Self.stateWithHistory(nights: 12)
        let morning = HealthSnapshotBuilder.build(appState: state)

        var care = CareDay(dayKey: state.todayKey)
        care.steps = 8_000
        state.careDays[state.todayKey] = care
        state.invalidateHealthSnapshot()
        let later = HealthSnapshotBuilder.build(appState: state)

        // A briefing is a statement about the morning. Walking during the day
        // must not make it look outdated; last night's sleep arriving late must.
        #expect(morning.overnightHash == later.overnightHash)
        #expect(morning.materialHash != later.materialHash)
    }

    @Test("Late-arriving sleep does disturb the overnight hash")
    func lateSleepInvalidatesBriefings() {
        let state = Self.stateWithHistory(nights: 12)
        let before = HealthSnapshotBuilder.build(appState: state)

        let key = Date().dayKey
        state.healthDays[key] = Self.day(key, sleepMin: 500, stageCoverage: 0.9)
        state.invalidateHealthSnapshot()
        let after = HealthSnapshotBuilder.build(appState: state)

        #expect(before.overnightHash != after.overnightHash)
    }

    @Test("A metric can never carry a value while claiming to be missing")
    func missingNeverCarriesAValue() {
        // The invariant every consumer relies on to decide whether to draw a
        // number. Enforced in the initialiser so no builder can break it.
        let contradiction = HealthMetric<Int>(value: 42, state: .missing, confidence: .high)
        #expect(contradiction.value == nil)

        let alsoContradiction = HealthMetric<Int>(value: nil, state: .ready, confidence: .high)
        #expect(alsoContradiction.state == .missing)
    }
}
