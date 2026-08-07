import Foundation

// MARK: - Progression Engine

/// Decides whether to add load, add reps, hold, or back off — from rules, not
/// from judgement.
///
/// **Gemini has no input here at all.** It may be asked to phrase the result in
/// a sentence; it may not change the result. That division exists because
/// progression is the one part of a training app where being wrong has a
/// physical cost: "add 5 kg" to someone who failed their last set is an
/// instruction to attempt a lift they have already demonstrated they cannot do.
/// A rule that can be read, tested and argued with is worth more here than a
/// model that is usually right.
///
/// Pure and `nonisolated`. Everything it needs arrives in `Input`.
enum ProgressionEngine {

    // MARK: Outcome

    /// What to do next time. Deliberately includes `insufficientInformation` as
    /// a first-class answer rather than defaulting to "hold" — they mean
    /// different things, and only one of them is worth showing a card for.
    enum Action: String, Equatable, Sendable, Codable {
        case increaseLoad
        case increaseReps
        case hold
        case reduceLoad
        /// Hit the target but with sets left incomplete or to failure. Repeat
        /// the same numbers before adding to them.
        case repeatSame
        case insufficientInformation

        var headline: String {
            switch self {
            case .increaseLoad:           return "Add a little load"
            case .increaseReps:           return "Add a rep"
            case .hold:                   return "Keep the same numbers"
            case .reduceLoad:             return "Ease the load back"
            case .repeatSame:             return "Repeat this one"
            case .insufficientInformation: return "Not enough to go on yet"
            }
        }
    }

    struct Proposal: Equatable, Sendable, Identifiable {
        var id: String { exerciseId }

        var exerciseId: String
        var exerciseName: String
        var action: Action

        /// What was done last time.
        var currentWeight: Double
        var currentReps: Int
        /// What is proposed. Equal to the current values for `.hold` and
        /// `.repeatSame`, so a preview can always render before → after without
        /// special-casing.
        var proposedWeight: Double
        var proposedReps: Int

        /// Why, in the user's terms. At most two lines.
        var evidence: [String]

        var changesAnything: Bool {
            proposedWeight != currentWeight || proposedReps != currentReps
        }
    }

    // MARK: Input

    struct Input: Equatable, Sendable {
        var exerciseId: String
        var exerciseName: String
        /// Target range from the routine.
        var repRangeMin: Int
        var repRangeMax: Int
        /// The working sets of the most recent session, in order.
        var lastSession: [SetResult]
        /// How many comparable sessions exist, including the last. Below
        /// `minimumSessions` the answer is `insufficientInformation` whatever
        /// the numbers say.
        var comparableSessions: Int
        /// The smallest load change the equipment allows. A barbell with 1.25 kg
        /// plates moves in 2.5 kg; a fixed dumbbell rack moves in 2 kg and
        /// pretending otherwise produces advice nobody can follow.
        var loadIncrement: Double

        init(
            exerciseId: String,
            exerciseName: String,
            repRangeMin: Int,
            repRangeMax: Int,
            lastSession: [SetResult],
            comparableSessions: Int,
            loadIncrement: Double = 2.5
        ) {
            self.exerciseId = exerciseId
            self.exerciseName = exerciseName
            self.repRangeMin = repRangeMin
            self.repRangeMax = repRangeMax
            self.lastSession = lastSession
            self.comparableSessions = comparableSessions
            self.loadIncrement = loadIncrement
        }
    }

    struct SetResult: Equatable, Sendable {
        var weight: Double
        var reps: Int
        var completed: Bool
        /// Recorded effort, where the user logged it. Optional because most
        /// people don't, and a rule that requires it would never fire.
        var rpe: Int?
        /// Marked as taken to failure.
        var toFailure: Bool

        init(weight: Double, reps: Int, completed: Bool = true, rpe: Int? = nil, toFailure: Bool = false) {
            self.weight = weight
            self.reps = reps
            self.completed = completed
            self.rpe = rpe
            self.toFailure = toFailure
        }
    }

