import Testing
import Foundation
@testable import Life

/// The network boundary and the write boundary — the two places a generated
/// workout can cost money or change data.
///
/// Nothing here touches the network: every test supplies its own
/// `StubTransport`. The call counts are the point in several of them, because
/// "did this cost one call or two" is the whole cost model.
@MainActor
struct WorkoutBuilderServiceTests {

    // MARK: Fixtures

    static func service(
        transport: CoachTransport,
        defaults: UserDefaults? = nil
    ) -> WorkoutBuilderService {
        let store = defaults ?? isolatedCoachDefaults()
        return WorkoutBuilderService(
            transport: transport,
            usage: CoachUsage(defaults: store),
            idTokenProvider: { "test-token" }
        )
    }

    static func context() -> CoachContext {
        CoachContext(
            generatedAt: Date(),
            timeOfDay: .morning,
            goals: [],
            sleep: nil, recovery: nil, activity: nil,
            training: nil, tasks: nil, habits: nil,
            dataWarnings: []
        )
    }

    static func brief(_ text: String = "45 minutes, upper body") -> WorkoutBrief {
        var brief = WorkoutBrief()
        brief.text = text
        brief.availableMinutes = 45
        return brief
    }

    static func validWorkoutResponse() -> [String: Any] {
        [
            "ok": true,
            "value": [
                "name": "Upper Body — Strength",
                "focus": "Pressing and pulling",
                "slots": [
                    ["muscle": "Chest", "equipment": "barbell", "sets": 4,
                     "repMin": 6, "repMax": 8, "restSeconds": 150],
                    ["muscle": "Back", "sets": 4, "repMin": 8, "repMax": 10, "restSeconds": 120],
                    ["muscle": "Shoulders", "sets": 3, "repMin": 10, "repMax": 12, "restSeconds": 90],
                ],
            ],
            "usage": ["promptTokens": 2400, "outputTokens": 820, "cost": 0.0006],
        ]
    }

    // MARK: Happy path

    @Test("A well-formed blueprint decodes in one call")
    func validBlueprintDecodes() async throws {
        let transport = StubTransport(Self.validWorkoutResponse())
        let draft = try await Self.service(transport: transport)
            .buildWorkout(brief: Self.brief(), context: Self.context(), settings: cloudCoachSettings())

        #expect(draft.blueprint.slots.count == 3)
        #expect(draft.blueprint.slots.first?.muscle == .chest)
        #expect(draft.blueprint.slots.first?.equipment == .barbell)
        #expect(transport.callCount == 1)
        #expect(transport.mode(at: 0) == "buildWorkout")
    }

    @Test("The provenance says Gemini wrote it")
    func provenanceNamesTheModel() async throws {
        let transport = StubTransport(Self.validWorkoutResponse())
        let draft = try await Self.service(transport: transport)
            .buildWorkout(brief: Self.brief(), context: Self.context(), settings: cloudCoachSettings())

        // The same rule as everywhere else: a local template presented as
        // Gemini's work makes the model look worse than it is, and the reverse
        // makes it look better.
        #expect(draft.provenance.origin == .gemini)
    }

    @Test("Usage is recorded from the response")
    func usageIsRecorded() async throws {
        let defaults = isolatedCoachDefaults()
        let transport = StubTransport(Self.validWorkoutResponse())

        _ = try await Self.service(transport: transport, defaults: defaults)
            .buildWorkout(brief: Self.brief(), context: Self.context(), settings: cloudCoachSettings())

        let snapshot = CoachUsage(defaults: defaults).snapshot()
        #expect(snapshot.calls == 1)
        #expect(snapshot.promptTokens == 2400)
        #expect(snapshot.cost > 0)
    }

    // MARK: Repair, once

    @Test("An unknown muscle is repaired once, then given up on")
    func unknownMuscleIsRepairedOnce() async {
        // "Forearms" is not in the closed vocabulary, so strict decoding throws
        // and the app asks for one correction.
        var bad = Self.validWorkoutResponse()
        var value = bad["value"] as! [String: Any]
        value["slots"] = [["muscle": "Forearms", "sets": 3, "repMin": 8, "repMax": 12, "restSeconds": 90]]
        bad["value"] = value

        let transport = StubTransport([.success(bad), .success(bad)])
        let service = Self.service(transport: transport)

        await #expect(throws: CoachError.self) {
            try await service.buildWorkout(
                brief: Self.brief(), context: Self.context(), settings: cloudCoachSettings()
            )
        }

