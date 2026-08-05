import Foundation

// MARK: - Coach Response Models

/// What the coach is allowed to suggest.
///
/// A closed set, decoded strictly. The model returns a string, and anything
/// outside this list fails decoding rather than arriving as an unrecognised
/// instruction the app then has to decide what to do with. That is the whole
/// point: a language model's output is untrusted input, and the safest shape
/// for untrusted input is a value from a list the app wrote itself.
///
/// Nothing here executes anything. Each case names a screen to open or a
/// prefilled action to *offer* — the user still has to press the button.
enum CoachActionType: String, Codable, CaseIterable, Sendable {
    case completeTask
    case scheduleTask
    case rescheduleTask
    case doPlannedWorkout
    case reduceWorkoutIntensity
    case takeWalk
    case completeHabit
    case rest
    case logMissingData
    case reviewGoal
    /// Advice with nothing to press. Not a failure — sometimes the right
    /// suggestion is "you're on track, carry on".
    case none

    /// Whether the action needs `relatedItemId` to point at something real.
    /// A recommendation to complete *a task* without saying which is not
    /// actionable, and is rejected in validation rather than shown.
    var requiresRelatedItem: Bool {
        switch self {
        case .completeTask, .scheduleTask, .rescheduleTask, .completeHabit:
            return true
        case .doPlannedWorkout, .reduceWorkoutIntensity, .takeWalk, .rest,
             .logMissingData, .reviewGoal, .none:
            return false
        }
    }
}

enum CoachCategory: String, Codable, CaseIterable, Sendable {
    case sleep, recovery, activity, training, tasks, habits, nutrition, general
}

enum CoachPriority: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

/// How much the coach should be trusted on this, given the data behind it.
///
/// Carried through from `CoachContext`: a recommendation built on a night the
/// tracker half-recorded cannot be more confident than the reading it rests on.
enum CoachConfidence: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

/// One reason, in the user's terms.
///
/// The brief requires the coach to explain which trusted metrics drove a
/// recommendation. This is that explanation, and it is a list of specific
/// figures rather than prose so the explanation sheet can show each one beside
/// the number it refers to.
struct CoachEvidence: Codable, Equatable, Sendable, Identifiable {
    /// The metric's name — "Steps", "Recovery".
    var label: String
    /// One sentence on what it showed.
    var explanation: String

    var id: String { label + explanation }
}

/// A single recommendation.
///
/// One action, never a list. A coach that offers five things has not decided
/// anything, and deciding is the entire value it adds over the numbers already
/// on the Today screen.
struct CoachRecommendation: Codable, Equatable, Sendable {
    var headline: String
    var summary: String
    var category: CoachCategory
    var actionType: CoachActionType
    /// The task, habit or session this refers to. Must be an id the app
    /// supplied in the context — see `validate(against:)`.
    var relatedItemId: String?
    var durationMinutes: Int?
    var priority: CoachPriority
    var confidence: CoachConfidence
    var evidence: [CoachEvidence]
    /// Present only when something in the data warrants care. Rendered
    /// prominently and never suppressed.
    var safetyNotice: String?

    /// Where this came from, so the UI can be honest about it. Not part of the
    /// model's response — set by the app after decoding.
    var origin: Origin = .cloud
    /// When it was produced, for the "generated at" line.
    var generatedAt: Date = Date()

    enum Origin: String, Codable, Sendable {
        /// Produced by the language model.
        case cloud
        /// Produced by `LocalCoach` — either because cloud AI is switched off,
        /// or because the call failed and the app fell back rather than showing
        /// an error where a suggestion should be.
        case local
    }

    enum CodingKeys: String, CodingKey {
        case headline, summary, category, actionType, relatedItemId
        case durationMinutes, priority, confidence, evidence, safetyNotice
        case origin, generatedAt
    }

