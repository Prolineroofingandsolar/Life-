import Testing
import Foundation
@testable import Life

// MARK: - Plateau

/// Detecting a lift that has stopped moving — and, more often, declining to.
@MainActor
struct PlateauEngineTests {

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    static let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 13; components.hour = 15
        return calendar.date(from: components)!
    }()

    static func state() -> AppState {
        let state = AppState()
        state.sessions = []
        state.routines = []
        state.plannedSessions = []
        state.exercises = [Exercise(name: "Bench press", muscle: "Chest", kind: .weight)]
        return state
    }

    /// One performance: `sets` working sets at `weight` for `reps`.
    static func session(
        daysAgo: Int,
        exerciseId: String,
        weight: Double,
        reps: Int = 8,
        sets: Int = 3
    ) -> WorkoutSession {
        let finished = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        var logged: [LoggedSet] = []
        for _ in 0..<sets {
            var set = LoggedSet(weight: weight, reps: reps)
            set.done = true
            logged.append(set)
        }
        var performed = SessionExercise(exerciseId: exerciseId)
        performed.sets = logged
        var session = WorkoutSession(name: "Session")
        session.startedAt = finished.addingTimeInterval(-3_000)
        session.finishedAt = finished
        session.exercises = [performed]
        return session
    }

    @Test("Four flat sessions over three weeks is a plateau")
    func flatIsAPlateau() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = [
            Self.session(daysAgo: 22, exerciseId: id, weight: 80),
            Self.session(daysAgo: 15, exerciseId: id, weight: 80),
            Self.session(daysAgo: 8, exerciseId: id, weight: 80),
            Self.session(daysAgo: 2, exerciseId: id, weight: 80),
        ]

        let findings = PlateauEngine.findings(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(findings.count == 1)
        #expect(findings.first?.exerciseName == "Bench press")
        #expect(findings.first?.sessions == 4)
    }

    /// Three sessions is not enough to call anything.
    @Test("Three sessions is below the threshold")
    func threeSessionsIsNotEnough() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = [
            Self.session(daysAgo: 15, exerciseId: id, weight: 80),
            Self.session(daysAgo: 8, exerciseId: id, weight: 80),
            Self.session(daysAgo: 2, exerciseId: id, weight: 80),
        ]

        #expect(PlateauEngine.findings(appState: state, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    /// Four sessions in one week is a busy week, not a stalled lift.
    @Test("Four sessions inside two weeks is below the week threshold")
    func weeksThresholdApplies() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = [
            Self.session(daysAgo: 8, exerciseId: id, weight: 80),
            Self.session(daysAgo: 6, exerciseId: id, weight: 80),
            Self.session(daysAgo: 3, exerciseId: id, weight: 80),
            Self.session(daysAgo: 1, exerciseId: id, weight: 80),
        ]

        #expect(PlateauEngine.findings(appState: state, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    @Test("A lift that's still going up isn't a plateau")
    func progressIsNotAPlateau() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = [
            Self.session(daysAgo: 22, exerciseId: id, weight: 70),
            Self.session(daysAgo: 15, exerciseId: id, weight: 75),
            Self.session(daysAgo: 8, exerciseId: id, weight: 80),
            Self.session(daysAgo: 2, exerciseId: id, weight: 85),
        ]

        #expect(PlateauEngine.findings(appState: state, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    /// Sets and reps are how most people actually progress. Calling that a
    /// plateau would be the app failing to recognise the thing it recommends.
    @Test("Flat load with rising volume is progress, not a plateau")
    func volumeProgressIsProgress() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = [
            Self.session(daysAgo: 22, exerciseId: id, weight: 80, reps: 6, sets: 3),
            Self.session(daysAgo: 15, exerciseId: id, weight: 80, reps: 7, sets: 3),
            Self.session(daysAgo: 8, exerciseId: id, weight: 80, reps: 8, sets: 3),
            Self.session(daysAgo: 2, exerciseId: id, weight: 80, reps: 10, sets: 4),
        ]

        #expect(PlateauEngine.findings(appState: state, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    /// Someone who cut a session short because the gym was closing has not got
    /// weaker, and counting it would generate a plateau out of a car park.
    @Test("A one-set session isn't comparable and doesn't count")
    func partialSessionsAreExcluded() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = [
            Self.session(daysAgo: 22, exerciseId: id, weight: 80),
            Self.session(daysAgo: 15, exerciseId: id, weight: 80),
            Self.session(daysAgo: 8, exerciseId: id, weight: 80),
            // One working set only — excluded, leaving three comparable.
            Self.session(daysAgo: 2, exerciseId: id, weight: 60, sets: 1),
        ]

        #expect(PlateauEngine.findings(appState: state, now: Self.now, calendar: Self.calendar).isEmpty)
    }

    /// Numbers and a name. No dates, no session log, nothing about health —
    /// so there is no material with which to speculate about a cause.
    @Test("The prompt carries figures and nothing else")
    func promptIsBare() {
        let finding = PlateauEngine.Finding(
            exerciseId: "x",
            exerciseName: "Bench press",
            sessions: 5,
            weeks: 4,
            startWeight: 80,
            currentWeight: 80,
            bestVolume: 2_000,
            evidence: []
        )
        let text = PlateauEngine.promptText(for: finding)

        #expect(text.contains("Bench press"))
        #expect(text.contains("5 comparable sessions"))
        #expect(!text.lowercased().contains("sleep"))
        #expect(!text.contains("x"))
    }

    // MARK: Advice

    @Test("An unknown remedy is dropped rather than throwing")
    func unknownRemediesAreDropped() throws {
        let json = #"{"remedies":["lighterWeek","doMoreCardio"],"explanation":"Try this."}"#
        let advice = try JSONDecoder().decode(PlateauAdvice.self, from: Data(json.utf8))

        #expect(advice.remedies == [.lighterWeek])
        #expect(advice.explanation == "Try this.")
    }

    @Test("The local advice never claims a cause")
    func localAdviceMakesNoClaim() {
        let finding = PlateauEngine.Finding(
            exerciseId: "x",
            exerciseName: "Squat",
            sessions: 5,
            weeks: 4,
            startWeight: 100,
            currentWeight: 100,
            bestVolume: 3_000,
            evidence: []
        )
        let advice = LocalPlateauAdvice.advice(for: finding)
        let text = advice.explanation.lowercased()

        for word in ["overtrain", "recovery", "hormone", "sleep", "injur", "deficien"] {
            #expect(!text.contains(word))
        }
        #expect(!advice.remedies.isEmpty)
    }

    @Test("A lift going backwards is offered a lighter week")
    func regressionSuggestsALighterWeek() {
        let finding = PlateauEngine.Finding(
            exerciseId: "x",
            exerciseName: "Squat",
            sessions: 5,
            weeks: 4,
            startWeight: 100,
            currentWeight: 90,
            bestVolume: 3_000,
            evidence: []
        )
        #expect(LocalPlateauAdvice.advice(for: finding).remedies.contains(.lighterWeek))
    }
}

