import Foundation

// MARK: - Workout Blueprint

/// What the model is allowed to say about a training session.
///
/// A blueprint describes the *shape* of a workout — muscle groups, sets, rep
/// ranges, rest — and never names a movement. The app resolves each slot to a
/// real `Exercise` from the user's own library; see `WorkoutResolver`.
///
/// That division is the whole safety model. The model cannot know which of the
/// 187 seeded exercises exist, so a name it produced would have to be matched by
/// string on this side, and a miss would either drop the exercise or manufacture
/// a new record. `ImportRoutineSheet` does exactly that for a CSV the user chose
/// to import, and it is quarantined for the reason: acceptable for text a person
/// typed, never acceptable for model output.
///
/// Decoding is strict, in the same spirit as `CoachProposal`. An unrecognised
/// muscle or equipment value **throws** rather than decoding to a default,
/// because a default here would silently produce a workout for a body part
/// nobody asked about.

/// The muscle vocabulary, closed.
///
/// Must stay in step with `Exercise.muscle` in `WorkoutSeed.swift` and with
/// `MUSCLES` in `functions/src/workoutSchema.ts`. Nothing in the compiler
/// enforces the second of those, so `WorkoutResolverTests` asserts the seed and
/// this enum agree — a muscle the model can ask for but this cannot represent
/// loses its slot silently, and presents to the user as "the coach keeps
/// forgetting my calves".
enum BlueprintMuscle: String, Codable, CaseIterable, Sendable {
    case back = "Back"
    case biceps = "Biceps"
    case calves = "Calves"
    case cardio = "Cardio"
    case chest = "Chest"
    case core = "Core"
    case glutes = "Glutes"
    case legs = "Legs"
    case shoulders = "Shoulders"
    case triceps = "Triceps"

    /// Muscles worth borrowing from when the library has nothing for this one.
    ///
    /// A fixed table rather than anything clever. Someone with no dedicated
    /// glute exercises almost certainly has leg exercises that train them, and
    /// dropping the slot outright would be a worse answer than a near one — but
    /// only along these specific lines, and never far enough to turn a pull day
    /// into a push day.
    var related: [BlueprintMuscle] {
        switch self {
        case .glutes:    return [.legs]
        case .calves:    return [.legs]
        case .legs:      return [.glutes]
        case .biceps:    return [.back]
        case .triceps:   return [.chest, .shoulders]
        case .back:      return [.biceps]
        case .chest:     return [.triceps]
        case .shoulders: return [.triceps]
        // Nothing sensibly stands in for these two.
        case .core, .cardio: return []
        }
    }

    /// The blueprint muscle an `Exercise.muscle` string names, if any.
    ///
    /// `Exercise.muscle` is a free `String` — a custom or imported exercise can
    /// carry "chest", "Upper back" or anything else — so this is the one place
    /// that decides what counts as a match. It exists so the resolver and the
    /// coach context agree: a muscle the context reports as having six
    /// exercises must be a muscle the resolver can find six exercises for, and
    /// two independent comparisons would eventually disagree.
    init?(appMuscle: String) {
        let trimmed = appMuscle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = BlueprintMuscle.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else { return nil }
        self = match
    }
}

enum BlueprintError: Error, Equatable {
    /// A muscle, equipment or movement value the app doesn't implement. Thrown
    /// rather than defaulted — see the type's note.
    case unsupportedValue(field: String, value: String)
}

/// One exercise-shaped hole in a session.
struct WorkoutSlot: Codable, Equatable, Sendable {

    var muscle: BlueprintMuscle
    /// A preference, not a requirement. The resolver scores it heavily and
    /// substitutes when the library has nothing matching, flagging the swap.
    var equipment: ExerciseEquipment?
    var movementType: MovementType?
    var sets: Int
    var repMin: Int
    var repMax: Int
    var restSeconds: Int
    /// Reps in reserve — effort guidance the app can show without knowing a
    /// load. Preferred over a starting weight, which cannot be inferred safely
    /// from no training history.
    var rir: Int?
    /// Slots sharing a number are performed back to back.
    var supersetGroup: Int?

    enum CodingKeys: String, CodingKey {
        case muscle, equipment, movementType, sets, repMin, repMax, restSeconds
        case rir, supersetGroup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let rawMuscle = try c.decode(String.self, forKey: .muscle)
        guard let muscle = BlueprintMuscle(rawValue: rawMuscle) else {
            throw BlueprintError.unsupportedValue(field: "muscle", value: rawMuscle)
        }
        self.muscle = muscle

        if let rawEquipment = try c.decodeIfPresent(String.self, forKey: .equipment) {
            guard let equipment = ExerciseEquipment(rawValue: rawEquipment) else {
                throw BlueprintError.unsupportedValue(field: "equipment", value: rawEquipment)
            }
            self.equipment = equipment
        }

        if let rawMovement = try c.decodeIfPresent(String.self, forKey: .movementType) {
            guard let movement = MovementType(rawValue: rawMovement) else {
                throw BlueprintError.unsupportedValue(field: "movementType", value: rawMovement)
            }
            self.movementType = movement
        }

        sets = try c.decode(Int.self, forKey: .sets)
        repMin = try c.decode(Int.self, forKey: .repMin)
        repMax = try c.decode(Int.self, forKey: .repMax)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        rir = try c.decodeIfPresent(Int.self, forKey: .rir)
        supersetGroup = try c.decodeIfPresent(Int.self, forKey: .supersetGroup)
    }

