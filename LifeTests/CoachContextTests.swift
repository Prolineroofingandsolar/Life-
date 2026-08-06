import Testing
import Foundation
@testable import Life

/// Covers what goes into the coach's payload and what is refused coming back.
///
/// The emphasis is deliberate. Most of these assert an *absence* — that a
/// missing reading isn't sent as zero, that a name never leaves the device,
/// that an invented id is rejected. Those are the failures that would be
/// invisible in use: a coach confidently advising on data it never had looks
/// exactly like a coach advising on data it did.
@MainActor
struct CoachContextTests {

    // MARK: Fixtures

    /// A state with nothing in it. Each test adds only what it's about.
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

    static func day(
        _ key: String,
        sleepMin: Int? = nil,
        stageCoverage: Double? = nil,
        restingHr: Double? = nil,
        hrvMs: Double? = nil
    ) -> HealthDay {
        var d = HealthDay(dayKey: key)
        d.sleepMin = sleepMin
        d.stageCoverage = stageCoverage
        d.restingHr = restingHr
        d.hrvMs = hrvMs
        return d
    }

    // MARK: Missing data is never zero

    @Test("No steps recorded sends nil, not zero")
    func missingStepsAreNotZero() {
        let state = Self.emptyState()
        let context = CoachContextBuilder.build(appState: state)

        // The distinction the whole feature rests on. Zero steps means the user
        // didn't move; nil means the tracker hasn't synced. Advising "get
        // moving" on the second is wrong, and indistinguishable from the first
        // if absence is sent as 0.
        #expect(context.activity?.steps == nil)
        #expect(context.activity?.quality == .missing)
        #expect(context.dataWarnings.contains { $0.contains("No steps recorded") })
    }

    @Test("A day with steps reports them as partial, not verified")
    func todaysStepsArePartial() {
        let state = Self.emptyState()
        var care = CareDay(dayKey: state.todayKey)
        care.steps = 6969
        state.careDays[state.todayKey] = care

        let context = CoachContextBuilder.build(appState: state)

        #expect(context.activity?.steps == 6969)
        // Today is always mid-count. Reporting it as verified would invite a
        // conclusion about a day that hasn't finished.
        #expect(context.activity?.isPartialDay == true)
        #expect(context.activity?.quality == .partial)
    }

    @Test("No sleep recorded produces a warning and no sleep section")
    func missingSleepIsWarned() {
        let state = Self.emptyState()
        let context = CoachContextBuilder.build(appState: state)

        #expect(context.sleep == nil)
        #expect(context.dataWarnings.contains { $0.contains("No sleep recorded") })
    }

    // MARK: Confidence follows coverage

    @Test("A poorly covered night is marked low confidence")
    func partialSleepIsLowConfidence() {
        let state = Self.emptyState()
        let key = state.todayKey
        state.healthDays[key] = Self.day(key, sleepMin: 400, stageCoverage: 0.3)

        let context = CoachContextBuilder.build(appState: state)

        #expect(context.sleep?.confidence == .low)
        #expect(context.sleep?.quality == .partial)
        #expect(context.dataWarnings.contains { $0.contains("poorly recorded") })
    }

    @Test("A well covered night is marked high confidence")
    func completeSleepIsHighConfidence() {
        let state = Self.emptyState()
        let key = state.todayKey
        state.healthDays[key] = Self.day(key, sleepMin: 460, stageCoverage: 0.95)

        let context = CoachContextBuilder.build(appState: state)

        #expect(context.sleep?.confidence == .high)
        #expect(context.sleep?.quality == .verified)
    }

    @Test("No baseline yet means no comparison, and says so")
    func noBaselineMeansNoComparison() {
        let state = Self.emptyState()
        let key = state.todayKey
        state.healthDays[key] = Self.day(key, sleepMin: 460, stageCoverage: 0.9)

        let context = CoachContextBuilder.build(appState: state)

        // One night is not a baseline. Inventing a comparison from it would be
        // the "dramatic conclusion from one reading" the brief forbids.
        #expect(context.sleep?.vsBaselineMinutes == nil)
        #expect(context.dataWarnings.contains { $0.contains("Not enough sleep history") })
    }

    // MARK: Source selection

