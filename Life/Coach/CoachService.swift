import Foundation
import FirebaseAuth

// MARK: - Transport

/// The network boundary, behind a protocol so tests never reach it.
///
/// Every test in this feature uses a stub conforming to this. The brief
/// requires it, and it is also the only way to test the paths that matter —
/// a malformed response, a refusal, a timeout — none of which a real endpoint
/// can be asked to produce on demand.
protocol CoachTransport: Sendable {
    /// Posts to the callable and returns its `result` payload.
    func send(_ body: [String: Any], idToken: String) async throws -> [String: Any]
}

/// Where the deployed function lives.
///
/// Configurable rather than compiled in. A Cloud Functions URL depends on the
/// project, the region and the generation of the runtime, and guessing it wrong
/// produces a feature that fails with no clue why. Settings can override it;
/// the default is the conventional form for the project.
enum CoachEndpoint {

    private static let key = "coach_endpoint_url_v1"

    static let defaultURL = "https://europe-west2-life-1812f.cloudfunctions.net"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: key) ?? defaultURL }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func url(for function: String) -> URL? {
        URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + function)
    }
}

/// Calls the Firebase callable function over plain HTTPS.
///
/// Deliberately not the FirebaseFunctions SDK. The app links only FirebaseAuth
/// and FirebaseFirestore, and adding a third package product is a change to the
/// Xcode project rather than to code. The callable protocol is simple enough to
/// speak directly — a bearer token and a `{"data": …}` envelope — and doing so
/// keeps this type substitutable, which the SDK's concrete client is not.
struct HTTPCoachTransport: CoachTransport {

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ body: [String: Any], idToken: String) async throws -> [String: Any] {
        guard let url = CoachEndpoint.url(for: "coach") else {
            throw CoachError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // What proves who is calling. Without it the function refuses, which is
        // the entire reason the key is safe on the other side.
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": body])

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CoachError.transport("No response.")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200..<300).contains(http.statusCode) else {
            // The callable error envelope carries a message written for the
            // user — a rate limit, a spend ceiling — so it is preferred over a
            // status code where present.
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            if http.statusCode == 429 || message?.localizedCaseInsensitiveContains("limit") == true {
                throw CoachError.limitReached(message ?? "Limit reached.")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CoachError.notSignedIn
            }
            throw CoachError.transport(message ?? "The coach is unavailable.")
        }

        guard let result = json?["result"] as? [String: Any] else {
            throw CoachError.transport("Unexpected response.")
        }
        return result
    }
}

// MARK: - Errors

enum CoachError: LocalizedError, Equatable {
    case disabled
    case notConfigured
    case notSignedIn
    case limitReached(String)
    case transport(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "The coach is switched off in Settings."
        case .notConfigured:
            return "The coach backend hasn't been set up yet."
        case .notSignedIn:
            return "Sign in to use the coach."
        case .limitReached(let message):
            return message
        case .transport(let message):
            return message
        case .invalidResponse(let reason):
            return "The coach's answer didn't make sense (\(reason))."
        }
    }
}

// MARK: - Coach Service

/// Produces coach output, from the cache, the network or the local rules — in
/// that order of preference.
///
/// The order is the design. Cache first because a repeated question with the
/// same answer shouldn't be paid for twice; network second because it's better;
/// local last because *something sensible* beats an error message on a card
/// whose whole job is to tell you what to do next.
@MainActor
final class CoachService {

    private let transport: CoachTransport
    private let cache: CoachCache
    private let usage: CoachUsage
    /// Injected so tests don't need a signed-in Firebase user.
    private let idTokenProvider: () async throws -> String?

    /// Collaborators default to nil rather than to `.shared`.
    ///
    /// A default argument is evaluated in the caller's context, which is not
    /// necessarily the main actor — so naming a main-actor-isolated singleton
    /// there is an isolation violation, and an error outright under Swift 6.
    /// Resolving nil inside the body works because the body *is* main-actor
    /// isolated, this type being `@MainActor`.
    init(
        transport: CoachTransport = HTTPCoachTransport(),
        cache: CoachCache? = nil,
        usage: CoachUsage? = nil,
        idTokenProvider: (() async throws -> String?)? = nil
    ) {
        self.transport = transport
        self.cache = cache ?? .shared
        self.usage = usage ?? .shared
        self.idTokenProvider = idTokenProvider ?? {
            guard AuthManager.isFirebaseReady, let user = Auth.auth().currentUser else { return nil }
            return try await user.getIDToken()
        }
    }

