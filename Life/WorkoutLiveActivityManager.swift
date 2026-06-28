import Foundation
import ActivityKit

/// Wraps ActivityKit lifecycle for the active-workout Live Activity.
@available(iOS 16.2, *)
final class WorkoutLiveActivityManager {
    static let shared = WorkoutLiveActivityManager()
    private init() {}

    private var activity: Activity<WorkoutActivityAttributes>?

    /// Begin a Live Activity for a workout. No-op if one is already running
    /// or if the user has Live Activities disabled.
    func start(workoutName: String, startedAt: Date, setsCompleted: Int = 0) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }

        let attributes = WorkoutActivityAttributes(workoutName: workoutName, startedAt: startedAt)
        let state = WorkoutActivityAttributes.ContentState(restEndsAt: nil, setsCompleted: setsCompleted)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    /// Push a new state (rest countdown and/or sets-completed change).
    func update(restEndsAt: Date?, setsCompleted: Int) {
        guard let activity else { return }
        let state = WorkoutActivityAttributes.ContentState(restEndsAt: restEndsAt, setsCompleted: setsCompleted)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    /// End and dismiss the Live Activity.
    func end() {
        guard let activity else { return }
        let finalState = activity.content.state
        Task { await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
