import Foundation

// MARK: - Workout Resolver

/// Turns a blueprint's slots into real exercises from the user's own library.
///
/// This is the half of the safety model that lives on the device. The model
/// describes shape; this picks the movement. It follows that **a hallucinated
/// exercise is not something to filter out — it is something that cannot be
/// expressed**, because the model never gets to name one.
///
/// Deliberately pure and `nonisolated`: no `AppState`, no clock, no randomness.
/// Every input arrives in `Inputs`, so the same blueprint and the same library
/// always produce the same workout. That matters twice over — a "regenerate"
/// button that shuffled results at random would be indistinguishable from one
/// that recomputed them, and a test suite over a random function is worthless.
///
/// The one thing it will never do is create an `Exercise`. When a muscle has
/// nothing behind it, the slot is dropped and a note explains why. That is the
/// specific mistake `ImportRoutineSheet.importFromText` makes — appending a
/// custom exercise on a name miss — and the reason nothing here resolves by
/// name.
enum WorkoutResolver {

    // MARK: Inputs

    struct Inputs: Equatable, Sendable {
        /// Every exercise the user has, seeded or custom.
        var library: [Exercise]
        /// Last working weight per exercise id, from completed sessions. Used
        /// for scoring familiarity and for suggesting a starting load — the one
        /// number the app can supply and the model cannot.
        var history: [String: Double] = [:]
        var favouriteIds: Set<String> = []
        /// Ids already appearing in the user's routines. A movement they have
        /// chosen before is a better guess than one they never have.
        var idsInExistingRoutines: Set<String> = []
        /// Muscles the user asked to avoid. Enforced here as well as in the
        /// prompt, because a prompt is a request and this is a rule.
        var excludedMuscles: Set<BlueprintMuscle> = []
        /// Equipment the user has. Empty means no restriction.
        var availableEquipment: Set<ExerciseEquipment> = []
        /// Score adjustments learned from what the user has accepted and
        /// dismissed — see `TrainingMemory.preferences`. Empty means the app has
        /// no opinion yet, which is where everyone starts.
        var preferences: [String: Int] = [:]
        /// Exercises declined often enough to stop offering. A hard filter
        /// rather than a penalty: three refusals is a clear enough answer that
        /// continuing to suggest it is the app not listening.
        var refusedIds: Set<String> = []

        init(
            library: [Exercise],
            history: [String: Double] = [:],
            favouriteIds: Set<String> = [],
            idsInExistingRoutines: Set<String> = [],
            excludedMuscles: Set<BlueprintMuscle> = [],
            availableEquipment: Set<ExerciseEquipment> = [],
            preferences: [String: Int] = [:],
            refusedIds: Set<String> = []
        ) {
            self.library = library
            self.history = history
            self.favouriteIds = favouriteIds
            self.idsInExistingRoutines = idsInExistingRoutines
            self.excludedMuscles = excludedMuscles
            self.availableEquipment = availableEquipment
            self.preferences = preferences
            self.refusedIds = refusedIds
        }
    }

    // MARK: Output

    struct ResolvedItem: Equatable, Identifiable, Sendable {
        var id: String { prescription.id }
        var exercise: Exercise
        var prescription: RoutineExercise
        var slotMuscle: BlueprintMuscle
        /// True when the slot asked for equipment the library couldn't provide.
        /// Surfaced as a badge — never hidden, because the user asked for
        /// dumbbells for a reason.
        var substitutedEquipment: Bool
        /// Reps in reserve, carried through for display. Guidance rather than a
        /// load, which cannot be inferred safely without history.
        var rir: Int?
    }

    /// Why a slot isn't in the workout, or isn't what was asked for.
    ///
    /// Shown, never swallowed. "You have no calf exercises, so that slot was
    /// left out" is the sentence that stops someone wondering why they asked for
    /// calves and got none.
    enum ResolutionNote: Equatable, Sendable, Identifiable {
        case noExerciseForMuscle(BlueprintMuscle)
        case borrowedFromRelated(requested: BlueprintMuscle, used: BlueprintMuscle)
        case equipmentUnavailable(muscle: BlueprintMuscle, requested: ExerciseEquipment, used: ExerciseEquipment)
        case slotDroppedAsDuplicate(BlueprintMuscle)
        case slotDroppedAsExcluded(BlueprintMuscle)
        case nameLookedLikeAnExercise(String)

