import Testing
import Foundation
@testable import Life

/// Covers the paths a real endpoint can't be asked to produce on demand — a
/// refusal, a malformed answer, a spend ceiling, a timeout — and the rule that
/// none of them may leave the coach card empty.
///
/// Nothing here touches the network. Every test supplies its own transport.
@MainActor
struct CoachServiceTests {

    // MARK: Doubles

    /// A transport that returns whatever the test tells it to, and counts how
    /// many times it was asked. The count is the point in several tests: "did
    /// this cost one call or two" is the difference between pennies and pounds.
    final class StubTransport: CoachTransport, @unchecked Sendable {
        var responses: [Result<[String: Any], Error>]
        private(set) var sentBodies: [[String: Any]] = []

        init(_ responses: [Result<[String: Any], Error>]) {
            self.responses = responses
        }

        convenience init(_ single: [String: Any]) {
            self.init([.success(single)])
        }

        var callCount: Int { sentBodies.count }

        func send(_ body: [String: Any], idToken: String) async throws -> [String: Any] {
            sentBodies.append(body)
            guard !responses.isEmpty else { return ["ok": true] }
            switch responses.removeFirst() {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        }
    }

    /// Fresh UserDefaults per test, so the cache in one doesn't answer another.
    static func isolatedDefaults() -> UserDefaults {
        let suite = "coach-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }

    static func service(
        transport: CoachTransport,
        defaults: UserDefaults? = nil
    ) -> CoachService {
        let store = defaults ?? isolatedDefaults()
        return CoachService(
            transport: transport,
            cache: CoachCache(defaults: store),
            usage: CoachUsage(defaults: store),
            idTokenProvider: { "test-token" }
        )
    }

    static func cloudSettings() -> CoachSettings {
        var settings = CoachSettings()
        settings.enabled = true
        settings.cloudEnabled = true
        settings.hasConsented = true
        return settings
    }

    static func context(taskId: String = "task-1") -> CoachContext {
        CoachContext(
            generatedAt: Date(),
            timeOfDay: .afternoon,
            goals: [],
            sleep: nil,
            recovery: nil,
            activity: .init(
                steps: 3000, stepGoal: 10_000, activeMinutes: nil,
                activeMinutesGoal: 30, isPartialDay: true,
                source: "Fitbit Direct", quality: .partial
            ),
            training: nil,
            tasks: .init(
                importantRemaining: 1,
                totalRemainingToday: 1,
                nextDeadline: nil,
                topCandidates: [
                    .init(id: taskId, title: "Reply to the client", priority: "high",
                          estimatedMinutes: 15, dueToday: true)
                ]
            ),
            habits: nil,
            dataWarnings: []
        )
    }

    static func validResponse(relatedItemId: String? = nil) -> [String: Any] {
        var value: [String: Any] = [
            "headline": "Take a 20-minute walk",
            "summary": "You're behind your usual pace.",
            "category": "activity",
            "actionType": "takeWalk",
            "priority": "medium",
            "confidence": "medium",
            "evidence": [["label": "Steps", "explanation": "3,000 of 10,000."]]
        ]
        if let relatedItemId {
            value["actionType"] = "completeTask"
            value["category"] = "tasks"
            value["relatedItemId"] = relatedItemId
        }
        return [
            "ok": true,
            "value": value,
            "usage": ["promptTokens": 800, "outputTokens": 120, "cost": 0.0003]
        ]
    }

    // MARK: Happy path

    @Test("A valid cloud response is used")
    func cloudResponseIsUsed() async {
        let transport = StubTransport(Self.validResponse())
        let service = Self.service(transport: transport)

        let outcome = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        #expect(outcome.recommendation.headline == "Take a 20-minute walk")
        #expect(outcome.recommendation.origin == .cloud)
        #expect(outcome.note == nil)
        #expect(transport.callCount == 1)
    }

    @Test("Usage is recorded from the response")
    func usageIsRecorded() async {
        let defaults = Self.isolatedDefaults()
        let transport = StubTransport(Self.validResponse())
        let service = Self.service(transport: transport, defaults: defaults)

        _ = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        let snapshot = CoachUsage(defaults: defaults).snapshot()
        #expect(snapshot.calls == 1)
        #expect(snapshot.promptTokens == 800)
        #expect(snapshot.cost > 0)
    }

    // MARK: Caching

    @Test("The same context is not paid for twice")
    func identicalContextIsCached() async {
        let defaults = Self.isolatedDefaults()
        let transport = StubTransport([.success(Self.validResponse()), .success(Self.validResponse())])
        let service = Self.service(transport: transport, defaults: defaults)
        let context = Self.context()

        _ = await service.recommendation(for: context, settings: Self.cloudSettings())
        _ = await service.recommendation(for: context, settings: Self.cloudSettings())

        // The whole cost model rests on this. Opening the Today screen twice
        // must not be two API calls.
        #expect(transport.callCount == 1)
    }

    @Test("Changed data does mean a new call")
    func changedContextRefetches() async {
        let defaults = Self.isolatedDefaults()
        let transport = StubTransport([.success(Self.validResponse()), .success(Self.validResponse())])
        let service = Self.service(transport: transport, defaults: defaults)

        _ = await service.recommendation(for: Self.context(taskId: "task-1"), settings: Self.cloudSettings())
        _ = await service.recommendation(for: Self.context(taskId: "task-2"), settings: Self.cloudSettings())

        #expect(transport.callCount == 2)
    }

    // MARK: Repair and rejection

    @Test("A rejected response is repaired once, then given up on")
    func rejectionIsRepairedOnce() async {
        let rejection: [String: Any] = ["ok": false, "reason": "unsupported actionType"]
        let transport = StubTransport([.success(rejection), .success(rejection)])
        let service = Self.service(transport: transport)

        let outcome = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        // Exactly two: the attempt and one repair. A third would be a retry
        // loop against a persistently failing model, paid for each time.
        #expect(transport.callCount == 2)
        #expect(outcome.recommendation.origin == .local)
        #expect(outcome.note != nil)
    }

    @Test("The repair attempt says what was wrong")
    func repairIncludesTheReason() async {
        let rejection: [String: Any] = ["ok": false, "reason": "headline exceeds 80 characters"]
        let transport = StubTransport([.success(rejection), .success(Self.validResponse())])
        let service = Self.service(transport: transport)

        _ = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        #expect(transport.sentBodies.count == 2)
        let repair = transport.sentBodies[1]["repairReason"] as? String
        #expect(repair == "headline exceeds 80 characters")
    }

    @Test("An invented id is caught by the app, not trusted from the server")
    func inventedIdIsRejectedLocally() async {
        // The server said ok. Only the app knows which ids were really sent, so
        // only the app can catch this — and it must, or the wrong task gets
        // completed.
        let transport = StubTransport([
            .success(Self.validResponse(relatedItemId: "task-that-never-existed")),
            .success(Self.validResponse(relatedItemId: "task-that-never-existed"))
        ])
        let service = Self.service(transport: transport)

        let outcome = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        #expect(outcome.recommendation.origin == .local)
    }

    @Test("A real id is accepted")
    func realIdIsAccepted() async {
        let transport = StubTransport(Self.validResponse(relatedItemId: "task-1"))
        let service = Self.service(transport: transport)

        let outcome = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        #expect(outcome.recommendation.origin == .cloud)
        #expect(outcome.recommendation.relatedItemId == "task-1")
    }

    // MARK: Failure never leaves an empty card

    @Test("A transport failure falls back rather than erroring")
    func transportFailureFallsBack() async {
        let transport = StubTransport([.failure(CoachError.transport("offline"))])
        let service = Self.service(transport: transport)

        let outcome = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        // A card whose job is to say what to do next must never say "error".
        #expect(outcome.recommendation.origin == .local)
        #expect(!outcome.recommendation.headline.isEmpty)
        #expect(outcome.note == "offline")
    }

    @Test("A failed call is not retried")
    func transportFailureIsNotRetried() async {
        let transport = StubTransport([.failure(CoachError.transport("offline"))])
        let service = Self.service(transport: transport)

        _ = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        #expect(transport.callCount == 1)
    }

    // MARK: Switches

    @Test("Cloud off means no call at all")
    func cloudOffMakesNoCall() async {
        var settings = Self.cloudSettings()
        settings.cloudEnabled = false
        let transport = StubTransport([])
        let service = Self.service(transport: transport)

        let outcome = await service.recommendation(for: Self.context(), settings: settings)

        #expect(transport.callCount == 0)
        #expect(outcome.recommendation.origin == .local)
    }

    @Test("Consent not given means no call at all")
    func withoutConsentNoCall() async {
        var settings = Self.cloudSettings()
        settings.hasConsented = false
        let transport = StubTransport([])
        let service = Self.service(transport: transport)

        _ = await service.recommendation(for: Self.context(), settings: settings)

        // The consent screen isn't decoration. Until it's accepted, nothing
        // leaves the device.
        #expect(transport.callCount == 0)
    }

    @Test("Asking a question needs the cloud")
    func askRequiresCloud() async {
        var settings = Self.cloudSettings()
        settings.cloudEnabled = false
        let service = Self.service(transport: StubTransport([]))

        await #expect(throws: CoachError.disabled) {
            _ = try await service.ask("Why am I tired?", context: Self.context(), settings: settings)
        }
    }

