import Foundation

// MARK: - Training Memory

/// What the app has learned about *this* person, as opposed to what it knows
/// about training.
///
/// Everything above this file reacts: something happens, a rule fires, the same
/// rule fires the same way next month. This is the part that changes. It has two
/// sources:
///
/// - **Feedback.** Every proposal accepted, edited or dismissed is recorded.
///   Reject the same exercise three times and the resolver stops offering it —
///   not because a model decided to, but because you said no three times and the
///   score moved.
/// - **Performance.** The increments you actually succeed with, and how long
///   your sessions actually take. The app shipped with 2.5 kg and three seconds
///   a rep for everybody; those are now starting guesses that get replaced by
///   your own numbers.
///
/// Deliberately not machine learning. Counting and averaging over the user's own
/// records is legible — every number here can be traced to specific sessions and
/// specific taps, which matters because these numbers change what gets
/// prescribed. A model that learned the same things would be a black box between
/// someone and their own training.
enum TrainingMemory {

    // MARK: What gets remembered

    /// How much a single accept or reject moves an exercise's score.
    ///
    /// The resolver's own signals run from +40 (equipment match) down to −6 per
    /// point of difficulty mismatch. ±12 is deliberately in the middle of that:
    /// enough that three rejections (−36) outweigh almost any single reason to
    /// pick something, and small enough that one stray dismissal doesn't
    /// blacklist an exercise for good.
    static let feedbackWeight = 12
    /// The most any one exercise's score can move, in either direction.
    ///
    /// Without a cap, an exercise rejected fifteen times would sit at −180 and
    /// could never come back even if the person's equipment changed. Three
    /// rejections is the strongest statement the memory will make.
    static let maximumAdjustment = 36
    /// Feedback older than this stops counting.
    ///
    /// People change gyms, recover from injuries and change their minds. A
    /// refusal from last spring should not still be shaping this week.
    static let relevanceDays = 120

    // MARK: Preference

    /// Score adjustments by exercise id, for `WorkoutResolver`.
    ///
    /// Positive means "you keep this one", negative means "you keep saying no".
    /// Absent means no opinion, which is different from neutral only in that it
    /// costs nothing to compute.
    @MainActor
    static func preferences(
        appState: AppState,
        now: Date = Date()
    ) -> [String: Int] {
        var out: [String: Int] = [:]

        for entry in relevant(appState.coachFeedback, now: now) {
            guard let id = entry.exerciseId else { continue }
            let delta: Int
            switch entry.outcome {
            case .accepted: delta = feedbackWeight
            case .dismissed: delta = -feedbackWeight
            // An edit is neither. Someone who changed the weight and kept the
            // exercise has endorsed the exercise, gently.
            case .edited: delta = feedbackWeight / 2
            }
            out[id, default: 0] += delta
        }

        return out.mapValues { max(-maximumAdjustment, min(maximumAdjustment, $0)) }
    }

    /// Exercises rejected enough times to stop offering.
    ///
    /// Three, matching `DriftEngine`'s threshold and for the same reason: two is
    /// a mood, three is a decision.
    @MainActor
    static func refused(appState: AppState, now: Date = Date()) -> Set<String> {
        var counts: [String: Int] = [:]
        for entry in relevant(appState.coachFeedback, now: now)
        where entry.outcome == .dismissed {
            guard let id = entry.exerciseId else { continue }
            counts[id, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 3 }.keys)
    }

    // MARK: Load increments

    /// The smallest load step this person actually succeeds with on this
    /// exercise.
    ///
    /// `ProgressionEngine.increment(for:)` returns 2.5 kg for every barbell in
    /// the world. That is a reasonable guess and it is wrong for anyone with
    /// microplates, anyone on a fixed dumbbell rack that jumps in 4s, and anyone
    /// whose gym's smallest plate is 5 kg. This reads what actually happened:
    /// the load changes that stuck.
    ///
    /// Falls back to the equipment default below `minimumIncrementSamples`,
    /// because a learned number from two sessions is a coincidence.
    static let minimumIncrementSamples = 3

    @MainActor
    static func increment(for exercise: Exercise, appState: AppState) -> Double {
        let sessions = appState.completedWorkouts
            .filter { $0.exercises.contains { $0.exerciseId == exercise.id } }
            .sorted { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }

        var tops: [Double] = []
        for session in sessions {
            guard let performed = session.exercises.first(where: { $0.exerciseId == exercise.id }) else { continue }
            let working = performed.sets.filter { $0.done && !$0.isWarmup && $0.weight > 0 }
            guard let top = working.map(\.weight).max() else { continue }
            tops.append(top)
        }

        // Only increases. A drop is a deload, an off day or a different
        // rep range, and averaging those in would produce an "increment" of
        // roughly zero for anyone who has ever had a bad week.
        var steps: [Double] = []
        for (previous, next) in zip(tops, tops.dropFirst()) where next > previous {
            steps.append(next - previous)
        }

        let fallback = ProgressionEngine.increment(for: exercise)
        guard steps.count >= minimumIncrementSamples else { return fallback }

        // The smallest step they have actually made, not the average — the
        // question is "what is the finest change available to this person",
        // and one 10 kg jump shouldn't hide the 1.25 kg ones.
        let smallest = steps.min() ?? fallback
        // Sanity bounds. A logging slip that records 100 kg as 10 kg would
        // otherwise teach the app that this person progresses in 90 kg steps.
        guard smallest >= 0.5, smallest <= 20 else { return fallback }
        return smallest
    }

