import Foundation

// MARK: - Weekly Review

/// What actually happened this week, counted by the app.
///
/// The division of labour is the same one the whole feature runs on: this
/// computes, the model summarises. Every figure below is arithmetic over the
/// user's own sessions, so a review can be produced with the network off and a
/// model that contradicts one of these numbers is wrong rather than
/// interesting.
///
/// Pure except for the one entry point that reads the store.
enum WeeklyReview {

    // MARK: Metrics

    struct Metrics: Equatable, Sendable {
        var weekStart: Date
        var plannedSessions: Int
        var completedSessions: Int
        /// Sessions completed as a percentage of sessions planned.
        ///
        /// Nil rather than zero when nothing was planned. Someone who trains
        /// four times a week without ever using the planner is not at 0%
        /// adherence, and saying so would be the app inventing a failure — the
        /// same missing-versus-zero rule as everywhere else.
        var adherencePercent: Int?
        var averageDurationMinutes: Int?
        /// Working sets per muscle, in the blueprint's vocabulary.
        var setsByMuscle: [String: Int]
        /// Muscles trained well under their weekly target.
        var underTargetMuscles: [String]
        var personalRecords: Int
        /// Sessions started and never finished.
        var incompleteSessions: Int
        /// Exercises planned repeatedly and skipped repeatedly. Ids, so a
        /// proposal about one can be acted on.
        var repeatedlySkippedExerciseIds: [String]
        var sessionsLastWeek: Int

        /// Whether there is enough here to say anything at all.
        ///
        /// One session is a week that happened, not a week worth reviewing.
        /// Producing three confident recommendations from it would be the
        /// feature talking for the sake of talking.
        var isReviewable: Bool { completedSessions >= 2 || plannedSessions >= 2 }

        var sessionsChange: Int { completedSessions - sessionsLastWeek }
    }

    /// Sessions skipped this many times before it is called a pattern.
    ///
    /// Two. One skipped exercise is a bad day; the brief is explicit that a
    /// preference must never be inferred from a single action.
    static let skipThreshold = 2

    // MARK: Building

