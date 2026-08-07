import Testing
import Foundation
@testable import Life

// MARK: - Drift

/// Drift detection, and — mostly — its refusal to detect.
///
/// Most of these assert that a signal does *not* fire. That is the feature: an
/// app that offers to redesign your programme because you skipped a Tuesday is
/// not observant, and the thresholds are the only thing standing between this
/// engine and that app.
@MainActor
struct DriftEngineTests {

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    /// Thursday 13 August 2026.
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
        var bench = Exercise(name: "Bench press", muscle: "Chest", kind: .weight)
        bench.equipment = .barbell
        var curl = Exercise(name: "Curl", muscle: "Biceps", kind: .weight)
        curl.equipment = .dumbbell
        state.exercises = [bench, curl]
        return state
    }

    static func session(
        daysAgo: Int,
        exerciseIds: [String],
        routineId: String?,
        minutes: Int = 45
    ) -> WorkoutSession {
        let finished = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        var performed: [SessionExercise] = []
        for id in exerciseIds {
            var set = LoggedSet(weight: 60, reps: 8)
            set.done = true
            var exercise = SessionExercise(exerciseId: id)
            exercise.sets = [set]
            performed.append(exercise)
        }
        var session = WorkoutSession(name: "Session")
        session.startedAt = calendar.date(byAdding: .minute, value: -minutes, to: finished)!
        session.finishedAt = finished
        session.routineId = routineId
        session.exercises = performed
        return session
    }

    /// The threshold in one test: twice is not a pattern.
    @Test("Two skips across two weeks isn't drift")
    func twoSkipsIsNotDrift() {
        let state = Self.state()
        let bench = state.exercises[0]
        let curl = state.exercises[1]
        var routine = Routine(name: "Upper")
        routine.exercises = [
            RoutineExercise(exerciseId: bench.id),
            RoutineExercise(exerciseId: curl.id),
        ]
        state.routines = [routine]
        state.sessions = [
            Self.session(daysAgo: 3, exerciseIds: [bench.id], routineId: routine.id),
            Self.session(daysAgo: 10, exerciseIds: [bench.id], routineId: routine.id),
        ]

        let signals = DriftEngine.signals(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(!signals.contains { if case .skipsExercise = $0 { return true } else { return false } })
    }

    @Test("Three skips across three weeks is drift")
    func threeSkipsAcrossThreeWeeksIsDrift() {
        let state = Self.state()
        let bench = state.exercises[0]
        let curl = state.exercises[1]
        var routine = Routine(name: "Upper")
        routine.exercises = [
            RoutineExercise(exerciseId: bench.id),
            RoutineExercise(exerciseId: curl.id),
        ]
        state.routines = [routine]
        state.sessions = [
            Self.session(daysAgo: 3, exerciseIds: [bench.id], routineId: routine.id),
            Self.session(daysAgo: 10, exerciseIds: [bench.id], routineId: routine.id),
            Self.session(daysAgo: 17, exerciseIds: [bench.id], routineId: routine.id),
        ]

        let signals = DriftEngine.signals(appState: state, now: Self.now, calendar: Self.calendar)
        guard case .skipsExercise(let id, let name, let times)? = signals.first(where: {
            if case .skipsExercise = $0 { return true } else { return false }
        }) else {
            Issue.record("expected a skip signal")
            return
        }
        #expect(id == curl.id)
        #expect(name == "Curl")
        #expect(times == 3)
    }

    /// Three skips in one bad week is a bad week, not a decision.
    @Test("Three skips inside one week isn't drift")
    func threeSkipsInOneWeekIsNotDrift() {
        let state = Self.state()
        let bench = state.exercises[0]
        let curl = state.exercises[1]
        var routine = Routine(name: "Upper")
        routine.exercises = [
            RoutineExercise(exerciseId: bench.id),
            RoutineExercise(exerciseId: curl.id),
        ]
        state.routines = [routine]
        state.sessions = [
            Self.session(daysAgo: 1, exerciseIds: [bench.id], routineId: routine.id),
            Self.session(daysAgo: 2, exerciseIds: [bench.id], routineId: routine.id),
            Self.session(daysAgo: 3, exerciseIds: [bench.id], routineId: routine.id),
        ]

        let signals = DriftEngine.signals(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(!signals.contains { if case .skipsExercise = $0 { return true } else { return false } })
    }

    /// One session short of the plan is a normal week.
    @Test("Training one day short isn't reported as drift")
    func oneDayShortIsNormal() {
        let state = Self.state()
        var programme = WorkoutProgram(name: "Four day")
        programme.isActive = true
        programme.days = (1...4).map { ProgramDay(weekday: $0, routineId: "r\($0)") }
        state.programs = [programme]

        // Three sessions a week for four weeks against a four-day plan.
        var sessions: [WorkoutSession] = []
        for week in 1...4 {
            for offset in 0..<3 {
                sessions.append(
                    Self.session(daysAgo: week * 7 + offset, exerciseIds: [state.exercises[0].id], routineId: nil)
                )
            }
        }
        state.sessions = sessions

        let signals = DriftEngine.signals(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(!signals.contains { if case .trainsFewerDays = $0 { return true } else { return false } })
    }

    @Test("Training two days short of a five-day plan is drift")
    func twoDaysShortIsDrift() {
        let state = Self.state()
        var programme = WorkoutProgram(name: "Five day")
        programme.isActive = true
        programme.days = (1...5).map { ProgramDay(weekday: $0, routineId: "r\($0)") }
        state.programs = [programme]

        var sessions: [WorkoutSession] = []
        for week in 1...4 {
            for offset in 0..<3 {
                sessions.append(
                    Self.session(daysAgo: week * 7 + offset, exerciseIds: [state.exercises[0].id], routineId: nil)
                )
            }
        }
        state.sessions = sessions

        let signals = DriftEngine.signals(appState: state, now: Self.now, calendar: Self.calendar)
        guard case .trainsFewerDays(let planned, let actual, _)? = signals.first(where: {
            if case .trainsFewerDays = $0 { return true } else { return false }
        }) else {
            Issue.record("expected a day-count signal")
            return
        }
        #expect(planned == 5)
        #expect(actual == 3)
    }

    /// A Monday morning would otherwise show every user as having collapsed.
    @Test("The current week is left out of the frequency median")
    func currentWeekIsExcluded() {
        let state = Self.state()
        var programme = WorkoutProgram(name: "Four day")
        programme.isActive = true
        programme.days = (1...4).map { ProgramDay(weekday: $0, routineId: "r\($0)") }
        state.programs = [programme]

        // Four full weeks at four sessions, and nothing yet this week.
        var sessions: [WorkoutSession] = []
        for week in 1...4 {
            for offset in 0..<4 {
                sessions.append(
                    Self.session(daysAgo: week * 7 + offset, exerciseIds: [state.exercises[0].id], routineId: nil)
                )
            }
        }
        state.sessions = sessions

        let signals = DriftEngine.signals(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(!signals.contains { if case .trainsFewerDays = $0 { return true } else { return false } })
    }

    @Test("With no programme there is nothing to drift from")
    func noProgrammeNoDrift() {
        let state = Self.state()
        state.sessions = (1...10).map {
            Self.session(daysAgo: $0 * 2, exerciseIds: [state.exercises[0].id], routineId: nil)
        }

        let signals = DriftEngine.signals(appState: state, now: Self.now, calendar: Self.calendar)
        #expect(!signals.contains { if case .trainsFewerDays = $0 { return true } else { return false } })
        #expect(!signals.contains { if case .prefersDifferentDay = $0 { return true } else { return false } })
    }

    // MARK: The brief

    /// Corrections only. Drift evidence says what someone does, never what they
    /// want, so it must not arrive at the builder carrying a goal.
    @Test("A drift brief carries corrections and no opinions")
    func briefCarriesOnlyCorrections() {
        let brief = DriftEngine.brief(from: [
            .trainsFewerDays(planned: 5, actual: 3, weeks: 4),
            .skipsExercise(exerciseId: "x", name: "Cable fly", times: 4),
            .substitutesEquipment(from: .barbell, to: .dumbbell, times: 3),
        ])

        #expect(brief.daysPerWeek == 3)
        #expect(brief.availableEquipment.contains(.dumbbell))
        #expect(brief.text.contains("Cable fly"))
        // The goal is left at its default — nothing about drift implies one.
        #expect(brief.goal == WorkoutBrief().goal)
    }

    @Test("An absurd day count is clamped rather than trusted")
    func briefClampsDays() {
        let brief = DriftEngine.brief(from: [.trainsFewerDays(planned: 9, actual: 0, weeks: 4)])
        #expect(brief.daysPerWeek == 2)
    }
}

// MARK: - Guardrails

/// Programme-quality warnings. Facts about a plan, never medical limits.
struct VolumeGuardrailTests {

    @Test("A big jump against a real norm is flagged")
    func suddenIncreaseIsFlagged() {
        let warnings = VolumeGuardrails.check(
            proposedSets: ["Chest": 20],
            recentWeeklySets: ["Chest": 10],
            weeksOfHistory: 4,
            targets: [:]
        )
        #expect(warnings.contains { if case .suddenIncrease = $0 { return true } else { return false } })
    }

    /// With no history there is no norm, and a first programme must not be
    /// warned about for being someone's first.
    @Test("A first programme isn't warned about for having no precedent")
    func noHistoryNoIncreaseWarning() {
        let warnings = VolumeGuardrails.check(
            proposedSets: ["Chest": 20],
            recentWeeklySets: [:],
            weeksOfHistory: 0,
            targets: [:]
        )
        #expect(warnings.isEmpty)
    }

    @Test("A modest increase isn't flagged")
    func modestIncreaseIsFine() {
        let warnings = VolumeGuardrails.check(
            proposedSets: ["Chest": 12],
            recentWeeklySets: ["Chest": 10],
            weeksOfHistory: 4,
            targets: [:]
        )
        #expect(warnings.isEmpty)
    }

    @Test("A muscle under half its target is flagged")
    func underTargetIsFlagged() {
        let warnings = VolumeGuardrails.check(
            proposedSets: ["Back": 3],
            recentWeeklySets: [:],
            weeksOfHistory: 0,
            targets: ["Back": 10...20]
        )
        guard case .underTarget(let muscle, let sets, let target)? = warnings.first else {
            Issue.record("expected an under-target warning")
            return
        }
        #expect(muscle == "Back")
        #expect(sets == 3)
        #expect(target == 10)
    }

    @Test("A focus that gets less work than everything else is flagged")
    func focusMismatchIsFlagged() {
        let warnings = VolumeGuardrails.check(
            proposedSets: ["Chest": 20, "Back": 20, "Legs": 4],
            recentWeeklySets: [:],
            weeksOfHistory: 0,
            targets: [:],
            focus: [.legs]
        )
        #expect(warnings.contains { if case .focusMismatch = $0 { return true } else { return false } })
    }

    @Test("A programme edit that reshapes the week is flagged, a tweak isn't")
    func changeWarningHasAThreshold() {
        #expect(VolumeGuardrails.changeWarning(from: 40, to: 70) != nil)
        #expect(VolumeGuardrails.changeWarning(from: 40, to: 45) == nil)
        // No previous programme to compare against.
        #expect(VolumeGuardrails.changeWarning(from: 0, to: 40) == nil)
    }

    @Test("Hard work for one muscle on consecutive days is caught, including across the weekend")
    func adjacentDaysWrap() {
        let library = [
            Exercise(name: "Squat", muscle: "Legs", kind: .weight),
        ]
        var heavy = RoutineExercise(exerciseId: library[0].id)
        heavy.defaultSets = 8

        // Sunday (7) and Monday (1) are consecutive in a repeating week.
        let clashes = VolumeGuardrails.adjacentHardMuscles(
            byWeekday: [7: [heavy], 1: [heavy]],
            library: library
        )
        #expect(clashes == ["Legs"])
    }

    @Test("Light work on consecutive days is not a clash")
    func lightAdjacentDaysAreFine() {
        let library = [Exercise(name: "Squat", muscle: "Legs", kind: .weight)]
        var light = RoutineExercise(exerciseId: library[0].id)
        light.defaultSets = 2

        let clashes = VolumeGuardrails.adjacentHardMuscles(
            byWeekday: [1: [light], 2: [light]],
            library: library
        )
        #expect(clashes.isEmpty)
    }
}

// MARK: - Post-workout review

/// Three lines at most, and never a health claim.
struct PostWorkoutReviewTests {

    static func input(
        completed: Int = 12,
        planned: Int = 12,
        failed: Int = 0,
        bests: [String] = [],
        actual: Int = 45,
        estimated: Int = 45,
        volume: Double? = nil,
        previousVolume: Double? = nil,
        skipped: [String] = []
    ) -> PostWorkoutReview.Input {
        PostWorkoutReview.Input(
            completedSets: completed,
            plannedSets: planned,
            failedSets: failed,
            personalBests: bests,
            actualMinutes: actual,
            estimatedMinutes: estimated,
            volumeKg: volume,
            previousVolumeKg: previousVolume,
            exercisesSkipped: skipped
        )
    }

    @Test("A personal best leads")
    func bestsLead() {
        let review = PostWorkoutReview.review(Self.input(bests: ["Bench press"]))
        #expect(review.success.contains("Bench press"))
    }

    /// There is something good in every finished session, starting with the
    /// fact that it was finished.
    @Test("An ordinary session still has a success line")
    func ordinarySessionsStillSucceed() {
        let review = PostWorkoutReview.review(Self.input())
        #expect(!review.success.isEmpty)
    }

    /// An "issue" invented to fill a slot teaches people to ignore the slot.
    @Test("A clean session raises nothing and proposes nothing")
    func cleanSessionHasNoAttention() {
        let review = PostWorkoutReview.review(Self.input(bests: ["Squat"]))
        #expect(review.attention == nil)
        #expect(review.nextAction == nil)
    }

    @Test("Skipped exercises are what gets raised, and the action follows from it")
    func skippedExercisesAreRaised() {
        let review = PostWorkoutReview.review(Self.input(skipped: ["Cable fly"]))
        #expect(review.attention?.contains("Cable fly") == true)
        #expect(review.nextAction != nil)
    }

    @Test("An overrun is raised only when it's substantial")
    func overrunHasAThreshold() {
        let small = PostWorkoutReview.review(Self.input(actual: 50, estimated: 45))
        #expect(small.attention == nil)

        let large = PostWorkoutReview.review(Self.input(actual: 75, estimated: 45))
        #expect(large.attention?.contains("30") == true)
    }

    /// It has no health data in front of it, so it must never reach for one of
    /// those words.
    @Test("The review never mentions recovery, sleep or tiredness")
    func noHealthClaims() {
        let review = PostWorkoutReview.review(
            Self.input(failed: 5, actual: 90, estimated: 45, skipped: ["Row"])
        )
        let text = [review.success, review.attention, review.nextAction]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        for word in ["recovery", "recovered", "sleep", "tired", "fatigue", "overtraining"] {
            #expect(!text.contains(word))
        }
    }

    @Test("A first session compares against nothing rather than against zero")
    func noPreviousVolumeMeansNoComparison() {
        let review = PostWorkoutReview.review(Self.input(volume: 4_000, previousVolume: nil))
        #expect(review.attention == nil)
        #expect(!review.success.contains("%"))
    }
}
