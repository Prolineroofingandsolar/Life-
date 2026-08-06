import Foundation

// MARK: - Training Stats

/// The figures behind Train's progress row.
///
/// Two of the three didn't exist before this. `AppState.computePRs(for:)` is
/// per-exercise and walks every session it has, so counting PRs by calling it
/// once per exercise would be 187 full passes over the workout history on every
/// render. And adherence had no implementation at all.
///
/// Every figure here follows the same rule as the health snapshot: **a figure
/// that cannot be computed is absent, not zero.** Someone who has never planned
/// a session has no adherence, which is not the same as 0% adherence, and
/// showing the latter tells them they have failed at something they never
/// started.
@MainActor
enum TrainingStats {

    /// One number for the progress row, with the state that decides how it is
    /// drawn.
    struct Figure: Equatable {
        var value: String?
        var label: String
        /// Nil when there is a real figure. Otherwise why there isn't.
        var absenceReason: String?

        var hasValue: Bool { value != nil }
    }

    struct Summary: Equatable {
        var workouts: Figure
        var personalRecords: Figure
        var adherence: Figure
        /// Weekly workout counts, oldest first, for the sparkline.
        var trend: [Int]
    }

    /// The window every figure is measured over.
    ///
    /// A calendar month rather than a rolling 30 days: people think in months,
    /// and "12 workouts" meaning "since the 1st" is a sentence anyone can check
    /// against their own memory.
    static func summary(appState: AppState, now: Date = Date(), calendar: Calendar = .current) -> Summary {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
            ?? calendar.startOfDay(for: now)

        return Summary(
            workouts: workoutsFigure(appState: appState, since: start),
            personalRecords: personalRecordsFigure(appState: appState, since: start),
            adherence: adherenceFigure(appState: appState, since: start, now: now, calendar: calendar),
            trend: appState.weeklyWorkoutCounts(weeks: 8).map(\.count)
        )
    }

    // MARK: Workouts

    static func workoutsFigure(appState: AppState, since start: Date) -> Figure {
        let count = appState.completedWorkouts.reduce(into: 0) { total, session in
            guard let finished = session.finishedAt, finished >= start else { return }
            total += 1
        }
        // Zero is a real answer here — the month genuinely contains no workouts,
        // and there is no ambiguity about whether it could be measured.
        return Figure(value: "\(count)", label: count == 1 ? "workout" : "workouts", absenceReason: nil)
    }

    // MARK: Personal records

    /// How many personal bests were set this month.
    ///
    /// Computed in **one pass** over the history rather than by asking
    /// `computePRs` per exercise. The rule is deliberately strict: a PR is a
    /// completed working set whose estimated one-rep max beats everything
    /// recorded for that exercise *before* it. Beating your own warm-up is not a
    /// personal record, and neither is the first time you ever do a movement.
    static func personalRecordsFigure(appState: AppState, since start: Date) -> Figure {
        let sessions = appState.completedWorkouts
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }

        var bestByExercise: [String: Double] = [:]
        var recordsThisPeriod = 0
        var hadPriorHistory = false

        for session in sessions {
            let finished = session.finishedAt ?? .distantPast
            let isInPeriod = finished >= start
            if !isInPeriod { hadPriorHistory = true }

            for exercise in session.exercises {
                let best = exercise.sets
                    .filter { $0.done && $0.kind.countsAsWorkingSet && $0.reps > 0 && $0.weight > 0 }
                    .map { estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }
                    .max()
                guard let best else { continue }

                let previous = bestByExercise[exercise.exerciseId]
                // The first time an exercise is ever performed sets a baseline,
                // not a record. Calling it a PR would give everyone a burst of
                // them in their first week and none afterwards.
                if let previous, best > previous, isInPeriod {
                    recordsThisPeriod += 1
                }
                if best > (previous ?? 0) {
                    bestByExercise[exercise.exerciseId] = best
                }
            }
        }

        guard hadPriorHistory || recordsThisPeriod > 0 else {
            return Figure(
                value: nil, label: "PRs",
                absenceReason: "Nothing to compare against yet"
            )
        }