        // Exactly two: the attempt and one repair. A third would be a retry loop
        // against a persistently failing model, paid for each time.
        #expect(transport.callCount == 2)
    }

    @Test("The repair attempt says what was wrong")
    func repairCarriesTheReason() async throws {
        var bad = Self.validWorkoutResponse()
        var value = bad["value"] as! [String: Any]
        value["slots"] = [["muscle": "Forearms", "sets": 3, "repMin": 8, "repMax": 12, "restSeconds": 90]]
        bad["value"] = value

        let transport = StubTransport([.success(bad), .success(Self.validWorkoutResponse())])
        _ = try await Self.service(transport: transport)
            .buildWorkout(brief: Self.brief(), context: Self.context(), settings: cloudCoachSettings())

        #expect(transport.callCount == 2)
        let repair = transport.sentBodies[1]["repairReason"] as? String
        #expect(repair?.contains("Forearms") == true)
    }

    @Test("A server-side rejection is repaired, not thrown")
    func serverRejectionIsRepaired() async throws {
        let rejection: [String: Any] = [
            "ok": false, "reason": "slot 0 carried an unexpected field: exerciseName",
        ]
        let transport = StubTransport([.success(rejection), .success(Self.validWorkoutResponse())])

        let draft = try await Self.service(transport: transport)
            .buildWorkout(brief: Self.brief(), context: Self.context(), settings: cloudCoachSettings())

        #expect(draft.blueprint.slots.count == 3)
        #expect(transport.sentBodies[1]["repairReason"] != nil)
    }

    // MARK: Refusing before spending

    @Test("Over the limit, no call is made at all")
    func limitStopsTheCall() async {
        let defaults = isolatedCoachDefaults()
        let usage = CoachUsage(defaults: defaults)
        usage.setCeiling(1.00)
        usage.record(promptTokens: 0, outputTokens: 0, cost: 1.50)

        let transport = StubTransport([])
        let service = Self.service(transport: transport, defaults: defaults)

        await #expect(throws: CoachError.self) {
            try await service.buildWorkout(
                brief: Self.brief(), context: Self.context(), settings: cloudCoachSettings()
            )
        }
        // Refused here rather than round-tripping to a server that would refuse
        // it anyway.
        #expect(transport.callCount == 0)
    }

    @Test("With cloud AI off, nothing is sent")
    func cloudOffSendsNothing() async {
        var settings = cloudCoachSettings()
        settings.cloudEnabled = false

        let transport = StubTransport([])
        let service = Self.service(transport: transport)

        await #expect(throws: CoachError.self) {
            try await service.buildWorkout(
                brief: Self.brief(), context: Self.context(), settings: settings
            )
        }
        #expect(transport.callCount == 0)
    }

    @Test("A long brief is truncated before it leaves the device")
    func briefIsTruncated() async throws {
        let transport = StubTransport(Self.validWorkoutResponse())
        let long = String(repeating: "a", count: 900)

        _ = try await Self.service(transport: transport)
            .buildWorkout(brief: Self.brief(long), context: Self.context(), settings: cloudCoachSettings())

        #expect((transport.question(at: 0)?.count ?? 0) <= 500)
    }

    @Test("A plan asks the plan endpoint")
    func planUsesItsOwnMode() async throws {
        let response: [String: Any] = [
            "ok": true,
            "value": [
                "name": "Upper / Lower",
                "weeks": 4,
                "sessions": [
                    ["key": "upper", "blueprint": [
                        "name": "Upper", "focus": "Press and pull",
                        "slots": [
                            ["muscle": "Chest", "sets": 4, "repMin": 6, "repMax": 8, "restSeconds": 120],
                            ["muscle": "Back", "sets": 4, "repMin": 8, "repMax": 10, "restSeconds": 120],
                            ["muscle": "Shoulders", "sets": 3, "repMin": 10, "repMax": 12, "restSeconds": 90],
                        ],
                    ]],
                ],
                "weekdays": [
                    ["weekday": 1, "sessionKey": "upper"],
                    ["weekday": 4, "sessionKey": "upper"],
                ],
                "progression": "Add a rep each week before adding load.",
            ],
        ]

        let transport = StubTransport(response)
        let draft = try await Self.service(transport: transport)
            .buildPlan(brief: Self.brief(), context: Self.context(), settings: cloudCoachSettings())

        #expect(transport.mode(at: 0) == "buildPlan")
        #expect(draft.blueprint.weeks == 4)
        #expect(draft.blueprint.sessions.count == 1)
        #expect(draft.blueprint.weekdays.count == 2)
    }
}