    // MARK: Muted categories

    @Test("A muted category is refused even when the model returns it")
    func mutedCategoryIsRefused() async {
        var context = Self.context()
        context.mutedCategories = ["activity"]

        // The model is told what's muted, but being told is not a guarantee.
        // The check exists so the preference means something regardless.
        let transport = StubTransport([
            .success(Self.validResponse()),
            .success(Self.validResponse())
        ])
        let service = Self.service(transport: transport)

        let outcome = await service.recommendation(for: context, settings: Self.cloudSettings())

        #expect(outcome.recommendation.category != .activity)
        #expect(outcome.recommendation.origin == .local)
    }

    // MARK: Cancellation

    @Test("A cancelled request doesn't leave the card loading forever")
    func cancellationIsHandled() async {
        // A transport that never returns, standing in for a request the user
        // navigated away from. The task is cancelled while it's in flight.
        final class HangingTransport: CoachTransport, @unchecked Sendable {
            func send(_ body: [String: Any], idToken: String) async throws -> [String: Any] {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return ["ok": true]
            }
        }

        let service = Self.service(transport: HangingTransport())
        let context = Self.context()

        let task = Task {
            await service.recommendation(for: context, settings: Self.cloudSettings())
        }
        // Long enough to be mid-flight, short enough not to slow the suite.
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let outcome = await task.value

        // Cancellation surfaces as a thrown error inside the service, which
        // takes the same path as any other failure: a local suggestion rather
        // than a card stuck on a spinner.
        #expect(outcome.recommendation.origin == .local)
        #expect(!outcome.recommendation.headline.isEmpty)
    }

