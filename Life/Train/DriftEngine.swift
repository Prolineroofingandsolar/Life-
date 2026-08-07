import Foundation

// MARK: - Drift Engine

/// When the programme on paper stops describing the training being done.
///
/// Five patterns, each behind the same evidence rule: **three occurrences across
/// at least three distinct weeks**. That threshold is the feature. Without it
/// this becomes an app that notices you skipped Tuesday and offers to redesign
/// your life around it, which is both wrong and exhausting — the brief is
/// explicit that a lasting preference is never inferred from one or two events.
///
/// Every signal carries its own evidence, in the user's terms, and the evidence
/// is shown rather than summarised away. "You've trained three days a week for
/// the last four weeks on a four-day programme" is checkable; "your programme
/// isn't working" is an opinion.
///
/// Pure. The one entry point that reads the store is `@MainActor`; everything
/// else takes plain values.
enum DriftEngine {

    // MARK: Signals

    enum Signal: Equatable, Sendable, Identifiable {
        /// Planned N days a week, trains M — consistently.
        case trainsFewerDays(planned: Int, actual: Int, weeks: Int)
        /// Prescribed and not done, repeatedly.
        case skipsExercise(exerciseId: String, name: String?, times: Int)
        /// The programme says barbell; the sessions say dumbbell.
        case substitutesEquipment(from: ExerciseEquipment, to: ExerciseEquipment, times: Int)
        /// A routine that consistently takes longer than it claims.
        case overrunsDuration(routineId: String, routineName: String, byMinutes: Int, times: Int)
        /// Planned for one weekday, trained on another. Weekday numbers are
        /// `Calendar`'s: 1 = Sunday.
        case prefersDifferentDay(planned: Int, actual: Int, times: Int)

        var id: String {
            switch self {
            case .trainsFewerDays(let planned, let actual, _):
                return "days-\(planned)-\(actual)"
            case .skipsExercise(let id, _, _):
                return "skip-\(id)"
            case .substitutesEquipment(let from, let to, _):
                return "kit-\(from.rawValue)-\(to.rawValue)"
            case .overrunsDuration(let id, _, _, _):
                return "time-\(id)"
            case .prefersDifferentDay(let planned, let actual, _):
                return "day-\(planned)-\(actual)"
            }
        }

        var headline: String {
            switch self {
            case .trainsFewerDays(let planned, let actual, _):
                return "You train \(actual) days, not \(planned)"
            case .skipsExercise(_, let name, _):
                return "\(name ?? "One exercise") keeps getting skipped"
            case .substitutesEquipment(let from, let to, _):
                return "\(from.label) work keeps becoming \(to.label.lowercased())"
            case .overrunsDuration(_, let name, let minutes, _):
                return "\(name) runs about \(minutes) minutes long"
            case .prefersDifferentDay:
                return "You train on a different day than planned"
            }
        }

        /// What the app saw. Shown in full — this is the part that makes the
        /// suggestion arguable rather than authoritative.
        var evidence: [String] {
            switch self {
            case .trainsFewerDays(let planned, let actual, let weeks):
                return [
                    "Programme asks for \(planned) sessions a week.",
                    "You've averaged \(actual) over \(weeks) weeks.",
                ]
            case .skipsExercise(_, let name, let times):
                return [
                    "\(name ?? "It") has been prescribed and not done \(times) times.",
                    "Across at least three separate weeks.",
                ]
            case .substitutesEquipment(let from, let to, let times):
                return [
                    "\(times) sessions swapped \(from.label.lowercased()) for \(to.label.lowercased()).",
                ]
            case .overrunsDuration(_, let name, let minutes, let times):
                return [
                    "\(name) has run over its estimate \(times) times.",
                    "By about \(minutes) minutes each time.",
                ]
            case .prefersDifferentDay(let planned, let actual, let times):
                return [
                    "Planned for \(Self.weekdayName(planned)), trained on \(Self.weekdayName(actual)).",
                    "\(times) times.",
                ]
            }
        }

        static func weekdayName(_ weekday: Int) -> String {
            let symbols = Calendar.current.weekdaySymbols
            let index = max(0, min(symbols.count - 1, weekday - 1))
            return symbols[index]
        }
    }

    // MARK: Thresholds

    /// Occurrences before a pattern is a pattern.
    static let minimumOccurrences = 3
    /// Distinct weeks those occurrences must span.
    ///
    /// Both, not either. Three skips in one bad week is a bad week; three skips
    /// across three weeks is a decision someone keeps making.
    static let minimumWeeks = 3
    /// Weeks of history considered.
    static let windowWeeks = 6
    /// Minutes over the estimate before a routine is "running long".
    static let overrunMinutes = 10

    // MARK: Detection