// MARK: - Committing

/// The write boundary. Nothing here may change app data except `commit`, and
/// `commit` may only run from a tap.
@MainActor
struct WorkoutBuilderActionTests {

    static func state() -> AppState {
        let state = AppState()
        state.tasks = []
        state.habits = []
        state.sessions = []
        state.routines = []
        state.programs = []
        state.plannedSessions = []
        state.exercises = WorkoutResolverTests.library
        return state
    }

    static func resolved(_ muscles: [BlueprintMuscle] = [.chest, .back, .shoulders]) -> WorkoutResolver.ResolvedWorkout {
        let blueprint = WorkoutBlueprint(
            name: "Upper Body",
            focus: "Strength",
            slots: muscles.map {
                WorkoutSlot(muscle: $0, sets: 3, repMin: 8, repMax: 12, restSeconds: 90)
            },
            notes: nil
        )
        return WorkoutResolver.resolve(
            blueprint,
            inputs: WorkoutResolver.Inputs(library: WorkoutResolverTests.library)
        )
    }

    static func resolvedPlan(weeks: Int = 4, days: [Int] = [1, 3, 5]) -> WorkoutResolver.ResolvedPlan {
        let session = WorkoutBlueprint(
            name: "Full Body",
            focus: "General",
            slots: [
                WorkoutSlot(muscle: .chest, sets: 3, repMin: 8, repMax: 12, restSeconds: 90),
                WorkoutSlot(muscle: .back, sets: 3, repMin: 8, repMax: 12, restSeconds: 90),
                WorkoutSlot(muscle: .legs, sets: 3, repMin: 8, repMax: 12, restSeconds: 90),
            ],
            notes: nil
        )
        let plan = PlanBlueprint(
            name: "Three Day Full Body",
            weeks: weeks,
            sessions: [PlanSession(key: "full", blueprint: session)],
            weekdays: days.map { PlanWeekday(weekday: $0, sessionKey: "full") },
            progression: "Add load when the top of the range is hit."
        )
        return WorkoutResolver.resolve(
            plan, inputs: WorkoutResolver.Inputs(library: WorkoutResolverTests.library)
        )
    }

