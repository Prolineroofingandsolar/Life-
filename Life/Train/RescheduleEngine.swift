import Foundation

// MARK: - Reschedule Engine

/// A session was planned for Tuesday and Tuesday has gone.
///
/// Detection is arithmetic: a planned session, in the past, not completed. The
/// options are generated here against the days that remain and the sessions
/// already on them. **Nothing moves on its own** — the engine produces choices
/// and the user picks one, which is the difference between an app that helps
/// and an app that rearranges your week while you're asleep.
///
/// Pure and `nonisolated` throughout.
enum RescheduleEngine {

    // MARK: Detection

    /// Planned, in the past, not done.
    ///
    /// Rest days are excluded — a rest day you failed to take is not a missed
    /// workout, and offering to reschedule one would be comic.
    nonisolated static func missedSessions(
        planned: [PlannedSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlannedSession] {
        let today = calendar.startOfDay(for: now)
        return planned
            .filter { !$0.completed && !$0.isRestDay && calendar.startOfDay(for: $0.date) < today }
            .sorted { $0.date > $1.date }
    }

    /// How far back a missed session is still worth moving.
    ///
    /// Eight days. Beyond that the week it belonged to is over, and moving it
    /// forward is not rescheduling — it is adding a session to a week that
    /// didn't ask for one.
    static let staleAfterDays = 8

    nonisolated static func isStale(
        _ session: PlannedSession,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: session.date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days > staleAfterDays
    }

    // MARK: Options

    enum Option: Equatable, Sendable, Identifiable {
        /// Put it on this date. The note explains the trade-off.
        case moveTo(date: Date, note: String, warning: String?)
        /// Leave it where it was and carry on with the week as planned.
        case skip
        /// Change nothing at all — the plan is right, the week wasn't.
        case keep

        var id: String {
            switch self {
            case .moveTo(let date, _, _): return "move-\(date.timeIntervalSince1970)"
            case .skip:                   return "skip"
            case .keep:                   return "keep"
            }
        }
    }

    struct Context: Sendable {
        /// Every planned session, so a proposed day isn't already busy.
        var planned: [PlannedSession]
        /// Routine id → the blueprint muscles it trains, for the consecutive-day
        /// guardrail.
        var musclesByRoutine: [String: Set<BlueprintMuscle>]
        var now: Date
        var calendar: Calendar

        init(
            planned: [PlannedSession],
            musclesByRoutine: [String: Set<BlueprintMuscle>] = [:],
            now: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.planned = planned
            self.musclesByRoutine = musclesByRoutine
            self.now = now
            self.calendar = calendar
        }
    }

    /// How many days ahead to look for a slot.
    static let searchDays = 7

    /// Muscles shared with an adjacent day before it counts as a clash.
    ///
    /// One. Two big sessions hitting the same muscle group on consecutive days
    /// is the specific thing the brief asks to avoid, and one overlapping group
    /// is enough to say so — quietly, as a warning on an option the user may
    /// still choose.
    static let clashThreshold = 1

    nonisolated static func options(for missed: PlannedSession, context: Context) -> [Option] {
        var options: [Option] = []
        let calendar = context.calendar
        let today = calendar.startOfDay(for: context.now)

        let missedMuscles = missed.routineId.flatMap { context.musclesByRoutine[$0] } ?? []

        for offset in 0..<searchDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }

            // A day that already has a session is not free. Doubling up is a
            // worse answer than moving to Thursday.
            let busy = context.planned.contains { session in
                !session.completed
                    && !session.isRestDay
                    && session.id != missed.id
                    && calendar.isDate(session.date, inSameDayAs: day)
            }
            if busy { continue }

            let warning = clashWarning(
                on: day,
                muscles: missedMuscles,
                context: context
            )

            options.append(
                .moveTo(
                    date: day,
                    note: note(for: offset, day: day, calendar: calendar),
                    warning: warning
                )
            )

            // Three concrete dates is a decision. Seven is a calendar.
            if options.count >= 3 { break }
        }

        options.append(.skip)
        options.append(.keep)
        return options
    }

    // MARK: Guardrails

    /// Whether moving here would put the same muscles on back-to-back days.
    private nonisolated static func clashWarning(
        on day: Date,
        muscles: Set<BlueprintMuscle>,
        context: Context
    ) -> String? {
        guard !muscles.isEmpty else { return nil }
        let calendar = context.calendar

        for direction in [-1, 1] {
            guard let neighbour = calendar.date(byAdding: .day, value: direction, to: day) else { continue }
            let sessions = context.planned.filter {
                !$0.isRestDay && calendar.isDate($0.date, inSameDayAs: neighbour)
            }
            for session in sessions {
                guard let routineId = session.routineId,
                      let neighbourMuscles = context.musclesByRoutine[routineId] else { continue }
                let shared = muscles.intersection(neighbourMuscles)
                guard shared.count >= clashThreshold else { continue }
                let names = shared.map(\.rawValue).sorted().joined(separator: " and ")
                return "Trains \(names.lowercased()) the day \(direction < 0 ? "after" : "before") \(session.routineName)."
            }
        }
        return nil
    }

    private nonisolated static func note(for offset: Int, day: Date, calendar: Calendar) -> String {
        switch offset {
        case 0:  return "Today"
        case 1:  return "Tomorrow"
        default:
            let weekday = calendar.component(.weekday, from: day)
            return calendar.weekdaySymbols[max(0, weekday - 1)]
        }
    }
}
