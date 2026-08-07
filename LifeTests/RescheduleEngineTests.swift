import Testing
import Foundation
@testable import Life

/// Missed sessions, and the options for them.
///
/// The engine is pure and holds no store, so every one of these is arithmetic
/// over a handful of planned sessions. Nothing here moves anything — that is
/// the point, and `RescheduleSheet` is the only place a date is written.
struct RescheduleEngineTests {

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    /// Thursday 13 August 2026, 15:00.
    static let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 13; components.hour = 15
        return calendar.date(from: components)!
    }()

    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    static func session(
        _ offset: Int,
        name: String = "Push",
        routineId: String? = "r1",
        completed: Bool = false
    ) -> PlannedSession {
        var session = PlannedSession(date: day(offset), routineId: routineId, routineName: name)
        session.completed = completed
        return session
    }

    // MARK: Detection

    @Test("A planned session in the past that wasn't done is missed")
    func pastAndUndoneIsMissed() {
        let missed = RescheduleEngine.missedSessions(
            planned: [Self.session(-2)], now: Self.now, calendar: Self.calendar
        )
        #expect(missed.count == 1)
    }

    @Test("A completed session is never missed")
    func completedIsNotMissed() {
        let missed = RescheduleEngine.missedSessions(
            planned: [Self.session(-2, completed: true)], now: Self.now, calendar: Self.calendar
        )
        #expect(missed.isEmpty)
    }

    @Test("Today's session hasn't been missed yet")
    func todayIsNotMissed() {
        let missed = RescheduleEngine.missedSessions(
            planned: [Self.session(0)], now: Self.now, calendar: Self.calendar
        )
        #expect(missed.isEmpty)
    }

    /// A rest day you failed to take is not a missed workout, and offering to
    /// reschedule one would be comic.
    @Test("A missed rest day is not a missed workout")
    func restDaysAreNeverMissed() {
        let rest = Self.session(-2, name: "Rest", routineId: nil)
        let missed = RescheduleEngine.missedSessions(
            planned: [rest], now: Self.now, calendar: Self.calendar
        )
        #expect(missed.isEmpty)
    }

    @Test("Missed sessions come back most recent first")
    func missedAreOrdered() {
        let missed = RescheduleEngine.missedSessions(
            planned: [Self.session(-5, name: "Old"), Self.session(-1, name: "Recent")],
            now: Self.now,
            calendar: Self.calendar
        )
        #expect(missed.first?.routineName == "Recent")
    }

    // MARK: Staleness

    @Test("A session from last month is past moving")
    func oldSessionsAreStale() {
        #expect(RescheduleEngine.isStale(Self.session(-30), now: Self.now, calendar: Self.calendar))
        #expect(!RescheduleEngine.isStale(Self.session(-2), now: Self.now, calendar: Self.calendar))
    }

    // MARK: Options

    @Test("Options always include leaving it alone")
    func skipAndKeepAreAlwaysOffered() {
        let options = RescheduleEngine.options(
            for: Self.session(-1),
            context: .init(planned: [], now: Self.now, calendar: Self.calendar)
        )
        #expect(options.contains(.skip))
        #expect(options.contains(.keep))
    }

    @Test("At most three dates are offered — a decision, not a calendar")
    func datesAreCapped() {
        let options = RescheduleEngine.options(
            for: Self.session(-1),
            context: .init(planned: [], now: Self.now, calendar: Self.calendar)
        )
        let moves = options.filter { if case .moveTo = $0 { return true } else { return false } }
        #expect(moves.count == 3)
    }

    @Test("A day that already has a session isn't offered")
    func busyDaysAreSkipped() {
        let missed = Self.session(-1)
        let today = Self.session(0, name: "Pull", routineId: "r2")

        let options = RescheduleEngine.options(
            for: missed,
            context: .init(planned: [missed, today], now: Self.now, calendar: Self.calendar)
        )

        let dates = options.compactMap { option -> Date? in
            if case .moveTo(let date, _, _) = option { return date }
            return nil
        }
        #expect(!dates.contains { Self.calendar.isDate($0, inSameDayAs: Self.now) })
    }

    /// The specific guardrail the brief asks for: two sessions hitting the same
    /// muscle group on consecutive days.
    @Test("Moving next to the same muscle group warns rather than refusing")
    func consecutiveMusclesWarn() {
        let missed = Self.session(-1, name: "Legs A", routineId: "legs-a")
        let tomorrow = Self.session(1, name: "Legs B", routineId: "legs-b")

        let options = RescheduleEngine.options(
            for: missed,
            context: .init(
                planned: [missed, tomorrow],
                musclesByRoutine: ["legs-a": [.legs, .glutes], "legs-b": [.legs]],
                now: Self.now,
                calendar: Self.calendar
            )
        )

        // Today is adjacent to tomorrow's leg session, so it carries a warning —
        // but it is still offered. The user may know something the app doesn't.
        let todayOption = options.first { option in
            if case .moveTo(let date, _, _) = option {
                return Self.calendar.isDate(date, inSameDayAs: Self.now)
            }
            return false
        }
        guard case .moveTo(_, _, let warning)? = todayOption else {
            Issue.record("expected today to be offered")
            return
        }
        #expect(warning != nil)
        #expect(warning?.lowercased().contains("legs") == true)
    }

    @Test("A day with nothing adjacent carries no warning")
    func unrelatedDaysAreClean() {
        let missed = Self.session(-1, name: "Legs", routineId: "legs")
        let options = RescheduleEngine.options(
            for: missed,
            context: .init(
                planned: [missed],
                musclesByRoutine: ["legs": [.legs]],
                now: Self.now,
                calendar: Self.calendar
            )
        )

        let warnings = options.compactMap { option -> String? in
            if case .moveTo(_, _, let warning) = option { return warning }
            return nil
        }
        #expect(warnings.isEmpty)
    }

    @Test("A routine with no known muscles produces no false warnings")
    func unknownRoutinesDontWarn() {
        let missed = Self.session(-1, routineId: "unknown")
        let neighbour = Self.session(1, name: "Something", routineId: "also-unknown")

        let options = RescheduleEngine.options(
            for: missed,
            context: .init(planned: [missed, neighbour], now: Self.now, calendar: Self.calendar)
        )

        let warnings = options.compactMap { option -> String? in
            if case .moveTo(_, _, let warning) = option { return warning }
            return nil
        }
        #expect(warnings.isEmpty)
    }
}
