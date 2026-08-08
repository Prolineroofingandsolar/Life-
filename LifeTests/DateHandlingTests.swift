import Testing
import Foundation
@testable import Life

/// Day boundaries, time zones and the calendar strip.
///
/// The bug these were written against: the simulator's system date was
/// Thursday 6 August 2026, and the Train screen highlighted Wednesday. Nothing
/// was off by 24 hours — the week strip was drawn from `Calendar.weekOfYear`,
/// which starts on Sunday under the simulator's default en_US locale, while the
/// column headers were the hardcoded string "M T W T F S S". Every date sat one
/// column away from its own name.
///
/// The rest cover the other half of the same class of fault: a day key derived
/// from a `DateFormatter` that captured the time zone once, at launch, and never
/// looked again.
@MainActor
struct DateHandlingTests {

    // MARK: Helpers

    static func calendar(_ zone: String, locale: String = "en_GB") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0,
        zone: String = "Europe/London"
    ) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return calendar(zone).date(from: components)!
    }

    // MARK: Local midnight

    @Test("Tomorrow resolves to a fixed calendar date")
    func tomorrowBecomesFixedDate() {
        let calendar = Self.calendar("Europe/London")
        let chosenOn = Self.date(2026, 8, 7, 22, 30, zone: "Europe/London")
        let fixed = DueDate.tomorrow.fixedDate(from: chosenOn, calendar: calendar)

        #expect(DayKey.string(for: fixed, calendar: calendar) == "2026-08-08")
        #expect(calendar.component(.hour, from: fixed) == 0)
    }

    @Test("The day key flips at local midnight, not at any other hour")
    func dayKeyFlipsAtLocalMidnight() {
        let london = Self.calendar("Europe/London")

        let lastSecond = Self.date(2026, 8, 6, 23, 59, zone: "Europe/London")
        let firstSecond = Self.date(2026, 8, 7, 0, 0, zone: "Europe/London")

        #expect(DayKey.string(for: lastSecond, calendar: london) == "2026-08-06")
        #expect(DayKey.string(for: firstSecond, calendar: london) == "2026-08-07")
    }

    @Test("An instant late in the local evening is not already tomorrow")
    func lateEveningIsNotTomorrow() {
        // 23:40 in London during BST is 22:40 UTC — the same instant, one day
        // apart in a zone far enough east. A key derived from a UTC formatter
        // would name the 7th while the user is plainly still living the 6th.
        let instant = Self.date(2026, 8, 6, 23, 40, zone: "Europe/London")

        #expect(DayKey.string(for: instant, calendar: Self.calendar("Europe/London")) == "2026-08-06")
        #expect(DayKey.string(for: instant, calendar: Self.calendar("Asia/Tokyo")) == "2026-08-07")
    }

    // MARK: UTC against local

    @Test("The same instant is a different day in different zones")
    func sameInstantDiffersByZone() {
        // 01:30 in London on the 6th is 20:30 in New York on the 5th.
        let instant = Self.date(2026, 8, 6, 1, 30, zone: "Europe/London")

        #expect(DayKey.string(for: instant, calendar: Self.calendar("Europe/London")) == "2026-08-06")
        #expect(DayKey.string(for: instant, calendar: Self.calendar("America/New_York")) == "2026-08-05")
    }

    @Test("A key parses back to local midnight, not to midnight UTC")
    func keysParseToLocalMidnight() {
        let newYork = Self.calendar("America/New_York")
        let parsed = DayKey.date(from: "2026-08-06", calendar: newYork)

        #expect(parsed != nil)
        // The round trip is the property that matters: parse in a zone, format
        // in the same zone, get the key back. Parsing "2026-08-06" as a UTC
        // instant and formatting it in a negative offset yields the 5th, which
        // is how a stored key decays by a day on each round trip.
        #expect(DayKey.string(for: parsed!, calendar: newYork) == "2026-08-06")
        #expect(newYork.component(.hour, from: parsed!) == 0)
    }

    // MARK: DST

    @Test("Every day of the year round-trips in zones with awkward DST rules")
    func keysRoundTripAcrossDST() {
        // Santiago and Beirut both move their clocks at midnight, so 00:00 does
        // not exist on the spring-forward date and `Calendar.date(from:)`
        // returns nil for it. Lord Howe shifts by thirty minutes. Any of the
        // three breaks a naive implementation on exactly one day a year, which
        // is the kind of bug that ships.
        for zone in ["America/Santiago", "Asia/Beirut", "Australia/Lord_Howe",
                     "Europe/London", "Pacific/Auckland"] {
            let calendar = Self.calendar(zone)
            var day = Self.date(2026, 1, 1, 12, 0, zone: zone)
            let end = Self.date(2026, 12, 31, 12, 0, zone: zone)

            while day <= end {
                let key = DayKey.string(for: day, calendar: calendar)
                let parsed = DayKey.date(from: key, calendar: calendar)
                #expect(parsed != nil, "\(zone) could not parse \(key)")
                if let parsed {
                    #expect(
                        DayKey.string(for: parsed, calendar: calendar) == key,
                        "\(zone) lost a day round-tripping \(key)"
                    )
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
    }

    @Test("End of day is the day's real last second, even when the day isn't 24 hours")
    func endOfDayHandlesShortAndLongDays() {
        // 25 October 2026: British Summer Time ends, so the local day is 25
        // hours long. Adding 86,399 seconds to the start would land at 23:00,
        // an hour short, and any "is this within today?" check using it would
        // wrongly exclude the last hour.
        let calendar = Self.calendar("Europe/London")
        let start = calendar.startOfDay(for: Self.date(2026, 10, 25, 12, 0, zone: "Europe/London"))
        let next = calendar.date(byAdding: .day, value: 1, to: start)!

        #expect(next.timeIntervalSince(start) == 25 * 3600)

        let endOfDay = Self.date(2026, 10, 25, 12, 0, zone: "Europe/London").endOfDay
        #expect(endOfDay.timeIntervalSince(next) == -1)
        #expect(DayKey.string(for: endOfDay, calendar: calendar) == "2026-10-25")
    }

    // MARK: Staying open across midnight

    @Test("Yesterday's key is still yesterday's after the day rolls over")
    func dayRolloverProducesANewKey() {
        let calendar = Self.calendar("Europe/London")
        let beforeMidnight = Self.date(2026, 8, 6, 23, 59, zone: "Europe/London")
        let afterMidnight = Self.date(2026, 8, 7, 0, 1, zone: "Europe/London")

        let yesterday = DayKey.string(for: beforeMidnight, calendar: calendar)
        let today = DayKey.string(for: afterMidnight, calendar: calendar)

        #expect(yesterday != today)
        // A snapshot built before midnight belongs to the day it was built in.
        // Reusing it after the rollover is what leaves a screen showing
        // yesterday's figures under today's heading, which is why
        // `AppState.invalidateHealthSnapshot()` runs on `NSCalendarDayChanged`.
        #expect(yesterday == "2026-08-06")
        #expect(today == "2026-08-07")
    }

    @Test("A persisted key from yesterday is recognised as not today")
    func persistedKeyFromYesterdayIsStale() {
        let calendar = Self.calendar("Europe/London")
        let now = Self.date(2026, 8, 6, 9, 0, zone: "Europe/London")
        let todayKey = DayKey.string(for: now, calendar: calendar)

        // Launching with a stored selection from the previous day must not be
        // treated as a current one. Overnight metrics are allowed one day of
        // lag; a step count is not.
        #expect(
            HealthSnapshotBuilder.state(
                forDayKey: "2026-08-05", todayKey: todayKey,
                calendar: calendar, allowedDaysBehind: 0
            ) == .stale
        )
        #expect(
            HealthSnapshotBuilder.state(
                forDayKey: "2026-08-05", todayKey: todayKey,
                calendar: calendar, allowedDaysBehind: 1
            ) == .ready
        )
        #expect(
            HealthSnapshotBuilder.state(
                forDayKey: "2026-08-03", todayKey: todayKey,
                calendar: calendar, allowedDaysBehind: 1
            ) == .stale
        )
    }

    @Test("Staleness is counted in calendar days, not in 86,400-second blocks")
    func stalenessSurvivesDST() {
        // The day the clocks go back is 25 hours long. Dividing elapsed seconds
        // by 86,400 would call a reading from that morning "more than a day
        // old" by the same evening.
        let calendar = Self.calendar("Europe/London")
        #expect(
            HealthSnapshotBuilder.state(
                forDayKey: "2026-10-25", todayKey: "2026-10-25",
                calendar: calendar, allowedDaysBehind: 0
            ) == .ready
        )
    }

    // MARK: Train's week strip

    @Test("The week strip is Monday-first whatever the device locale says")
    func weekStripIsAlwaysMondayFirst() {
        let thursday = Self.date(2026, 8, 6, 10, 0, zone: "Europe/London")

        // en_US puts Sunday first; en_GB puts Monday first. The strip's column
        // headers are the fixed string "M T W T F S S", so only one of those can
        // be right — and the whole point is that it must not depend on which.
        for locale in ["en_US", "en_GB", "ar_EG"] {
            let calendar = Self.calendar("Europe/London", locale: locale)
            let days = WorkoutCalendarCard.weekDays(containing: thursday, calendar: calendar)

            #expect(days.count == 7)
            #expect(days[0].shortDay == "Mon")
            // 6 August 2026 is a Thursday: Monday of that week is the 3rd.
            #expect(calendar.component(.day, from: days[0].date) == 3, "locale \(locale)")
            #expect(calendar.component(.day, from: days[3].date) == 6, "locale \(locale)")
        }
    }

    @Test("Every cell in the strip sits under its own weekday name")
    func weekStripLabelsMatchTheirDates() {
        let calendar = Self.calendar("Europe/London", locale: "en_US")
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        // Swept across a fortnight so the assertion holds for a week beginning
        // on any day, not just the one that happens to pass.
        for offset in 0..<14 {
            let day = calendar.date(
                byAdding: .day, value: offset,
                to: Self.date(2026, 8, 1, 10, 0, zone: "Europe/London")
            )!
            for entry in WorkoutCalendarCard.weekDays(containing: day, calendar: calendar) {
                // weekday is 1=Sunday…7=Saturday regardless of firstWeekday.
                let index = (calendar.component(.weekday, from: entry.date) + 5) % 7
                #expect(
                    entry.shortDay == names[index],
                    "\(entry.shortDay) cell held a \(names[index])"
                )
            }
        }
    }

    @Test("Today is inside the week the strip draws")
    func stripContainsToday() {
        let calendar = Self.calendar("Europe/London", locale: "en_US")
        let thursday = Self.date(2026, 8, 6, 10, 0, zone: "Europe/London")

        let days = WorkoutCalendarCard.weekDays(containing: thursday, calendar: calendar)
        let matches = days.filter { calendar.isDate($0.date, inSameDayAs: thursday) }

        // Exactly one, and it is the cell labelled Thu. The reported symptom was
        // the strip selecting Wednesday on a Thursday.
        #expect(matches.count == 1)
        #expect(days.first { calendar.isDate($0.date, inSameDayAs: thursday) }?.shortDay == "Thu")
    }

    @Test("A week containing a DST change still has seven distinct days")
    func stripSurvivesDST() {
        let calendar = Self.calendar("Europe/London", locale: "en_US")
        // 25 October 2026, the Sunday the clocks go back.
        let inThatWeek = Self.date(2026, 10, 22, 10, 0, zone: "Europe/London")

        let days = WorkoutCalendarCard.weekDays(containing: inThatWeek, calendar: calendar)
        let keys = Set(days.map { DayKey.string(for: $0.date, calendar: calendar) })

        // Adding 86,400-second multiples instead of calendar days would produce
        // two cells on the same date and skip another entirely.
        #expect(keys.count == 7)
    }
}