    /// Below this, no proposal is made.
    ///
    /// One session is an event, not a trend. Progressing off a single good day
    /// is how someone ends up adding load every session until they can't.
    static let minimumSessions = 2

    /// An RPE at or above this is "that was everything I had".
    static let hardEffortRPE = 9

    // MARK: The rules

    static func propose(_ input: Input) -> Proposal {
        let sets = input.lastSession
        let currentWeight = sets.map(\.weight).max() ?? 0
        let currentReps = sets.filter(\.completed).map(\.reps).min() ?? 0

        func proposal(
            _ action: Action,
            weight: Double? = nil,
            reps: Int? = nil,
            evidence: [String]
        ) -> Proposal {
            Proposal(
                exerciseId: input.exerciseId,
                exerciseName: input.exerciseName,
                action: action,
                currentWeight: currentWeight,
                currentReps: currentReps,
                proposedWeight: weight ?? currentWeight,
                proposedReps: reps ?? currentReps,
                evidence: evidence
            )
        }

        // 1. Nothing to reason from.
        guard !sets.isEmpty else {
            return proposal(.insufficientInformation, evidence: ["No sets recorded for this exercise yet."])
        }
        guard input.comparableSessions >= minimumSessions else {
            return proposal(
                .insufficientInformation,
                evidence: [
                    "Only \(input.comparableSessions) session\(input.comparableSessions == 1 ? "" : "s") recorded.",
                    "One session is an event rather than a trend.",
                ]
            )
        }

        let completed = sets.filter(\.completed)
        let incomplete = sets.count - completed.count

        // 2. Sets left unfinished. The load was too heavy for the volume asked
        //    for, and that is true regardless of what the finished sets did.
        if incomplete > 0 {
            // With no load to shed, backing off means fewer reps rather than
            // less weight.
            guard input.loadIncrement > 0 else {
                return proposal(
                    .repeatSame,
                    reps: max(1, input.repRangeMin),
                    evidence: [
                        "\(incomplete) of \(sets.count) sets weren't completed.",
                        "Aim for the bottom of the range next time before pushing on.",
                    ]
                )
            }
            return proposal(
                .reduceLoad,
                weight: max(0, currentWeight - input.loadIncrement),
                evidence: [
                    "\(incomplete) of \(sets.count) sets weren't completed.",
                    "Easing back a little should let you finish all of them.",
                ]
            )
        }

        guard let lowestReps = completed.map(\.reps).min() else {
            return proposal(.insufficientInformation, evidence: ["No completed sets to judge."])
        }

        let hitTop = lowestReps >= input.repRangeMax
        let belowBottom = lowestReps < input.repRangeMin
        let wasVeryHard = completed.contains { ($0.rpe ?? 0) >= hardEffortRPE || $0.toFailure }

        // 3. Below the target range: the load is ahead of the person.
        if belowBottom {
            return proposal(
                .reduceLoad,
                weight: max(0, currentWeight - input.loadIncrement),
                evidence: [
                    "You managed \(lowestReps) reps against a target of \(input.repRangeMin)–\(input.repRangeMax).",
                    "A smaller load should bring the reps back into range.",
                ]
            )
        }

        // 4. Top of the range on every set, and it wasn't a maximal effort:
        //    time to add load and drop back to the bottom of the range.
        if hitTop && !wasVeryHard {
            // Unless there is no load to add. A press-up has no plates, so the
            // only honest progression is more reps — proposing "add 0 kg" would
            // be a card that changes nothing while claiming to.
            guard input.loadIncrement > 0 else {
                return proposal(
                    .increaseReps,
                    reps: lowestReps + 1,
                    evidence: [
                        "Every set reached \(input.repRangeMax) reps, the top of your range.",
                        "There's no load to add here, so the next step is another rep.",
                    ]
                )
            }
            return proposal(
                .increaseLoad,
                weight: currentWeight + input.loadIncrement,
                reps: input.repRangeMin,
                evidence: [
                    "Every set reached \(input.repRangeMax) reps, the top of your range.",
                    "Adding \(input.loadIncrement.weightDisplay) kg puts you back near the bottom of it.",
                ]
            )
        }

        // 5. Top of the range but it cost everything. The reps are there; the
        //    capacity isn't yet. Repeating consolidates rather than gambling.
        if hitTop && wasVeryHard {
            return proposal(
                .repeatSame,
                evidence: [
                    "You reached the top of the range, but at close to maximum effort.",
                    "Repeating the same numbers first tends to make the next jump stick.",
                ]
            )
        }

        // 6. Inside the range with room left: add a rep.
        if lowestReps < input.repRangeMax {
            return proposal(
                .increaseReps,
                reps: min(lowestReps + 1, input.repRangeMax),
                evidence: [
                    "\(lowestReps) reps, inside your \(input.repRangeMin)–\(input.repRangeMax) range.",
                    "A rep at a time is the cheapest progress available.",
                ]
            )
        }

        return proposal(.hold, evidence: ["Nothing in the last session suggests a change."])
    }

