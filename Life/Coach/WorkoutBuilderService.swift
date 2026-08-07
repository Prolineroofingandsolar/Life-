import Foundation
import FirebaseAuth

// MARK: - Workout Builder Service

/// Asks Gemini for the shape of a session or a week.
///
/// Deliberately a sibling of `CoachService` rather than a method on it. They
/// share the transport, the usage ledger and the token provider — everything
/// that costs money or needs auth — but they differ in every way that matters
/// to their callers: this one is asked a specific question by a specific form,
/// its answer is large and structured, and its failure mode is "show the local
/// template" rather than "show a plainer sentence".
///
/// **No cache, on purpose.** `CoachCache` keys on `CoachContext.materialHash`,
/// which does not include the brief — so a cached plan would answer a question
/// it was never asked. "Build me a leg day" returning yesterday's push session
/// because the health figures hadn't moved is worse than paying for the call.
/// Generation is rare and user-initiated; the cache exists for the card that
/// renders on every appearance of the Today screen.
@MainActor
final class WorkoutBuilderService {

    private let transport: CoachTransport
    private let usage: CoachUsage
    private let idTokenProvider: () async throws -> String?

    /// Same nil-defaulting as `CoachService`: a default argument is evaluated in
    /// the caller's context, which is not necessarily the main actor, so naming
    /// a main-actor singleton there is an isolation violation.
    init(
        transport: CoachTransport = HTTPCoachTransport(),
        usage: CoachUsage? = nil,
        idTokenProvider: (() async throws -> String?)? = nil
    ) {
        self.transport = transport
        self.usage = usage ?? .shared
        self.idTokenProvider = idTokenProvider ?? {
            guard AuthManager.isFirebaseReady, let user = Auth.auth().currentUser else { return nil }
            return try await user.getIDToken()
        }
    }

    /// What came back, and where from.
    ///
    /// Provenance travels with the draft for the same reason it travels with a
    /// recommendation: a locally-templated programme presented as Gemini's work
    /// makes the model look worse than it is, and a Gemini programme presented
    /// as a template makes it look better.
    struct WorkoutDraft {
        var blueprint: WorkoutBlueprint
        var provenance: CoachProvenance
    }

    struct PlanDraft {
        var blueprint: PlanBlueprint
        var provenance: CoachProvenance
    }

    // MARK: Building

    /// One session.
    ///
    /// Throws rather than falling back. The caller decides whether a local
    /// template is the right answer, because only the caller knows whether the
    /// user asked for something a template can express — "45 minutes, upper
    /// body" yes, "something for my rotator cuff after a long flight" no.
    func buildWorkout(
        brief: WorkoutBrief,
        context: CoachContext,
        settings: CoachSettings
    ) async throws -> WorkoutDraft {
        let blueprint: WorkoutBlueprint = try await generate(
            mode: "buildWorkout",
            question: brief.promptText,
            context: context,
            settings: settings
        )
        return WorkoutDraft(
            blueprint: blueprint,
            provenance: .cloud(at: Date(), dataUpdatedAt: context.dataUpdatedAt)
        )
    }

    func buildPlan(
        brief: WorkoutBrief,
        context: CoachContext,
        settings: CoachSettings
    ) async throws -> PlanDraft {
        let blueprint: PlanBlueprint = try await generate(
            mode: "buildPlan",
            question: brief.planPromptText,
            context: context,
            settings: settings
        )
        return PlanDraft(
            blueprint: blueprint,
            provenance: .cloud(at: Date(), dataUpdatedAt: context.dataUpdatedAt)
        )
    }

    // MARK: Weekly review

    /// A review of a week the app has already counted.
    ///
    /// The metrics go over as a sentence rather than as a document: they are all
    /// small integers, and prose is what the model reads best. Nothing here is a
    /// figure the app didn't calculate, so a review that contradicts one is
    /// simply wrong.
    ///
    /// Falls back to `LocalWeeklyReview` rather than throwing, because a review
    /// nobody can read is worse than a plainer one honestly labelled.
    func weeklyReview(
        metrics: WeeklyReview.Metrics,
        context: CoachContext,
        settings: CoachSettings
    ) async -> WeeklyReviewOutcome {
        guard settings.mayUseCloud else {
            return local(metrics: metrics, origin: .onDevice, note: nil)
        }

        do {
            let response: WeeklyReviewResponse = try await generate(
                mode: "weeklyReview",
                question: Self.promptText(for: metrics),
                context: context,
                settings: settings
            )
            return WeeklyReviewOutcome(
                headline: response.headline,
                summary: response.summary,
                actions: response.actions,
                provenance: .cloud(at: Date(), dataUpdatedAt: context.dataUpdatedAt),
                metrics: metrics
            )
        } catch {
            let coachError = error as? CoachError
            return local(
                metrics: metrics,
                origin: Self.isUsageLimit(coachError) ? .usageLimited : .offlineFallback,
                note: coachError?.errorDescription
            )
        }
    }

    private func local(
        metrics: WeeklyReview.Metrics,
        origin: CoachProvenance.Origin,
        note: String?
    ) -> WeeklyReviewOutcome {
        let response = LocalWeeklyReview.review(for: metrics)
        return WeeklyReviewOutcome(
            headline: response.headline,
            summary: response.summary,
            actions: response.actions,
            provenance: CoachProvenance(
                origin: origin,
                generatedAt: Date(),
                failureNote: note
            ),
            metrics: metrics
        )
    }

    /// A spend ceiling is a different sentence from a network failure, and the
    /// label under the review says which.
    nonisolated static func isUsageLimit(_ error: CoachError?) -> Bool {
        if case .limitReached = error { return true }
        return false
    }