    @MainActor
    static func signals(
        appState: AppState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Signal] {
        let cutoff = calendar.date(byAdding: .day, value: -7 * windowWeeks, to: now) ?? now
        let sessions = appState.completedWorkouts
            .filter { ($0.finishedAt ?? .distantPast) >= cutoff }

        var out: [Signal] = []

        if let days = dayCountDrift(appState: appState, sessions: sessions, now: now, calendar: calendar) {
            out.append(days)
        }
        out.append(contentsOf: skippedExercises(appState: appState, sessions: sessions, calendar: calendar))
        if let kit = equipmentDrift(appState: appState, sessions: sessions) {
            out.append(kit)
        }
        out.append(contentsOf: overruns(appState: appState, sessions: sessions, calendar: calendar))
        if let day = weekdayDrift(appState: appState, sessions: sessions, calendar: calendar) {
            out.append(day)
        }

        return out
    }

    // MARK: Days per week

    @MainActor
    private static func dayCountDrift(
        appState: AppState,
        sessions: [WorkoutSession],
        now: Date,
        calendar: Calendar
    ) -> Signal? {
        guard let programme = appState.activeProgram else { return nil }
        let planned = programme.days.filter { $0.routineId != nil }.count
        guard planned >= 2 else { return nil }

        var weeks: [Date: Int] = [:]
        for session in sessions {
            guard let finishedAt = session.finishedAt else { continue }
            weeks[WeeklyReview.startOfWeek(containing: finishedAt, calendar: calendar), default: 0] += 1
        }

        // The current week is still being lived. Counting it would report every
        // Monday as a collapse in training frequency.
        let thisWeek = WeeklyReview.startOfWeek(containing: now, calendar: calendar)
        weeks.removeValue(forKey: thisWeek)

        guard weeks.count >= minimumWeeks else { return nil }
        guard let actual = TrainingHistoryDigest.median(Array(weeks.values)) else { return nil }

        // One session short is a normal week. Two is a different programme.
        guard planned - actual >= 2 else { return nil }
        return .trainsFewerDays(planned: planned, actual: actual, weeks: weeks.count)
    }

    // MARK: Skipped exercises

    @MainActor
    private static func skippedExercises(
        appState: AppState,
        sessions: [WorkoutSession],
        calendar: Calendar
    ) -> [Signal] {
        var counts: [String: Int] = [:]
        var weeks: [String: Set<Date>] = [:]

        for session in sessions {
            guard let finishedAt = session.finishedAt,
                  let routineId = session.routineId,
                  let routine = appState.routines.first(where: { $0.id == routineId }) else { continue }

            let performed = Set(
                session.exercises.filter { $0.sets.contains { $0.done } }.map(\.exerciseId)
            )
            let week = WeeklyReview.startOfWeek(containing: finishedAt, calendar: calendar)

            for planned in routine.exercises where !performed.contains(planned.exerciseId) {
                counts[planned.exerciseId, default: 0] += 1
                weeks[planned.exerciseId, default: []].insert(week)
            }
        }

        var out: [Signal] = []
        for (id, count) in counts.sorted(by: { $0.key < $1.key }) {
            guard count >= minimumOccurrences,
                  (weeks[id]?.count ?? 0) >= minimumWeeks else { continue }
            out.append(
                .skipsExercise(
                    exerciseId: id,
                    name: appState.exercises.first { $0.id == id }?.name,
                    times: count
                )
            )
        }
        // Two is enough to make the point. Five is a list nobody reads.
        return Array(out.prefix(2))
    }

    // MARK: Equipment

    /// The programme prescribes one thing and the sessions do another.
    ///
    /// Detected from what was *performed* against what the routine asked for,
    /// so it catches someone who has quietly moved to a home gym without ever
    /// telling the app.
    @MainActor
    private static func equipmentDrift(
        appState: AppState,
        sessions: [WorkoutSession]
    ) -> Signal? {
        var swaps: [String: Int] = [:]

        for session in sessions {
            guard let routineId = session.routineId,
                  let routine = appState.routines.first(where: { $0.id == routineId }) else { continue }

            let performedIds = Set(
                session.exercises.filter { $0.sets.contains { $0.done } }.map(\.exerciseId)
            )
            let plannedIds = Set(routine.exercises.map(\.exerciseId))

            let added = performedIds.subtracting(plannedIds)
            let missing = plannedIds.subtracting(performedIds)
            guard !added.isEmpty, !missing.isEmpty else { continue }

            let addedKit = Set(added.compactMap { id in
                appState.exercises.first { $0.id == id }?.equipment
            })
            let missingKit = Set(missing.compactMap { id in
                appState.exercises.first { $0.id == id }?.equipment
            })

            for from in missingKit.subtracting(addedKit) {
                for to in addedKit.subtracting(missingKit) {
                    swaps["\(from.rawValue)>\(to.rawValue)", default: 0] += 1
                }
            }
        }

        guard let best = swaps.filter({ $0.value >= minimumOccurrences })
            .sorted(by: { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            })
            .first else { return nil }

        let parts = best.key.components(separatedBy: ">")
        guard parts.count == 2,
              let from = ExerciseEquipment(rawValue: parts[0]),
              let to = ExerciseEquipment(rawValue: parts[1]) else { return nil }

        return .substitutesEquipment(from: from, to: to, times: best.value)
    }

