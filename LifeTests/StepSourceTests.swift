import Testing
import Foundation
@testable import Life

/// Which tracker today's step count belongs to.
///
/// The bug these exist for: `mergeSteps` kept the higher of the stored and
/// incoming figures for today, and "higher" was evaluated without regard to
/// which device wrote the stored one. An iPhone-only 6,000 from the morning beat
/// a wrist tracker's 4,500 in the afternoon, so the number on screen was the
/// highest figure *either* source had reported — which is indistinguishable, to
/// anyone looking at it, from reading both at once.
@MainActor
struct StepSourceTests {

    static let fitbit = "Fitbit"
    static let appleHealth = "Apple Health"

    static func state() -> AppState {
        let state = AppState()
        state.careDays = [:]
        return state
    }

    // MARK: The bug

    /// The exact reported symptom.
    @Test("A lower figure from the authoritative tracker replaces a higher one from the other")
    func differentSourceOverwritesEvenWhenLower() {
        let state = Self.state()
        let today = state.todayKey

        // Morning: the phone reports 6,000.
        state.mergeSteps([today: 6_000], source: Self.appleHealth)
        #expect(state.careDays[today]?.steps == 6_000)

        // Afternoon: the wrist tracker — now the authoritative source — reports
        // 4,500. That is the answer, even though it is smaller.
        state.mergeSteps([today: 4_500], source: Self.fitbit)

        #expect(state.careDays[today]?.steps == 4_500)
        #expect(state.careDays[today]?.stepsSource == Self.fitbit)
    }

    /// The behaviour the max() was introduced for, which must survive the fix:
    /// a sync catching the source mid-import returns less than it did a minute
    /// ago, and the count must not visibly go backwards during the day.
    @Test("The same tracker reporting less mid-import doesn't move the count backwards")
    func sameSourceKeepsTheHigherFigure() {
        let state = Self.state()
        let today = state.todayKey

        state.mergeSteps([today: 8_000], source: Self.fitbit)
        state.mergeSteps([today: 6_200], source: Self.fitbit)

        #expect(state.careDays[today]?.steps == 8_000)
    }

    @Test("The same tracker reporting more moves the count up")
    func sameSourceStillRises() {
        let state = Self.state()
        let today = state.todayKey

        state.mergeSteps([today: 8_000], source: Self.fitbit)
        state.mergeSteps([today: 9_100], source: Self.fitbit)

        #expect(state.careDays[today]?.steps == 9_100)
    }

    /// Past days were always a straight overwrite so a correction can reduce
    /// them. That must hold regardless of source.
    @Test("A past day is overwritten, up or down")
    func pastDaysAreOverwritten() {
        let state = Self.state()
        let yesterday = DayKey.string(for: Date().addingTimeInterval(-86_400))

        state.mergeSteps([yesterday: 9_000], source: Self.fitbit)
        state.mergeSteps([yesterday: 7_400], source: Self.fitbit)

        #expect(state.careDays[yesterday]?.steps == 7_400)
    }

    // MARK: Upgrading

    /// Days saved before the field existed carry no source. Treating those as a
    /// rival tracker would block the first sync after upgrading from correcting
    /// them.
    @Test("A day with no recorded source is adopted rather than fought with")
    func unattributedDaysAreAdopted() {
        let state = Self.state()
        let today = state.todayKey

        // As written by a build that predates `stepsSource`.
        var day = CareDay(dayKey: today)
        day.steps = 5_000
        state.careDays[today] = day

        state.mergeSteps([today: 7_200], source: Self.fitbit)

        #expect(state.careDays[today]?.steps == 7_200)
        #expect(state.careDays[today]?.stepsSource == Self.fitbit)
    }

    /// The whole point of the field is that it survives a save.
    @Test("The source survives encoding and decoding")
    func sourceRoundTrips() throws {
        var day = CareDay(dayKey: "2026-08-13")
        day.steps = 9_000
        day.stepsSource = Self.fitbit

        let data = try JSONEncoder().encode(day)
        let decoded = try JSONDecoder().decode(CareDay.self, from: data)

        #expect(decoded.stepsSource == Self.fitbit)
        #expect(decoded.steps == 9_000)
    }

