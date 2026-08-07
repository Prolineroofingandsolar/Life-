import Foundation

// MARK: - Volume Guardrails

/// Programme-quality warnings, calculated rather than opined.
///
/// These are **not medical limits** and are worded so they cannot be mistaken
/// for any. The app does not know what anyone's body can take; it knows what
/// their last four weeks looked like and what a programme prescribes, and the
/// gap between those two is a fact worth showing.
///
/// Gemini may explain one of these in a weekly review. It cannot clear one, and
/// there is no path by which a model response removes a warning — they are
/// computed from the data at render time.
///
/// Pure. Every threshold is a named constant so a warning can be argued with.
enum VolumeGuardrails {

    // MARK: Warnings

    enum Warning: Equatable, Sendable, Identifiable {
        /// Weekly sets for a muscle far above the recent norm.
        case suddenIncrease(muscle: String, from: Int, to: Int)
        /// A muscle getting well under its weekly target.
        case underTarget(muscle: String, sets: Int, target: Int)
        /// The same muscle worked hard on consecutive days.
        case backToBack(muscle: String)
        /// A programme edit that changes the week substantially.
        case largeProgrammeChange(from: Int, to: Int)
        /// Volume contradicting what the person said they wanted.
        case focusMismatch(focus: String, sets: Int)

        var id: String {
            switch self {
            case .suddenIncrease(let muscle, _, _):  return "jump-\(muscle)"
            case .underTarget(let muscle, _, _):     return "low-\(muscle)"
            case .backToBack(let muscle):            return "adjacent-\(muscle)"
            case .largeProgrammeChange:              return "change"
            case .focusMismatch(let focus, _):       return "focus-\(focus)"
            }
        }

        /// Deliberately descriptive rather than prescriptive. "Worth knowing"
        /// is the register; "dangerous" is not a claim this app can make.
        var text: String {
            switch self {
            case .suddenIncrease(let muscle, let from, let to):
                return "\(muscle) goes from about \(from) sets a week to \(to). A jump that size is usually worth easing into."
            case .underTarget(let muscle, let sets, let target):
                return "\(muscle) gets \(sets) sets a week against a target of \(target)."
            case .backToBack(let muscle):
                return "\(muscle) is worked hard on two days running. Fine occasionally; not usually what you'd plan."
            case .largeProgrammeChange(let from, let to):
                return "This changes your week from about \(from) working sets to \(to)."
            case .focusMismatch(let focus, let sets):
                return "You asked to focus on \(focus.lowercased()), and it gets \(sets) sets a week — less than the rest."
            }
        }

        var isSevere: Bool {
            switch self {
            case .suddenIncrease, .largeProgrammeChange: return true
            case .underTarget, .backToBack, .focusMismatch: return false
            }
        }
    }

    // MARK: Thresholds

    /// Proportional increase over the recent norm before it's called sudden.
    static let suddenIncreaseRatio = 1.6
    /// Below this fraction of the weekly minimum, a muscle is under-served.
    static let underTargetFraction = 0.5
    /// Weekly-set change before an edit counts as a different programme.
    static let programmeChangeRatio = 1.4
    /// Sets in a session before it counts as hard work for that muscle.
    static let hardSessionSets = 6
    /// Below this many weeks of history, no increase warning fires — there is
    /// no norm to be above.
    static let minimumWeeksForNorm = 2

    // MARK: Checking a proposed week

    /// Warnings for a set of routines about to become someone's week.
    ///
    /// `recentWeeklySets` is the norm to compare against, and it is passed in
    /// rather than read here so the same function serves the preview sheet, the
    /// programme screen and the tests.
    nonisolated static func check(
        proposedSets: [String: Int],
        recentWeeklySets: [String: Int],
        weeksOfHistory: Int,
        targets: [String: ClosedRange<Int>],
        focus: Set<BlueprintMuscle> = [],
        adjacentMuscles: Set<String> = []
    ) -> [Warning] {
        var warnings: [Warning] = []

        // 1. Sudden increases, but only where there's a norm to increase from.
        if weeksOfHistory >= minimumWeeksForNorm {
            for (muscle, proposed) in proposedSets.sorted(by: { $0.key < $1.key }) {
                guard let recent = recentWeeklySets[muscle], recent > 0 else { continue }
                guard Double(proposed) >= Double(recent) * suddenIncreaseRatio else { continue }
                warnings.append(.suddenIncrease(muscle: muscle, from: recent, to: proposed))
            }
        }

        // 2. Muscles well under target.
        for (muscle, target) in targets.sorted(by: { $0.key < $1.key }) {
            let sets = proposedSets[muscle] ?? 0
            guard Double(sets) < Double(target.lowerBound) * underTargetFraction else { continue }
            warnings.append(.underTarget(muscle: muscle, sets: sets, target: target.lowerBound))
        }

        // 3. Consecutive hard days.
        for muscle in adjacentMuscles.sorted() {
            warnings.append(.backToBack(muscle: muscle))
        }

        // 4. Focus contradicted by the volume actually prescribed.
        let average = proposedSets.values.isEmpty
            ? 0
            : proposedSets.values.reduce(0, +) / proposedSets.count
        for muscle in focus.sorted(by: { $0.rawValue < $1.rawValue }) {
            let sets = proposedSets[muscle.rawValue] ?? 0
            guard average > 0, sets < average else { continue }
            warnings.append(.focusMismatch(focus: muscle.rawValue, sets: sets))
        }

        return warnings
    }