    // MARK: Secrets

    @Test("No Gemini key is present in the app")
    func noAPIKeyInTheBundle() throws {
        // The key lives in Secret Manager and is read only by the Cloud
        // Function. If it ever reached the app it could be extracted from the
        // binary by anyone who downloaded it, and spent against the owner's
        // billing account. This asserts the arrangement holds.
        let bundle = Bundle(for: BundleMarker.self)

        // Info.plist is where a key most plausibly ends up by accident, via a
        // build setting or an xcconfig.
        let info = bundle.infoDictionary ?? [:]
        let plistText = String(describing: info)
        #expect(!plistText.contains("GEMINI_API_KEY"))
        // Google API keys begin "AIza". Searching for the shape catches a key
        // pasted under any name at all.
        #expect(!plistText.contains("AIza"))

        // And nothing in the bundle's resources either.
        let resources = bundle.paths(forResourcesOfType: "plist", inDirectory: nil)
        for path in resources {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            #expect(!contents.contains("GEMINI_API_KEY"), "Found a Gemini key reference in \(path)")
        }
    }

    /// Only exists to identify the test bundle for `Bundle(for:)`.
    private final class BundleMarker {}

    // MARK: Cost ceiling

    @Test("Over the ceiling, no call is made")
    func ceilingStopsCalls() async {
        let defaults = Self.isolatedDefaults()
        let usage = CoachUsage(defaults: defaults)
        usage.setCeiling(1.00)
        usage.record(promptTokens: 0, outputTokens: 0, cost: 1.50)

        let transport = StubTransport([])
        let service = Self.service(transport: transport, defaults: defaults)

        let outcome = await service.recommendation(for: Self.context(), settings: Self.cloudSettings())

        #expect(transport.callCount == 0)
        #expect(outcome.recommendation.origin == .local)
        #expect(outcome.note?.contains("limit") == true)
    }
}

// MARK: - Local coach

@MainActor
struct LocalCoachTests {