    // MARK: Duration

    @MainActor
    private static func overruns(
        appState: AppState,
        sessions: [WorkoutSession],
        calendar: Calendar
    ) -> [Signal] {
        var overshoot: [String: [Int]] = [:]
        var weeks: [String: Set<Date>] = [:]

        for session in sessions {
            guard let finishedAt = session.finishedAt,
                  let routineId = session.routineId,
                  let routine = appState.routines.first(where: { $0.id == routineId }) else { continue }

            let actual = Int(finishedAt.timeIntervalSince(session.startedAt)) / 60
            // A forgotten timer is not a four-hour session, and treating it as
            // one would have the app shortening a routine that was fine.
            guard actual > 0, actual < 240 else { continue }

            let estimate = WorkoutAdjuster.estimatedMinutes(routine.exercises)
            let over = actual - estimate
            guard over >= overrunMinutes else { continue }

            overshoot[routineId, default: []].append(over)
            weeks[routineId, default: []].insert(
                WeeklyReview.startOfWeek(containing: finishedAt, calendar: calendar)
            )
        }

        var out: [Signal] = []
        for (routineId, overs) in overshoot.sorted(by: { $0.key < $1.key }) {
            guard overs.count >= minimumOccurrences,
                  (weeks[routineId]?.count ?? 0) >= minimumWeeks,
                  let typical = TrainingHistoryDigest.median(overs),
                  let routine = appState.routines.first(where: { $0.id == routineId }) else { continue }
            out.append(
                .overrunsDuration(
                    routineId: routineId,
                    routineName: routine.name,
                    byMinutes: typical,
                    times: overs.count
                )
            )
        }
        return Array(out.prefix(2))
    }

    // MARK: Weekday

    @MainActor
    private static func weekdayDrift(
        appState: AppState,
        sessions: [WorkoutSession],
        calendar: Calendar
    ) -> Signal? {
        guard let programme = appState.activeProgram else { return nil }

        // ProgramDay.weekday is 1 = Monday; Calendar's is 1 = Sunday.
        let plannedWeekdays = Set(
            programme.days
                .filter { $0.routineId != nil }
                .map { ($0.weekday % 7) + 1 }
        )
        guard !plannedWeekdays.isEmpty, plannedWeekdays.count < 7 else { return nil }

        var offDays: [Int: Int] = [:]
        var weeks: [Int: Set<Date>] = [:]

        for session in sessions {
            guard let finishedAt = session.finishedAt else { continue }
            let weekday = calendar.component(.weekday, from: finishedAt)
            guard !plannedWeekdays.contains(weekday) else { continue }
            offDays[weekday, default: 0] += 1
            weeks[weekday, default: []].insert(
                WeeklyReview.startOfWeek(containing: finishedAt, calendar: calendar)
            )
        }

        guard let best = offDays
            .filter({ $0.value >= minimumOccurrences && (weeks[$0.key]?.count ?? 0) >= minimumWeeks })
            .sorted(by: { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            })
            .first else { return nil }

        let plannedDay = plannedWeekdays.sorted().first ?? 2
        return .prefersDifferentDay(planned: plannedDay, actual: best.key, times: best.value)
    }

    // MARK: Turning drift into a brief

    /// What the builder should be told, if the user chooses to rebuild.
    ///
    /// Corrections only — the days they actually train, the things they
    /// actually skip. It never carries a goal or an opinion, because drift
    /// evidence says what someone does, not what they want.
    nonisolated static func brief(from signals: [Signal]) -> WorkoutBrief {
        var brief = WorkoutBrief()
        var notes: [String] = []

        for signal in signals {
            switch signal {
            case .trainsFewerDays(_, let actual, _):
                brief.daysPerWeek = min(max(actual, 2), 6)
            case .skipsExercise(_, let name, _):
                if let name { notes.append("Leave out \(name) — it never gets done.") }
            case .substitutesEquipment(_, let to, _):
                brief.availableEquipment.insert(to)
            case .overrunsDuration(_, _, let minutes, _):
                notes.append("Sessions have been running about \(minutes) minutes long.")
            case .prefersDifferentDay(_, let actual, _):
                notes.append("Training tends to happen on \(Signal.weekdayName(actual)).")
            }
        }

        brief.text = notes.joined(separator: " ")
        return brief
    }
}
