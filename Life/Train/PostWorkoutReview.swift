import Foundation

// MARK: - Post-Workout Review

/// One thing that went well, one thing worth noticing, and at most one thing to
/// do about it.
///
/// **No model call.** This fires after every single workout, and paying for a
/// call to rephrase four numbers the app already knows would be a running cost
/// for no gain — the figures are the content, and they are already in the user's
/// own units.
///
/// What it deliberately never says: anything about tiredness, recovery,
/// soreness or how someone felt. It has no health data in front of it, and a
/// sentence about fatigue derived from set counts would be a guess wearing a
/// coach's voice.
///
/// Pure. `session` and `previous` are passed in; nothing is read from a store.
enum PostWorkoutReview {

    struct Review: Equatable, Sendable {
        /// Always present. There is something good in every finished session,
        /// starting with the fact that it was finished.
        var success: String
        /// Nil when there genuinely isn't one. An "issue" invented to fill a
        /// slot teaches people to ignore the slot.
        var attention: String?
        /// At most one, and only when it follows from the two above.
        var nextAction: String?
    }

    struct Input: Equatable, Sendable {
        var completedSets: Int
        var plannedSets: Int
        /// Working sets recorded as incomplete or to failure.
        var failedSets: Int
        var personalBests: [String]
        var actualMinutes: Int
        var estimatedMinutes: Int
        /// Total working volume this session, and last comparable one. Nil
        /// where there is nothing to compare against — which is not zero.
        var volumeKg: Double?
        var previousVolumeKg: Double?
        var exercisesSkipped: [String]
    }

    /// How far over the estimate before it is worth mentioning.
    static let overrunMinutes = 15
    /// Proportional volume change before it counts as a real move.
    static let volumeChangeThreshold = 0.1

    // MARK: Building

    nonisolated static func review(_ input: Input) -> Review {
        Review(
            success: success(input),
            attention: attention(input),
            nextAction: nextAction(input)
        )
    }

    private nonisolated static func success(_ input: Input) -> String {
        if input.personalBests.count == 1 {
            return "Personal best on \(input.personalBests[0])."
        }
        if input.personalBests.count > 1 {
            return "\(input.personalBests.count) personal bests, including \(input.personalBests[0])."
        }
        if let volume = input.volumeKg, let previous = input.previousVolumeKg, previous > 0 {
            let change = (volume - previous) / previous
            if change >= volumeChangeThreshold {
                return "More total work than last time — up about \(Int(change * 100))%."
            }
        }
        if input.plannedSets > 0, input.completedSets >= input.plannedSets {
            return "Every set done."
        }
        return "Session logged — \(input.completedSets) sets in the book."
    }

    private nonisolated static func attention(_ input: Input) -> String? {
        if !input.exercisesSkipped.isEmpty {
            let names = input.exercisesSkipped.prefix(2).joined(separator: " and ")
            return "\(names) didn't get done."
        }
        if input.failedSets >= 3 {
            return "\(input.failedSets) sets came up short of the target reps."
        }
        if input.actualMinutes - input.estimatedMinutes >= overrunMinutes {
            return "That took about \(input.actualMinutes - input.estimatedMinutes) minutes longer than planned."
        }
        if let volume = input.volumeKg, let previous = input.previousVolumeKg, previous > 0 {
            let change = (volume - previous) / previous
            if change <= -volumeChangeThreshold {
                return "Less total work than last time, by about \(Int(abs(change) * 100))%."
            }
        }
        return nil
    }

    /// Follows from the attention line, or there isn't one.
    ///
    /// Never a health suggestion. "Get more sleep" is not something a set count
    /// can justify, and this has no sleep data in front of it.
    private nonisolated static func nextAction(_ input: Input) -> String? {
        if !input.exercisesSkipped.isEmpty {
            return "If those keep getting skipped, worth swapping them for something you'll do."
        }
        if input.failedSets >= 3 {
            return "Consider repeating these numbers next time before adding to them."
        }
        if input.actualMinutes - input.estimatedMinutes >= overrunMinutes {
            return "Adjust the session to fit the time you actually have."
        }
        return nil
    }

    // MARK: Reading a session

    /// The input, assembled from a finished session and the one before it.
    @MainActor
    static func input(
        for session: WorkoutSession,
        appState: AppState
    ) -> Input {
        let workingSets = session.exercises.flatMap { performed in
            performed.sets.filter { !$0.isWarmup }
        }
        let completed = workingSets.filter(\.done)

        let routine = session.routineId.flatMap { id in
            appState.routines.first { $0.id == id }
        }
        let plannedSets = routine?.exercises.reduce(0) { $0 + $1.defaultSets } ?? completed.count

        let performedIds = Set(
            session.exercises.filter { $0.sets.contains { $0.done } }.map(\.exerciseId)
        )
        let skipped = (routine?.exercises ?? [])
            .filter { !performedIds.contains($0.exerciseId) }
            .compactMap { item in appState.exercises.first { $0.id == item.exerciseId }?.name }

        // A personal best is a working set heavier than anything recorded for
        // that exercise in any earlier session.
        var bests: [String] = []
        for performed in session.exercises {
            let heaviest = performed.sets.filter { $0.done && !$0.isWarmup }.map(\.weight).max() ?? 0
            guard heaviest > 0 else { continue }
            let previousBest = appState.completedWorkouts
                .filter { $0.id != session.id && ($0.finishedAt ?? .distantPast) < (session.finishedAt ?? Date()) }
                .flatMap(\.exercises)
                .filter { $0.exerciseId == performed.exerciseId }
                .flatMap { $0.sets.filter { $0.done && !$0.isWarmup } }
                .map(\.weight)
                .max() ?? 0
            guard heaviest > previousBest else { continue }
            if let name = appState.exercises.first(where: { $0.id == performed.exerciseId })?.name {
                bests.append(name)
            }
        }

        let previous = appState.completedWorkouts
            .filter { $0.id != session.id && $0.routineId == session.routineId }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .first

        let actual = Int((session.finishedAt ?? Date()).timeIntervalSince(session.startedAt)) / 60

        return Input(
            completedSets: completed.count,
            plannedSets: plannedSets,
            failedSets: completed.filter(\.isFailure).count,
            personalBests: bests,
            // Guarded, because a session left running overnight would otherwise
            // report a nine-hour overrun as the thing worth noticing.
            actualMinutes: (actual > 0 && actual < 240) ? actual : 0,
            estimatedMinutes: routine.map { WorkoutAdjuster.estimatedMinutes($0.exercises) } ?? 0,
            volumeKg: session.totalVolumeKg > 0 ? session.totalVolumeKg : nil,
            previousVolumeKg: previous.map(\.totalVolumeKg),
            exercisesSkipped: skipped
        )
    }
}