    /// A CareDay written before this field must decode, not throw — `load()`
    /// reads a decode failure as first launch and seeds defaults over real data.
    @Test("A day saved before the field existed still decodes")
    func oldDaysStillDecode() throws {
        let json = #"{"dayKey":"2026-08-13","waterGlasses":4,"meals":[],"breaksTaken":0,"steps":5000}"#
        let day = try JSONDecoder().decode(CareDay.self, from: Data(json.utf8))

        #expect(day.steps == 5_000)
        #expect(day.stepsSource == nil)
    }

    // MARK: Switching tracker

    /// Days the new tracker doesn't return would otherwise keep the old one's
    /// figures forever, with nothing on screen saying two devices are being
    /// read from.
    @Test("Switching tracker clears the other one's days")
    func switchingClearsTheOtherSource() {
        let state = Self.state()
        let today = state.todayKey
        let yesterday = DayKey.string(for: Date().addingTimeInterval(-86_400))

        state.mergeSteps([today: 6_000, yesterday: 8_000], source: Self.appleHealth)
        state.clearSteps(notFrom: Self.fitbit)

        #expect(state.careDays[today]?.steps == 0)
        #expect(state.careDays[yesterday]?.steps == 0)
        #expect(state.careDays[today]?.stepsSource == nil)
    }

    @Test("Clearing leaves the current tracker's days alone")
    func clearingSparesTheActiveSource() {
        let state = Self.state()
        let today = state.todayKey

        state.mergeSteps([today: 6_000], source: Self.fitbit)
        state.clearSteps(notFrom: Self.fitbit)

        #expect(state.careDays[today]?.steps == 6_000)
    }

    /// Water and meals belong to the person, not the tracker, and a change of
    /// step source must not touch them.
    @Test("Clearing steps leaves everything else on the day intact")
    func clearingOnlyTouchesSteps() {
        let state = Self.state()
        let today = state.todayKey

        var day = CareDay(dayKey: today)
        day.waterGlasses = 5
        day.meals = ["Porridge"]
        day.steps = 6_000
        day.stepsSource = Self.appleHealth
        state.careDays[today] = day

        state.clearSteps(notFrom: Self.fitbit)

        #expect(state.careDays[today]?.waterGlasses == 5)
        #expect(state.careDays[today]?.meals == ["Porridge"])
        #expect(state.careDays[today]?.steps == 0)
    }

    // MARK: Two devices, one account

    /// `CareDay.merging` runs when two phones sync the same day. Same source is
    /// one tracker seen at two moments; different sources are two trackers, and
    /// taking the larger there silently prefers whichever was more generous.
    @Test("Merging two devices takes the larger figure from one tracker")
    func mergeKeepsHigherWithinASource() {
        var mine = CareDay(dayKey: "2026-08-13")
        mine.steps = 9_000
        mine.stepsSource = Self.fitbit

        var theirs = CareDay(dayKey: "2026-08-13")
        theirs.steps = 7_000
        theirs.stepsSource = Self.fitbit

        #expect(CareDay.merging(mine, onto: theirs).steps == 9_000)
        #expect(CareDay.merging(theirs, onto: mine).steps == 9_000)
    }

    @Test("Merging across trackers takes the incoming one, not the larger")
    func mergeAcrossSourcesPrefersIncoming() {
        var incoming = CareDay(dayKey: "2026-08-13")
        incoming.steps = 4_500
        incoming.stepsSource = Self.fitbit

        var existing = CareDay(dayKey: "2026-08-13")
        existing.steps = 6_000
        existing.stepsSource = Self.appleHealth

        let merged = CareDay.merging(incoming, onto: existing)
        #expect(merged.steps == 4_500)
        #expect(merged.stepsSource == Self.fitbit)
    }

    @Test("An unattributed incoming day doesn't wipe an attributed stored one")
    func unattributedIncomingLoses() {
        var incoming = CareDay(dayKey: "2026-08-13")
        incoming.steps = 0

        var existing = CareDay(dayKey: "2026-08-13")
        existing.steps = 8_000
        existing.stepsSource = Self.fitbit

        let merged = CareDay.merging(incoming, onto: existing)
        #expect(merged.steps == 8_000)
        #expect(merged.stepsSource == Self.fitbit)
    }
}
