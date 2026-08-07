import Testing
import Foundation
@testable import Life

/// The weekly review's arithmetic, and the local review written from it.
///
/// The assertion that matters most is the one about an absent denominator.
/// Telling someone who trains four times a week that they are at 0% adherence,
/// because they happen not to use the planner, is the app inventing a failure —
/// and it is the same missing-versus-zero mistake the health snapshot was built
/// to stop.
@MainActor
struct WeeklyReviewTests {

    // MARK: Fixtures

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    /// Thursday 13 August 2026, mid-afternoon. Mid-week, so neither boundary is
    /// doing the work by accident.
    static let now: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 13; components.hour = 15
        return calendar.date(from: components)!
    }()

    static func state() -> AppState {
        let state = AppState()
        state.sessions = []
        state.routines = []
        state.programs = []
        state.plannedSessions = []
        state.exercises = [
            Exercise(name: "Bench press", muscle: "Chest", kind: .weight),
            Exercise(name: "Row", muscle: "Back", kind: .weight),
        ]
        return state
    }

    static func session(
        daysBeforeNow days: Int,
        exerciseId: String,
        weight: Double = 60,
        reps: Int = 8,
        sets: Int = 3,
        routineId: String? = nil,
        minutes: Int = 45
    ) -> WorkoutSession {
        let finished = calendar.date(byAdding: .day, value: -days, to: now)!
        var logged: [LoggedSet] = []
        for _ in 0..<sets {
            var set = LoggedSet(weight: weight, reps: reps)
            set.done = true
            logged.append(set)
        }
        var performed = SessionExercise(exerciseId: exerciseId)
        performed.sets = logged
        var session = WorkoutSession(name: "Session")
        session.startedAt = calendar.date(byAdding: .minute, value: -minutes, to: finished)!
        session.finishedAt = finished
        session.routineId = routineId
        session.exercises = [performed]
        return session
    }

    // MARK: Week boundaries

    @Test("The week starts on Monday, not Sunday")
    func weekStartsMonday() {
        let start = WeeklyReview.startOfWeek(containing: Self.now, calendar: Self.calendar)
        // Monday 10 August 2026.
        #expect(Self.calendar.component(.day, from: start) == 10)
        #expect(Self.calendar.component(.weekday, from: start) == 2)
    }

    @Test("Sunday belongs to the week that just ended")
    func sundayIsTheEndOfTheWeek() {
        let sunday = Self.calendar.date(byAdding: .day, value: 2, to: Self.now)!
        let start = WeeklyReview.startOfWeek(containing: sunday, calendar: Self.calendar)
        #expect(Self.calendar.component(.day, from: start) == 10)
    }

    // MARK: Adherence

    /// The whole point. An empty denominator is not zero per cent.
    @Test("Nothing planned means no adherence figure, not 0%")
    func adherenceIsAbsentNotZero() {
        let state = Self.state()
        let exerciseId = state.exercises[0].id
        state.sessions = [
            Self.session(daysBeforeNow: 1, exerciseId: exerciseId),
            Self.session(daysBeforeNow: 2, exerciseId: exerciseId),
        ]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)

        #expect(metrics.completedSessions == 2)
        #expect(metrics.adherencePercent == nil)
    }

    @Test("Adherence counts completed planned sessions against planned ones")
    func adherenceCounts() {
        let state = Self.state()
        let weekStart = WeeklyReview.startOfWeek(containing: Self.now, calendar: Self.calendar)

        var done = PlannedSession(date: weekStart, routineId: "r1", routineName: "Push")
        done.completed = true
        let notDone = PlannedSession(
            date: Self.calendar.date(byAdding: .day, value: 1, to: weekStart)!,
            routineId: "r1",
            routineName: "Pull"
        )
        state.plannedSessions = [done, notDone]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)

        #expect(metrics.plannedSessions == 2)
        #expect(metrics.adherencePercent == 50)
    }

    /// A rest day you failed to take is not a missed workout.
    @Test("Rest days aren't part of the adherence denominator")
    func restDaysAreExcluded() {
        let state = Self.state()
        let weekStart = WeeklyReview.startOfWeek(containing: Self.now, calendar: Self.calendar)
        state.plannedSessions = [
            PlannedSession(date: weekStart, routineId: nil, routineName: "Rest"),
        ]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)

        #expect(metrics.plannedSessions == 0)
        #expect(metrics.adherencePercent == nil)
    }

    // MARK: Figures

    @Test("Sets are counted per blueprint muscle")
    func setsAreCountedByMuscle() {
        let state = Self.state()
        state.sessions = [
            Self.session(daysBeforeNow: 1, exerciseId: state.exercises[0].id, sets: 3),
            Self.session(daysBeforeNow: 2, exerciseId: state.exercises[1].id, sets: 4),
        ]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)

        #expect(metrics.setsByMuscle["Chest"] == 3)
        #expect(metrics.setsByMuscle["Back"] == 4)
    }

    @Test("A personal best is a working set heavier than anything before it")
    func personalBestsAreCounted() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = [
            Self.session(daysBeforeNow: 20, exerciseId: id, weight: 60),
            Self.session(daysBeforeNow: 1, exerciseId: id, weight: 70),
        ]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(metrics.personalRecords == 1)
    }

    @Test("Matching last week's weight is not a personal best")
    func equallingIsNotABest() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = [
            Self.session(daysBeforeNow: 20, exerciseId: id, weight: 70),
            Self.session(daysBeforeNow: 1, exerciseId: id, weight: 70),
        ]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(metrics.personalRecords == 0)
    }

    /// A forgotten timer is not an eight-hour session.
    @Test("Implausible durations are left out of the average")
    func absurdDurationsAreIgnored() {
        let state = Self.state()
        let id = state.exercises[0].id
        var marathon = Self.session(daysBeforeNow: 1, exerciseId: id)
        marathon.startedAt = Self.calendar.date(byAdding: .hour, value: -9, to: marathon.finishedAt!)!
        state.sessions = [marathon, Self.session(daysBeforeNow: 2, exerciseId: id, minutes: 50)]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(metrics.averageDurationMinutes == 50)
    }

    // MARK: Skipped exercises

    /// One skipped exercise is a bad day. The brief forbids reading a
    /// preference into a single action.
    @Test("An exercise skipped once isn't reported as a pattern")
    func oneSkipIsNotAPattern() {
        let state = Self.state()
        let bench = state.exercises[0]
        let row = state.exercises[1]
        var routine = Routine(name: "Upper")
        routine.exercises = [
            RoutineExercise(exerciseId: bench.id),
            RoutineExercise(exerciseId: row.id),
        ]
        state.routines = [routine]
        state.sessions = [
            Self.session(daysBeforeNow: 2, exerciseId: bench.id, routineId: routine.id),
        ]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(metrics.repeatedlySkippedExerciseIds.isEmpty)
    }

    @Test("An exercise skipped twice is reported")
    func twoSkipsIsAPattern() {
        let state = Self.state()
        let bench = state.exercises[0]
        let row = state.exercises[1]
        var routine = Routine(name: "Upper")
        routine.exercises = [
            RoutineExercise(exerciseId: bench.id),
            RoutineExercise(exerciseId: row.id),
        ]
        state.routines = [routine]
        state.sessions = [
            Self.session(daysBeforeNow: 2, exerciseId: bench.id, routineId: routine.id),
            Self.session(daysBeforeNow: 4, exerciseId: bench.id, routineId: routine.id),
        ]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(metrics.repeatedlySkippedExerciseIds == [row.id])
    }

    // MARK: Reviewability

    @Test("One session is not a week worth reviewing")
    func oneSessionIsNotReviewable() {
        let state = Self.state()
        state.sessions = [Self.session(daysBeforeNow: 1, exerciseId: state.exercises[0].id)]

        let metrics = WeeklyReview.metrics(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(metrics.isReviewable == false)
    }

    // MARK: The local review

    @Test("The local review says what it doesn't know")
    func localReviewIsHonestAboutMissingAdherence() {
        let metrics = WeeklyReview.Metrics(
            weekStart: Self.now,
            plannedSessions: 0,
            completedSessions: 3,
            adherencePercent: nil,
            averageDurationMinutes: 45,
            setsByMuscle: [:],
            underTargetMuscles: [],
            personalRecords: 0,
            incompleteSessions: 0,
            repeatedlySkippedExerciseIds: [],
            sessionsLastWeek: 2
        )

        let review = LocalWeeklyReview.review(for: metrics)
        #expect(review.summary.contains("Nothing was planned"))
        // Never phrased as poor adherence.
        #expect(!review.summary.contains("0%"))
    }

    /// "Keep going" is a real answer. A review that always finds something to
    /// change is a review nobody trusts twice.
    @Test("A good week proposes keeping it unchanged")
    func goodWeekKeepsItUnchanged() {
        let metrics = WeeklyReview.Metrics(
            weekStart: Self.now,
            plannedSessions: 4,
            completedSessions: 4,
            adherencePercent: 100,
            averageDurationMinutes: 50,
            setsByMuscle: ["Chest": 12],
            underTargetMuscles: [],
            personalRecords: 2,
            incompleteSessions: 0,
            repeatedlySkippedExerciseIds: [],
            sessionsLastWeek: 4
        )

        let review = LocalWeeklyReview.review(for: metrics)
        #expect(review.actions.count == 1)
        #expect(review.actions.first?.kind == .keepUnchanged)
    }

    @Test("The local review never proposes more than three actions")
    func actionsAreCapped() {
        let metrics = WeeklyReview.Metrics(
            weekStart: Self.now,
            plannedSessions: 5,
            completedSessions: 1,
            adherencePercent: 20,
            averageDurationMinutes: 30,
            setsByMuscle: [:],
            underTargetMuscles: ["Back", "Legs", "Calves"],
            personalRecords: 0,
            incompleteSessions: 2,
            repeatedlySkippedExerciseIds: ["a", "b"],
            sessionsLastWeek: 4
        )

        let review = LocalWeeklyReview.review(for: metrics)
        #expect(review.actions.count <= 3)
    }

    // MARK: Decoding

    @Test("An unknown review action is dropped, not fatal")
    func unknownActionIsDropped() throws {
        let json = """
        {
          "headline": "A solid week",
          "summary": "Three sessions.",
          "actions": [
            {"type": "deleteProgramme", "label": "Nuke it", "rationale": "no"},
            {"type": "keepUnchanged", "label": "Keep going", "rationale": "Nothing to change."}
          ]
        }
        """
        let review = try JSONDecoder().decode(WeeklyReviewResponse.self, from: Data(json.utf8))

        // The prose survives; only the action the app can't perform is lost.
        #expect(review.actions.count == 1)
        #expect(review.actions.first?.kind == .keepUnchanged)
    }
}
