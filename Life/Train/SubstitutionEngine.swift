import Foundation

// MARK: - Substitution Engine

/// Finds exercises that could stand in for another one.
///
/// The candidate list is built here, deterministically, from the user's real
/// library. **Gemini may rank and explain that list; it cannot add to it.** The
/// response schema for ranking is an array of *indices into the candidates*, so
/// choosing something outside the list is not expressible — the same trick as
/// the blueprint's slots, applied to a smaller problem.
///
/// The priority order is the one from the brief:
/// movement pattern → primary muscle → equipment → exclusions → position in the
/// workout → expected fatigue → similar difficulty and setup time.
///
/// Pure and `nonisolated`. No randomness, ties broken on id.
enum SubstitutionEngine {

    struct Candidate: Equatable, Sendable, Identifiable {
        var id: String { exercise.id }
        var exercise: Exercise
        /// Higher is a closer match. Exposed so the preview can show why the
        /// order is what it is, rather than presenting it as an opinion.
        var score: Int
        /// What makes this a reasonable stand-in, in the user's terms.
        var reasons: [String]
        /// Where it differs in a way worth knowing before swapping.
        var differences: [String]
    }

    struct Request: Equatable, Sendable {
        /// The exercise being replaced.
        var replacing: Exercise
        var library: [Exercise]
        /// Already in this workout — never offered twice.
        var idsInWorkout: Set<String>
        /// Muscles the user has excluded outright.
        var excludedMuscles: Set<BlueprintMuscle>
        /// Equipment actually available. Empty means no restriction.
        var availableEquipment: Set<ExerciseEquipment>
        /// Exercises with recorded history, for the familiarity bonus.
        var trainedIds: Set<String>
        var favouriteIds: Set<String>

        init(
            replacing: Exercise,
            library: [Exercise],
            idsInWorkout: Set<String> = [],
            excludedMuscles: Set<BlueprintMuscle> = [],
            availableEquipment: Set<ExerciseEquipment> = [],
            trainedIds: Set<String> = [],
            favouriteIds: Set<String> = []
        ) {
            self.replacing = replacing
            self.library = library
            self.idsInWorkout = idsInWorkout
            self.excludedMuscles = excludedMuscles
            self.availableEquipment = availableEquipment
            self.trainedIds = trainedIds
            self.favouriteIds = favouriteIds
        }
    }

    /// The most candidates worth showing.
    ///
    /// A substitution list is a decision, not an inventory. Six is enough to
    /// find something; twenty is a second exercise library.
    static let maximumCandidates = 6

    // MARK: Building the list

    static func candidates(for request: Request) -> [Candidate] {
        let replacing = request.replacing

        let pool = request.library.filter { candidate in
            // Never itself, never something already in the workout.
            guard candidate.id != replacing.id else { return false }
            guard !request.idsInWorkout.contains(candidate.id) else { return false }

            // Exclusions are absolute. A model that ignores one must not be
            // able to route round it by suggesting a substitution.
            if let muscle = BlueprintMuscle(rawValue: candidate.muscle),
               request.excludedMuscles.contains(muscle) {
                return false
            }

            // Equipment the user doesn't have is a hard filter, not a penalty.
            if !request.availableEquipment.isEmpty,
               !request.availableEquipment.contains(candidate.equipment) {
                return false
            }

            // Must train something related. A calf raise is not a substitute
            // for a bench press however conveniently it scores.
            return trainsSomethingRelated(candidate, to: replacing)
        }

        return pool
            .map { build($0, replacing: replacing, request: request) }
            .sorted { $0.score == $1.score ? $0.exercise.id < $1.exercise.id : $0.score > $1.score }
            .prefix(maximumCandidates)
            .map { $0 }
    }

    /// Whether two exercises are in the same neighbourhood at all.
    ///
    /// Same muscle, or a muscle the blueprint's related table connects them by.
    /// This is the gate that stops the scorer producing a technically-highest
    /// candidate that makes no sense.
    private static func trainsSomethingRelated(_ candidate: Exercise, to replacing: Exercise) -> Bool {
        if candidate.muscle.caseInsensitiveCompare(replacing.muscle) == .orderedSame { return true }

        guard let from = BlueprintMuscle(rawValue: replacing.muscle),
              let to = BlueprintMuscle(rawValue: candidate.muscle) else { return false }
        return from.related.contains(to)
    }