    /// The week as one paragraph of already-computed figures.
    ///
    /// No dates, no session names, no exercise names — a muscle, a count and a
    /// percentage each. What the model needs to write a review, and nothing
    /// that would identify a day.
    nonisolated static func promptText(for metrics: WeeklyReview.Metrics) -> String {
        var parts: [String] = []
        parts.append("Sessions completed: \(metrics.completedSessions) (last week: \(metrics.sessionsLastWeek)).")
        parts.append("Sessions planned: \(metrics.plannedSessions).")

        if let adherence = metrics.adherencePercent {
            parts.append("Adherence: \(adherence)%.")
        } else {
            parts.append("Adherence: not applicable — nothing was planned.")
        }
        if let duration = metrics.averageDurationMinutes {
            parts.append("Average session: \(duration) minutes.")
        }
        if !metrics.setsByMuscle.isEmpty {
            let sets = metrics.setsByMuscle
                .sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }
                .joined(separator: ", ")
            parts.append("Working sets by muscle: \(sets).")
        }
        if !metrics.underTargetMuscles.isEmpty {
            parts.append("Well under weekly target: \(metrics.underTargetMuscles.joined(separator: ", ")).")
        }
        parts.append("Personal bests: \(metrics.personalRecords).")
        parts.append("Sessions started and not finished: \(metrics.incompleteSessions).")
        parts.append("Exercises repeatedly prescribed and skipped: \(metrics.repeatedlySkippedExerciseIds.count).")
        if !metrics.isReviewable {
            parts.append("This is a small sample — say so rather than reading a trend into it.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Adjustment

    /// Reads one sentence and returns one adjustment.
    ///
    /// Throws rather than falling back: there is no sensible local reading of
    /// "make today a bit easier on my shoulder", and guessing at one would be
    /// the app performing an edit nobody asked for. The caller offers the four
    /// preset buttons instead, which need no interpretation at all.
    func interpretAdjustment(
        request text: String,
        context: CoachContext,
        settings: CoachSettings
    ) async throws -> WorkoutAdjustmentSuggestion {
        try await generate(
            mode: "adjustWorkout",
            question: String(text.prefix(300)),
            context: context,
            settings: settings
        )
    }

    // MARK: Transport

    /// One call, one repair attempt, then give up.
    ///
    /// The same rule as `CoachService.fetchRecommendation`, and for the same
    /// reasons: a repair is only worth attempting when the *first response*
    /// failed validation, because then the model has something specific to
    /// correct. A transport failure is retried by nobody — the brief forbids
    /// repeated retries, and a second call to a failing endpoint mostly buys a
    /// second failure and a second charge.
    private func generate<T: Decodable>(
        mode: String,
        question: String,
        context: CoachContext,
        settings: CoachSettings
    ) async throws -> T {
        guard settings.enabled, settings.mayUseCloud else { throw CoachError.disabled }
        guard usage.canAffordCall() else {
            throw CoachError.limitReached("This month's AI limit has been reached.")
        }

        switch try await call(mode: mode, question: question, context: context, settings: settings) as CallResult<T> {
        case .success(let value):
            return value
        case .rejected(let reason):
            switch try await call(
                mode: mode, question: question, context: context,
                settings: settings, repairReason: reason
            ) as CallResult<T> {
            case .success(let value):
                return value
            case .rejected(let secondReason):
                throw CoachError.invalidResponse(secondReason)
            }
        }
    }

    private enum CallResult<T> {
        case success(T)
        case rejected(String)
    }

    private func call<T: Decodable>(
        mode: String,
        question: String,
        context: CoachContext,
        settings: CoachSettings,
        repairReason: String? = nil
    ) async throws -> CallResult<T> {
        guard let idToken = try await idTokenProvider() else {
            throw CoachError.notSignedIn
        }

        // Same 500-character cap as `ask`. The brief is assembled from a form,
        // so it should never approach this — but the form has a free-text field
        // and a paste is a paste.
        let trimmed = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { throw CoachError.invalidResponse("empty brief") }

        var body: [String: Any] = [
            "mode": mode,
            "context": try encodeContext(context),
            "question": trimmed,
            "style": settings.style.instruction,
        ]
        if let repairReason { body["repairReason"] = repairReason }

        let result = try await transport.send(body, idToken: idToken)

        if let usageInfo = result["usage"] as? [String: Any] {
            usage.record(
                promptTokens: usageInfo["promptTokens"] as? Int ?? 0,
                outputTokens: usageInfo["outputTokens"] as? Int ?? 0,
                cost: usageInfo["cost"] as? Double ?? 0
            )
        }

        // The server reports a failed schema check as data rather than an error,
        // because the app needs the reason in order to ask for a repair.
        if let ok = result["ok"] as? Bool, ok == false {
            return .rejected(result["reason"] as? String ?? "unknown")
        }

        guard let value = result["value"],
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            throw CoachError.invalidResponse("no value")
        }

        // The second gate, and the one the server cannot perform in full: strict
        // decoding throws on any muscle, equipment or movement value this
        // version doesn't implement. A default here would silently produce a
        // workout for a body part nobody asked about.
        do {
            return .success(try JSONDecoder().decode(T.self, from: data))
        } catch let error as BlueprintError {
            switch error {
            case .unsupportedValue(let field, let value):
                return .rejected("\(field) \"\(value)\" isn't one the app knows")
            }
        } catch {
            return .rejected("the answer didn't have the expected shape")
        }
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
}