        var id: String { description }

        /// British English, written for the person rather than the log.
        var description: String {
            switch self {
            case .noExerciseForMuscle(let muscle):
                return "You have no \(muscle.rawValue.lowercased()) exercises, so that part was left out."
            case .borrowedFromRelated(let requested, let used):
                return "No \(requested.rawValue.lowercased()) exercises, so a \(used.rawValue.lowercased()) movement was used instead."
            case .equipmentUnavailable(let muscle, let requested, let used):
                return "No \(requested.label.lowercased()) \(muscle.rawValue.lowercased()) exercise, so a \(used.label.lowercased()) one was used."
            case .slotDroppedAsDuplicate(let muscle):
                return "Only one \(muscle.rawValue.lowercased()) exercise available, so the repeat was dropped."
            case .slotDroppedAsExcluded(let muscle):
                return "\(muscle.rawValue) was excluded, so that part was left out."
            case .nameLookedLikeAnExercise(let name):
                return "The suggested name matched an exercise (\(name)), so it was renamed."
            }
        }
    }

    struct ResolvedWorkout: Equatable, Identifiable, Sendable {
        var id = UUID()
        var name: String
        var focus: String
        var items: [ResolvedItem]
        var notes: [ResolutionNote]

        /// Computed here, never taken from the model.
        ///
        /// A model-supplied minute count is an unverifiable number the preview
        /// would have to either display or ignore. This one can be checked
        /// against the prescription it came from.
        var estimatedMinutes: Int {
            let seconds = items.reduce(0) { total, item in
                let reps = (item.prescription.repRangeMin + item.prescription.repRangeMax) / 2
                let working = reps * Self.secondsPerRep
                let rest = item.prescription.restSeconds
                return total + item.prescription.defaultSets * (working + rest)
            }
            // Plus setup: finding the rack, changing the plates, waiting for the
            // bench. A minute an exercise is conservative and stops the estimate
            // reading as suspiciously tidy.
            let overhead = items.count * 60
            return max(1, (seconds + overhead) / 60)
        }

        /// Two exercises is not a workout.
        ///
        /// The preview's confirm button is disabled on this, and says why. Saving
        /// a routine with one movement in it because the library was thin would
        /// be a worse outcome than refusing.
        var isViable: Bool { items.count >= 3 }

        static let secondsPerRep = 3

        /// Content, not identity.
        ///
        /// `id` is a fresh `UUID` per resolve, so synthesised equality would
        /// make every workout unequal to every other — including a workout and
        /// the identical one produced by resolving the same blueprint again,
        /// which is exactly the comparison the determinism tests need to make.
        static func == (lhs: ResolvedWorkout, rhs: ResolvedWorkout) -> Bool {
            lhs.name == rhs.name
                && lhs.focus == rhs.focus
                && lhs.notes == rhs.notes
                && lhs.items.count == rhs.items.count
                && zip(lhs.items, rhs.items).allSatisfy { a, b in
                    a.exercise.id == b.exercise.id
                        && a.slotMuscle == b.slotMuscle
                        && a.substitutedEquipment == b.substitutedEquipment
                        && a.rir == b.rir
                        && a.prescription.exerciseId == b.prescription.exerciseId
                        && a.prescription.defaultSets == b.prescription.defaultSets
                        && a.prescription.repRangeMin == b.prescription.repRangeMin
                        && a.prescription.repRangeMax == b.prescription.repRangeMax
                        && a.prescription.restSeconds == b.prescription.restSeconds
                        && a.prescription.defaultWeight == b.prescription.defaultWeight
                        && a.prescription.supersetGroupId == b.prescription.supersetGroupId
                }
        }
    }

    /// One session in a resolved plan.
    ///
    /// A named type rather than a `(key:workout:)` tuple: tuples cannot conform
    /// to `Sendable` or `Identifiable`, and this is handed to a `ForEach` in the
    /// preview.
    struct ResolvedPlanSession: Equatable, Identifiable, Sendable {
        var id: String { key }
        var key: String
        var workout: ResolvedWorkout
    }