    @MainActor
    static func metrics(
        appState: AppState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Metrics {
        let weekStart = startOfWeek(containing: now, calendar: calendar)
        let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart

        let finished = appState.completedWorkouts.filter { $0.finishedAt != nil }

        let thisWeek = finished.filter { session in
            guard let at = session.finishedAt else { return false }
            return at >= weekStart && at < calendar.date(byAdding: .day, value: 7, to: weekStart)!
        }
        let lastWeek = finished.filter { session in
            guard let at = session.finishedAt else { return false }
            return at >= previousStart && at < weekStart
        }

        let plannedThisWeek = appState.plannedSessions.filter { session in
            session.date >= weekStart
                && session.date < (calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart)
                && !session.isRestDay
        }

        let planned = plannedThisWeek.count
        let completed = thisWeek.count

        var adherence: Int?
        if planned > 0 {
            adherence = min(100, Int((Double(plannedThisWeek.filter(\.completed).count) / Double(planned) * 100).rounded()))
        }

        let durations = thisWeek.compactMap { session -> Int? in
            guard let finishedAt = session.finishedAt else { return nil }
            let seconds = Int(finishedAt.timeIntervalSince(session.startedAt))
            // A session logged as eight hours is a forgotten timer, not a
            // workout. Left out rather than allowed to drag the average.
            guard seconds > 0, seconds < 4 * 60 * 60 else { return nil }
            return seconds / 60
        }
        let averageDuration = durations.isEmpty ? nil : durations.reduce(0, +) / durations.count

        return Metrics(
            weekStart: weekStart,
            plannedSessions: planned,
            completedSessions: completed,
            adherencePercent: adherence,
            averageDurationMinutes: averageDuration,
            setsByMuscle: setsByMuscle(sessions: thisWeek, appState: appState),
            underTargetMuscles: underTargetMuscles(appState: appState),
            personalRecords: personalRecordCount(in: thisWeek, appState: appState),
            incompleteSessions: incompleteCount(appState: appState, since: weekStart),
            repeatedlySkippedExerciseIds: repeatedlySkipped(appState: appState, since: previousStart),
            sessionsLastWeek: lastWeek.count
        )
    }

    // MARK: Pieces

    /// Monday-first week start, derived from the weekday component rather than
    /// from `Calendar.weekOfYear` — whose first day is Sunday in en_US and would
    /// put Sunday's session in the wrong week for everyone else.
    nonisolated static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        // Calendar weekday: 1 = Sunday. Monday-first offset:
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: startOfDay) ?? startOfDay
    }

    @MainActor
    private static func setsByMuscle(sessions: [WorkoutSession], appState: AppState) -> [String: Int] {
        var counts: [String: Int] = [:]
        for session in sessions {
            for performed in session.exercises {
                let done = performed.sets.filter { $0.done && !$0.isWarmup }.count
                guard done > 0 else { continue }
                guard let exercise = appState.exercises.first(where: { $0.id == performed.exerciseId }),
                      let muscle = BlueprintMuscle(appMuscle: exercise.muscle) else { continue }
                counts[muscle.rawValue, default: 0] += done
            }
        }
        return counts
    }

    @MainActor
    private static func underTargetMuscles(appState: AppState) -> [String] {
        var out: [String] = []
        for status in MuscleRecoveryEngine.statuses(appState: appState) {
            guard let muscle = status.blueprintMuscle else { continue }
            // Half the minimum, so this fires on real neglect rather than on a
            // week that ran one set short.
            guard status.weeklySets * 2 < status.weeklyTarget.lowerBound else { continue }
            if !out.contains(muscle.rawValue) { out.append(muscle.rawValue) }
        }
        return out.sorted()
    }

    /// A personal record is a working set heavier than anything recorded for
    /// that exercise before this week.
    @MainActor
    private static func personalRecordCount(in sessions: [WorkoutSession], appState: AppState) -> Int {
        let weekIds = Set(sessions.map(\.id))
        var bestBefore: [String: Double] = [:]
        for session in appState.completedWorkouts where !weekIds.contains(session.id) {
            for performed in session.exercises {
                let heaviest = performed.sets.filter { $0.done && !$0.isWarmup }.map(\.weight).max() ?? 0
                bestBefore[performed.exerciseId] = max(bestBefore[performed.exerciseId] ?? 0, heaviest)
            }
        }

        var records = 0
        for session in sessions {
            for performed in session.exercises {
                let heaviest = performed.sets.filter { $0.done && !$0.isWarmup }.map(\.weight).max() ?? 0
                guard heaviest > 0, heaviest > (bestBefore[performed.exerciseId] ?? 0) else { continue }
                records += 1
                bestBefore[performed.exerciseId] = heaviest
            }
        }
        return records
    }

    @MainActor
    private static func incompleteCount(appState: AppState, since: Date) -> Int {
        appState.sessions.filter { $0.finishedAt == nil && $0.startedAt >= since }.count
    }

    /// Exercises the programme keeps prescribing and the user keeps not doing.
    ///
    /// Counted against the routines they belong to, over the last fortnight, and
    /// only reported at or above `skipThreshold`. One skipped exercise is a bad
    /// day; the brief forbids reading a preference into a single action.
    @MainActor
    private static func repeatedlySkipped(appState: AppState, since: Date) -> [String] {
        var skips: [String: Int] = [:]

        for session in appState.completedWorkouts {
            guard let finishedAt = session.finishedAt, finishedAt >= since else { continue }
            guard let routineId = session.routineId,
                  let routine = appState.routines.first(where: { $0.id == routineId }) else { continue }

            let performedIds = Set(
                session.exercises
                    .filter { $0.sets.contains { $0.done } }
                    .map(\.exerciseId)
            )
            for planned in routine.exercises where !performedIds.contains(planned.exerciseId) {
                skips[planned.exerciseId, default: 0] += 1
            }
        }

        return skips
            .filter { $0.value >= skipThreshold }
            .keys
            .sorted()
    }
}