    /// Decodes leniently on the app's own fields and strictly on the model's.
    ///
    /// `origin` and `generatedAt` are written by the app when it caches a
    /// recommendation, so they are absent from a fresh model response and get
    /// defaults. Everything else must be present and valid.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = try c.decode(String.self, forKey: .headline)
        summary = try c.decode(String.self, forKey: .summary)
        category = try c.decode(CoachCategory.self, forKey: .category)
        actionType = try c.decode(CoachActionType.self, forKey: .actionType)
        relatedItemId = try c.decodeIfPresent(String.self, forKey: .relatedItemId)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        priority = try c.decode(CoachPriority.self, forKey: .priority)
        confidence = try c.decode(CoachConfidence.self, forKey: .confidence)
        evidence = try c.decodeIfPresent([CoachEvidence].self, forKey: .evidence) ?? []
        safetyNotice = try c.decodeIfPresent(String.self, forKey: .safetyNotice)
        origin = try c.decodeIfPresent(Origin.self, forKey: .origin) ?? .cloud
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
    }

    init(
        headline: String,
        summary: String,
        category: CoachCategory,
        actionType: CoachActionType,
        relatedItemId: String? = nil,
        durationMinutes: Int? = nil,
        priority: CoachPriority = .medium,
        confidence: CoachConfidence = .medium,
        evidence: [CoachEvidence] = [],
        safetyNotice: String? = nil,
        origin: Origin = .cloud,
        generatedAt: Date = Date()
    ) {
        self.headline = headline
        self.summary = summary
        self.category = category
        self.actionType = actionType
        self.relatedItemId = relatedItemId
        self.durationMinutes = durationMinutes
        self.priority = priority
        self.confidence = confidence
        self.evidence = evidence
        self.safetyNotice = safetyNotice
        self.origin = origin
        self.generatedAt = generatedAt
    }
}

// MARK: - Validation

extension CoachRecommendation {

    /// Why a response was rejected. Each case is a thing the app checked rather
    /// than assumed.
    enum ValidationFailure: Equatable, Sendable {
        case emptyHeadline
        case headlineTooLong(Int)
        /// The action needs something to act on and didn't name one.
        case missingRelatedItem(CoachActionType)
        /// It named an id the app never sent. A model inventing a plausible-
        /// looking identifier is the failure mode this exists to catch: acting
        /// on it would complete or reschedule the wrong thing.
        case unknownRelatedItem(String)
        case implausibleDuration(Int)
        /// The user asked not to be nudged about this. Refused rather than
        /// shown, so the preference means something even when the model
        /// ignores it.
        case mutedCategory(CoachCategory)

        var description: String {
            switch self {
            case .emptyHeadline:
                return "The recommendation had no headline."
            case .headlineTooLong(let count):
                return "The headline was \(count) characters; the limit is \(CoachRecommendation.maximumHeadlineCharacters)."
            case .missingRelatedItem(let action):
                return "\(action.rawValue) needs to name what it refers to, and didn't."
            case .unknownRelatedItem(let id):
                return "It referred to \(id), which wasn't in the data sent."
            case .implausibleDuration(let minutes):
                return "\(minutes) minutes isn't a sensible duration."
            case .mutedCategory(let category):
                return "You've asked not to be nudged about \(category.rawValue)."
            }
        }
    }

    static let maximumHeadlineCharacters = 80
    static let plausibleDurationMinutes: ClosedRange<Int> = 1...240

    /// Checks a decoded response against the context it was produced from.
    ///
    /// Decoding proves the *shape* is right. This proves the *content* refers
    /// to things that exist. The two are separate because a well-formed
    /// response naming a task id that was never sent is exactly as unusable as
    /// malformed JSON, and far easier to act on by mistake.
    func validate(against context: CoachContext) -> ValidationFailure? {
        let trimmedHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHeadline.isEmpty { return .emptyHeadline }
        if trimmedHeadline.count > Self.maximumHeadlineCharacters {
            return .headlineTooLong(trimmedHeadline.count)
        }

        if let durationMinutes, !Self.plausibleDurationMinutes.contains(durationMinutes) {
            return .implausibleDuration(durationMinutes)
        }

        if context.mutedCategories.contains(category.rawValue) {
            return .mutedCategory(category)
        }

        if actionType.requiresRelatedItem {
            guard let relatedItemId, !relatedItemId.isEmpty else {
                return .missingRelatedItem(actionType)
            }
            guard context.referencableIds.contains(relatedItemId) else {
                return .unknownRelatedItem(relatedItemId)
            }
        } else if let relatedItemId, !relatedItemId.isEmpty,
                  !context.referencableIds.contains(relatedItemId) {
            // An id on an action that doesn't need one is dropped rather than
            // rejected — the advice still stands without it.
            return .unknownRelatedItem(relatedItemId)
        }

        return nil
    }
}

// MARK: - Briefings

/// A morning briefing or evening review.
///
/// Separate from `CoachRecommendation` because it summarises rather than
/// proposes: there is no single action, and no button.
struct CoachBriefing: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case morning, evening
    }

    var kind: Kind
    var headline: String
    /// Two or three short paragraphs at most.
    var body: String
    var evidence: [CoachEvidence]
    var safetyNotice: String?
    var origin: CoachRecommendation.Origin = .cloud
    var generatedAt: Date = Date()
    /// The context hash this was built from, so it can be reused until the
    /// underlying figures actually change.
    var contextHash: String = ""
}
