import Foundation

// MARK: - Weekly Review Models

/// What comes back from a review, and what the app will do with it.
///
/// Strict `Codable` in the same style as `CoachProposal`: an action kind this
/// version doesn't implement fails to decode and the action is dropped. An
/// action the app can't perform must never reach a button that looks like it
/// can.
struct WeeklyReviewOutcome: Equatable, Sendable {
    var headline: String
    var summary: String
    var actions: [ReviewAction]
    var provenance: CoachProvenance
    /// The figures the review was written from, kept so the sheet can show them
    /// beside the prose. A review that cites a number the user can't see is a
    /// review they have to take on trust.
    var metrics: WeeklyReview.Metrics
}

enum ReviewActionKind: String, Codable, CaseIterable, Sendable {
    case keepUnchanged
    case condenseSessions
    case moveTrainingDay
    case adjustVolume
    case reviewSkippedExercise

    /// Every one of these opens something. None of them writes.
    var opensBuilder: Bool {
        self == .condenseSessions || self == .adjustVolume
    }

    var icon: String {
        switch self {
        case .keepUnchanged:          return "checkmark.circle"
        case .condenseSessions:       return "arrow.trianglehead.merge"
        case .moveTrainingDay:        return "calendar"
        case .adjustVolume:           return "slider.horizontal.3"
        case .reviewSkippedExercise:  return "questionmark.circle"
        }
    }
}

struct ReviewAction: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(kind.rawValue)-\(label)" }

    let kind: ReviewActionKind
    let label: String
    /// One sentence, citing a figure the app calculated. Shown under the button
    /// rather than hidden, because "why is it suggesting this?" is the first
    /// thing anyone asks.
    let rationale: String
    let muscle: BlueprintMuscle?

    enum CodingKeys: String, CodingKey {
        case type, label, rationale, muscle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let kind = ReviewActionKind(
            rawValue: try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        ) else {
            throw CoachProposalError.unsupportedKind
        }
        self.kind = kind
        self.label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.rationale = try c.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        if let raw = try c.decodeIfPresent(String.self, forKey: .muscle) {
            guard let muscle = BlueprintMuscle(rawValue: raw) else {
                throw BlueprintError.unsupportedValue(field: "muscle", value: raw)
            }
            self.muscle = muscle
        } else {
            self.muscle = nil
        }
    }

    init(kind: ReviewActionKind, label: String, rationale: String, muscle: BlueprintMuscle? = nil) {
        self.kind = kind
        self.label = label
        self.rationale = rationale
        self.muscle = muscle
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .type)
        try c.encode(label, forKey: .label)
        try c.encode(rationale, forKey: .rationale)
        try c.encodeIfPresent(muscle?.rawValue, forKey: .muscle)
    }
}

/// The review as the model returns it, before provenance and metrics are
/// attached.
struct WeeklyReviewResponse: Codable, Equatable, Sendable {
    var headline: String
    var summary: String
    /// Actions that failed to decode are dropped rather than failing the whole
    /// review — the prose is still worth reading, and a missing button is a
    /// smaller loss than an error page.
    var actions: [ReviewAction]

    enum CodingKeys: String, CodingKey { case headline, summary, actions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = try c.decode(String.self, forKey: .headline)
        summary = try c.decode(String.self, forKey: .summary)
        let lossy = try c.decodeIfPresent([FailableAction].self, forKey: .actions) ?? []
        actions = lossy.compactMap(\.action)
    }

    init(headline: String, summary: String, actions: [ReviewAction]) {
        self.headline = headline
        self.summary = summary
        self.actions = actions
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(headline, forKey: .headline)
        try c.encode(summary, forKey: .summary)
        try c.encode(actions, forKey: .actions)
    }

    /// Decodes an action or records that it couldn't.
    private struct FailableAction: Decodable {
        let action: ReviewAction?
        init(from decoder: Decoder) throws {
            action = try? ReviewAction(from: decoder)
        }
    }
}

// MARK: - Adjustment suggestion

/// The model's reading of "make this shorter", turned into something the
/// adjuster can perform.
///
/// The narrowest job the model is given anywhere in this app: classify one
/// sentence into one of four cases that already exist in Swift. It cannot
/// describe an edit of its own, so the worst a misreading produces is the wrong
/// *valid* adjustment — which the user then sees as a diff, and declines.
struct WorkoutAdjustmentSuggestion: Codable, Equatable, Sendable {

    enum Kind: String, Codable, Sendable {
        case shorten, equipmentOnly, lighter, avoid
    }

    var kind: Kind
    var minutes: Int?
    var equipment: [ExerciseEquipment]
    var muscle: BlueprintMuscle?
    var explanation: String

    enum CodingKeys: String, CodingKey {
        case kind, minutes, equipment, muscle, explanation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let rawKind = try c.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            throw BlueprintError.unsupportedValue(field: "kind", value: rawKind)
        }
        self.kind = kind

        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""

        let rawEquipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        var parsed: [ExerciseEquipment] = []
        for raw in rawEquipment {
            guard let value = ExerciseEquipment(rawValue: raw) else {
                throw BlueprintError.unsupportedValue(field: "equipment", value: raw)
            }
            parsed.append(value)
        }
        equipment = parsed

        if let raw = try c.decodeIfPresent(String.self, forKey: .muscle) {
            guard let muscle = BlueprintMuscle(rawValue: raw) else {
                throw BlueprintError.unsupportedValue(field: "muscle", value: raw)
            }
            self.muscle = muscle
        } else {
            muscle = nil
        }
    }

    init(
        kind: Kind,
        minutes: Int? = nil,
        equipment: [ExerciseEquipment] = [],
        muscle: BlueprintMuscle? = nil,
        explanation: String
    ) {
        self.kind = kind
        self.minutes = minutes
        self.equipment = equipment
        self.muscle = muscle
        self.explanation = explanation
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encodeIfPresent(minutes, forKey: .minutes)
        try c.encode(equipment.map(\.rawValue), forKey: .equipment)
        try c.encodeIfPresent(muscle?.rawValue, forKey: .muscle)
        try c.encode(explanation, forKey: .explanation)
    }

    /// The adjuster request this describes, or nil when the pieces it needs are
    /// missing.
    ///
    /// Returning nil rather than substituting a default: an `avoid` with no
    /// muscle is not an instruction to avoid something arbitrary, it is a
    /// response that didn't answer.
    var request: WorkoutAdjuster.Request? {
        switch kind {
        case .shorten:
            guard let minutes, minutes >= 5 else { return nil }
            return .shorten(byMinutes: min(minutes, 180))
        case .equipmentOnly:
            guard !equipment.isEmpty else { return nil }
            return .equipmentOnly(Set(equipment))
        case .lighter:
            return .lighter
        case .avoid:
            guard let muscle else { return nil }
            return .avoid(muscle)
        }
    }
}
