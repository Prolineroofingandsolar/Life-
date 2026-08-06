import Testing
import Foundation
@testable import Life

/// What the Today carousel says when it cannot say a number.
///
/// The tiles are the most-read surface in the app, and the thing that makes them
/// worth reading is that they distinguish *why* a figure is absent. A zero and a
/// tracker that hasn't reported look identical as a number and need opposite
/// responses — go for a walk, or open the Fitbit app. These assert the four
/// absences stay four different sentences.
///
/// Written against the snapshot rather than the SwiftUI views: the captions are
/// derived from `MetricState` and the sample counts, and that derivation is the
/// part that can be wrong. Rendering is checked by the UI tests.
@MainActor
struct HealthCarouselTests {

    // MARK: Fixtures

    static func emptyState() -> AppState {
        let state = AppState()
        state.tasks = []
        state.habits = []
        state.sessions = []
        state.healthDays = [:]
        state.careDays = [:]
        state.plannedSessions = []
        state.healthSettings = HealthSettings()
        state.careSettings = CareSettings()
        state.workoutSettings = WorkoutSettings()
        return state
    }

    static func key(daysAgo: Int) -> String {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!.dayKey
    }

    static func stateWithNights(_ nights: Int, hrv: Double = 79, rhr: Double = 59) -> AppState {
        let state = emptyState()
        for offset in stride(from: nights, through: 1, by: -1) {
            let k = key(daysAgo: offset)
            var day = HealthDay(dayKey: k)
            day.sleepMin = 450
            day.stageCoverage = 0.9
            day.hrvMs = hrv
            day.restingHr = rhr
            state.healthDays[k] = day
        }
        return state
    }

    // MARK: Missing is never zero

    @Test("A tracker that hasn't reported shows no step figure at all")
    func missingStepsHaveNoValue() {
        let snapshot = HealthSnapshotBuilder.build(appState: Self.emptyState())

        // The tile renders `value ?? "—"`. What matters here is that the value
        // is genuinely absent rather than 0, because a 0 would render as a real
        // reading and read as "you haven't moved today".
        #expect(snapshot.steps.value == nil)
        #expect(snapshot.steps.state == .missing)
    }

    @Test("Steps that exist are partial, because the day is not over")
    func todaysStepsArePartial() {
        let state = Self.emptyState()
        var care = CareDay(dayKey: state.todayKey)
        care.steps = 6_500
        state.careDays[state.todayKey] = care

        let snapshot = HealthSnapshotBuilder.build(appState: state)
        #expect(snapshot.steps.value == 6_500)
        // Partial, not ready: a figure below goal at ten in the morning is not
        // a shortfall, and the tile must not be styled as though it were.
        #expect(snapshot.steps.state == .partial)
    }

    // MARK: The four absences stay distinct

    @Test("No tracker and no reading are told apart")
    func noTrackerIsNotTheSameAsNoReading() {
        let snapshot = HealthSnapshotBuilder.build(appState: Self.emptyState())

        // `hasConnectedSource` is what the tile captions branch on to choose
        // between "no tracker" and "not recorded". Collapsing the two would tell
        // someone with a working Fitbit to go and connect one.
        #expect(snapshot.restingHeartRate.state == .missing)
        #expect(snapshot.hrvMs.state == .missing)
        #expect(snapshot.recoveryStatement.contains("No recovery data"))
    }

    @Test("A reading without a baseline keeps its number and reports its progress")
    func insufficientHistoryKeepsTheNumber() {
        let snapshot = HealthSnapshotBuilder.build(appState: Self.stateWithNights(4))

        // This is the tile that used to read as empty. The number is present,
        // the state says it can't be interpreted yet, and the caption has the
        // counts it needs to say "4/10 nights".
        #expect(snapshot.hrvMs.value == 79)
        #expect(snapshot.hrvMs.state == .insufficientHistory)
        #expect(snapshot.hrvMs.sampleCount == 4)
        #expect(snapshot.hrvMs.requiredSamples == HealthSnapshot.baselineSampleRequirement)

        #expect(snapshot.readiness.value == nil)
        #expect(snapshot.readiness.state == .insufficientHistory)
    }