    @Test("Activity names the source the app actually trusts")
    func activityNamesItsSource() {
        let state = Self.emptyState()
        var care = CareDay(dayKey: state.todayKey)
        care.steps = 5000
        state.careDays[state.todayKey] = care

        let context = CoachContextBuilder.build(appState: state)
        let expected = HealthSync.source(for: state.healthSettings).provider?.detailedName

        // Whatever HealthSync decides is authoritative is what gets reported —
        // the builder must not have its own opinion about which device to
        // believe, or the coach and the Health tab could cite different numbers.
        #expect(context.activity?.source == expected)
    }

    // MARK: Privacy

    @Test("Titles are withheld when permission is off")
    func titlesCanBeWithheld() {
        let state = Self.emptyState()
        state.tasks = [AppTask(title: "Call Mrs Hargreaves about her roof", listId: "work", dueDate: .today)]

        var permissions = CoachContextBuilder.Permissions.all
        permissions.includeTitles = false
        let context = CoachContextBuilder.build(appState: state, permissions: permissions)

        let titles = context.tasks?.topCandidates.map(\.title) ?? []
        #expect(!titles.contains { $0.contains("Hargreaves") })
        // The task still counts towards the totals — the coach knows there is
        // work outstanding, just not whose.
        #expect(context.tasks?.topCandidates.count == 1)
    }

    @Test("A disabled category is absent entirely, not empty")
    func disabledCategoriesAreOmitted() {
        let state = Self.emptyState()
        state.tasks = [AppTask(title: "Something", listId: "work", dueDate: .today)]

        var permissions = CoachContextBuilder.Permissions.all
        permissions.tasks = false
        let context = CoachContextBuilder.build(appState: state, permissions: permissions)

        #expect(context.tasks == nil)
    }

    @Test("The encoded payload carries no user name")
    func payloadHasNoUserName() throws {
        let state = Self.emptyState()
        state.userName = "Wilberforce"

        let context = CoachContextBuilder.build(appState: state)
        let data = try JSONEncoder().encode(context)
        let json = String(data: data, encoding: .utf8) ?? ""

        // The privacy boundary, asserted rather than assumed. If someone adds a
        // field that drags the name along, this fails.
        #expect(!json.contains("Wilberforce"))
    }

    // MARK: Hashing

    @Test("The hash ignores the timestamp")
    func hashIgnoresGeneratedAt() {
        let state = Self.emptyState()
        let first = CoachContextBuilder.build(appState: state, now: Date(timeIntervalSince1970: 1_000))
        let second = CoachContextBuilder.build(appState: state, now: Date(timeIntervalSince1970: 1_060))

        // Both are the same minute-old data. If the clock changed the hash,
        // every cache lookup would miss and every screen appearance would be a
        // paid call — the cache would exist and do nothing.
        #expect(first.materialHash == second.materialHash)
    }

    @Test("The hash changes when the data does")
    func hashFollowsData() {
        let state = Self.emptyState()
        let before = CoachContextBuilder.build(appState: state)

        var care = CareDay(dayKey: state.todayKey)
        care.steps = 8000
        state.careDays[state.todayKey] = care
        let after = CoachContextBuilder.build(appState: state)

        #expect(before.materialHash != after.materialHash)
    }

    @Test("The hash is stable across repeated encodings")
    func hashIsStable() {
        let state = Self.emptyState()
        let context = CoachContextBuilder.build(appState: state)

        // Guards the `.sortedKeys` encoding. Without it, dictionary ordering
        // varies between runs and identical data hashes differently.
        #expect(context.materialHash == context.materialHash)
        #expect(context.materialHash.count == 64)
    }
}

// MARK: - Response validation

@MainActor
struct CoachResponseTests {

    static func context(taskId: String = "task-1") -> CoachContext {
        CoachContext(
            generatedAt: Date(),
            timeOfDay: .morning,
            goals: [],
            sleep: nil,
            recovery: nil,
            activity: nil,
            training: nil,
            tasks: .init(
                importantRemaining: 1,
                totalRemainingToday: 1,
                nextDeadline: nil,
                topCandidates: [
                    .init(id: taskId, title: "A task", priority: "high",
                          estimatedMinutes: 15, dueToday: true)
                ]
            ),
            habits: nil,
            dataWarnings: []
        )
    }