    // MARK: Session pace

    /// How long this person's sets actually take.
    ///
    /// `WorkoutResolver` estimates three seconds a rep plus the prescribed rest
    /// plus a minute an exercise. For someone who supersets and rushes, every
    /// estimate is long; for someone who chats between sets, every estimate is
    /// short — and "make this 20 minutes shorter" is computed from that
    /// estimate, so a wrong pace makes the adjuster wrong too.
    struct Pace: Equatable, Sendable {
        /// Multiplier on the standard estimate. 1.0 is the shipped default.
        var factor: Double
        /// Sessions the figure is based on, so a caller can hedge.
        var samples: Int

        static let standard = Pace(factor: 1.0, samples: 0)

        /// Below this the learned figure is ignored — see `minimumPaceSamples`.
        var isLearned: Bool { samples >= TrainingMemory.minimumPaceSamples }
    }

    static let minimumPaceSamples = 4

    @MainActor
    static func pace(appState: AppState, now: Date = Date()) -> Pace {
        let cutoff = Calendar.current.date(byAdding: .day, value: -56, to: now) ?? now

        var ratios: [Double] = []
        for session in appState.completedWorkouts {
            guard let finishedAt = session.finishedAt, finishedAt >= cutoff else { continue }
            guard let routineId = session.routineId,
                  let routine = appState.routines.first(where: { $0.id == routineId }) else { continue }

            let actual = finishedAt.timeIntervalSince(session.startedAt) / 60
            // A forgotten timer teaches nothing except that timers get
            // forgotten.
            guard actual > 5, actual < 240 else { continue }

            let estimate = Double(WorkoutAdjuster.estimatedMinutes(routine.exercises))
            guard estimate > 0 else { continue }
            ratios.append(actual / estimate)
        }

        guard ratios.count >= minimumPaceSamples else { return .standard }

        let sorted = ratios.sorted()
        // Median, so one enormous session doesn't set everyone's pace.
        let median = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2

        // Clamped hard. Beyond this range the figure is describing a data
        // problem rather than a person.
        return Pace(factor: max(0.6, min(1.8, median)), samples: ratios.count)
    }

    // MARK: What the coach is told

    /// One sentence about what the app has learned, for the builder prompt.
    ///
    /// Counts and multipliers. No exercise names — the model must never see one
    /// to imitate — and nothing that would identify a session.
    @MainActor
    static func promptText(appState: AppState, now: Date = Date()) -> String? {
        var parts: [String] = []

        let refusedCount = refused(appState: appState, now: now).count
        if refusedCount > 0 {
            parts.append("\(refusedCount) exercise(s) have been repeatedly declined and are excluded by the app.")
        }

        let learned = pace(appState: appState, now: now)
        if learned.isLearned, abs(learned.factor - 1) > 0.15 {
            parts.append(
                learned.factor > 1
                    ? "Sessions run about \(Int((learned.factor - 1) * 100))% longer than prescribed — budget fewer exercises."
                    : "Sessions run about \(Int((1 - learned.factor) * 100))% quicker than prescribed."
            )
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Helpers

    nonisolated static func relevant(
        _ entries: [CoachFeedbackEntry],
        now: Date
    ) -> [CoachFeedbackEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -relevanceDays, to: now) ?? now
        return entries.filter { $0.date >= cutoff }
    }
}

// MARK: - Feedback entry

/// One thing the app proposed and one thing the person did about it.
///
/// Persisted, and therefore optional-with-default everywhere it is stored — see
/// the note on `StateSnapshot`. It records *what kind* of proposal and *which
/// exercise*, never the wording: the point is to learn a preference, not to keep
/// a transcript.
struct CoachFeedbackEntry: Codable, Equatable, Sendable, Identifiable {

    enum Source: String, Codable, Sendable {
        case builder
        case progression
        case substitution
        case adjustment
        case review
        case drift
        case deload
        case plateau
    }

    enum Outcome: String, Codable, Sendable {
        case accepted
        case edited
        case dismissed
    }

    var id: String = UUID().uuidString
    var date: Date = Date()
    var source: Source
    var outcome: Outcome
    /// The exercise the feedback is about, when it is about one. Nil for
    /// whole-programme decisions.
    var exerciseId: String?

    init(
        id: String = UUID().uuidString,
        date: Date = Date(),
        source: Source,
        outcome: Outcome,
        exerciseId: String? = nil
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.outcome = outcome
        self.exerciseId = exerciseId
    }
}