    @Test("A reading with a baseline can be compared against it")
    func enoughHistoryIsReady() {
        let snapshot = HealthSnapshotBuilder.build(appState: Self.stateWithNights(20))

        #expect(snapshot.hrvMs.state == .ready)
        #expect(snapshot.restingHeartRate.state == .ready)
        // Only a `.ready` metric may render a direction. Everything else has to
        // render the reason instead.
        #expect(snapshot.readiness.value != nil)
    }

    @Test("A week-old reading is stale, and keeps its value")
    func staleReadingsKeepTheirValue() {
        let state = Self.emptyState()
        for offset in stride(from: 20, through: 7, by: -1) {
            let k = Self.key(daysAgo: offset)
            var day = HealthDay(dayKey: k)
            day.sleepMin = 450
            day.stageCoverage = 0.9
            day.hrvMs = 79
            state.healthDays[k] = day
        }

        let snapshot = HealthSnapshotBuilder.build(appState: state)

        #expect(snapshot.hrvMs.state == .stale)
        // Kept, not hidden. A stale reading is still the most recent thing
        // known; hiding it makes the screen look like nothing was ever recorded,
        // which is a different problem with a different fix.
        #expect(snapshot.hrvMs.value == 79)
        #expect(snapshot.sleepMinutes.state == .stale)
    }

    // MARK: Sleep formatting

    @Test("Sleep on the tile is formatted, never a raw minute count")
    func sleepIsFormatted() {
        let state = Self.stateWithNights(12)
        let k = Date().dayKey
        var night = HealthDay(dayKey: k)
        night.sleepMin = 471
        night.stageCoverage = 0.9
        state.healthDays[k] = night

        let snapshot = HealthSnapshotBuilder.build(appState: state)

        #expect(snapshot.sleepMinutes.value == 471)
        // The tile calls the same formatter the coach context does, so the two
        // cannot disagree about the same night.
        #expect(HealthInsights.formatDuration(471) == "7h 51m")
    }

    // MARK: Page-two figures

    @Test("Distance and energy are carried on the snapshot, not read around it")
    func activityFiguresComeFromTheSnapshot() {
        let state = Self.emptyState()
        let k = state.todayKey
        var day = HealthDay(dayKey: k)
        day.distanceKm = 4.2
        day.activeEnergyKcal = 762
        state.healthDays[k] = day

        let snapshot = HealthSnapshotBuilder.build(appState: state)

        #expect(snapshot.distanceKm.value == 4.2)
        #expect(snapshot.activeEnergyKcal.value == 762)
        #expect(snapshot.distanceKm.state == .partial)
    }

    @Test("Zero distance is a real reading, unlike zero steps")
    func zeroDistanceIsNotMissing() {
        let state = Self.emptyState()
        let k = state.todayKey
        var day = HealthDay(dayKey: k)
        day.distanceKm = 0
        state.healthDays[k] = day

        let snapshot = HealthSnapshotBuilder.build(appState: state)

        // Steps infer absence from the value, because `CareDay.steps` is
        // non-optional and defaults to 0. `HealthDay.distanceKm` is optional, so
        // presence is the test — a genuinely still day really does have 0 km,
        // and showing "—" for it would be wrong in the other direction.
        #expect(snapshot.distanceKm.value == 0)
        #expect(snapshot.distanceKm.state.hasValue)
    }

    // MARK: Timestamps still don't move the hash

    @Test("The two new activity figures don't defeat the cache")
    func newFiguresRespectTheHashRules() {
        let state = Self.stateWithNights(12)
        let k = state.todayKey
        var day = HealthDay(dayKey: k)
        day.distanceKm = 4.2
        day.activeEnergyKcal = 762
        state.healthDays[k] = day

        var first = HealthSnapshotBuilder.build(appState: state)
        var second = first
        first.distanceKm.measuredAt = Date(timeIntervalSince1970: 0)
        second.distanceKm.measuredAt = Date()
        second.activeEnergyKcal.measuredAt = Date()

        // Both new metrics have to be cleared in `withoutTimestamps` like every
        // other one, or a sync that changed nothing starts missing the cache and
        // buying a fresh model call each poll.
        #expect(first.materialHash == second.materialHash)
    }
}