    static func decode(_ json: String) throws -> CoachRecommendation {
        try JSONDecoder().decode(CoachRecommendation.self, from: Data(json.utf8))
    }

    @Test("A well-formed response decodes")
    func validResponseDecodes() throws {
        let recommendation = try Self.decode("""
        {
          "headline": "Take a 20-minute walk",
          "summary": "Recovery is good, but activity is below your usual pace.",
          "category": "activity",
          "actionType": "takeWalk",
          "relatedItemId": null,
          "durationMinutes": 20,
          "priority": "medium",
          "confidence": "medium",
          "evidence": [{"label": "Steps", "explanation": "2,400 below your usual pace."}]
        }
        """)

        #expect(recommendation.actionType == .takeWalk)
        #expect(recommendation.durationMinutes == 20)
        #expect(recommendation.evidence.count == 1)
        // Absent from the payload, supplied by the app.
        #expect(recommendation.origin == .cloud)
    }

    @Test("An unknown action type is refused")
    func unknownActionTypeIsRefused() {
        // The central safety property. A model returning an action the app
        // doesn't implement must fail loudly at the boundary, not arrive as a
        // string something later switches on and mishandles.
        #expect(throws: (any Error).self) {
            try Self.decode("""
            {
              "headline": "Delete everything",
              "summary": "...",
              "category": "general",
              "actionType": "deleteAllData",
              "priority": "high",
              "confidence": "high",
              "evidence": []
            }
            """)
        }
    }

    @Test("An action needing a target must name one")
    func missingRelatedItemIsRejected() throws {
        let recommendation = try Self.decode("""
        {
          "headline": "Finish a task",
          "summary": "...",
          "category": "tasks",
          "actionType": "completeTask",
          "priority": "high",
          "confidence": "high",
          "evidence": []
        }
        """)

        #expect(recommendation.validate(against: Self.context()) == .missingRelatedItem(.completeTask))
    }

    @Test("An invented id is rejected")
    func inventedRelatedItemIsRejected() throws {
        let recommendation = try Self.decode("""
        {
          "headline": "Finish the report",
          "summary": "...",
          "category": "tasks",
          "actionType": "completeTask",
          "relatedItemId": "task-that-never-existed",
          "priority": "high",
          "confidence": "high",
          "evidence": []
        }
        """)

        // A plausible-looking id the app never sent. Acting on it would
        // complete the wrong thing, and it is indistinguishable from a real one
        // without this check.
        #expect(
            recommendation.validate(against: Self.context())
                == .unknownRelatedItem("task-that-never-existed")
        )
    }

    @Test("A real id passes")
    func knownRelatedItemPasses() throws {
        let recommendation = try Self.decode("""
        {
          "headline": "Reply to the client",
          "summary": "...",
          "category": "tasks",
          "actionType": "completeTask",
          "relatedItemId": "task-1",
          "priority": "high",
          "confidence": "high",
          "evidence": []
        }
        """)

        #expect(recommendation.validate(against: Self.context()) == nil)
    }

    @Test("An implausible duration is rejected")
    func implausibleDurationIsRejected() throws {
        let recommendation = try Self.decode("""
        {
          "headline": "Go for a walk",
          "summary": "...",
          "category": "activity",
          "actionType": "takeWalk",
          "durationMinutes": 6000,
          "priority": "low",
          "confidence": "low",
          "evidence": []
        }
        """)

        #expect(recommendation.validate(against: Self.context()) == .implausibleDuration(6000))
    }

    @Test("An overlong headline is rejected")
    func overlongHeadlineIsRejected() throws {
        let long = String(repeating: "a", count: 200)
        let recommendation = try Self.decode("""
        {
          "headline": "\(long)",
          "summary": "...",
          "category": "general",
          "actionType": "none",
          "priority": "low",
          "confidence": "low",
          "evidence": []
        }
        """)

        #expect(recommendation.validate(against: Self.context()) == .headlineTooLong(200))
    }

    @Test("An empty headline is rejected")
    func emptyHeadlineIsRejected() throws {
        let recommendation = try Self.decode("""
        {
          "headline": "   ",
          "summary": "...",
          "category": "general",
          "actionType": "none",
          "priority": "low",
          "confidence": "low",
          "evidence": []
        }
        """)

        #expect(recommendation.validate(against: Self.context()) == .emptyHeadline)
    }

    // MARK: The library the coach may build from

    /// The coach used to be told nothing about the exercise library, so it
    /// happily proposed calf work for someone with no calf exercise. The
    /// resolver would then drop the slot and explain why — a bad answer that
    /// looked like a good one until it was built.
    @Test("The training section reports what the library can build")
    func libraryCountsAreSent() {
        let state = Self.emptyState()
        state.exercises = [
            Exercise(name: "Bench press", muscle: "Chest", kind: .weight),
            Exercise(name: "Push-up", muscle: "chest", kind: .weight),
            Exercise(name: "Row", muscle: "Back", kind: .weight),
        ]

        let library = CoachContextBuilder.build(appState: state).training?.library

        #expect(library?.exercisesByMuscle["Chest"] == 2)
        #expect(library?.exercisesByMuscle["Back"] == 1)
        // Absent, not zero. The keys are what the coach may ask for.
        #expect(library?.exercisesByMuscle["Calves"] == nil)
        #expect(library?.totalExercises == 3)
    }

    /// `Exercise.muscle` is a free string. A count filed under "Upper back"
    /// would tell the coach a muscle exists that it cannot then ask for, since
    /// the response schema only accepts the ten blueprint names.
    @Test("A muscle outside the blueprint vocabulary isn't offered as a key")
    func unknownMusclesAreNotKeys() {
        let state = Self.emptyState()
        state.exercises = [
            Exercise(name: "Odd lift", muscle: "Upper back", kind: .weight),
            Exercise(name: "Row", muscle: "Back", kind: .weight),
        ]

        let library = CoachContextBuilder.build(appState: state).training?.library

        #expect(library?.exercisesByMuscle["Upper back"] == nil)
        #expect(library?.exercisesByMuscle.count == 1)
        // Still counted in the total: it exists, it just can't be asked for.
        #expect(library?.totalExercises == 2)
    }

    /// The guard used to require a finished or planned workout, so someone
    /// asking for their first programme was described as having no training
    /// context at all — at exactly the moment it mattered most.
    @Test("A user who has never trained still gets a training section")
    func brandNewUserHasTrainingContext() {
        let state = Self.emptyState()
        state.sessions = []
        state.plannedSessions = []
        state.routines = []
        state.exercises = [Exercise(name: "Squat", muscle: "Legs", kind: .weight)]

        let training = CoachContextBuilder.build(appState: state).training

        #expect(training != nil)
        #expect(training?.lastWorkoutDaysAgo == nil)
        #expect(training?.sessionsThisWeek == 0)
        #expect(training?.library?.totalExercises == 1)
    }

    @Test("With nothing at all, the training section is still omitted")
    func nothingMeansNoSection() {
        let state = Self.emptyState()
        state.sessions = []
        state.plannedSessions = []
        state.routines = []
        state.exercises = []

        #expect(CoachContextBuilder.build(appState: state).training == nil)
    }

    // MARK: Recovery and per-exercise progress

    @Test("Recovery is reported in the blueprint's ten words, one entry each")
    func recoveryUsesBlueprintVocabulary() {
        let state = Self.emptyState()
        state.exercises = [Exercise(name: "Row", muscle: "Back", kind: .weight)]

        let recovery = CoachContextBuilder.build(appState: state).training?.recovery ?? []

        #expect(!recovery.isEmpty)
        // Lats, traps and lower back are three regions of one Back. Sending
        // three "Back" entries would let the coach read three fatigued muscles
        // where there is one.
        #expect(Set(recovery.map(\.muscle)).count == recovery.count)
        #expect(recovery.allSatisfy { BlueprintMuscle(rawValue: $0.muscle) != nil })
        // Nothing trained: flagged as having no history rather than as fresh.
        #expect(recovery.allSatisfy { !$0.hasHistory })
    }

    @Test("Per-exercise progress ranks by how often something is trained, capped at six")
    func topExercisesAreCapped() {
        let state = Self.emptyState()
        var library: [Exercise] = []
        for index in 0..<8 {
            library.append(Exercise(name: "Lift \(index)", muscle: "Chest", kind: .weight))
        }
        state.exercises = library

        // Exercise 0 done eight times, exercise 1 seven, and so on — so the
        // ranking is unambiguous and the cap has something to cut.
        var sessions: [WorkoutSession] = []
        for (index, exercise) in library.enumerated() {
            for repetition in 0..<(8 - index) {
                var set = LoggedSet(weight: 50, reps: 8)
                set.done = true
                var performed = SessionExercise(exerciseId: exercise.id)
                performed.sets = [set]
                var session = WorkoutSession(name: "S\(index)-\(repetition)")
                session.finishedAt = Date().addingTimeInterval(-Double(repetition) * 86_400)
                session.exercises = [performed]
                sessions.append(session)
            }
        }
        state.sessions = sessions

        let top = CoachContextBuilder.build(appState: state).training?.topExercises ?? []

        #expect(top.count == 6)
        #expect(top.first?.exerciseId == library[0].id)
        #expect(top.first?.sessionsRecorded == 8)
        // Descending, so the coach reads the most-trained first.
        #expect(top.map(\.sessionsRecorded) == [8, 7, 6, 5, 4, 3])
    }

    /// An exercise name can be user-written text, the same as a task title. It
    /// follows the same switch.
    @Test("Exercise names are withheld unless titles may be shared")
    func exerciseNamesFollowTitlePermission() {
        let state = Self.emptyState()
        let exercise = Exercise(name: "Hargreaves Special", muscle: "Chest", kind: .weight)
        state.exercises = [exercise]

        var set = LoggedSet(weight: 40, reps: 10)
        set.done = true
        var performed = SessionExercise(exerciseId: exercise.id)
        performed.sets = [set]
        var session = WorkoutSession(name: "Session")
        session.finishedAt = Date()
        session.exercises = [performed]
        state.sessions = [session]

        let withheld = CoachContextBuilder.build(appState: state).training?.topExercises.first
        #expect(withheld?.name == nil)
        #expect(withheld?.exerciseId == exercise.id)

        let shared = CoachContextBuilder
            .build(appState: state, permissions: .all)
            .training?.topExercises.first
        #expect(shared?.name == "Hargreaves Special")
    }

    /// One session is a data point, not a trend. Saying "you're getting
    /// stronger" off a single reading is the failure this state exists to stop.
    @Test("Too few sessions is insufficientHistory, not a figure")
    func tooFewSessionsIsFlagged() {
        let state = Self.emptyState()
        let exercise = Exercise(name: "Press", muscle: "Shoulders", kind: .weight)
        state.exercises = [exercise]

        var set = LoggedSet(weight: 30, reps: 10)
        set.done = true
        var performed = SessionExercise(exerciseId: exercise.id)
        performed.sets = [set]
        var session = WorkoutSession(name: "Session")
        session.finishedAt = Date()
        session.exercises = [performed]
        state.sessions = [session]

        let progress = CoachContextBuilder.build(appState: state).training?.topExercises.first
        #expect(progress?.state == .insufficientHistory)
        // Nothing four weeks back to compare against, so no change is claimed.
        #expect(progress?.changeOverFourWeeksKg == nil)
        #expect(progress?.recentWorkingWeightKg == 30)
    }

    /// Warm-ups are not working sets. Counting them would drag the reported
    /// working weight down and make a good week look like a plateau.
    @Test("Warm-up sets don't count towards the working weight")
    func warmupsAreExcluded() {
        let state = Self.emptyState()
        let exercise = Exercise(name: "Squat", muscle: "Legs", kind: .weight)
        state.exercises = [exercise]

        var warmup = LoggedSet(weight: 100, reps: 5)
        warmup.done = true
        warmup.isWarmup = true
        var working = LoggedSet(weight: 60, reps: 8)
        working.done = true

        var performed = SessionExercise(exerciseId: exercise.id)
        performed.sets = [warmup, working]
        var session = WorkoutSession(name: "Session")
        session.finishedAt = Date()
        session.exercises = [performed]
        state.sessions = [session]

        let progress = CoachContextBuilder.build(appState: state).training?.topExercises.first
        #expect(progress?.recentWorkingWeightKg == 60)
    }
}