    /// A fixed Monday, so scheduling never depends on the day the test runs.
    static let monday: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 3
        components.hour = 9
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar.date(from: components)!
    }()

    // MARK: Previewing writes nothing

    @Test("Resolving and previewing changes no app data at all")
    func previewIsInert() {
        let state = Self.state()
        let exercisesBefore = state.exercises.count

        _ = Self.resolved()
        _ = Self.resolvedPlan()

        // The whole architecture rests on this. A draft exists in memory and
        // touches nothing until a finger lands on the confirm button.
        #expect(state.routines.isEmpty)
        #expect(state.programs.isEmpty)
        #expect(state.plannedSessions.isEmpty)
        #expect(state.exercises.count == exercisesBefore)
    }

    // MARK: Committing a session

    @Test("Committing a workout adds exactly one routine")
    func commitAddsOneRoutine() {
        let state = Self.state()
        let workout = Self.resolved()

        let message = WorkoutBuilderActions.commit(workout, appState: state)

        #expect(message != nil)
        #expect(state.routines.count == 1)
        #expect(state.routines.first?.name == "Upper Body")
        #expect(state.routines.first?.exercises.count == 3)
        // No programme, no calendar entries — a session is a session.
        #expect(state.programs.isEmpty)
        #expect(state.plannedSessions.isEmpty)
    }

    @Test("The saved routine points at real exercise ids")
    func savedRoutineUsesRealIds() {
        let state = Self.state()
        WorkoutBuilderActions.commit(Self.resolved(), appState: state)

        let realIds = Set(state.exercises.map(\.id))
        for exercise in state.routines.first!.exercises {
            #expect(realIds.contains(exercise.exerciseId))
        }
    }

    @Test("An exercise deleted between preview and tap blocks the commit")
    func staleDraftIsRefused() {
        let state = Self.state()
        let workout = Self.resolved()

        // Deleted on another device while the preview was on screen. Two
        // different moments, which is why `usable` at draw time isn't enough.
        state.exercises.removeAll { $0.id == workout.items.first!.exercise.id }

        let message = WorkoutBuilderActions.commit(workout, appState: state)

        #expect(message == nil)
        #expect(state.routines.isEmpty)
    }

    @Test("A workout with too few exercises cannot be committed")
    func unviableWorkoutIsRefused() {
        let state = Self.state()
        let thin = Self.resolved([.chest])

        #expect(thin.isViable == false)
        #expect(WorkoutBuilderActions.isCommittable(thin, appState: state) == false)
        #expect(WorkoutBuilderActions.commit(thin, appState: state) == nil)
        #expect(state.routines.isEmpty)
    }

    // MARK: Committing a plan

    @Test("A three-day four-week plan writes one programme and twelve sessions")
    func planCommitWritesEverything() {
        let state = Self.state()
        let plan = Self.resolvedPlan(weeks: 4, days: [1, 3, 5])

        let message = WorkoutBuilderActions.commit(
            plan, appState: state,
            options: .init(makeActive: true, startingFrom: Self.monday)
        )

        #expect(message != nil)
        #expect(state.routines.count == 1)
        #expect(state.programs.count == 1)
        #expect(state.programs.first?.days.map(\.weekday) == [1, 3, 5])
        #expect(state.plannedSessions.count == 12)
    }

    @Test("Programme days point at the routines that were just created")
    func programmeDaysPointAtRealRoutines() {
        let state = Self.state()
        WorkoutBuilderActions.commit(
            Self.resolvedPlan(), appState: state,
            options: .init(makeActive: false, startingFrom: Self.monday)
        )

        let routineIds = Set(state.routines.map(\.id))
        for day in state.programs.first!.days {
            #expect(day.routineId != nil)
            #expect(routineIds.contains(day.routineId!))
        }
    }

    @Test("An existing active programme is left alone unless asked")
    func existingActiveProgrammeSurvives() {
        let state = Self.state()
        state.addProgram(name: "My Split", days: [])
        state.setActiveProgram(id: state.programs.first!.id)
        let originalId = state.programs.first!.id

        WorkoutBuilderActions.commit(
            Self.resolvedPlan(), appState: state,
            options: .init(makeActive: false, startingFrom: Self.monday)
        )

        // Silently replacing someone's active split is exactly the unconsented
        // mutation this architecture exists to prevent.
        #expect(state.activeProgram?.id == originalId)
        #expect(state.programs.count == 2)
    }

    @Test("Asking to activate does replace the active programme")
    func activationIsHonoured() {
        let state = Self.state()
        state.addProgram(name: "My Split", days: [])
        state.setActiveProgram(id: state.programs.first!.id)

        WorkoutBuilderActions.commit(
            Self.resolvedPlan(), appState: state,
            options: .init(makeActive: true, startingFrom: Self.monday)
        )

        #expect(state.activeProgram?.name == "Three Day Full Body")
        #expect(state.programs.filter(\.isActive).count == 1)
    }

    @Test("Scheduling can be declined without losing the programme")
    func schedulingIsOptional() {
        let state = Self.state()
        WorkoutBuilderActions.commit(
            Self.resolvedPlan(), appState: state,
            options: .init(makeActive: false, scheduleSessions: false, startingFrom: Self.monday)
        )

        #expect(state.programs.count == 1)
        #expect(state.plannedSessions.isEmpty)
    }

    @Test("A twelve-week six-day plan is capped rather than flooding the calendar")
    func plannedSessionsAreCapped() {
        let state = Self.state()
        let huge = Self.resolvedPlan(weeks: 12, days: [1, 2, 3, 4, 5, 6])

        WorkoutBuilderActions.commit(
            huge, appState: state,
            options: .init(makeActive: false, startingFrom: Self.monday)
        )

        // 72 entries is a wall, not a plan.
        #expect(state.plannedSessions.count == WorkoutBuilderActions.maximumPlannedSessions)
    }

    @Test("Sessions are never scheduled in the past")
    func noBackdatedSessions() {
        let state = Self.state()
        // Created on the Wednesday: Monday and Tuesday of that week have gone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: Self.monday)!

        WorkoutBuilderActions.commit(
            Self.resolvedPlan(weeks: 1, days: [1, 3, 5]), appState: state,
            options: .init(makeActive: false, startingFrom: wednesday)
        )

        // A planned session in the past is a missed session nobody had the
        // chance to do.
        let earliest = state.plannedSessions.map(\.date).min()
        #expect(earliest != nil)
        #expect(earliest! >= calendar.startOfDay(for: wednesday))
        #expect(state.plannedSessions.count == 2)
    }

    @Test("The week starts on Monday whatever the device locale says")
    func weekStartIsLocaleIndependent() {
        var us = Calendar(identifier: .gregorian)
        us.timeZone = TimeZone(identifier: "Europe/London")!
        us.locale = Locale(identifier: "en_US")

        let start = WorkoutBuilderActions.startOfWeek(containing: Self.monday, calendar: us)

        // en_US puts Sunday first. Deriving the week start from weekOfYear would
        // shift the entire schedule by a day — the same bug that put Thursday
        // under the "Wed" column on the Train calendar.
        #expect(start != nil)
        #expect(us.component(.weekday, from: start!) == 2)
    }

    // MARK: One save, not fifteen

    @Test("A plan commit leaves no orphan routines behind")
    func commitIsAllOrNothing() {
        let state = Self.state()
        let plan = Self.resolvedPlan()

        WorkoutBuilderActions.commit(
            plan, appState: state,
            options: .init(makeActive: false, startingFrom: Self.monday)
        )

        // Every routine written belongs to the programme that was written with
        // it. Building this out of addRoutine + addProgram would save fifteen
        // times and could stop halfway, leaving routines pointing at nothing.
        let programmeRoutineIds = Set(state.programs.first!.days.compactMap(\.routineId))
        let writtenRoutineIds = Set(state.routines.map(\.id))
        #expect(writtenRoutineIds == programmeRoutineIds)
    }
}