    /// How the answer was arrived at, so the UI can be honest about it rather
    /// than presenting a rule-based line as though a model wrote it.
    struct Outcome {
        var recommendation: CoachRecommendation
        /// Set when the cloud was tried and didn't work. Shown quietly — the
        /// recommendation is still usable.
        var note: String?
    }

    // MARK: Recommendation

    func recommendation(
        for context: CoachContext,
        settings: CoachSettings
    ) async -> Outcome {
        guard settings.enabled else {
            return Outcome(recommendation: LocalCoach.recommend(from: context), note: nil)
        }

        if let cached = cache.recommendation(for: context) {
            return Outcome(recommendation: cached, note: nil)
        }

        guard settings.mayUseCloud else {
            let local = LocalCoach.recommend(from: context)
            cache.store(local, for: context)
            return Outcome(recommendation: local, note: nil)
        }

        // Refusing here saves a round trip that the server would reject anyway,
        // and lets the card explain itself instead of showing a failure.
        guard usage.canAffordCall() else {
            let local = LocalCoach.recommend(from: context)
            cache.store(local, for: context)
            return Outcome(
                recommendation: local,
                note: "This month's AI limit has been reached — showing a local suggestion."
            )
        }

        do {
            let recommendation = try await fetchRecommendation(context: context, settings: settings)
            cache.store(recommendation, for: context)
            return Outcome(recommendation: recommendation, note: nil)
        } catch {
            // The fallback, not an error state. A card that says "couldn't
            // reach the coach" where a suggestion belongs has failed at its job
            // twice over: no advice, and a complaint.
            let local = LocalCoach.recommend(from: context)
            cache.store(local, for: context)
            return Outcome(
                recommendation: local,
                note: (error as? CoachError)?.errorDescription
            )
        }
    }

    /// One call, one repair attempt, then give up.
    ///
    /// Exactly one retry, and only when the first response failed *validation*
    /// — a transport failure is retried by nobody, because the brief forbids
    /// repeated retries and because a second call to a failing endpoint mostly
    /// buys a second failure and a second charge.
    private func fetchRecommendation(
        context: CoachContext,
        settings: CoachSettings
    ) async throws -> CoachRecommendation {
        let first = try await call(mode: "recommendation", context: context, settings: settings)

        switch first {
        case .success(let recommendation):
            return recommendation
        case .rejected(let reason):
            let repaired = try await call(
                mode: "recommendation",
                context: context,
                settings: settings,
                repairReason: reason
            )
            switch repaired {
            case .success(let recommendation):
                return recommendation
            case .rejected(let reason):
                throw CoachError.invalidResponse(reason)
            }
        }
    }

    private enum CallResult {
        case success(CoachRecommendation)
        case rejected(String)
    }

    private func call(
        mode: String,
        context: CoachContext,
        settings: CoachSettings,
        question: String? = nil,
        repairReason: String? = nil
    ) async throws -> CallResult {
        guard let idToken = try await idTokenProvider() else {
            throw CoachError.notSignedIn
        }

        var body: [String: Any] = [
            "mode": mode,
            "context": try encodeContext(context),
            "style": settings.style.instruction
        ]
        if let question { body["question"] = question }
        if let repairReason { body["repairReason"] = repairReason }

        let result = try await transport.send(body, idToken: idToken)

        recordUsage(from: result)

        // The server reports a failed schema check as data rather than an
        // error, because the app needs the reason in order to ask for a repair.
        if let ok = result["ok"] as? Bool, ok == false {
            return .rejected(result["reason"] as? String ?? "unknown")
        }

        guard let value = result["value"],
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            throw CoachError.invalidResponse("no value")
        }

        // Decoding is the second gate: a response naming an action the app
        // doesn't implement fails here rather than arriving as a live
        // instruction.
        let decoder = JSONDecoder()
        guard var recommendation = try? decoder.decode(CoachRecommendation.self, from: data) else {
            return .rejected("could not be decoded")
        }