    struct ResolvedPlan: Equatable, Identifiable, Sendable {
        var id = UUID()
        var name: String
        var weeks: Int
        /// In blueprint order.
        var sessions: [ResolvedPlanSession]
        /// 1 = Monday → session key. A weekday absent from this map is a rest
        /// day.
        var schedule: [Int: String]
        var progression: String?
        var notes: [ResolutionNote]

        /// How many dated `PlannedSession`s committing this would create.
        /// Shown before the tap, because "adds 12 planned sessions" is the sort
        /// of thing people want to know in advance.
        var sessionCount: Int { schedule.count * weeks }

        var isViable: Bool {
            !sessions.isEmpty && !schedule.isEmpty && sessions.allSatisfy { $0.workout.isViable }
        }

        /// Content, not identity — same reasoning as `ResolvedWorkout`.
        static func == (lhs: ResolvedPlan, rhs: ResolvedPlan) -> Bool {
            lhs.name == rhs.name
                && lhs.weeks == rhs.weeks
                && lhs.schedule == rhs.schedule
                && lhs.progression == rhs.progression
                && lhs.notes == rhs.notes
                && lhs.sessions == rhs.sessions
        }
    }

    // MARK: Clamps

    // Every number from the model is clamped, not trusted — the same
    // belt-and-braces as `CoachActions`'s `min(max(count, 1), 8)` on water.
    // A schema constrains generation; it does not guarantee the result.
    static let setsRange = 1...6
    static let repsRange = 1...50
    static let restRange = 15...300
    static let rirRange = 0...5

    // MARK: Resolving a session

    static func resolve(
        _ blueprint: WorkoutBlueprint,
        inputs: Inputs,
        excludingIds: Set<String> = []
    ) -> ResolvedWorkout {
        var items: [ResolvedItem] = []
        var notes: [ResolutionNote] = []
        var usedIds = excludingIds
        var supersetIds: [Int: String] = [:]

        for slot in blueprint.slots {
            if inputs.excludedMuscles.contains(slot.muscle) {
                appendUnique(.slotDroppedAsExcluded(slot.muscle), to: &notes)
                continue
            }

            guard let pick = choose(slot: slot, inputs: inputs, usedIds: usedIds, notes: &notes) else {
                continue
            }

            usedIds.insert(pick.exercise.id)

            // A superset group number becomes a stable id shared by its members.
            var supersetGroupId: String?
            if let group = slot.supersetGroup {
                if let existing = supersetIds[group] {
                    supersetGroupId = existing
                } else {
                    let fresh = "superset-\(group)"
                    supersetIds[group] = fresh
                    supersetGroupId = fresh
                }
            }

            let repMin = clamp(slot.repMin, to: repsRange)
            let repMax = max(repMin, clamp(slot.repMax, to: repsRange))

            let prescription = RoutineExercise(
                exerciseId: pick.exercise.id,
                defaultSets: clamp(slot.sets, to: setsRange),
                defaultReps: (repMin + repMax) / 2,
                // The one number the app can supply and the model cannot. Absent
                // history it stays zero, and the RIR guidance carries the effort
                // instead — a starting weight guessed from nothing is the kind
                // of number someone gets under a bar with.
                defaultWeight: inputs.history[pick.exercise.id] ?? 0,
                repRangeMin: repMin,
                repRangeMax: repMax,
                restSeconds: clamp(slot.restSeconds, to: restRange),
                supersetGroupId: supersetGroupId
            )

            items.append(
                ResolvedItem(
                    exercise: pick.exercise,
                    prescription: prescription,
                    slotMuscle: slot.muscle,
                    substitutedEquipment: pick.substitutedEquipment,
                    rir: slot.rir.map { clamp($0, to: rirRange) }
                )
            )
        }

        // The last gate on naming. The server checks the slots; only this side
        // holds the library, so only this side can catch a *session name* that
        // happens to be a movement — "Bench Press" as the name of a whole
        // workout reads as though the model ignored the rule.
        var name = blueprint.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if inputs.library.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            notes.append(.nameLookedLikeAnExercise(name))
            name = generatedName(for: items)
        }
        if name.isEmpty { name = generatedName(for: items) }

