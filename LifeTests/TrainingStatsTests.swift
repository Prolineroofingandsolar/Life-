import Testing
import Foundation
@testable import Life

/// The three figures on Train's progress row.
///
/// Two of them are new, and the interesting one is adherence — because its
/// denominator can legitimately be empty, and the naive answer to an empty
/// denominator is 0%. Telling someone who trains four times a week that they are
/// at 0% adherence, because they happen not to use the planner, is worse than
/// telling them nothing at all.
@MainActor
struct TrainingStatsTests {

    // MARK: Fixtures

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    /// Wednesday 12 August 2026. Mid-month and mid-week, so neither boundary is
    /// accidentally doing the work.
    static let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 12; components.hour = 18
        return calendar.date(from: components)!
    }()

    static var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
    }

    static func state() -> AppState {
        let state = AppState()
        state.sessions = []
        state.routines = []
        state.programs = []
        state.plannedSessions = []
        state.exercises = WorkoutResolverTests.library
        return state
    }

    static func session(
        daysBeforeNow days: Int,
        exerciseId: String = "ex-bench",
        weight: Double = 60,
        reps: Int = 10
    ) -> WorkoutSession {
        let finished = calendar.date(byAdding: .day, value: -days, to: now)!
        var set = LoggedSet(weight: weight, reps: reps)
        set.done = true
        var exercise = SessionExercise(exerciseId: exerciseId)
        exercise.sets = [set]
        var session = WorkoutSession(name: "Session")
        session.startedAt = finished
        session.finishedAt = finished
        session.exercises = [exercise]
        return session
    }

    // MARK: Workouts

    @Test("Workouts counts only this calendar month")
    func workoutsAreMonthScoped() {
        let state = Self.state()
        state.sessions = [
            Self.session(daysBeforeNow: 1),
            Self.session(daysBeforeNow: 5),
            // 20 days back from the 12th is late July — the previous month.
            Self.session(daysBeforeNow: 20),
        ]

        let figure = TrainingStats.workoutsFigure(appState: state, since: Self.monthStart)
        #expect(figure.value == "2")
        #expect(figure.label == "workouts")
    }

    @Test("A month with no workouts really is zero, not absent")
    func zeroWorkoutsIsAFigure() {
        let figure = TrainingStats.workoutsFigure(appState: Self.state(), since: Self.monthStart)

        // Unlike adherence, there is no ambiguity here — the month genuinely
        // contains no workouts and the number is measurable.
        #expect(figure.value == "0")
        #expect(figure.absenceReason == nil)
    }

    // MARK: Personal records

    @Test("The first time an exercise is performed is a baseline, not a record")
    func firstEverSessionIsNotAPR() {
        let state = Self.state()
        state.sessions = [Self.session(daysBeforeNow: 2, weight: 60, reps: 10)]

        // Counting it would give everyone a burst of PRs in their first week and
        // none afterwards.
        let figure = TrainingStats.personalRecordsFigure(appState: state, since: Self.monthStart)
        #expect(figure.value == "0")
    }

    @Test("Beating a previous best counts")
    func beatingAPreviousBestCounts() {
        let state = Self.state()
        state.sessions = [
            Self.session(daysBeforeNow: 40, weight: 60, reps: 10),   // last month
            Self.session(daysBeforeNow: 3, weight: 70, reps: 10),    // this month
        ]

        let figure = TrainingStats.personalRecordsFigure(appState: state, since: Self.monthStart)
        #expect(figure.value == "1")
        #expect(figure.label == "PR")
    }

    @Test("A lighter session doesn't count, and doesn't lower the best")
    func lighterSessionsAreNotRecords() {
        let state = Self.state()
        state.sessions = [
            Self.session(daysBeforeNow: 40, weight: 80, reps: 8),
            Self.session(daysBeforeNow: 3, weight: 60, reps: 8),
        ]

        let figure = TrainingStats.personalRecordsFigure(appState: state, since: Self.monthStart)
        #expect(figure.value == "0")
    }

    @Test("More reps at the same weight is a record")
    func repsCountTowardsTheEstimate() {
        let state = Self.state()
        state.sessions = [
            Self.session(daysBeforeNow: 40, weight: 60, reps: 8),
            Self.session(daysBeforeNow: 3, weight: 60, reps: 12),
        ]

        // Epley, same as AppState.computePRs — so the two never disagree about
        // what a good set is worth.
        #expect(TrainingStats.estimatedOneRepMax(weight: 60, reps: 12)
                > TrainingStats.estimatedOneRepMax(weight: 60, reps: 8))
        #expect(TrainingStats.personalRecordsFigure(appState: state, since: Self.monthStart).value == "1")
    }

    @Test("With no history at all, PRs are absent rather than zero")
    func noHistoryMeansNoPRFigure() {
        let figure = TrainingStats.personalRecordsFigure(appState: Self.state(), since: Self.monthStart)

        #expect(figure.value == nil)
        #expect(figure.absenceReason == "Nothing to compare against yet")
    }

    // MARK: Adherence — the denominator problem

    @Test("With nothing planned and no programme, adherence is absent")
    func noProgrammeMeansNoAdherence() {
        let figure = TrainingStats.adherenceFigure(
            appState: Self.state(), since: Self.monthStart,
            now: Self.now, calendar: Self.calendar
        )

        // This is the case the naive implementation renders as 0%.
        #expect(figure.value == nil)
        #expect(figure.absenceReason == "No programme yet")
    }

    @Test("Planned sessions are the denominator when they exist")
    func plannedSessionsDrivenAdherence() {
        let state = Self.state()
        for offset in [1, 3, 5, 7] {
            var planned = PlannedSession(
                date: Self.calendar.date(byAdding: .day, value: -offset, to: Self.now)!,
                routineId: nil, routineName: "Session"
            )
            planned.completed = offset != 7
            state.plannedSessions.append(planned)
        }

        let figure = TrainingStats.adherenceFigure(
            appState: state, since: Self.monthStart,
            now: Self.now, calendar: Self.calendar
        )
        #expect(figure.value == "75%")
    }

    @Test("Sessions still in the future don't count against you")
    func futureSessionsAreNotMissed() {
        let state = Self.state()
        var done = PlannedSession(
            date: Self.calendar.date(byAdding: .day, value: -1, to: Self.now)!,
            routineId: nil, routineName: "Done"
        )
        done.completed = true
        state.plannedSessions = [
            done,
            // Later this month, not yet due.
            PlannedSession(
                date: Self.calendar.date(byAdding: .day, value: 5, to: Self.now)!,
                routineId: nil, routineName: "Upcoming"
            ),
        ]

        // Counting the rest of the month as missed shows everyone a falling
        // percentage that mysteriously recovers on the 1st.
        let figure = TrainingStats.adherenceFigure(
            appState: state, since: Self.monthStart,
            now: Self.now, calendar: Self.calendar
        )
        #expect(figure.value == "100%")
    }

    @Test("An active programme supplies a denominator when nothing is planned")
    func activeProgrammeSuppliesTheDenominator() {
        let state = Self.state()
        state.routines = [Routine(id: "r1", name: "Full Body")]
        state.programs = [
            WorkoutProgram(
                name: "Three Day",
                days: [
                    ProgramDay(weekday: 1, routineId: "r1"),
                    ProgramDay(weekday: 3, routineId: "r1"),
                    ProgramDay(weekday: 5, routineId: "r1"),
                ],
                isActive: true
            )
        ]
        state.sessions = [Self.session(daysBeforeNow: 1), Self.session(daysBeforeNow: 3)]

        let figure = TrainingStats.adherenceFigure(
            appState: state, since: Self.monthStart,
            now: Self.now, calendar: Self.calendar
        )

        // Someone diligently following their programme without ever using the
        // planner now gets a real figure instead of 0%.
        #expect(figure.value != nil)
        #expect(figure.absenceReason == nil)
    }

    @Test("Adherence never exceeds 100%")
    func adherenceIsCapped() {
        let state = Self.state()
        state.routines = [Routine(id: "r1", name: "Full Body")]
        state.programs = [
            WorkoutProgram(name: "One Day", days: [ProgramDay(weekday: 1, routineId: "r1")], isActive: true)
        ]
        // Trained far more often than the programme asked for.
        state.sessions = (1...10).map { Self.session(daysBeforeNow: $0) }

        let figure = TrainingStats.adherenceFigure(
            appState: state, since: Self.monthStart,
            now: Self.now, calendar: Self.calendar
        )
        #expect(figure.value == "100%")
    }

    @Test("Expected sessions are counted a day at a time, not divided")
    func expectedSessionsWalkTheCalendar() {
        let program = WorkoutProgram(
            name: "Three Day",
            days: [
                ProgramDay(weekday: 1, routineId: "r1"),
                ProgramDay(weekday: 3, routineId: "r1"),
                ProgramDay(weekday: 5, routineId: "r1"),
            ]
        )

        // 1–12 August 2026: Mondays on the 3rd and 10th, Wednesdays on the 5th
        // and 12th, Fridays on the 7th. A month is not a whole number of weeks,
        // and the arithmetic version is wrong at both ends.
        let expected = TrainingStats.expectedSessions(
            from: program, between: Self.monthStart, and: Self.now, calendar: Self.calendar
        )
        #expect(expected == 5)
    }

    @Test("A rest day in the programme is not an expected session")
    func restDaysAreNotExpected() {
        let program = WorkoutProgram(
            name: "With rest",
            days: [
                ProgramDay(weekday: 1, routineId: "r1"),
                ProgramDay(weekday: 2, routineId: nil),   // rest
                ProgramDay(weekday: 3, routineId: "r1"),
            ]
        )

        let expected = TrainingStats.expectedSessions(
            from: program, between: Self.monthStart, and: Self.now, calendar: Self.calendar
        )
        // Mondays 3rd and 10th, Wednesdays 5th and 12th. Tuesday contributes
        // nothing.
        #expect(expected == 4)
    }

    // MARK: Programme progress

    @Test("Programme progress reports the week, not the month")
    func programmeProgressIsWeekly() {
        let state = Self.state()
        state.routines = [Routine(id: "r1", name: "Push")]
        state.programs = [
            WorkoutProgram(
                name: "Four Day",
                days: [
                    ProgramDay(weekday: 1, routineId: "r1", label: "Push"),
                    ProgramDay(weekday: 2, routineId: "r1", label: "Pull"),
                    ProgramDay(weekday: 4, routineId: "r1", label: "Legs"),
                    ProgramDay(weekday: 6, routineId: "r1", label: "Upper"),
                ],
                isActive: true
            )
        ]
        // Wednesday the 12th; Monday and Tuesday of this week are the 10th/11th.
        state.sessions = [Self.session(daysBeforeNow: 1), Self.session(daysBeforeNow: 2)]

        let progress = TrainingStats.programmeProgress(
            appState: state, now: Self.now, calendar: Self.calendar
        )

        #expect(progress?.name == "Four Day")
        #expect(progress?.plannedThisWeek == 4)
        #expect(progress?.completedThisWeek == 2)
        // Thursday and Saturday are still ahead.
        #expect(progress?.upcoming == ["Thu Legs", "Sat Upper"])
    }

    @Test("No active programme means no progress card")
    func noProgrammeNoCard() {
        #expect(TrainingStats.programmeProgress(
            appState: Self.state(), now: Self.now, calendar: Self.calendar
        ) == nil)
    }

    @Test("Completed is capped at planned, so the bar can't overfill")
    func completedIsCapped() {
        let state = Self.state()
        state.routines = [Routine(id: "r1", name: "Push")]
        state.programs = [
            WorkoutProgram(
                name: "Two Day",
                days: [ProgramDay(weekday: 1, routineId: "r1"), ProgramDay(weekday: 3, routineId: "r1")],
                isActive: true
            )
        ]
        state.sessions = (1...5).map { Self.session(daysBeforeNow: $0) }

        let progress = TrainingStats.programmeProgress(
            appState: state, now: Self.now, calendar: Self.calendar
        )
        #expect(progress?.completedThisWeek == 2)
    }

    // MARK: The summary holds together

    @Test("A fresh account produces a summary that renders without lying")
    func freshAccountSummary() {
        let summary = TrainingStats.summary(
            appState: Self.state(), now: Self.now, calendar: Self.calendar
        )

        // Workouts is a real zero; the other two are absent with reasons. Every
        // figure either has a value or explains itself — nothing renders as a
        // number it can't justify.
        #expect(summary.workouts.hasValue)
        #expect(!summary.personalRecords.hasValue)
        #expect(summary.personalRecords.absenceReason != nil)
        #expect(!summary.adherence.hasValue)
        #expect(summary.adherence.absenceReason != nil)
        #expect(summary.trend.count == 8)
    }
}
