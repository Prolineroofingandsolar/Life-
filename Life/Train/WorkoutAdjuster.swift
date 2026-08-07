import Foundation

// MARK: - Workout Adjuster

/// "Make this twenty minutes shorter." "Dumbbells only." "Go lighter today."
///
/// All four requests are executed here, in Swift, against the real library. The
/// model's only possible role is turning a sentence into one of these cases —
/// and even that is a closed enum, so the worst a bad interpretation can do is
/// produce the wrong *valid* adjustment, which the user then sees in a diff and
/// rejects.
///
/// Nothing here mutates anything. It returns a proposed list of exercises and
/// the list of changes that would produce it; the caller shows both and waits
/// for a tap.
///
/// Pure and `nonisolated`. No randomness; ties break on id.
enum WorkoutAdjuster {

    // MARK: Requests

    enum Request: Equatable, Sendable {
        /// Shorter by roughly this many minutes.
        case shorten(byMinutes: Int)
        /// Only this equipment is available.
        case equipmentOnly(Set<ExerciseEquipment>)
        /// Same movements, less of them.
        case lighter
        /// Leave this muscle alone today.
        case avoid(BlueprintMuscle)

        var label: String {
            switch self {
            case .shorten(let minutes):    return "\(minutes) minutes shorter"
            case .equipmentOnly(let kit):
                let names = kit.map(\.label).sorted().joined(separator: ", ")
                return kit.isEmpty ? "Any equipment" : "\(names) only"
            case .lighter:                 return "Lighter today"
            case .avoid(let muscle):       return "No \(muscle.rawValue.lowercased())"
            }
        }
    }

    // MARK: Changes

    /// One line of the diff. Every one of these is shown; none is applied
    /// silently.
    enum Change: Equatable, Sendable, Identifiable {
        case removed(exerciseId: String, name: String, reason: String)
        case replaced(fromId: String, fromName: String, toId: String, toName: String, reason: String)
        case setsReduced(exerciseId: String, name: String, from: Int, to: Int)
        case restShortened(exerciseId: String, name: String, from: Int, to: Int)
        case effortReduced(exerciseId: String, name: String)
        /// The request could not be met in full, and by how much.
        case shortfall(String)

        var id: String {
            switch self {
            case .removed(let id, _, _):            return "removed-\(id)"
            case .replaced(let from, _, _, _, _):   return "replaced-\(from)"
            case .setsReduced(let id, _, _, _):     return "sets-\(id)"
            case .restShortened(let id, _, _, _):   return "rest-\(id)"
            case .effortReduced(let id, _):         return "effort-\(id)"
            case .shortfall(let text):              return "shortfall-\(text)"
            }
        }

        var text: String {
            switch self {
            case .removed(_, let name, let reason):
                return "Removed \(name) — \(reason)."
            case .replaced(_, let fromName, _, let toName, let reason):
                return "\(fromName) → \(toName) — \(reason)."
            case .setsReduced(_, let name, let from, let to):
                return "\(name): \(from) sets → \(to)."
            case .restShortened(_, let name, let from, let to):
                return "\(name): \(from)s rest → \(to)s."
            case .effortReduced(_, let name):
                return "\(name): one rep further from failure."
            case .shortfall(let text):
                return text
            }
        }
    }

    struct Adjustment: Equatable, Sendable {
        var exercises: [RoutineExercise]
        var changes: [Change]
        var originalMinutes: Int
        var adjustedMinutes: Int

        /// Nothing to show. Rendered as "already fits" rather than as an empty
        /// diff, which reads as a failure.
        var isEmpty: Bool { changes.isEmpty }
        var minutesSaved: Int { max(0, originalMinutes - adjustedMinutes) }
    }

    /// Below three exercises it stops being the workout that was asked for.
    ///
    /// A "twenty minutes shorter" request that empties the session has not been
    /// honoured; it has been misunderstood. The adjuster stops here and reports
    /// the shortfall instead.
    static let minimumExercises = 3
    /// Rest never goes below a minute, sets never below two, and rest comes off
    /// in half-minute steps.
    ///
    /// Named rather than inline because the trim loops read them repeatedly and
    /// a silent disagreement between the loop's floor and the note's floor would
    /// produce a diff that doesn't match what was done.
    static let minimumRestSeconds = 60
    static let minimumSets = 2
    static let restStepSeconds = 30

    // MARK: Estimating