    init(
        muscle: BlueprintMuscle,
        equipment: ExerciseEquipment? = nil,
        movementType: MovementType? = nil,
        sets: Int,
        repMin: Int,
        repMax: Int,
        restSeconds: Int,
        rir: Int? = nil,
        supersetGroup: Int? = nil
    ) {
        self.muscle = muscle
        self.equipment = equipment
        self.movementType = movementType
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.restSeconds = restSeconds
        self.rir = rir
        self.supersetGroup = supersetGroup
    }
}

/// One session, as shape.
struct WorkoutBlueprint: Codable, Equatable, Sendable {
    /// A label — "Upper Body — Strength", "Push A". Never a movement; the
    /// resolver replaces it if it happens to match a real exercise name.
    var name: String
    var focus: String
    var slots: [WorkoutSlot]
    var notes: String?
}

/// A repeating week, and how long to repeat it for.
///
/// One session set, not a different week three. `WorkoutProgram` is a weekly
/// split and cannot enact variation between weeks, so a blueprint that
/// described one would produce drafts that fail on save. Week-to-week intent
/// lives in `progression` as prose.
struct PlanBlueprint: Codable, Equatable, Sendable {
    var name: String
    var weeks: Int
    var sessions: [PlanSession]
    var weekdays: [PlanWeekday]
    var progression: String?
}

struct PlanSession: Codable, Equatable, Sendable {
    /// Referenced by `PlanWeekday.sessionKey`. Checked for existence
    /// server-side, and again by the resolver.
    var key: String
    var blueprint: WorkoutBlueprint
}

struct PlanWeekday: Codable, Equatable, Sendable {
    /// 1 = Monday, matching `ProgramDay.weekday`.
    var weekday: Int
    /// Nil is a rest day.
    var sessionKey: String?
}

// MARK: - Brief

/// What the user asked for, in the form the builder sends.
///
/// A guided form fills this in; free text is the optional last field rather than
/// the only one. Asking six specific questions produces a far better blueprint
/// than a sentence, and it means the local template fallback has the same inputs
/// to work from when the network isn't available.
struct WorkoutBrief: Equatable, Sendable, Identifiable {

    enum Energy: String, CaseIterable, Sendable, Identifiable {
        case low, normal, high
        var id: String { rawValue }
        var label: String {
            switch self {
            case .low:    return "Low"
            case .normal: return "Normal"
            case .high:   return "High"
            }
        }
    }

    enum Experience: String, CaseIterable, Sendable, Identifiable {
        case beginner, intermediate, advanced
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum Goal: String, CaseIterable, Sendable, Identifiable {
        case strength, muscle, endurance, general
        var id: String { rawValue }
        var label: String {
            switch self {
            case .strength:  return "Get stronger"
            case .muscle:    return "Build muscle"
            case .endurance: return "Build endurance"
            case .general:   return "General fitness"
            }
        }
    }

    var id = UUID()

    /// Free text. Capped at 500 characters by the service, matching `ask`.
    var text: String = ""
    var goal: Goal = .general
    var experience: Experience = .intermediate
    var availableMinutes: Int = 45
    var energy: Energy = .normal
    /// Empty means no restriction — the resolver treats an empty set as "any".
    var availableEquipment: Set<ExerciseEquipment> = []
    var focusMuscles: Set<BlueprintMuscle> = []
    var avoidMuscles: Set<BlueprintMuscle> = []

    // Plan-only.
    var daysPerWeek: Int = 3
    /// 1 = Monday. Empty means the builder chooses.
    var preferredWeekdays: Set<Int> = []
    var weeks: Int = 4

    /// The brief as one sentence for the model, built from the form.
    ///
    /// Assembled here rather than in the service so the same string can be shown
    /// back to the user in the preview — "this is what I asked for" is the only
    /// way to tell a bad answer from a badly-phrased question.
    var promptText: String {
        var parts: [String] = []
        parts.append("Goal: \(goal.label).")
        parts.append("Experience: \(experience.label).")
        parts.append("Time available: \(availableMinutes) minutes.")
        parts.append("Energy today: \(energy.label).")

        if !availableEquipment.isEmpty {
            let names = availableEquipment.map(\.rawValue).sorted().joined(separator: ", ")
            parts.append("Equipment available: \(names).")
        } else {
            parts.append("Equipment: assume a well-equipped gym.")
        }

        if !focusMuscles.isEmpty {
            parts.append("Focus on: \(focusMuscles.map(\.rawValue).sorted().joined(separator: ", ")).")
        }
        if !avoidMuscles.isEmpty {
            parts.append("Avoid entirely: \(avoidMuscles.map(\.rawValue).sorted().joined(separator: ", ")).")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append("Also: \(trimmed)") }

        return parts.joined(separator: " ")
    }

    /// The plan brief adds scheduling to the session brief.
    var planPromptText: String {
        var parts = [promptText]
        parts.append("Train \(daysPerWeek) days a week for \(weeks) weeks.")
        if !preferredWeekdays.isEmpty {
            let names = preferredWeekdays.sorted().map { Self.weekdayName($0) }.joined(separator: ", ")
            parts.append("Preferred days: \(names).")
        }
        return parts.joined(separator: " ")
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        guard (1...7).contains(weekday) else { return "Day \(weekday)" }
        return names[weekday - 1]
    }
}