    /// A single warning for an edit that reshapes the week.
    nonisolated static func changeWarning(from: Int, to: Int) -> Warning? {
        guard from > 0, to > 0 else { return nil }
        let ratio = Double(max(from, to)) / Double(min(from, to))
        guard ratio >= programmeChangeRatio else { return nil }
        return .largeProgrammeChange(from: from, to: to)
    }

    // MARK: Reading the store

    /// Weekly sets per muscle across a resolved plan, in blueprint vocabulary.
    nonisolated static func weeklySets(
        in sessions: [[RoutineExercise]],
        library: [Exercise]
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for session in sessions {
            for item in session {
                guard let exercise = library.first(where: { $0.id == item.exerciseId }),
                      let muscle = BlueprintMuscle(appMuscle: exercise.muscle) else { continue }
                counts[muscle.rawValue, default: 0] += item.defaultSets
            }
        }
        return counts
    }

    /// Muscles worked hard on two consecutive scheduled days.
    ///
    /// Takes weekday → the session on it, so the caller decides what "the week"
    /// means and this stays free of calendars.
    nonisolated static func adjacentHardMuscles(
        byWeekday: [Int: [RoutineExercise]],
        library: [Exercise]
    ) -> Set<String> {
        var hardByDay: [Int: Set<String>] = [:]

        for (weekday, items) in byWeekday {
            var counts: [String: Int] = [:]
            for item in items {
                guard let exercise = library.first(where: { $0.id == item.exerciseId }),
                      let muscle = BlueprintMuscle(appMuscle: exercise.muscle) else { continue }
                counts[muscle.rawValue, default: 0] += item.defaultSets
            }
            hardByDay[weekday] = Set(counts.filter { $0.value >= hardSessionSets }.keys)
        }

        var clashes = Set<String>()
        for (weekday, muscles) in hardByDay {
            // Wraps, because Sunday and Monday are consecutive days in a
            // repeating week even though 7 and 1 don't look adjacent.
            let next = weekday % 7 + 1
            guard let neighbour = hardByDay[next] else { continue }
            clashes.formUnion(muscles.intersection(neighbour))
        }
        return clashes
    }

    /// The recent norm, from finished sessions.
    @MainActor
    static func recentWeeklySets(
        appState: AppState,
        weeks: Int = 4,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (sets: [String: Int], weeks: Int) {
        let cutoff = calendar.date(byAdding: .day, value: -7 * weeks, to: now) ?? now
        var totals: [String: Int] = [:]
        var seenWeeks = Set<Date>()

        for session in appState.completedWorkouts {
            guard let finishedAt = session.finishedAt, finishedAt >= cutoff else { continue }
            seenWeeks.insert(WeeklyReview.startOfWeek(containing: finishedAt, calendar: calendar))
            for performed in session.exercises {
                let done = performed.sets.filter { $0.done && !$0.isWarmup }.count
                guard done > 0,
                      let exercise = appState.exercises.first(where: { $0.id == performed.exerciseId }),
                      let muscle = BlueprintMuscle(appMuscle: exercise.muscle) else { continue }
                totals[muscle.rawValue, default: 0] += done
            }
        }

        let weekCount = max(1, seenWeeks.count)
        // Per week, not the total — comparing a proposed week against a month's
        // work would warn about every programme ever written.
        return (totals.mapValues { $0 / weekCount }, seenWeeks.count)
    }
}
