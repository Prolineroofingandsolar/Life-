import Foundation
import ActivityKit
import os

/// Wraps ActivityKit lifecycle for the active-workout Live Activity.
@available(iOS 16.2, *)
final class WorkoutLiveActivityManager {
    static let shared = WorkoutLiveActivityManager()
    private init() {}

    private static let log = Logger(subsystem: "uk.co.prolineroofingandsolar.life", category: "LiveActivity")

    private var activity: Activity<WorkoutActivityAttributes>?

    /// Begin a Live Activity for a workout. No-op if one is already running
    /// or if the user has Live Activities disabled.
    func start(workoutName: String, startedAt: Date, setsCompleted: Int = 0) {
        print("🟢 [LiveActivity] start() called for: \(workoutName)")
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        print("🟢 [LiveActivity] areActivitiesEnabled = \(enabled)")
        guard enabled else {
            print("🔴 [LiveActivity] DISABLED — check Settings > Life > Live Activities, or Info.plist NSSupportsLiveActivities")
            return
        }
        guard activity == nil else {
            print("🟡 [LiveActivity] already running — skip")
            return
        }

        let attributes = WorkoutActivityAttributes(workoutName: workoutName, startedAt: startedAt)
        let state = WorkoutActivityAttributes.ContentState(restEndsAt: nil, setsCompleted: setsCompleted)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            print("✅ [LiveActivity] STARTED for \(workoutName) — id: \(activity?.id ?? "?")")
        } catch {
            print("🔴 [LiveActivity] Activity.request FAILED: \(error)")
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