// MARK: - Deload

/// The rule that matters here is the refusal: enough history, two independent
/// signals, and never from one bad thing.
@MainActor
struct DeloadEngineTests {

    static func state() -> AppState {
        let state = AppState()
        state.sessions = []
        state.routines = []
        state.programs = []
        state.plannedSessions = []
        state.exercises = [Exercise(name: "Bench press", muscle: "Chest", kind: .weight)]
        return state
    }

    @Test("Four weeks of history is never enough for a deload")
    func historyGate() {
        let state = Self.state()
        let id = state.exercises[0].id
        // Four weeks of flat, hard training — every signal it could want,
        // except the history to justify acting on them.
        state.sessions = (0..<8).map { index in
            PlateauEngineTests.session(daysAgo: 3 + index * 3, exerciseId: id, weight: 80)
        }

        #expect(DeloadEngine.proposal(appState: state, now: PlateauEngineTests.now, calendar: PlateauEngineTests.calendar) == nil)
    }

    @Test("With no training at all there is nothing to deload from")
    func emptyStateProposesNothing() {
        #expect(DeloadEngine.proposal(appState: Self.state()) == nil)
    }

    /// Fewer sets and less load, and reps untouched — cutting reps as well
    /// turns a deload into a week off.
    @Test("A deload cuts sets and load, and leaves reps alone")
    func deloadArithmetic() {
        let proposal = DeloadEngine.Proposal(
            signals: [.plateau, .sustainedFatigue],
            weeksOfHistory: 8,
            setsReductionPercent: 30,
            loadReductionPercent: 10,
            extraRIR: 2,
            sessionsToDrop: 0
        )

        var item = RoutineExercise(exerciseId: "x")
        item.defaultSets = 4
        item.defaultWeight = 100
        item.repRangeMin = 8
        item.repRangeMax = 12

        let after = DeloadEngine.deloaded([item], proposal: proposal)

        #expect(after.first?.defaultSets == 3)
        #expect(after.first?.defaultWeight == 90)
        #expect(after.first?.repRangeMin == 8)
        #expect(after.first?.repRangeMax == 12)
    }

    @Test("A single set is never reduced to zero")
    func setsNeverReachZero() {
        let proposal = DeloadEngine.Proposal(
            signals: [.plateau, .effortCreep],
            weeksOfHistory: 8,
            setsReductionPercent: 90,
            loadReductionPercent: 10,
            extraRIR: 2,
            sessionsToDrop: 0
        )
        var item = RoutineExercise(exerciseId: "x")
        item.defaultSets = 1

        #expect(DeloadEngine.deloaded([item], proposal: proposal).first?.defaultSets == 1)
    }

    @Test("Bodyweight exercises keep their zero weight")
    func bodyweightIsUntouched() {
        let proposal = DeloadEngine.Proposal(
            signals: [.plateau, .effortCreep],
            weeksOfHistory: 8,
            setsReductionPercent: 30,
            loadReductionPercent: 10,
            extraRIR: 2,
            sessionsToDrop: 0
        )
        var item = RoutineExercise(exerciseId: "x")
        item.defaultSets = 3
        item.defaultWeight = 0

        #expect(DeloadEngine.deloaded([item], proposal: proposal).first?.defaultWeight == 0)
    }

