import Testing
import Foundation
@testable import Life

/// The recovery arithmetic, tested for the first time.
///
/// It has been shipping for a while — as private methods on a view, where
/// nothing could reach it. These assertions pin the *current* answers rather
/// than better ones, because the extraction was meant to move the code and
/// change nothing, and a test written to what the code should do would have
/// hidden it if it hadn't.
struct MuscleRecoveryEngineTests {

    // MARK: Set intensity

    @Test("Set count maps to effort in four bands")
    func setIntensityBands() {
        #expect(MuscleRecoveryEngine.setIntensity(0) == 0.35)
        #expect(MuscleRecoveryEngine.setIntensity(2) == 0.35)
        #expect(MuscleRecoveryEngine.setIntensity(3) == 0.6)
        #expect(MuscleRecoveryEngine.setIntensity(5) == 0.6)
        #expect(MuscleRecoveryEngine.setIntensity(6) == 0.85)
        #expect(MuscleRecoveryEngine.setIntensity(9) == 0.85)
        #expect(MuscleRecoveryEngine.setIntensity(10) == 1.0)
        #expect(MuscleRecoveryEngine.setIntensity(40) == 1.0)
    }

    // MARK: Intensity

    /// With no prior session to compare against, the set count is the whole
    /// answer — otherwise the only session on record is also the best one, and
    /// every first workout reads as maximum effort.
    @Test("Without a personal best, intensity is the set-count baseline alone")
    func intensityWithoutHistory() {
        #expect(MuscleRecoveryEngine.intensity(sets: 4, volume: 1_000, personalBest: 0) == 0.6)
    }

    @Test("With a personal best, intensity blends sets and volume")
    func intensityBlends() {
        // (0.6 + 0.5) / 2
        let value = MuscleRecoveryEngine.intensity(sets: 4, volume: 500, personalBest: 1_000)
        #expect(abs(value - 0.55) < 0.0001)
    }

    /// A session beating the previous best still counts as one full session, not
    /// one and a bit.
    @Test("Volume above the previous best is capped at full effort")
    func intensityCapsAtOne() {
        let value = MuscleRecoveryEngine.intensity(sets: 12, volume: 5_000, personalBest: 1_000)
        #expect(value == 1.0)
    }

    // MARK: Day fatigue

    @Test("Training today is always high fatigue, whatever the window")
    func todayIsAlwaysHigh() {
        #expect(MuscleRecoveryEngine.dayFatigue(daysAgo: 0, recoveryDays: 1.5) == 85)
        #expect(MuscleRecoveryEngine.dayFatigue(daysAgo: 0, recoveryDays: 3) == 85)
    }

    /// The point of per-muscle windows: biceps recover before legs do.
    @Test("A short window clears sooner than a long one")
    func shortWindowsClearFirst() {
        let biceps = MuscleRecoveryEngine.dayFatigue(daysAgo: 2, recoveryDays: 1.5)
        let legs = MuscleRecoveryEngine.dayFatigue(daysAgo: 2, recoveryDays: 3)
        #expect(biceps < legs)
        // Past its window, a muscle sits at the residual floor rather than zero.
        #expect(biceps == 8)
    }

    @Test("Halfway through the window is halfway down")
    func halfwayTapers() {
        // 8 + 0.5 × 77
        #expect(MuscleRecoveryEngine.dayFatigue(daysAgo: 1, recoveryDays: 2) == 46.5)
    }

    // MARK: Bands

    @Test("Bands split at 25, 45 and 70")
    func bandBoundaries() {
        #expect(MuscleRecoveryEngine.Band(fatigue: 0) == .fresh)
        #expect(MuscleRecoveryEngine.Band(fatigue: 24) == .fresh)
        #expect(MuscleRecoveryEngine.Band(fatigue: 25) == .light)
        #expect(MuscleRecoveryEngine.Band(fatigue: 44) == .light)
        #expect(MuscleRecoveryEngine.Band(fatigue: 45) == .recovering)
        #expect(MuscleRecoveryEngine.Band(fatigue: 69) == .recovering)
        #expect(MuscleRecoveryEngine.Band(fatigue: 70) == .fatigued)
        #expect(MuscleRecoveryEngine.Band(fatigue: 100) == .fatigued)
    }

    // MARK: Fresh in

    @Test("A fresh muscle has no waiting time")
    func freshNeedsNoWait() {
        #expect(MuscleRecoveryEngine.freshInDays(fatigue: 20, daysAgo: 3, recoveryDays: 3) == nil)
    }

    @Test("A fatigued muscle never reports less than a day")
    func waitIsAtLeastADay() {
        // Window elapsed but fatigue still high: the honest answer is "not yet",
        // and zero days would read as "ready now".
        #expect(MuscleRecoveryEngine.freshInDays(fatigue: 80, daysAgo: 5, recoveryDays: 3) == 1)
        #expect(MuscleRecoveryEngine.freshInDays(fatigue: 80, daysAgo: 0, recoveryDays: 3) == 3)
    }

    // MARK: Readiness

    @Test("Readiness is 100 minus mean fatigue")
    func readinessAverages() {
        let statuses = [Self.status(fatigue: 60), Self.status(fatigue: 20)]
        #expect(MuscleRecoveryEngine.readiness(from: statuses) == 60)
    }

    @Test("Readiness with nothing to average is 100, not a crash")
    func readinessWithNoStatuses() {
        #expect(MuscleRecoveryEngine.readiness(from: []) == 100)
    }

    // MARK: Never trained is not recovered

    /// The distinction the health snapshot enforces everywhere else. A muscle
    /// with no history scores zero fatigue, which reads as "fully recovered, go
    /// hard" — and telling someone their never-trained calves are fresh is true
    /// and useless.
    @Test("A never-trained muscle is flagged, not reported as fresh")
    @MainActor
    func neverTrainedIsFlagged() {
        let state = AppState()
        state.sessions = []

        let statuses = MuscleRecoveryEngine.statuses(appState: state)
        #expect(!statuses.isEmpty)
        #expect(statuses.allSatisfy { !$0.hasTrainingHistory })
        #expect(statuses.allSatisfy { $0.fatigue == 0 })
        #expect(statuses.allSatisfy { $0.daysSinceTrained == nil })
    }

    /// Forearms have no `appMuscle`, so nothing can be said about them. They
    /// must not be reported as trained.
    @Test("A group the app doesn't track carries no history")
    @MainActor
    func untrackedGroupsHaveNoHistory() {
        let state = AppState()
        guard let forearms = MuscleGroup.allUnique.first(where: { $0.appMuscle == nil }) else {
            Issue.record("expected at least one untracked group")
            return
        }

        let status = MuscleRecoveryEngine.status(for: forearms, appState: state)
        #expect(status.hasTrainingHistory == false)
        #expect(status.blueprintMuscle == nil)
    }

    // MARK: Fixture

    static func status(fatigue: Int) -> MuscleRecoveryEngine.Status {
        MuscleRecoveryEngine.Status(
            id: "test-\(fatigue)",
            key: "test",
            name: "Test",
            appMuscle: "Chest",
            fatigue: fatigue,
            daysSinceTrained: 1,
            weeklySets: 0,
            weeklyTarget: 8...16,
            hasTrainingHistory: true,
            freshInDays: nil
        )
    }
}
