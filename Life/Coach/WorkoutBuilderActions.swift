import Foundation

// MARK: - Workout Builder Actions

/// The only thing that writes a generated workout to the user's data.
///
/// The `CoachActions` of the training feature, and it keeps the same promise:
/// the model produces a description, this is the only thing that acts on one, it
/// acts only when called from a tap, and it re-checks everything against real
/// data before it does.
///
/// Verified twice, at two different moments. `WorkoutResolver` picks exercises
/// that existed when the preview was drawn; this checks they still exist when
/// the button is pressed. Those are different instants, and an exercise deleted
/// on another device in between is the case that would otherwise write a routine
/// pointing at nothing.
@MainActor
enum WorkoutBuilderActions {

    /// How many dated sessions a single commit may create.
    ///
    /// Twelve weeks of six-day training is 72 entries in the calendar, which is
    /// not a plan so much as a wall. Capped, and the count is stated in the
    /// preview before the tap.
    static let maximumPlannedSessions = 42

    // MARK: Validation

    /// Whether a draft is worth offering a button for.
    ///
    /// Checked before the confirm button is enabled, not after it is pressed.
    /// A button that fails on tap is worse than a button that isn't there.
    static func isCommittable(_ workout: WorkoutResolver.ResolvedWorkout, appState: AppState) -> Bool {
        guard workout.isViable else { return false }
        return workout.items.allSatisfy { item in
            appState.exercises.contains { $0.id == item.exercise.id }
        }
    }

    static func isCommittable(_ plan: WorkoutResolver.ResolvedPlan, appState: AppState) -> Bool {
        guard plan.isViable else { return false }
        return plan.sessions.allSatisfy { isCommittable($0.workout, appState: appState) }
    }

    // MARK: Committing

    /// Saves a single generated session as a routine.
    ///
    /// Returns what to tell the user, or nil when the draft is no longer valid —
    /// which `AskCoachView`'s proposal path already knows how to render as
    /// "that's no longer available".
    @discardableResult
    static func commit(
        _ workout: WorkoutResolver.ResolvedWorkout,
        appState: AppState
    ) -> String? {
        guard isCommittable(workout, appState: appState) else { return nil }

        appState.applyGeneratedPlan(
            routines: [routine(from: workout)],
            program: nil,
            plannedSessions: [],
            makeActive: false
        )
        return "Saved “\(workout.name)” to your routines."
    }

    /// What a plan commit will do, decided before it does any of it.
    struct PlanCommitOptions: Equatable {
        /// Defaults are set by the caller from context, not assumed here — see
        /// `WorkoutPreviewSheet`, which turns this on only when there is no
        /// active programme to displace.
        var makeActive: Bool
        /// Whether to write dated sessions as well as the weekly programme.
        var scheduleSessions: Bool
        /// The day the first week starts. Passed in rather than taken from the
        /// clock so the result is testable.
        var startingFrom: Date

        init(makeActive: Bool, scheduleSessions: Bool = true, startingFrom: Date = Date()) {
            self.makeActive = makeActive
            self.scheduleSessions = scheduleSessions
            self.startingFrom = startingFrom
        }
    }

    @discardableResult
    static func commit(
        _ plan: WorkoutResolver.ResolvedPlan,
        appState: AppState,
        options: PlanCommitOptions
    ) -> String? {
        guard isCommittable(plan, appState: appState) else { return nil }

        // Routines first, because the programme and the sessions both need
        // their ids. Built as values; nothing is appended to `appState` until
        // the single call at the end.
        var routineIdsByKey: [String: String] = [:]
        var newRoutines: [Routine] = []
        for session in plan.sessions {
            let built = routine(from: session.workout)
            routineIdsByKey[session.key] = built.id
            newRoutines.append(built)
        }

        let days: [ProgramDay] = plan.schedule
            .sorted { $0.key < $1.key }
            .compactMap { weekday, sessionKey in
                guard let routineId = routineIdsByKey[sessionKey] else { return nil }
                return ProgramDay(
                    weekday: weekday,
                    routineId: routineId,
                    label: plan.sessions.first { $0.key == sessionKey }?.workout.name ?? ""
                )
            }

        let program = WorkoutProgram(name: plan.name, days: days, isActive: false)

        let sessions = options.scheduleSessions
            ? plannedSessions(for: plan, routineIdsByKey: routineIdsByKey, options: options)
            : []

        appState.applyGeneratedPlan(
            routines: newRoutines,
            program: program,
            plannedSessions: sessions,
            makeActive: options.makeActive
        )

        var message = "Created “\(plan.name)” with \(newRoutines.count) session\(newRoutines.count == 1 ? "" : "s")."
        if !sessions.isEmpty {
            message += " Added \(sessions.count) to your calendar."
        }
        return message
    }

    // MARK: Building values

    /// A `Routine` from a resolved session.
    ///
    /// Every `exerciseId` here came from the library via `WorkoutResolver`, so
    /// there is no name resolution and nothing to invent.
    private static func routine(from workout: WorkoutResolver.ResolvedWorkout) -> Routine {
        Routine(
            name: workout.name,
            exercises: workout.items.map(\.prescription)
        )
    }

    /// Dated sessions for the weeks requested, from the next occurrence of each
    /// scheduled weekday.
    ///
    /// Starts from the coming week rather than today, so a plan created on a
    /// Thursday doesn't quietly drop Monday to Wednesday of its own first week
    /// and look like it lost sessions.
    private static func plannedSessions(
        for plan: WorkoutResolver.ResolvedPlan,
        routineIdsByKey: [String: String],
        options: PlanCommitOptions,
        calendar: Calendar = .current
    ) -> [PlannedSession] {
        guard let weekStart = startOfWeek(containing: options.startingFrom, calendar: calendar) else {
            return []
        }

        var out: [PlannedSession] = []

        for week in 0..<plan.weeks {
            for (weekday, sessionKey) in plan.schedule.sorted(by: { $0.key < $1.key }) {
                guard let routineId = routineIdsByKey[sessionKey] else { continue }
                guard let date = calendar.date(
                    byAdding: .day, value: (week * 7) + (weekday - 1), to: weekStart
                ) else { continue }

                // Days already past are skipped rather than back-dated. A
                // planned session in the past is a missed session the person
                // never had the chance to do.
                if date < calendar.startOfDay(for: options.startingFrom) { continue }

                out.append(
                    PlannedSession(
                        date: calendar.startOfDay(for: date),
                        routineId: routineId,
                        routineName: plan.sessions.first { $0.key == sessionKey }?.workout.name ?? plan.name
                    )
                )

                if out.count >= maximumPlannedSessions { return out }
            }
        }

        return out
    }

    /// The Monday of the week containing `date`.
    ///
    /// Derived from the weekday component rather than `Calendar.weekOfYear`,
    /// which starts on Sunday in en_US and would shift the whole schedule by a
    /// day for anyone on a US locale — the same bug that put Thursday under the
    /// "Wed" column on the Train calendar.
    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: startOfDay) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay)
    }
}