    // MARK: Reading a session

    /// Proposals for every exercise in a finished session.
    ///
    /// Ordered as the session was, and filtered to those that actually say
    /// something — a list where half the rows read "not enough to go on" is a
    /// list nobody reads.
    @MainActor
    static func proposals(
        forSessionId sessionId: String,
        appState: AppState
    ) -> [Proposal] {
        guard let session = appState.sessions.first(where: { $0.id == sessionId }) else { return [] }

        return session.exercises.compactMap { exercise -> Proposal? in
            guard let library = appState.exercises.first(where: { $0.id == exercise.exerciseId }) else {
                return nil
            }

            let working = exercise.sets
                .filter { $0.kind.countsAsWorkingSet }
                .map {
                    SetResult(
                        weight: $0.weight,
                        reps: $0.reps,
                        completed: $0.done,
                        rpe: $0.rpe,
                        toFailure: $0.isFailure
                    )
                }
            guard !working.isEmpty else { return nil }

            let proposal = propose(
                Input(
                    exerciseId: exercise.exerciseId,
                    exerciseName: library.name,
                    repRangeMin: exercise.targetRepMin,
                    repRangeMax: exercise.targetRepMax,
                    lastSession: working,
                    comparableSessions: comparableSessionCount(
                        exerciseId: exercise.exerciseId, appState: appState
                    ),
                    // The increment this person actually succeeds with, where
                    // there is enough history to know it. `increment(for:)` is
                    // the shipped guess and stays as the fallback.
                    loadIncrement: TrainingMemory.increment(for: library, appState: appState)
                )
            )

            // `hold` and `insufficientInformation` are correct answers and bad
            // cards. They stay in the model and out of the list.
            switch proposal.action {
            case .hold, .insufficientInformation: return nil
            default: return proposal
            }
        }
    }

    /// How many finished sessions contain this exercise with a working set.
    static func comparableSessionCount(
        exerciseId: String,
        appState: AppState
    ) -> Int {
        appState.completedWorkouts.reduce(into: 0) { total, session in
            let hasWorkingSet = session.exercises.contains { exercise in
                exercise.exerciseId == exerciseId
                    && exercise.sets.contains { $0.done && $0.kind.countsAsWorkingSet }
            }
            if hasWorkingSet { total += 1 }
        }
    }

    /// The smallest load step the equipment realistically allows.
    ///
    /// Advising "add 2.5 kg" on a fixed dumbbell rack that jumps in 2s produces
    /// a number nobody can act on. Approximate, but closer than one constant for
    /// everything.
    static func increment(for exercise: Exercise) -> Double {
        switch exercise.equipment {
        case .barbell, .ezBar:            return 2.5
        case .dumbbell:                   return 2.0
        case .machine, .cable:            return 2.5
        case .kettlebell:                 return 4.0
        case .bodyweight, .band, .other:  return 0
        }
    }
}