// MARK: - Editing a draft before saving

/// The preview gained swap, set-editing, remove and start-now. The view isn't
/// unit-testable, but the invariants those edits must not break are.
@MainActor
struct PreviewEditingTests {

    static func state() -> AppState {
        let state = AppState()
        state.sessions = []
        state.routines = []
        state.programs = []
        state.plannedSessions = []
        state.exercises = WorkoutResolverTests.library
        state.coachFeedback = []
        return state
    }

    static func workout() -> WorkoutResolver.ResolvedWorkout {
        let blueprint = WorkoutBlueprint(
            name: "Upper",
            focus: "Chest and back",
            slots: [
                WorkoutSlot(muscle: .chest, sets: 3, repMin: 8, repMax: 12, restSeconds: 90),
                WorkoutSlot(muscle: .back, sets: 3, repMin: 8, repMax: 12, restSeconds: 90),
                WorkoutSlot(muscle: .shoulders, sets: 3, repMin: 8, repMax: 12, restSeconds: 90),
            ],
            notes: nil
        )
        return WorkoutResolver.resolve(
            blueprint,
            inputs: WorkoutResolver.Inputs(library: WorkoutResolverTests.library)
        )
    }

    /// Starting a generated session used to mean save, close, find the routine,
    /// start it. The one-tap path has to leave the store in exactly the state
    /// those four steps would have.
    @Test("Saving a draft creates one routine whose exercises match the preview")
    func commitMatchesThePreview() {
        let state = Self.state()
        let workout = Self.workout()

        let message = WorkoutBuilderActions.commit(workout, appState: state)

        #expect(message != nil)
        #expect(state.routines.count == 1)
        #expect(state.routines.first?.exercises.map(\.exerciseId) == workout.items.map(\.exercise.id))
        // A draft is not a session until one is started.
        #expect(state.activeSession == nil)
    }

    /// The state "start it now" lands in: one routine, one live session on it.
    @Test("Starting from a saved draft produces a live session on that routine")
    func startingAfterCommit() {
        let state = Self.state()
        _ = WorkoutBuilderActions.commit(Self.workout(), appState: state)

        let routine = state.routines.last
        state.startSession(name: routine?.name ?? "", routineId: routine?.id)

        #expect(state.activeSession != nil)
        #expect(state.activeSession?.routineId == routine?.id)
    }

    /// Editing the draft must not reach the store. Everything the preview's
    /// edits touch is a local copy until the confirm button.
    @Test("A resolved workout is a value — editing a copy leaves the original alone")
    func editingIsLocal() {
        let original = Self.workout()
        var edited = original
        edited.items.removeLast()
        edited.items[0].prescription.defaultSets = 5

        #expect(original.items.count == 3)
        #expect(original.items[0].prescription.defaultSets == 3)
        #expect(edited.items.count == 2)
    }

    /// Removing exercises in the preview can take a draft below the floor, and
    /// the save button reads that same check.
    @Test("A draft edited below three exercises can't be saved")
    func tooFewExercisesBlocksTheSave() {
        let state = Self.state()
        var workout = Self.workout()
        workout.items.removeLast()

        #expect(workout.isViable == false)
        #expect(WorkoutBuilderActions.isCommittable(workout, appState: state) == false)
        #expect(WorkoutBuilderActions.commit(workout, appState: state) == nil)
        #expect(state.routines.isEmpty)
    }
}
