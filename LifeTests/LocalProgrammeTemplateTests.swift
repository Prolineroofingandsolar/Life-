import Testing
import Foundation
@testable import Life

/// The programmes the app builds without a model.
///
/// These matter more than they look: cloud AI is off by default, so on first run
/// this *is* the programme builder for everybody. The volume assertions are the
/// point — a split that looks sensible as a list of muscle names can still
/// prescribe a third of the work a muscle needs.
struct LocalProgrammeTemplateTests {

    static func brief(
        days: Int = 3,
        minutes: Int = 45,
        goal: WorkoutBrief.Goal = .general
    ) -> WorkoutBrief {
        var brief = WorkoutBrief()
        brief.daysPerWeek = days
        brief.availableMinutes = minutes
        brief.goal = goal
        return brief
    }

    /// Weekly sets per muscle across the whole plan.
    static func weeklySets(_ plan: PlanBlueprint) -> [BlueprintMuscle: Int] {
        var byKey: [String: [WorkoutSlot]] = [:]
        for session in plan.sessions { byKey[session.key] = session.blueprint.slots }

        var out: [BlueprintMuscle: Int] = [:]
        // Counted through the schedule, not the session list: a session used
        // twice in a week is twice the volume, and one that's never scheduled
        // is none.
        for weekday in plan.weekdays {
            guard let key = weekday.sessionKey, let slots = byKey[key] else { continue }
            for slot in slots {
                out[slot.muscle, default: 0] += slot.sets
            }
        }
        return out
    }

    // MARK: The bug this file exists for

    /// A push/pull/legs week gave legs four sets. The target is about twelve.
    ///
    /// The cause was a leg day listed as `[legs, glutes, calves, core]` — one
    /// leg movement and three accessories — and legs are trained once a week in
    /// this split, so that was the entire weekly volume.
    @Test("A three-day push/pull/legs week gives legs a real amount of work")
    func pplGivesLegsEnoughVolume() throws {
        let plan = try #require(LocalProgrammeTemplates.plan(for: Self.brief(days: 3)))
        let sets = Self.weeklySets(plan)

        #expect((sets[.legs] ?? 0) >= 9)
        // And the other two days are not starved to pay for it.
        #expect((sets[.chest] ?? 0) >= 6)
        #expect((sets[.back] ?? 0) >= 6)
    }

    /// Truncation has to drop the accessories, not the main lift. A 30-minute
    /// leg day that keeps calf raises and loses squats is the same bug wearing a
    /// different hat.
    @Test("A short session keeps the primary muscle and drops the accessories")
    func shortSessionsKeepThePrimaryMuscle() throws {
        let plan = try #require(LocalProgrammeTemplates.plan(for: Self.brief(days: 3, minutes: 30)))
        let legs = try #require(plan.sessions.first { $0.key == "legs" })

        #expect(legs.blueprint.slots.count >= 4)
        let legSlots = legs.blueprint.slots.filter { $0.muscle == .legs }.count
        #expect(legSlots >= 2)
        // The first movement of a leg day is a leg movement.
        #expect(legs.blueprint.slots.first?.muscle == .legs)
    }

    @Test("Every split gives its primary muscle at least two slots")
    func everySplitLeadsWithItsPrimary() throws {
        for days in 2...6 {
            let plan = try #require(LocalProgrammeTemplates.plan(for: Self.brief(days: days)))
            for session in plan.sessions {
                let first = try #require(session.blueprint.slots.first?.muscle)
                let count = session.blueprint.slots.filter { $0.muscle == first }.count
                #expect(count >= 2, "\(session.key) on a \(days)-day plan")
            }
        }
    }

    // MARK: Shape

    @Test("The number of training days matches what was asked for")
    func dayCountIsHonoured() throws {
        for days in 2...6 {
            let plan = try #require(LocalProgrammeTemplates.plan(for: Self.brief(days: days)))
            let training = plan.weekdays.filter { $0.sessionKey != nil }
            #expect(training.count == days)
        }
    }

    @Test("Sessions are spread across the week rather than stacked")
    func sessionsAreSpread() {
        // Three days is Monday, Wednesday, Friday — not Monday, Tuesday,
        // Wednesday.
        #expect(LocalProgrammeTemplates.scheduleWeekdays(count: 3, preferred: []) == [1, 3, 5])
        #expect(LocalProgrammeTemplates.scheduleWeekdays(count: 2, preferred: []) == [1, 4])
    }

    @Test("A stated day preference is honoured")
    func preferredDaysWin() {
        #expect(LocalProgrammeTemplates.scheduleWeekdays(count: 2, preferred: [6, 7]) == [6, 7])
        // More sessions than preferred days: use them all, then fill.
        let filled = LocalProgrammeTemplates.scheduleWeekdays(count: 3, preferred: [6, 7])
        #expect(filled.count == 3)
        #expect(filled.contains(6) && filled.contains(7))
    }

    @Test("A single session fits the time budget it was given")
    func sessionFitsTheBudget() {
        let short = LocalProgrammeTemplates.session(for: Self.brief(minutes: 20))
        let long = LocalProgrammeTemplates.session(for: Self.brief(minutes: 90))

        #expect(short.slots.count < long.slots.count)
        #expect(short.slots.count >= 3)
        #expect(long.slots.count <= 8)
    }

    /// The blueprint travels the same resolver as Gemini's, so an unknown
    /// muscle here would fail in exactly the same way. Everything it emits must
    /// be in the closed vocabulary.
    @Test("Templates only ever name muscles the resolver knows")
    func templatesUseTheClosedVocabulary() throws {
        for days in 2...6 {
            let plan = try #require(LocalProgrammeTemplates.plan(for: Self.brief(days: days)))
            for session in plan.sessions {
                for slot in session.blueprint.slots {
                    #expect(BlueprintMuscle.allCases.contains(slot.muscle))
                }
            }
        }
    }
}
