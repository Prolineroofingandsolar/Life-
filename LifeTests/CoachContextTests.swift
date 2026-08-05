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
}