        // The third gate, and the one the server cannot perform: it never saw
        // the real id list, so only the app can tell an invented reference from
        // a genuine one.
        if let failure = recommendation.validate(against: context) {
            return .rejected(failure.description)
        }

        recommendation.origin = .cloud
        recommendation.generatedAt = Date()
        return .success(recommendation)
    }

    private func encodeContext(_ context: CoachContext) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(context)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoachError.invalidResponse("context could not be encoded")
        }
        return object
    }

    private func recordUsage(from result: [String: Any]) {
        guard let usageInfo = result["usage"] as? [String: Any] else { return }
        usage.record(
            promptTokens: usageInfo["promptTokens"] as? Int ?? 0,
            outputTokens: usageInfo["outputTokens"] as? Int ?? 0,
            cost: usageInfo["cost"] as? Double ?? 0
        )
    }

    // MARK: Briefings

    func briefing(
        kind: CoachBriefing.Kind,
        context: CoachContext,
        settings: CoachSettings
    ) async -> CoachBriefing {
        // One a day, whatever else happens. A briefing regenerated at eleven
        // because the step count moved is a different briefing about the same
        // morning.
        if let cached = cache.briefing(kind: kind) { return cached }

        guard settings.enabled else { return LocalCoach.briefing(kind: kind, from: context) }

        guard settings.mayUseCloud, usage.canAffordCall() else {
            let local = LocalCoach.briefing(kind: kind, from: context)
            cache.store(local)
            return local
        }

        do {
            let briefing = try await fetchBriefing(kind: kind, context: context, settings: settings)
            cache.store(briefing)
            return briefing
        } catch {
            let local = LocalCoach.briefing(kind: kind, from: context)
            cache.store(local)
            return local
        }
    }

    private func fetchBriefing(
        kind: CoachBriefing.Kind,
        context: CoachContext,
        settings: CoachSettings
    ) async throws -> CoachBriefing {
        guard let idToken = try await idTokenProvider() else {
            throw CoachError.notSignedIn
        }

        let body: [String: Any] = [
            "mode": kind == .morning ? "morningBriefing" : "eveningReview",
            "context": try encodeContext(context),
            "style": settings.style.instruction
        ]

        let result = try await transport.send(body, idToken: idToken)
        recordUsage(from: result)

        guard let value = result["value"] as? [String: Any],
              let headline = value["headline"] as? String,
              let text = value["body"] as? String else {
            throw CoachError.invalidResponse("briefing was incomplete")
        }

        let evidence = (value["evidence"] as? [[String: Any]] ?? []).compactMap { entry -> CoachEvidence? in
            guard let label = entry["label"] as? String,
                  let explanation = entry["explanation"] as? String else { return nil }
            return CoachEvidence(label: label, explanation: explanation)
        }

        return CoachBriefing(
            kind: kind,
            headline: headline,
            body: text,
            evidence: evidence,
            safetyNotice: value["safetyNotice"] as? String,
            origin: .cloud,
            generatedAt: Date(),
            contextHash: context.materialHash
        )
    }

    // MARK: Ask

    /// A free-text question. Never falls back to a local answer — the rules can
    /// recommend an action but they cannot answer "why was my sleep bad this
    /// week", and inventing something would be worse than saying it failed.
    func ask(
        _ question: String,
        context: CoachContext,
        settings: CoachSettings
    ) async throws -> String {
        guard settings.enabled else { throw CoachError.disabled }
        guard settings.mayUseCloud else { throw CoachError.disabled }
        guard usage.canAffordCall() else {
            throw CoachError.limitReached("This month's AI limit has been reached.")
        }

        guard let idToken = try await idTokenProvider() else {
            throw CoachError.notSignedIn
        }

        let trimmed = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { throw CoachError.invalidResponse("empty question") }

        let body: [String: Any] = [
            "mode": "ask",
            "context": try encodeContext(context),
            "question": trimmed,
            "style": settings.style.instruction
        ]

        let result = try await transport.send(body, idToken: idToken)
        recordUsage(from: result)

        guard let value = result["value"] as? [String: Any],
              let summary = (value["summary"] as? String) ?? (value["body"] as? String) else {
            throw CoachError.invalidResponse("no answer")
        }
        return summary
    }
}