    /// The same arithmetic `ResolvedWorkout.estimatedMinutes` uses.
    ///
    /// Shared deliberately: an adjustment measured by one estimate and displayed
    /// beside another would show a session getting shorter while the number went
    /// up.
    nonisolated static func estimatedMinutes(_ exercises: [RoutineExercise]) -> Int {
        let seconds = exercises.reduce(0) { total, item in
            let reps = (item.repRangeMin + item.repRangeMax) / 2
            let working = reps * WorkoutResolver.ResolvedWorkout.secondsPerRep
            return total + item.defaultSets * (working + item.restSeconds)
        }
        let overhead = exercises.count * 60
        return max(1, (seconds + overhead) / 60)
    }

    // MARK: Adjusting

    nonisolated static func adjust(
        exercises: [RoutineExercise],
        library: [Exercise],
        request: Request
    ) -> Adjustment {
        let original = estimatedMinutes(exercises)

        switch request {
        case .shorten(let minutes):
            return shorten(exercises, library: library, byMinutes: minutes, original: original)
        case .equipmentOnly(let equipment):
            return restrictEquipment(exercises, library: library, to: equipment, original: original)
        case .lighter:
            return lighten(exercises, library: library, original: original)
        case .avoid(let muscle):
            return avoid(muscle, in: exercises, library: library, original: original)
        }
    }

    // MARK: Shorten

    /// Trims in the order a person would.
    ///
    /// Rest first, because ninety seconds between curl sets is the cheapest
    /// minute in the session. Then sets, from the last exercise backwards — the
    /// accessories at the end are what the session can afford to lose. Only then
    /// whole exercises, and never below `minimumExercises`.
    private nonisolated static func shorten(
        _ exercises: [RoutineExercise],
        library: [Exercise],
        byMinutes minutes: Int,
        original: Int
    ) -> Adjustment {
        var working = exercises
        var changes: [Change] = []
        let target = max(1, original - max(1, minutes))

        // 1. Rest, down to 60 seconds.
        //
        // Repeated until it stops helping, not one pass. A single pass takes
        // 30 seconds off each exercise and stops — so a session with 180-second
        // rests would keep 150 of them, report that it couldn't reach the
        // target, and start deleting exercises while two full minutes of
        // standing about were still on the table. Each iteration must remove
        // something or the loop ends, so it terminates.
        var restStartedAt: [String: Int] = [:]
        while estimatedMinutes(working) > target {
            var reducedAnything = false
            for index in working.indices where estimatedMinutes(working) > target {
                let current = working[index].restSeconds
                guard current > minimumRestSeconds else { continue }
                if restStartedAt[working[index].exerciseId] == nil {
                    restStartedAt[working[index].exerciseId] = current
                }
                working[index].restSeconds = max(minimumRestSeconds, current - restStepSeconds)
                reducedAnything = true
            }
            if !reducedAnything { break }
        }

        // 2. Sets, from the back, never below two.
        //
        // Also repeated: one pass removes a single set from each exercise, and a
        // 60-minute session asked to lose 30 minutes needs more than that.
        var setsStartedAt: [String: Int] = [:]
        while estimatedMinutes(working) > target {
            var reducedAnything = false
            for index in working.indices.reversed() where estimatedMinutes(working) > target {
                let current = working[index].defaultSets
                guard current > minimumSets else { continue }
                if setsStartedAt[working[index].exerciseId] == nil {
                    setsStartedAt[working[index].exerciseId] = current
                }
                working[index].defaultSets = current - 1
                reducedAnything = true
            }
            if !reducedAnything { break }
        }

        // 3. Whole exercises, last first.
        while estimatedMinutes(working) > target, working.count > minimumExercises {
            let removed = working.removeLast()
            changes.append(
                .removed(
                    exerciseId: removed.exerciseId,
                    name: name(of: removed, in: library),
                    reason: "the session had to lose something"
                )
            )
        }

        // Notes last, and only for exercises still in the result.
        //
        // Emitting them as the trims happened listed "120s rest → 60s" for
        // exercises that were then deleted a few lines later, so the diff
        // described changes to a session that no longer contained them. One note
        // per surviving exercise, showing the whole change rather than each
        // 30-second step: "120s → 60s" is the fact, the four iterations that got
        // there are implementation detail.
        for item in working {
            if let from = restStartedAt[item.exerciseId], from != item.restSeconds {
                changes.append(
                    .restShortened(
                        exerciseId: item.exerciseId,
                        name: name(of: item, in: library),
                        from: from,
                        to: item.restSeconds
                    )
                )
            }
            if let from = setsStartedAt[item.exerciseId], from != item.defaultSets {
                changes.append(
                    .setsReduced(
                        exerciseId: item.exerciseId,
                        name: name(of: item, in: library),
                        from: from,
                        to: item.defaultSets
                    )
                )
            }
        }

        let adjusted = estimatedMinutes(working)
        if adjusted > target {
            changes.append(
                .shortfall(
                    "That's as short as it goes without dropping below \(minimumExercises) exercises — \(adjusted) minutes, not \(target)."
                )
            )
        }

        return Adjustment(
            exercises: working,
            changes: changes,
            originalMinutes: original,
            adjustedMinutes: adjusted
        )
    }