    @Test("Reductions land on something you can actually load")
    func loadRoundsToTheHalfKilo() {
        let proposal = DeloadEngine.Proposal(
            signals: [.plateau, .effortCreep],
            weeksOfHistory: 8,
            setsReductionPercent: 30,
            loadReductionPercent: 10,
            extraRIR: 2,
            sessionsToDrop: 0
        )
        var item = RoutineExercise(exerciseId: "x")
        item.defaultWeight = 67.5

        // 67.5 − 10% = 60.75 → 61.0 (nearest half kilo, rounding up).
        #expect(DeloadEngine.deloaded([item], proposal: proposal).first?.defaultWeight == 61)
    }
}

// MARK: - Automations

/// Six checks that propose and never apply.
@MainActor
struct AutomationTests {

    static func state() -> AppState {
        let state = AppState()
        state.sessions = []
        state.routines = []
        state.programs = []
        state.plannedSessions = []
        state.exercises = [Exercise(name: "Bench press", muscle: "Chest", kind: .weight)]
        return state
    }

    @Test("A disabled automation produces nothing")
    func disabledAutomationsDontRun() {
        let state = Self.state()
        state.plannedSessions = [
            PlannedSession(
                date: Date().addingTimeInterval(-2 * 86_400),
                routineId: "r1",
                routineName: "Push"
            )
        ]

        let all = AutomationRunner.run(appState: state, enabled: Set(AutomationKind.allCases))
        #expect(all.contains { $0.kind == .missedWorkout })

        let none = AutomationRunner.run(appState: state, enabled: [])
        #expect(none.isEmpty)
    }

    /// Every outcome has to be able to answer "why am I seeing this?".
    @Test("Every outcome states its reason, its data and its author")
    func outcomesExplainThemselves() {
        let state = Self.state()
        state.plannedSessions = [
            PlannedSession(
                date: Date().addingTimeInterval(-2 * 86_400),
                routineId: "r1",
                routineName: "Push"
            )
        ]

        let outcomes = AutomationRunner.run(appState: state, enabled: Set(AutomationKind.allCases))
        #expect(!outcomes.isEmpty)
        for outcome in outcomes {
            #expect(!outcome.reason.isEmpty)
            #expect(!outcome.dataUsed.isEmpty)
            #expect(!outcome.proposal.isEmpty)
        }
    }

    @Test("Automations change nothing by running")
    func runningWritesNothing() {
        let state = Self.state()
        state.plannedSessions = [
            PlannedSession(
                date: Date().addingTimeInterval(-2 * 86_400),
                routineId: "r1",
                routineName: "Push"
            )
        ]
        let plannedBefore = state.plannedSessions
        let routinesBefore = state.routines.count
        let sessionsBefore = state.sessions.count

        _ = AutomationRunner.run(appState: state, enabled: Set(AutomationKind.allCases))

        #expect(state.plannedSessions.map(\.id) == plannedBefore.map(\.id))
        #expect(state.plannedSessions.allSatisfy { !$0.completed })
        #expect(state.routines.count == routinesBefore)
        #expect(state.sessions.count == sessionsBefore)
    }

    /// Stored as disabled rather than enabled, so an automation added in a
    /// future version arrives switched on without a migration.
    @Test("Settings default to all six on, and survive a round trip")
    func settingsRoundTrip() throws {
        var settings = CoachSettings()
        #expect(settings.enabledAutomations.count == AutomationKind.allCases.count)

        settings.disabledAutomations = [AutomationKind.plateauReview.rawValue]
        #expect(!settings.isAutomationEnabled(.plateauReview))
        #expect(settings.isAutomationEnabled(.weeklyReview))

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CoachSettings.self, from: data)
        #expect(decoded.disabledAutomations == [AutomationKind.plateauReview.rawValue])
    }

    /// This was a real bug: the property existed, the coding key didn't, and
    /// the camera consent silently reset on every launch.
    @Test("Machine-scanning consent survives a round trip")
    func machineScanningPersists() throws {
        var settings = CoachSettings()
        settings.allowMachineScanning = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CoachSettings.self, from: data)
        #expect(decoded.allowMachineScanning)
    }

    /// Old snapshots have neither key. Both must decode to their defaults
    /// rather than throwing — `AppState.load()` reads a decode failure as first
    /// launch and seeds defaults over the user's data.
    @Test("A snapshot from before these fields still decodes")
    func backwardCompatibleDecoding() throws {
        let json = #"{"enabled":true,"cloudEnabled":true,"hasConsented":true}"#
        let settings = try JSONDecoder().decode(CoachSettings.self, from: Data(json.utf8))

        #expect(settings.allowMachineScanning == false)
        #expect(settings.disabledAutomations.isEmpty)
        #expect(settings.enabledAutomations.count == AutomationKind.allCases.count)
    }
}
