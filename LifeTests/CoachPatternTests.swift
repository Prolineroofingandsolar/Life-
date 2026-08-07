import Testing
import Foundation
@testable import Life

/// The connections the app finds between one part of someone's life and
/// another.
///
/// Mostly tests that it *doesn't* find them. A correlation over four days is
/// noise, and a model handed one will build a confident paragraph on it — the
/// thresholds are the entire safety mechanism here, so they're what gets
/// asserted.
@MainActor
struct CoachPatternTests {

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    static let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 13; components.hour = 15
        return calendar.date(from: components)!
    }()

    static func state() -> AppState {
        let state = AppState()
        state.sessions = []
        state.habits = []
        state.healthDays = [:]
        state.careDays = [:]
        state.routines = []
        state.plannedSessions = []
        return state
    }

    static func key(daysAgo: Int) -> String {
        DayKey.string(for: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, calendar: calendar)
    }

    /// A day with a night's sleep and a step count.
    static func record(
        _ state: AppState,
        daysAgo: Int,
        sleepMinutes: Int,
        steps: Int
    ) {
        let key = Self.key(daysAgo: daysAgo)
        var day = HealthDay(dayKey: key)
        day.sleepMin = sleepMinutes
        state.healthDays[key] = day

        var care = CareDay(dayKey: key)
        care.steps = steps
        state.careDays[key] = care
    }

    // MARK: Thresholds

    /// Four days each side is a fortnight with a good week in it.
    @Test("Too few days on either side produces no pattern")
    func thinDataProducesNothing() {
        let state = Self.state()
        for day in 1...4 { Self.record(state, daysAgo: day, sleepMinutes: 8 * 60, steps: 12_000) }
        for day in 5...8 { Self.record(state, daysAgo: day, sleepMinutes: 5 * 60, steps: 3_000) }

        let patterns = CoachPatterns.patterns(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(!patterns.contains { $0.key == "sleep-steps" })
    }

    @Test("A clear difference over enough days is reported, with its sample size")
    func realDifferenceIsReported() {
        let state = Self.state()
        for day in 1...8 { Self.record(state, daysAgo: day, sleepMinutes: 8 * 60, steps: 12_000) }
        for day in 9...16 { Self.record(state, daysAgo: day, sleepMinutes: 5 * 60, steps: 4_000) }

        let patterns = CoachPatterns.patterns(appState: state, now: Self.now, calendar: Self.calendar)
        guard let steps = patterns.first(where: { $0.key == "sleep-steps" }) else {
            Issue.record("expected a sleep/steps pattern")
            return
        }
        #expect(steps.samples == 16)
        #expect(steps.strength == .strong)
        #expect(steps.statement.contains("12000") || steps.statement.contains("12,000") || steps.statement.contains("11"))
    }

    /// The failure mode this file exists to prevent: reporting a 3% wobble as a
    /// finding, which a model will then explain at length.
    @Test("A difference too small to matter is not a pattern")
    func noiseIsNotAPattern() {
        let state = Self.state()
        for day in 1...8 { Self.record(state, daysAgo: day, sleepMinutes: 8 * 60, steps: 10_000) }
        for day in 9...16 { Self.record(state, daysAgo: day, sleepMinutes: 5 * 60, steps: 10_200) }

        let patterns = CoachPatterns.patterns(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(!patterns.contains { $0.key == "sleep-steps" })
    }

    @Test("An empty app produces no patterns rather than empty ones")
    func emptyStateIsSilent() {
        #expect(CoachPatterns.patterns(appState: Self.state(), now: Self.now, calendar: Self.calendar).isEmpty)
    }

    @Test("At most four patterns are ever sent")
    func patternsAreCapped() {
        let state = Self.state()
        for day in 1...20 { Self.record(state, daysAgo: day, sleepMinutes: day % 2 == 0 ? 8 * 60 : 5 * 60, steps: day % 2 == 0 ? 14_000 : 3_000) }

        let patterns = CoachPatterns.patterns(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(patterns.count <= CoachPatterns.maximum)
    }

    /// Every statement describes the record. None of them claims a cause — the
    /// app has no idea why, and neither does the model it hands these to.
    @Test("Statements describe the record and never claim causation")
    func statementsAreNotCausal() {
        let state = Self.state()
        for day in 1...8 { Self.record(state, daysAgo: day, sleepMinutes: 8 * 60, steps: 13_000) }
        for day in 9...16 { Self.record(state, daysAgo: day, sleepMinutes: 5 * 60, steps: 4_000) }

        for pattern in CoachPatterns.patterns(appState: state, now: Self.now, calendar: Self.calendar) {
            let text = pattern.statement.lowercased()
            for word in ["because", "causes", "caused", "due to", "leads to", "makes you"] {
                #expect(!text.contains(word), "\(pattern.key): \(pattern.statement)")
            }
        }
    }
}

// MARK: - The widened context

/// What the coach can now see, and the ceiling it has to fit inside.
@MainActor
struct WidenedContextTests {

    @Test("Weight is sent as movement, and two readings is flagged as thin")
    func bodyNeedsHistory() {
        let state = CoachPatternTests.state()
        state.weightEntries = [
            WeightEntry(date: Date().addingTimeInterval(-40 * 86_400), valueKg: 84),
            WeightEntry(date: Date(), valueKg: 82),
        ]

        let body = CoachContextBuilder.build(appState: state).body
        #expect(body?.weightKg == 82)
        #expect(body?.changeOver30DaysKg == -2)
        // Two weigh-ins is a pair of numbers, not a trend.
        #expect(body?.state == .insufficientHistory)
    }

    @Test("With no weigh-ins there is no body section at all")
    func noWeighInsNoBody() {
        #expect(CoachContextBuilder.build(appState: CoachPatternTests.state()).body == nil)
    }

    /// "Four glasses" means nothing until you know whether they normally drink
    /// three or ten.
    @Test("Hydration is sent against their own usual")
    func hydrationIsRelative() {
        let state = CoachPatternTests.state()
        for day in 0...10 {
            let key = CoachPatternTests.key(daysAgo: day)
            var care = CareDay(dayKey: key)
            care.waterGlasses = day == 0 ? 2 : 8
            state.careDays[key] = care
        }

        let hydration = CoachContextBuilder.build(
            appState: state, now: CoachPatternTests.now, calendar: CoachPatternTests.calendar
        ).hydration
        #expect(hydration?.glassesToday == 2)
        #expect(hydration?.typicalGlasses == 8)
    }

    @Test("Trends need a few days before they say anything")
    func trendsNeedDays() {
        let state = CoachPatternTests.state()
        CoachPatternTests.record(state, daysAgo: 1, sleepMinutes: 7 * 60, steps: 9_000)

        let trends = CoachContextBuilder.build(
            appState: state, now: CoachPatternTests.now, calendar: CoachPatternTests.calendar
        ).trends
        #expect(trends == nil)
    }

    @Test("A week below the month's average reads as falling")
    func directionIsNamed() {
        let state = CoachPatternTests.state()
        for day in 1...7 { CoachPatternTests.record(state, daysAgo: day, sleepMinutes: 5 * 60, steps: 5_000) }
        for day in 8...28 { CoachPatternTests.record(state, daysAgo: day, sleepMinutes: 8 * 60, steps: 11_000) }

        let trends = CoachContextBuilder.build(
            appState: state, now: CoachPatternTests.now, calendar: CoachPatternTests.calendar
        ).trends
        #expect(trends?.sleepDirection == .falling)
        #expect(trends?.stepsDirection == .falling)
        #expect(trends?.sleepMinutes7Day == 300)
        #expect(trends?.sleepMinutes28Day ?? 0 > 300)
    }

    /// 23:40 and 00:20 are forty minutes apart, not twenty-three hours.
    /// Averaging them naively puts someone's typical bedtime at lunchtime.
    @Test("Bedtimes either side of midnight average to a bedtime")
    func bedtimeCrossesMidnightSafely() {
        let state = CoachPatternTests.state()
        for day in 1...10 {
            let key = CoachPatternTests.key(daysAgo: day)
            var health = HealthDay(dayKey: key)
            health.sleepMin = 7 * 60
            let hour = day % 2 == 0 ? 23 : 0
            let minute = day % 2 == 0 ? 40 : 20
            health.bedtime = CoachPatternTests.calendar.date(
                bySettingHour: hour, minute: minute, second: 0,
                of: CoachPatternTests.calendar.date(byAdding: .day, value: -day, to: CoachPatternTests.now)!
            )
            state.healthDays[key] = health
        }

        let trends = CoachContextBuilder.build(
            appState: state, now: CoachPatternTests.now, calendar: CoachPatternTests.calendar
        ).trends
        let bedtime = trends?.typicalBedtimeMinutes ?? 0
        // Somewhere near midnight, not near noon.
        #expect(bedtime >= 23 * 60 || bedtime <= 60)
    }

    /// The context has a 12,000-byte ceiling server-side. Widening it is only
    /// safe if a busy account still fits.
    @Test("A full context stays well inside the size limit")
    func contextFitsTheCeiling() throws {
        let state = CoachPatternTests.state()
        for day in 1...28 {
            CoachPatternTests.record(state, daysAgo: day, sleepMinutes: 7 * 60, steps: 9_000)
        }
        state.weightEntries = (0..<20).map {
            WeightEntry(date: Date().addingTimeInterval(-Double($0) * 5 * 86_400), valueKg: 84 - Double($0) * 0.1)
        }

        let context = CoachContextBuilder.build(
            appState: state, permissions: .all,
            now: CoachPatternTests.now, calendar: CoachPatternTests.calendar
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(context).count

        #expect(bytes < 12_000)
    }

    /// Health off means health off — the new sections follow the same switch as
    /// the figures they're derived from.
    @Test("Trends, body and patterns respect the health permission")
    func newSectionsFollowPermissions() {
        let state = CoachPatternTests.state()
        for day in 1...20 { CoachPatternTests.record(state, daysAgo: day, sleepMinutes: 7 * 60, steps: 9_000) }
        state.weightEntries = [WeightEntry(date: Date(), valueKg: 82)]

        var permissions = CoachContextBuilder.Permissions()
        permissions.health = false

        let context = CoachContextBuilder.build(
            appState: state, permissions: permissions,
            now: CoachPatternTests.now, calendar: CoachPatternTests.calendar
        )
        #expect(context.trends == nil)
        #expect(context.body == nil)
        #expect(context.patterns.isEmpty)
    }
}