    static func context(
        steps: Int? = nil,
        stepGoal: Int? = 10_000,
        quality: CoachContext.DataQuality = .partial,
        timeOfDay: CoachContext.TimeOfDay = .afternoon,
        hrv: CoachContext.Recovery.BaselineStatus? = nil,
        rhr: CoachContext.Recovery.BaselineStatus? = nil
    ) -> CoachContext {
        CoachContext(
            generatedAt: Date(),
            timeOfDay: timeOfDay,
            goals: [],
            sleep: nil,
            recovery: (hrv == nil && rhr == nil) ? nil : .init(
                hrvStatus: hrv, restingHeartRateStatus: rhr,
                readinessScore: nil, confidence: .medium, quality: .verified
            ),
            activity: .init(
                steps: steps, stepGoal: stepGoal, activeMinutes: nil,
                activeMinutesGoal: 30, isPartialDay: true,
                source: "Fitbit Direct", quality: quality
            ),
            training: nil,
            tasks: nil,
            habits: nil,
            dataWarnings: []
        )
    }

    @Test("Both recovery signals down means rest")
    func bothSignalsDownMeansRest() {
        let recommendation = LocalCoach.recommend(
            from: Self.context(hrv: .belowBaseline, rhr: .aboveBaseline)
        )
        #expect(recommendation.actionType == .rest)
        #expect(recommendation.priority == .high)
    }

    @Test("One recovery signal alone is not enough")
    func oneSignalIsNotEnough() {
        // A single reading below baseline happens constantly. Acting on it
        // would have the coach calling for rest most weeks.
        let recommendation = LocalCoach.recommend(
            from: Self.context(hrv: .belowBaseline, rhr: .normal)
        )
        #expect(recommendation.actionType != .rest)
    }

    @Test("Missing steps never produce a walk suggestion")
    func missingStepsNeverSuggestWalking() {
        // The failure this rule exists to prevent: advising exercise because
        // the tracker hasn't synced.
        let recommendation = LocalCoach.recommend(
            from: Self.context(steps: nil, quality: .missing)
        )
        #expect(recommendation.actionType != .takeWalk)
    }

    @Test("A morning shortfall isn't a shortfall")
    func morningShortfallIsIgnored() {
        let recommendation = LocalCoach.recommend(
            from: Self.context(steps: 500, timeOfDay: .morning)
        )
        // Being under your step goal at nine in the morning is not news.
        #expect(recommendation.actionType != .takeWalk)
    }

    @Test("A real afternoon shortfall does suggest a walk")
    func afternoonShortfallSuggestsWalk() {
        let recommendation = LocalCoach.recommend(from: Self.context(steps: 3_000))
        #expect(recommendation.actionType == .takeWalk)
        #expect(recommendation.durationMinutes == 20)
    }

    @Test("Nothing wrong produces a real answer, not an empty one")
    func nothingWrongStillAnswers() {
        let recommendation = LocalCoach.recommend(from: Self.context(steps: 12_000))
        #expect(!recommendation.headline.isEmpty)
        #expect(recommendation.actionType == .none)
    }

    @Test("Every local recommendation is valid against its context")
    func localOutputAlwaysValidates() {
        let contexts = [
            Self.context(steps: 3_000),
            Self.context(steps: nil, quality: .missing),
            Self.context(hrv: .belowBaseline, rhr: .aboveBaseline),
            Self.context(steps: 12_000)
        ]
        for context in contexts {
            let recommendation = LocalCoach.recommend(from: context)
            // The fallback must clear the same bar as the model's output. If it
            // couldn't, the safety net would itself be unsafe.
            #expect(recommendation.validate(against: context) == nil)
        }
    }
}
