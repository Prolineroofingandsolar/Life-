import Foundation
import ActivityKit

// Shared between the app target and the LifeTasksWidget extension.
// IMPORTANT: this file's Target Membership must include BOTH "Life" and
// "LifeTasksWidget" so the ActivityAttributes type matches across processes.
struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the current rest period ends; nil when not resting.
        var restEndsAt: Date?
        /// Number of sets marked done so far.
        var setsCompleted: Int
    }

    /// Display name of the workout (fixed for the life of the activity).
    var workoutName: String
    /// When the workout started — used to drive the live elapsed timer.
    var startedAt: Date
}