        return ResolvedWorkout(
            name: name,
            focus: blueprint.focus.trimmingCharacters(in: .whitespacesAndNewlines),
            items: items,
            notes: notes
        )
    }

    // MARK: Resolving a plan

    static func resolve(_ plan: PlanBlueprint, inputs: Inputs) -> ResolvedPlan {
        var sessions: [ResolvedPlanSession] = []
        var notes: [ResolutionNote] = []

        // Weekday → session key, dropping references to sessions that don't
        // exist. The server checks this too, but both sides of the reference are
        // in the response, so checking twice costs nothing and the client is
        // what actually schedules.
        let validKeys = Set(plan.sessions.map(\.key))
        var schedule: [Int: String] = [:]
        for day in plan.weekdays {
            guard (1...7).contains(day.weekday) else { continue }
            guard let key = day.sessionKey, validKeys.contains(key) else { continue }
            schedule[day.weekday] = key
        }

        // Which sessions land on days next to each other, so the same movement
        // isn't prescribed on consecutive days. Computed before resolving, since
        // the penalty has to be known while choosing.
        let adjacency = adjacentKeys(in: schedule)

        var idsByKey: [String: Set<String>] = [:]
        for session in plan.sessions {
            // Exclude what its neighbours already used. Not a hard rule across
            // the whole week — a push day and a pull day may share nothing, but
            // two leg days in a week legitimately repeat a squat.
            let neighbourIds = (adjacency[session.key] ?? [])
                .reduce(into: Set<String>()) { $0.formUnion(idsByKey[$1] ?? []) }

            let workout = resolve(session.blueprint, inputs: inputs, excludingIds: neighbourIds)
            idsByKey[session.key] = Set(workout.items.map(\.exercise.id))
            sessions.append(ResolvedPlanSession(key: session.key, workout: workout))
            notes.append(contentsOf: workout.notes)
        }

        // Deduplicated: the same missing muscle across four sessions is one
        // fact, not four.
        var uniqueNotes: [ResolutionNote] = []
        for note in notes { appendUnique(note, to: &uniqueNotes) }

        return ResolvedPlan(
            name: plan.name.trimmingCharacters(in: .whitespacesAndNewlines),
            weeks: max(1, min(plan.weeks, 12)),
            sessions: sessions,
            schedule: schedule,
            progression: plan.progression,
            notes: uniqueNotes
        )
    }

    /// For each session key, the keys scheduled on adjacent weekdays.
    ///
    /// Wraps around Sunday to Monday, because a Sunday session followed by a
    /// Monday one is as consecutive as any other pair.
    private static func adjacentKeys(in schedule: [Int: String]) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for (weekday, key) in schedule {
            let neighbours = [weekday == 1 ? 7 : weekday - 1, weekday == 7 ? 1 : weekday + 1]
            for neighbour in neighbours {
                guard let other = schedule[neighbour], other != key else { continue }
                out[key, default: []].insert(other)
            }
        }
        return out
    }

    // MARK: Choosing

    private struct Pick {
        var exercise: Exercise
        var substitutedEquipment: Bool
    }

    /// Picks one exercise for a slot, or nothing, appending a note either way
    /// when the answer isn't the obvious one.
    private static func choose(
        slot: WorkoutSlot,
        inputs: Inputs,
        usedIds: Set<String>,
        notes: inout [ResolutionNote]
    ) -> Pick? {
        var pool = candidates(for: slot.muscle, in: inputs)
        var borrowedFrom: BlueprintMuscle?

        if pool.isEmpty {
            for related in slot.muscle.related where !inputs.excludedMuscles.contains(related) {
                let fallback = candidates(for: related, in: inputs)
                if !fallback.isEmpty {
                    pool = fallback
                    borrowedFrom = related
                    break
                }
            }
        }

        guard !pool.isEmpty else {
            appendUnique(.noExerciseForMuscle(slot.muscle), to: &notes)
            return nil
        }

        let unused = pool.filter { !usedIds.contains($0.id) }
        guard !unused.isEmpty else {
            // Everything for this muscle is already in the workout. A shorter
            // honest session beats the same exercise twice.
            appendUnique(.slotDroppedAsDuplicate(slot.muscle), to: &notes)
            return nil
        }

        let best = unused
            .map { (exercise: $0, score: score($0, for: slot, inputs: inputs)) }
            // Descending by score, then ascending by id. The tie-break is what
            // makes this deterministic — without it, two equally good exercises
            // resolve in whatever order the array happened to be in.
            .sorted { $0.score == $1.score ? $0.exercise.id < $1.exercise.id : $0.score > $1.score }
            .first!
            .exercise

        if let borrowedFrom {
            appendUnique(.borrowedFromRelated(requested: slot.muscle, used: borrowedFrom), to: &notes)
        }

        var substituted = false
        if let wanted = slot.equipment, best.equipment != wanted {
            substituted = true
            appendUnique(
                .equipmentUnavailable(muscle: slot.muscle, requested: wanted, used: best.equipment),
                to: &notes
            )
        }

        return Pick(exercise: best, substitutedEquipment: substituted)
    }

    /// Exercises for a muscle that the user can actually perform.
    ///
    /// Matched case-insensitively, because `Exercise.muscle` is a free `String`
    /// rather than an enum — a custom exercise can carry "chest", "Chest" or
    /// anything else, and dropping it over a capital letter would quietly
    /// shrink the library.
    private static func candidates(for muscle: BlueprintMuscle, in inputs: Inputs) -> [Exercise] {
        inputs.library.filter { exercise in
            guard BlueprintMuscle(appMuscle: exercise.muscle) == muscle else { return false }
            // Declined three times. Offering it a fourth is not persistence.
            guard !inputs.refusedIds.contains(exercise.id) else { return false }
            // Equipment the user doesn't have is a hard filter, unlike the
            // slot's *preferred* equipment, which is only a score. Prescribing a
            // cable row to someone training in a garage is not a near miss.
            guard !inputs.availableEquipment.isEmpty else { return true }
            return inputs.availableEquipment.contains(exercise.equipment)
        }
    }

    /// How well an exercise fits a slot. Higher is better; ties break on id.
    private static func score(_ exercise: Exercise, for slot: WorkoutSlot, inputs: Inputs) -> Int {
        var score = 0

        if let wanted = slot.equipment, exercise.equipment == wanted { score += 40 }
        if let wanted = slot.movementType, exercise.movementType == wanted { score += 25 }
        if inputs.favouriteIds.contains(exercise.id) { score += 12 }
        // A movement they have actually performed beats one they haven't: the
        // app knows a working weight for it, and they know how to do it.
        if inputs.history[exercise.id] != nil { score += 10 }
        if inputs.idsInExistingRoutines.contains(exercise.id) { score += 8 }

        // Compounds should be the harder movements; isolation work shouldn't
        // need a spotter. Difficulty runs 1–3 in the seed.
        let targetDifficulty = (slot.movementType ?? .compound) == .isolation ? 1 : 2
        score -= 6 * abs(exercise.difficulty - targetDifficulty)

        // What the person has actually said about this exercise, by accepting
        // or dismissing it. Capped at ±36 by `TrainingMemory`, so it can
        // outweigh any single reason to pick something but never becomes the
        // only reason.
        score += inputs.preferences[exercise.id] ?? 0

        return score
    }

    // MARK: Helpers

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Notes are facts, and a fact repeated is still one fact.
    private static func appendUnique(_ note: ResolutionNote, to notes: inout [ResolutionNote]) {
        guard !notes.contains(note) else { return }
        notes.append(note)
    }

    /// A label built from what the session actually contains.
    ///
    /// Used when the model's name was empty or turned out to be a movement.
    private static func generatedName(for items: [ResolvedItem]) -> String {
        var counts: [BlueprintMuscle: Int] = [:]
        for item in items { counts[item.slotMuscle, default: 0] += 1 }
        let dominant = counts
            .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .first?.key
        guard let dominant else { return "Workout" }
        return "\(dominant.rawValue) session"
    }
}