    // MARK: Equipment

    private nonisolated static func restrictEquipment(
        _ exercises: [RoutineExercise],
        library: [Exercise],
        to equipment: Set<ExerciseEquipment>,
        original: Int
    ) -> Adjustment {
        guard !equipment.isEmpty else {
            return Adjustment(
                exercises: exercises,
                changes: [],
                originalMinutes: original,
                adjustedMinutes: original
            )
        }

        var working: [RoutineExercise] = []
        var changes: [Change] = []
        var usedIds = Set(exercises.map(\.exerciseId))

        for item in exercises {
            guard let exercise = library.first(where: { $0.id == item.exerciseId }) else {
                working.append(item)
                continue
            }
            if equipment.contains(exercise.equipment) {
                working.append(item)
                continue
            }

            let candidates = SubstitutionEngine.candidates(
                for: SubstitutionEngine.Request(
                    replacing: exercise,
                    library: library,
                    idsInWorkout: usedIds,
                    availableEquipment: equipment
                )
            )

            guard let best = candidates.first else {
                changes.append(
                    .removed(
                        exerciseId: item.exerciseId,
                        name: exercise.name,
                        reason: "nothing in your library trains that with what you've got"
                    )
                )
                continue
            }

            var swapped = item
            swapped.exerciseId = best.exercise.id
            // The load was for a different movement. Carrying it over would put
            // a barbell number on a dumbbell exercise, which is not a smaller
            // mistake for being an obvious one.
            swapped.defaultWeight = 0
            working.append(swapped)
            usedIds.insert(best.exercise.id)
            changes.append(
                .replaced(
                    fromId: exercise.id,
                    fromName: exercise.name,
                    toId: best.exercise.id,
                    toName: best.exercise.name,
                    reason: best.reasons.first ?? "same muscle, equipment you have"
                )
            )
        }

        return Adjustment(
            exercises: working,
            changes: changes,
            originalMinutes: original,
            adjustedMinutes: estimatedMinutes(working)
        )
    }

    // MARK: Lighter

    /// One set off everything that can spare one, and a rep further from
    /// failure.
    ///
    /// Deliberately not "reduce the weight by 10%". The app has no reliable idea
    /// what someone's working weight should be on a bad day, and prescribing a
    /// number it can't justify is exactly the guess the whole design avoids.
    private nonisolated static func lighten(
        _ exercises: [RoutineExercise],
        library: [Exercise],
        original: Int
    ) -> Adjustment {
        var working = exercises
        var changes: [Change] = []

        for index in working.indices {
            let current = working[index].defaultSets
            let displayName = name(of: working[index], in: library)
            if current > 2 {
                working[index].defaultSets = current - 1
                changes.append(
                    .setsReduced(
                        exerciseId: working[index].exerciseId,
                        name: displayName,
                        from: current,
                        to: current - 1
                    )
                )
            }
            changes.append(
                .effortReduced(exerciseId: working[index].exerciseId, name: displayName)
            )
        }

        return Adjustment(
            exercises: working,
            changes: changes,
            originalMinutes: original,
            adjustedMinutes: estimatedMinutes(working)
        )
    }

    // MARK: Avoid a muscle

    private nonisolated static func avoid(
        _ muscle: BlueprintMuscle,
        in exercises: [RoutineExercise],
        library: [Exercise],
        original: Int
    ) -> Adjustment {
        var working: [RoutineExercise] = []
        var changes: [Change] = []

        for item in exercises {
            guard let exercise = library.first(where: { $0.id == item.exerciseId }),
                  BlueprintMuscle(appMuscle: exercise.muscle) == muscle else {
                working.append(item)
                continue
            }
            changes.append(
                .removed(
                    exerciseId: item.exerciseId,
                    name: exercise.name,
                    reason: "you asked to leave \(muscle.rawValue.lowercased()) alone"
                )
            )
        }

        if working.count < minimumExercises, !changes.isEmpty {
            changes.append(
                .shortfall(
                    "That leaves \(working.count) exercise\(working.count == 1 ? "" : "s") — worth picking a different session today."
                )
            )
        }

        return Adjustment(
            exercises: working,
            changes: changes,
            originalMinutes: original,
            adjustedMinutes: estimatedMinutes(working)
        )
    }

    // MARK: Helpers

    private nonisolated static func name(of item: RoutineExercise, in library: [Exercise]) -> String {
        library.first { $0.id == item.exerciseId }?.name ?? "That exercise"
    }
}
