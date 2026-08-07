import Foundation

// MARK: - Training History Digest

/// What the user's own training says about what to build next.
///
/// Aggregates only. No session, no date, no note, no exercise name unless the
/// caller is allowed names — the digest exists so a generated programme can be
/// shaped by what someone actually does, without their training log leaving the
/// device.
///
/// Three rules the brief is explicit about, and they are enforced here rather
/// than left to the model:
///
/// - **Nothing is inferred from a single action.** Every threshold below is at
///   least two occurrences.
/// - **One missed workout is not a pattern.** Frequency is a median over weeks,
///   so a fortnight's holiday doesn't rewrite the plan.
/// - **No starting loads are invented.** Working ranges are reported only where
///   there are enough sessions to mean something, and even then as a range.
enum TrainingHistoryDigest {

    struct Digest: Equatable, Sendable {
        /// Sessions per week, median over the window. Nil below `minimumWeeks`.
        var typicalSessionsPerWeek: Int?
        /// Median session length in minutes. Nil when nothing plausible is
        /// recorded.
        var typicalDurationMinutes: Int?
        /// Blueprint muscles trained most, most first.
        var frequentMuscles: [String]
        /// Exercises done often enough to be worth keeping in a new programme.
        var reliableExerciseIds: [String]
        /// Exercises repeatedly prescribed and repeatedly skipped.
        var avoidedExerciseIds: [String]
        /// Equipment actually used, which is better evidence than what someone
        /// says they have.
        var equipmentUsed: [String]
        /// How many finished sessions this is built from, so a consumer can
        /// hedge rather than treat a thin digest as a rich one.
        var sessionsConsidered: Int

        /// Whether there is enough to shape anything.
        var isUsable: Bool { sessionsConsidered >= minimumSessions }

        static let empty = Digest(
            typicalSessionsPerWeek: nil,
            typicalDurationMinutes: nil,
            frequentMuscles: [],
            reliableExerciseIds: [],
            avoidedExerciseIds: [],
            equipmentUsed: [],
            sessionsConsidered: 0
        )
    }

    /// Below this, history says nothing worth acting on.
    static let minimumSessions = 6
    /// Weeks of history considered.
    static let windowWeeks = 8
    /// Times an exercise must appear before it counts as part of someone's
    /// training rather than something they tried once.
    static let reliableThreshold = 3

    // MARK: Building

    @MainActor
    static func build(
        appState: AppState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Digest {
        let cutoff = calendar.date(byAdding: .day, value: -7 * windowWeeks, to: now) ?? now
        let sessions = appState.completedWorkouts.filter { ($0.finishedAt ?? .distantPast) >= cutoff }

        guard sessions.count >= minimumSessions else { return .empty }

        var exerciseCounts: [String: Int] = [:]
        var muscleCounts: [String: Int] = [:]
        var equipment = Set<String>()
        var durations: [Int] = []
        var weekBuckets: [Date: Int] = [:]

        for session in sessions {
            guard let finishedAt = session.finishedAt else { continue }

            let seconds = Int(finishedAt.timeIntervalSince(session.startedAt))
            if seconds > 0, seconds < 4 * 60 * 60 { durations.append(seconds / 60) }

            let week = WeeklyReview.startOfWeek(containing: finishedAt, calendar: calendar)
            weekBuckets[week, default: 0] += 1

            for performed in session.exercises {
                guard performed.sets.contains(where: { $0.done && !$0.isWarmup }) else { continue }
                exerciseCounts[performed.exerciseId, default: 0] += 1
                guard let exercise = appState.exercises.first(where: { $0.id == performed.exerciseId })
                else { continue }
                equipment.insert(exercise.equipment.rawValue)
                if let muscle = BlueprintMuscle(appMuscle: exercise.muscle) {
                    muscleCounts[muscle.rawValue, default: 0] += 1
                }
            }
        }

        // A median, not a mean. One holiday week of zero and one heroic week of
        // six should not average into "four" — the median says what a normal
        // week looks like, which is the question being asked.
        let perWeek = weekBuckets.count >= 2 ? median(Array(weekBuckets.values)) : nil

        let frequentMuscles = muscleCounts
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(5)
            .map(\.key)

        let reliable = exerciseCounts
            .filter { $0.value >= reliableThreshold }
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(10)
            .map(\.key)

        return Digest(
            typicalSessionsPerWeek: perWeek,
            typicalDurationMinutes: durations.isEmpty ? nil : median(durations),
            frequentMuscles: Array(frequentMuscles),
            reliableExerciseIds: Array(reliable),
            avoidedExerciseIds: avoided(appState: appState, since: cutoff),
            equipmentUsed: equipment.sorted(),
            sessionsConsidered: sessions.count
        )
    }

    /// Exercises the routine keeps prescribing and the session keeps not doing.
    @MainActor
    private static func avoided(appState: AppState, since: Date) -> [String] {
        var skips: [String: Int] = [:]
        for session in appState.completedWorkouts {
            guard let finishedAt = session.finishedAt, finishedAt >= since else { continue }
            guard let routineId = session.routineId,
                  let routine = appState.routines.first(where: { $0.id == routineId }) else { continue }
            let performed = Set(
                session.exercises.filter { $0.sets.contains { $0.done } }.map(\.exerciseId)
            )
            for planned in routine.exercises where !performed.contains(planned.exerciseId) {
                skips[planned.exerciseId, default: 0] += 1
            }
        }
        return skips.filter { $0.value >= WeeklyReview.skipThreshold }.keys.sorted()
    }

    // MARK: Prompt text

    /// The digest as a sentence for the builder, or nil when there isn't one
    /// worth sending.
    ///
    /// No ids and no names — the model receives shape, the resolver holds the
    /// library. "Trains three times a week, around fifty minutes, mostly chest
    /// and back" is everything it needs and nothing it could misuse.
    nonisolated static func promptText(_ digest: Digest) -> String? {
        guard digest.isUsable else { return nil }
        var parts: [String] = []

        if let perWeek = digest.typicalSessionsPerWeek {
            parts.append("Usually trains \(perWeek) times a week.")
        }
        if let minutes = digest.typicalDurationMinutes {
            parts.append("Sessions usually run about \(minutes) minutes.")
        }
        if !digest.frequentMuscles.isEmpty {
            parts.append("Most-trained: \(digest.frequentMuscles.joined(separator: ", ")).")
        }
        if !digest.equipmentUsed.isEmpty {
            parts.append("Equipment they actually use: \(digest.equipmentUsed.joined(separator: ", ")).")
        }
        if !digest.avoidedExerciseIds.isEmpty {
            // Counted, never named. Which exercise it is doesn't change the
            // shape of the week, and the id means nothing to the model.
            parts.append("\(digest.avoidedExerciseIds.count) prescribed exercise(s) are routinely skipped.")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Helpers

    nonisolated static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}
