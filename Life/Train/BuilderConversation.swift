import Foundation

// MARK: - Builder Conversation

/// The questions the builder asks, and what the answers mean.
///
/// **The app asks; Gemini builds.** That division is deliberate and it is the
/// difference between a conversation that works and one that usually works.
/// `WorkoutResolver` cannot resolve a slot without knowing what equipment is
/// available, and a model free to steer its own interview will sometimes finish
/// without having asked — producing a barbell programme for someone with a pair
/// of dumbbells and a floor. A fixed sequence guarantees the fields that matter
/// arrive, and costs one model call at the end rather than one per turn.
///
/// It still reads as a conversation, because it is one: one question at a time,
/// answers as chips or free text, skippable, and "just build it" available from
/// the second question onwards.
///
/// Pure and `nonisolated` — the script is data, so the flow is testable without
/// a view or a network.
enum BuilderConversation {

    // MARK: Steps

    /// One question.
    ///
    /// `chips` are the fast path; `allowsFreeText` decides whether the composer
    /// is enabled underneath them. Most questions accept both, because "about
    /// forty minutes" and tapping *45* are the same intent and refusing one of
    /// them is just rudeness.
    struct Step: Equatable, Identifiable, Sendable {
        var id: Kind { kind }
        var kind: Kind
        var question: String
        var chips: [Chip]
        var allowsMultipleChips: Bool = false
        var allowsFreeText: Bool = true
        /// Shown under the question in smaller type, when the question needs a
        /// word of explanation to be answerable.
        var hint: String?
        /// Whether the conversation can move on without an answer.
        var isSkippable: Bool = true
    }

    enum Kind: String, Equatable, Sendable, CaseIterable {
        case goal
        case experience
        case daysPerWeek
        case weeks
        case duration
        case energy
        case equipment
        case avoid
        case history
        case anythingElse
    }

    struct Chip: Equatable, Identifiable, Sendable {
        var id: String { value }
        /// The stored value — an enum raw value, or a number as a string.
        var value: String
        var label: String
    }

    // MARK: The scripts

    /// A single session: five questions, none of them about scheduling.
    static let workoutScript: [Kind] = [
        .goal, .duration, .energy, .equipment, .avoid, .history, .anythingElse,
    ]

    /// A programme: the same, plus how the week is shaped, and no energy —
    /// how you feel today says nothing about week three.
    static let planScript: [Kind] = [
        .goal, .experience, .daysPerWeek, .weeks, .duration, .equipment, .avoid, .history,
        .anythingElse,
    ]

    static func script(for kind: BuilderKind) -> [Kind] {
        kind == .workout ? workoutScript : planScript
    }

    /// Mirrors `WorkoutPreviewSheet.Kind` without depending on a view type, so
    /// this file stays testable on its own.
    enum BuilderKind: String, Equatable, Sendable {
        case workout, plan
    }

    // MARK: Step definitions

    static func step(_ kind: Kind, for builder: BuilderKind) -> Step {
        switch kind {
        case .goal:
            return Step(
                kind: .goal,
                question: builder == .workout
                    ? "What are we training for today?"
                    : "What's the programme for?",
                chips: WorkoutBrief.Goal.allCases.map { Chip(value: $0.rawValue, label: $0.label) },
                isSkippable: false
            )

        case .experience:
            return Step(
                kind: .experience,
                question: "How long have you been training?",
                chips: [
                    Chip(value: WorkoutBrief.Experience.beginner.rawValue, label: "Under a year"),
                    Chip(value: WorkoutBrief.Experience.intermediate.rawValue, label: "A year or two"),
                    Chip(value: WorkoutBrief.Experience.advanced.rawValue, label: "Longer than that"),
                ]
            )

        case .daysPerWeek:
            return Step(
                kind: .daysPerWeek,
                question: "How many days a week can you train?",
                chips: (2...6).map { Chip(value: "\($0)", label: "\($0) days") },
                hint: "Be honest rather than optimistic — a plan you follow beats a plan you admire.",
                isSkippable: false
            )

        case .weeks:
            return Step(
                kind: .weeks,
                question: "How many weeks should it run for?",
                chips: [4, 6, 8, 12].map { Chip(value: "\($0)", label: "\($0) weeks") }
            )

        case .duration:
            return Step(
                kind: .duration,
                question: builder == .workout
                    ? "How long have you got?"
                    : "How long can a session be?",
                chips: [15, 30, 45, 60, 90].map { Chip(value: "\($0)", label: "\($0) min") },
                isSkippable: false
            )

        case .energy:
            return Step(
                kind: .energy,
                question: "How are you feeling?",
                chips: WorkoutBrief.Energy.allCases.map { Chip(value: $0.rawValue, label: $0.label) },
                hint: "This changes the effort, not the exercises."
            )

        case .equipment:
            return Step(
                kind: .equipment,
                question: "What have you got to work with?",
                chips: ExerciseEquipment.allCases.map { Chip(value: $0.rawValue, label: $0.label) },
                allowsMultipleChips: true,
                hint: "Skip this if you're somewhere well equipped."
            )

        case .avoid:
            return Step(
                kind: .avoid,
                question: "Anything to leave out?",
                chips: BlueprintMuscle.allCases.map { Chip(value: $0.rawValue, label: $0.rawValue) },
                allowsMultipleChips: true,
                hint: "Anything you pick here is never programmed, whatever the coach suggests."
            )

        case .history:
            return Step(
                kind: .history,
                question: "Should I build this around how you've been training?",
                chips: [
                    Chip(value: "yes", label: "Yes, use my history"),
                    Chip(value: "no", label: "Start fresh"),
                ],
                allowsFreeText: false,
                hint: "Your usual days, session length and the movements you actually do. Aggregates only — no session log is sent."
            )

        case .anythingElse:
            return Step(
                kind: .anythingElse,
                question: "Anything else I should know?",
                chips: [],
                hint: "A niggling shoulder, a race coming up, something you hate doing."
            )
        }
    }