        return Figure(
            value: "\(recordsThisPeriod)",
            label: recordsThisPeriod == 1 ? "PR" : "PRs",
            absenceReason: nil
        )
    }

    /// Epley. Matches `AppState.computePRs`, so the two never disagree about
    /// what a good set is worth.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        weight * (1 + Double(reps) / 30)
    }

    // MARK: Adherence

    /// Sessions done against sessions expected.
    ///
    /// **The denominator is the hard part.** `PlannedSession.completed` only
    /// exists when the user explicitly planned something or applied a generated
    /// plan — so someone diligently following their active programme without
    /// ever planning a date would divide by zero, and naively that renders as
    /// 0%. Telling a consistent trainer they are at 0% adherence is worse than
    /// telling them nothing.
    ///
    /// So there are three cases, and they are kept apart:
    /// 1. Planned sessions exist → measure against those.
    /// 2. None planned, but an active programme → expand its weekdays across the
    ///    period and measure against that.
    /// 3. Neither → no figure, and say so.
    static func adherenceFigure(
        appState: AppState,
        since start: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Figure {
        let today = calendar.startOfDay(for: now)

        // Only days that have already happened can be adhered to. Counting the
        // rest of the month as missed would show everyone a falling percentage
        // that recovers on the 1st.
        let planned = appState.plannedSessions.filter { session in
            let day = calendar.startOfDay(for: session.date)
            return day >= start && day <= today
        }

        if !planned.isEmpty {
            let done = planned.filter(\.completed).count
            return percentageFigure(done: done, expected: planned.count)
        }

        if let program = appState.activeProgram, !program.days.isEmpty {
            let expected = expectedSessions(
                from: program, between: start, and: today, calendar: calendar
            )
            guard expected > 0 else {
                return Figure(value: nil, label: "adherence", absenceReason: "Programme only just started")
            }
            let done = appState.completedWorkouts.reduce(into: 0) { total, session in
                guard let finished = session.finishedAt else { return }
                let day = calendar.startOfDay(for: finished)
                if day >= start && day <= today { total += 1 }
            }
            return percentageFigure(done: min(done, expected), expected: expected)
        }

        return Figure(
            value: nil, label: "adherence",
            absenceReason: "No programme yet"
        )
    }

    private static func percentageFigure(done: Int, expected: Int) -> Figure {
        guard expected > 0 else {
            return Figure(value: nil, label: "adherence", absenceReason: "Nothing scheduled yet")
        }
        let percent = Int((Double(done) / Double(expected) * 100).rounded())
        return Figure(value: "\(percent)%", label: "adherence", absenceReason: nil)
    }

    /// How many sessions a programme expected between two dates.
    ///
    /// Counts each calendar day in range whose weekday the programme trains.
    /// Monday is 1, matching `ProgramDay.weekday` and `todaysSuggestedRoutine`.
    static func expectedSessions(
        from program: WorkoutProgram,
        between start: Date,
        and end: Date,
        calendar: Calendar = .current
    ) -> Int {
        let trainingWeekdays = Set(program.days.compactMap { $0.routineId == nil ? nil : $0.weekday })
        guard !trainingWeekdays.isEmpty else { return 0 }

        var count = 0
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)

        // Walked a day at a time rather than divided. A month is not a whole
        // number of weeks, and the arithmetic version is wrong at both ends.
        while day <= last {
            // weekday is 1=Sunday…7=Saturday; ProgramDay is 1=Monday.
            let mondayBased = (calendar.component(.weekday, from: day) + 5) % 7 + 1
            if trainingWeekdays.contains(mondayBased) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    // MARK: Programme progress

    /// Where the user is in this week of their active programme.
    struct ProgrammeProgress: Equatable {
        var name: String
        var completedThisWeek: Int
        var plannedThisWeek: Int
        /// The next two sessions, as "Thu Legs" strings.
        var upcoming: [String]
    }

    static func programmeProgress(
        appState: AppState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgrammeProgress? {
        guard let program = appState.activeProgram, !program.days.isEmpty else { return nil }

        guard let weekStart = WorkoutBuilderActions.startOfWeek(containing: now, calendar: calendar),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return nil }

        let trainingDays = program.days.filter { $0.routineId != nil }

        let completed = appState.completedWorkouts.reduce(into: 0) { total, session in
            guard let finished = session.finishedAt else { return }
            if finished >= weekStart && finished < weekEnd { total += 1 }
        }

        let todayWeekday = (calendar.component(.weekday, from: now) + 5) % 7 + 1
        let upcoming = trainingDays
            .filter { $0.weekday > todayWeekday }
            .sorted { $0.weekday < $1.weekday }
            .prefix(2)
            .map { day -> String in
                let name = day.label.isEmpty
                    ? (appState.routines.first { $0.id == day.routineId }?.name ?? "Session")
                    : day.label
                return "\(shortWeekday(day.weekday)) \(name)"
            }

        return ProgrammeProgress(
            name: program.name,
            completedThisWeek: min(completed, trainingDays.count),
            plannedThisWeek: trainingDays.count,
            upcoming: Array(upcoming)
        )
    }

    private static func shortWeekday(_ weekday: Int) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard (1...7).contains(weekday) else { return "" }
        return names[weekday - 1]
    }
}
