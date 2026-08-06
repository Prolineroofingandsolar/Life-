import Foundation

// MARK: - Coach Actions

/// Turns a proposal into a change, having first checked it is a change worth
/// offering.
///
/// The second half of the promise `CoachProposal` makes. The model produces a
/// description of an intent; this is the only thing that acts on one, it acts
/// only when called from a tap, and it refuses anything it cannot verify
/// against the app's real data first.
///
/// Verification happens *before* the button is drawn, not after it is pressed.
/// A proposal naming a task id that doesn't exist is dropped rather than shown
/// and then failed — an offer the app can't honour is worse than no offer, and
/// a model that hallucinates an id should cost the user nothing at all.
@MainActor
enum CoachActions {

    /// The proposals worth showing, in the order the coach gave them.
    ///
    /// Anything referring to something that isn't there is discarded silently.
    /// There is nothing useful to say about it — "the coach suggested
    /// completing a task that doesn't exist" is a sentence about our problem,
    /// not the user's.
    static func usable(_ proposals: [CoachProposal], appState: AppState) -> [CoachProposal] {
        proposals.filter { isUsable($0, appState: appState) }
    }

    private static func isUsable(_ proposal: CoachProposal, appState: AppState) -> Bool {
        switch proposal.kind {
        case .addTask:
            guard let title = proposal.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return false }
            return true

        case .completeTask:
            guard let id = proposal.targetId else { return false }
            // Already-done tasks are excluded as well as missing ones: a button
            // offering to finish something finished does nothing visible and
            // reads as broken.
            return appState.tasks.contains { $0.id == id && !$0.done }

        case .addHabitLog:
            guard let id = proposal.targetId else { return false }
            return appState.habits.contains { $0.id == id && !$0.isArchived }

        case .logWater:
            return true

        case .planWorkout:
            guard let id = proposal.targetId else { return false }
            return appState.routines.contains { $0.id == id }

        case .buildWorkout:
            // Nothing to verify against — the builder resolves against the
            // library at the moment it runs. Offered only when there is a
            // library to resolve against at all.
            return !appState.exercises.isEmpty
        }
    }

    /// What performing a proposal did.
    ///
    /// `perform` used to return `String?`, with nil meaning "no longer
    /// available". That worked while every proposal was a mutation with a
    /// sentence to show. `buildWorkout` is neither: it changes nothing and
    /// presents a sheet, so `nil` would have printed "that's no longer
    /// available" over a perfectly good offer, and a non-nil string would have
    /// claimed a change that hadn't happened.
    ///
    /// Splitting them strengthens the invariant rather than merely fixing the
    /// message: `.opensBuilder` is a statement in the type system that the
    /// branch wrote nothing, checkable by the compiler at every call site.
    enum Effect: Equatable {
        /// A change happened. The string is what to tell the user.
        case changed(String)
        /// Nothing changed. Present the builder with this brief.
        case opensBuilder(WorkoutBrief)
        /// Valid when it was offered, gone by the time it was tapped.
        case unavailable
    }

    /// Performs a proposal, returning what it did.
    ///
    /// Re-checked here rather than trusted from `usable`, because those are two
    /// different moments: a task can be completed on another device between the
    /// answer arriving and the button being pressed.
    @discardableResult
    static func perform(_ proposal: CoachProposal, appState: AppState) -> Effect {
        guard isUsable(proposal, appState: appState) else { return .unavailable }

        switch proposal.kind {
        case .addTask:
            let title = (proposal.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let listId = resolvedListId(proposal.listId, appState: appState)
            let due = DueDate(rawValue: proposal.due ?? "") ?? .today
            appState.addTask(title: title, listId: listId, dueDate: due)
            return .changed("Added “\(title)” to \(listName(listId, appState: appState)).")

        case .completeTask:
            guard let id = proposal.targetId,
                  let task = appState.tasks.first(where: { $0.id == id }) else { return .unavailable }
            appState.toggleTask(id: id)
            return .changed("Marked “\(task.title)” done.")

        case .addHabitLog:
            guard let id = proposal.targetId,
                  let habit = appState.habits.first(where: { $0.id == id }) else { return .unavailable }
            appState.logHabit(id: id, count: max(1, proposal.count ?? 1))
            return .changed("Logged \(habit.name).")

        case .logWater:
            // Clamped rather than trusted. `count` comes from a model, and a
            // stray zero or a 500 would otherwise become a real edit to real
            // data — eight glasses is already a day's worth.
            let glasses = min(max(proposal.count ?? 1, 1), 8)
            for _ in 0..<glasses { appState.addWater() }
            return .changed(
                glasses == 1 ? "Logged a glass of water." : "Logged \(glasses) glasses of water."
            )

        case .planWorkout:
            guard let id = proposal.targetId,
                  let routine = appState.routines.first(where: { $0.id == id }) else { return .unavailable }
            appState.planSession(date: Date(), routineId: id, name: routine.name)
            return .changed("Planned \(routine.name) for today.")

        case .buildWorkout:
            return .opensBuilder(brief(from: proposal))
        }
    }

    /// The brief a `buildWorkout` proposal carries.
    ///
    /// Deliberately thin. The coach contributes the free text and, at most, a
    /// duration; everything else is the builder's own default, and the user is
    /// asked the same questions they would have been asked from the Train tab.
    /// A model that had confidently pre-answered "equipment: barbell" would be
    /// deciding something it was never told.
    static func brief(from proposal: CoachProposal) -> WorkoutBrief {
        var brief = WorkoutBrief()
        if let title = proposal.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            brief.text = String(title.prefix(200))
        }
        if let minutes = proposal.count {
            brief.availableMinutes = min(max(minutes, 10), 180)
        }
        return brief
    }

    // MARK: Helpers

    /// A list id the app actually has.
    ///
    /// The coach is told the list ids in its context, but "personal" is a
    /// safer landing place for a near-miss than refusing the whole proposal —
    /// the task itself is what the person asked for, and the list is a detail
    /// they can change in a tap.
    private static func resolvedListId(_ proposed: String?, appState: AppState) -> String {
        if let proposed, appState.taskLists.contains(where: { $0.id == proposed }) {
            return proposed
        }
        return appState.taskLists.first(where: { $0.id == "personal" })?.id
            ?? appState.taskLists.first?.id
            ?? "personal"
    }

    private static func listName(_ id: String, appState: AppState) -> String {
        appState.taskLists.first { $0.id == id }?.name ?? "your tasks"
    }
}