    // MARK: Applying answers

    /// Folds an answer into the brief.
    ///
    /// Free text is parsed where a number is expected — someone typing "about
    /// 40 minutes" means 40, and refusing it because it isn't one of the chips
    /// would be the app being difficult on purpose. Unparseable text falls
    /// through to the free-text field rather than being discarded, so nothing
    /// the user said is ever silently lost.
    static func apply(
        answer: String,
        chips: [String],
        for kind: Kind,
        to brief: inout WorkoutBrief
    ) {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .goal:
            if let goal = chips.compactMap({ WorkoutBrief.Goal(rawValue: $0) }).first {
                brief.goal = goal
            } else if let goal = matchGoal(in: text) {
                brief.goal = goal
            } else if !text.isEmpty {
                appendNote(text, to: &brief)
            }

        case .experience:
            if let value = chips.compactMap({ WorkoutBrief.Experience(rawValue: $0) }).first {
                brief.experience = value
            } else if !text.isEmpty {
                appendNote(text, to: &brief)
            }

        case .daysPerWeek:
            if let days = firstNumber(in: chips.first ?? text) {
                brief.daysPerWeek = min(max(days, 2), 6)
            } else if !text.isEmpty {
                appendNote(text, to: &brief)
            }

        case .weeks:
            if let weeks = firstNumber(in: chips.first ?? text) {
                brief.weeks = min(max(weeks, 1), 12)
            } else if !text.isEmpty {
                appendNote(text, to: &brief)
            }

        case .duration:
            if let minutes = firstNumber(in: chips.first ?? text) {
                brief.availableMinutes = min(max(minutes, 10), 180)
            } else if !text.isEmpty {
                appendNote(text, to: &brief)
            }

        case .energy:
            if let value = chips.compactMap({ WorkoutBrief.Energy(rawValue: $0) }).first {
                brief.energy = value
            } else if !text.isEmpty {
                appendNote(text, to: &brief)
            }

        case .equipment:
            let picked = chips.compactMap { ExerciseEquipment(rawValue: $0) }
            if !picked.isEmpty { brief.availableEquipment = Set(picked) }
            if !text.isEmpty { appendNote(text, to: &brief) }

        case .avoid:
            let picked = chips.compactMap { BlueprintMuscle(rawValue: $0) }
            if !picked.isEmpty { brief.avoidMuscles = Set(picked) }
            if !text.isEmpty { appendNote(text, to: &brief) }

        case .history:
            if let choice = chips.first { brief.useHistory = choice == "yes" }

        case .anythingElse:
            if !text.isEmpty { appendNote(text, to: &brief) }
        }
    }

    /// What the coach says back, so an answer visibly lands.
    ///
    /// Not conversational filler. Each of these repeats the answer in the app's
    /// own words, which is how someone catches "45" being read as 45 weeks
    /// before a programme gets built on it.
    static func acknowledgement(for kind: Kind, brief: WorkoutBrief) -> String? {
        switch kind {
        case .goal:
            return "Right — \(brief.goal.label.lowercased())."
        case .daysPerWeek:
            return "\(brief.daysPerWeek) days a week."
        case .weeks:
            return "\(brief.weeks) weeks."
        case .duration:
            return "Up to \(brief.availableMinutes) minutes."
        case .equipment:
            guard !brief.availableEquipment.isEmpty else { return "I'll assume a full gym." }
            let names = brief.availableEquipment.map(\.label).sorted().joined(separator: ", ")
            return "Working with: \(names.lowercased())."
        case .avoid:
            guard !brief.avoidMuscles.isEmpty else { return nil }
            let names = brief.avoidMuscles.map(\.rawValue).sorted().joined(separator: ", ")
            return "I'll leave out \(names.lowercased())."
        case .history:
            return brief.useHistory
                ? "I'll take your recent training into account."
                : "Starting fresh, then — I'll ignore what you've done before."
        case .experience, .energy, .anythingElse:
            return nil
        }
    }

    // MARK: Parsing helpers

    /// The first whole number in a string, for "about 40 minutes" and "3 days".
    static func firstNumber(in text: String) -> Int? {
        let digits = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        guard let first = digits.first else { return nil }
        return Int(first)
    }

    /// A goal named in prose rather than tapped.
    static func matchGoal(in text: String) -> WorkoutBrief.Goal? {
        let lower = text.lowercased()
        if lower.contains("strong") || lower.contains("strength") { return .strength }
        if lower.contains("muscle") || lower.contains("size") || lower.contains("bigger") { return .muscle }
        if lower.contains("endurance") || lower.contains("fitness") || lower.contains("stamina") {
            return lower.contains("general") ? .general : .endurance
        }
        return nil
    }

    /// Everything the user typed, kept, in the order they said it.
    ///
    /// Free text from any question ends up here rather than being dropped when
    /// it doesn't parse — someone who typed "my left shoulder is sore" while
    /// answering the equipment question said something that matters, and the
    /// builder should hear it.
    private static func appendNote(_ text: String, to brief: inout WorkoutBrief) {
        let existing = brief.text.trimmingCharacters(in: .whitespacesAndNewlines)
        brief.text = existing.isEmpty ? text : existing + ". " + text
    }
}