    private static func build(
        _ candidate: Exercise,
        replacing: Exercise,
        request: Request
    ) -> Candidate {
        var score = 0
        var reasons: [String] = []
        var differences: [String] = []

        // 1. Movement pattern first — a compound replaced by an isolation
        //    exercise changes what the session is, not just how it feels.
        if candidate.movementType == replacing.movementType {
            score += 50
            reasons.append("Same \(candidate.movementType.label.lowercased()) movement")
        } else {
            differences.append(
                "\(candidate.movementType.label) rather than \(replacing.movementType.label.lowercased())"
            )
        }

        // 2. Primary muscle.
        if candidate.muscle.caseInsensitiveCompare(replacing.muscle) == .orderedSame {
            score += 40
            reasons.append("Trains \(candidate.muscle.lowercased())")
        } else {
            score += 15
            differences.append("Trains \(candidate.muscle.lowercased()) instead")
        }

        // 3. Equipment.
        if candidate.equipment == replacing.equipment {
            score += 20
            reasons.append("Same equipment")
        } else {
            differences.append("Uses \(candidate.equipment.label.lowercased())")
        }

        // 4. Familiarity — something they have actually done, and know how to
        //    set up, is a better substitute than something theoretically closer.
        if request.trainedIds.contains(candidate.id) {
            score += 14
            reasons.append("You've trained this before")
        }
        if request.favouriteIds.contains(candidate.id) {
            score += 8
            reasons.append("One of your favourites")
        }

        // 5. Difficulty and setup. Swapping mid-workout for something two
        //    grades harder is not a substitution, it's a different session.
        let difficultyGap = abs(candidate.difficulty - replacing.difficulty)
        score -= difficultyGap * 10
        if difficultyGap >= 2 {
            differences.append(
                candidate.difficulty > replacing.difficulty
                    ? "Noticeably harder to perform"
                    : "Easier to perform"
            )
        }

        // 6. Expected fatigue. A barbell compound taxes more than a machine
        //    version of the same pattern, which matters late in a session.
        if candidate.kind == .bodyweight && replacing.kind == .weight {
            differences.append("Bodyweight — you won't be able to load it the same way")
        }

        return Candidate(
            exercise: candidate,
            score: score,
            reasons: reasons,
            differences: differences
        )
    }

    // MARK: Applying

    /// A substitution as a change to the prescription.
    ///
    /// Sets and rest carry over; the rep range only moves when the movement type
    /// changes, because eight reps of a compound and eight of an isolation
    /// exercise are not the same ask.
    static func substituted(
        _ prescription: RoutineExercise,
        with candidate: Candidate,
        replacing: Exercise
    ) -> RoutineExercise {
        var updated = prescription
        updated.exerciseId = candidate.exercise.id

        // A load carried across to a different movement is meaningless and
        // potentially unsafe — 80 kg on a barbell row is not 80 kg on a
        // dumbbell row. It resets, and the user sets it on the first set.
        updated.defaultWeight = 0

        if candidate.exercise.movementType != replacing.movementType {
            switch candidate.exercise.movementType {
            case .isolation:
                updated.repRangeMin = max(prescription.repRangeMin, 10)
                updated.repRangeMax = max(prescription.repRangeMax, 15)
            case .compound:
                updated.repRangeMin = min(prescription.repRangeMin, 8)
                updated.repRangeMax = min(prescription.repRangeMax, 12)
            case .cardio:
                break
            }
            updated.defaultReps = (updated.repRangeMin + updated.repRangeMax) / 2
        }

        return updated
    }

    /// Whether swapping changes the prescription as well as the exercise, so
    /// the UI can say "sets and reps stay the same" or show what moves.
    static func changesPrescription(
        _ prescription: RoutineExercise,
        with candidate: Candidate,
        replacing: Exercise
    ) -> Bool {
        let updated = substituted(prescription, with: candidate, replacing: replacing)
        return updated.repRangeMin != prescription.repRangeMin
            || updated.repRangeMax != prescription.repRangeMax
            || updated.defaultWeight != prescription.defaultWeight
    }
}
