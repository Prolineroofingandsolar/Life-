import Testing
import Foundation
@testable import Life

/// What history is allowed to say about a new programme.
///
/// Three rules from the brief, all enforced here rather than left to the model:
/// nothing is inferred from a single action, one missed workout is not a
/// pattern, and no starting load is invented.
@MainActor
struct TrainingHistoryDigestTests {

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
        state.routines = []
        state.plannedSessions = []
        var bench = Exercise(name: "Bench press", muscle: "Chest", kind: .weight)
        bench.equipment = .barbell
        var curl = Exercise(name: "Dumbbell curl", muscle: "Biceps", kind: .weight)
        curl.equipment = .dumbbell
        state.exercises = [bench, curl]
        return state
    }

    static func session(
        daysAgo: Int,
        exerciseId: String,
        minutes: Int = 50,
        routineId: String? = nil
    ) -> WorkoutSession {
        let finished = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        var set = LoggedSet(weight: 60, reps: 8)
        set.done = true
        var performed = SessionExercise(exerciseId: exerciseId)
        performed.sets = [set]
        var session = WorkoutSession(name: "Session")
        session.startedAt = calendar.date(byAdding: .minute, value: -minutes, to: finished)!
        session.finishedAt = finished
        session.routineId = routineId
        session.exercises = [performed]
        return session
    }

    // MARK: Thresholds

    /// Five sessions is not a training pattern. Below the threshold the digest
    /// is empty rather than thin, so a caller can't accidentally build a
    /// programme around one good fortnight.
    @Test("Below six sessions the digest is empty")
    func thinHistoryIsEmpty() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = (1...5).map { Self.session(daysAgo: $0 * 2, exerciseId: id) }

        let digest = TrainingHistoryDigest.build(
            appState: state, now: Self.now, calendar: Self.calendar
        )
        #expect(digest == .empty)
        #expect(digest.isUsable == false)
        #expect(TrainingHistoryDigest.promptText(digest) == nil)
    }

    @Test("Enough history produces a usable digest")
    func realHistoryIsUsable() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = (1...8).map { Self.session(daysAgo: $0 * 2, exerciseId: id) }

        let digest = TrainingHistoryDigest.build(
            appState: state, now: Self.now, calendar: Self.calendar
        )
        #expect(digest.isUsable)
        #expect(digest.sessionsConsidered == 8)
        #expect(digest.frequentMuscles.contains("Chest"))
        #expect(digest.equipmentUsed.contains("barbell"))
    }

    /// An exercise done twice is something you tried. Three times is something
    /// you do.
    @Test("An exercise done twice isn't called reliable")
    func reliabilityNeedsThree() {
        let state = Self.state()
        let bench = state.exercises[0].id
        let curl = state.exercises[1].id

        var sessions = (1...6).map { Self.session(daysAgo: $0 * 2, exerciseId: bench) }
        sessions.append(Self.session(daysAgo: 20, exerciseId: curl))
        sessions.append(Self.session(daysAgo: 22, exerciseId: curl))
        state.sessions = sessions

        let digest = TrainingHistoryDigest.build(
            appState: state, now: Self.now, calendar: Self.calendar
        )
        #expect(digest.reliableExerciseIds.contains(bench))
        #expect(!digest.reliableExerciseIds.contains(curl))
    }

    // MARK: Medians, not means

    /// One holiday week of zero and one heroic week of six should not average
    /// into "four". The median says what a normal week looks like.
    @Test("Frequency is a median, so one odd week doesn't move it")
    func frequencyUsesMedian() {
        #expect(TrainingHistoryDigest.median([3, 3, 3, 12]) == 3)
        #expect(TrainingHistoryDigest.median([2, 4]) == 3)
        #expect(TrainingHistoryDigest.median([]) == nil)
    }

    @Test("A forgotten timer doesn't become the typical session length")
    func absurdDurationsAreIgnored() {
        let state = Self.state()
        let id = state.exercises[0].id
        var sessions = (1...7).map { Self.session(daysAgo: $0 * 2, exerciseId: id, minutes: 45) }
        var marathon = Self.session(daysAgo: 16, exerciseId: id)
        marathon.startedAt = Self.calendar.date(byAdding: .hour, value: -9, to: marathon.finishedAt!)!
        sessions.append(marathon)
        state.sessions = sessions

        let digest = TrainingHistoryDigest.build(
            appState: state, now: Self.now, calendar: Self.calendar
        )
        #expect(digest.typicalDurationMinutes == 45)
    }

    // MARK: What leaves the device

    /// The digest goes to Gemini as prose. No exercise name, no id, no date —
    /// the model gets shape and the resolver holds the library.
    @Test("The prompt text names no exercise and quotes no id")
    func promptTextCarriesNoIdentifiers() {
        let state = Self.state()
        let id = state.exercises[0].id
        state.sessions = (1...8).map { Self.session(daysAgo: $0 * 2, exerciseId: id) }

        let digest = TrainingHistoryDigest.build(
            appState: state, now: Self.now, calendar: Self.calendar
        )
        let text = TrainingHistoryDigest.promptText(digest) ?? ""

        #expect(!text.isEmpty)
        #expect(!text.contains(id))
        #expect(!text.contains("Bench press"))
    }

    // MARK: Skipped exercises

    @Test("One skipped exercise is not held against the programme")
    func oneSkipIsNotAvoidance() {
        let state = Self.state()
        let bench = state.exercises[0]
        let curl = state.exercises[1]
        var routine = Routine(name: "Upper")
        routine.exercises = [
            RoutineExercise(exerciseId: bench.id),
            RoutineExercise(exerciseId: curl.id),
        ]
        state.routines = [routine]
        state.sessions = (1...7).map { index in
            // Only the first session skips the curl.
            Self.session(
                daysAgo: index * 2,
                exerciseId: index == 1 ? bench.id : curl.id,
                routineId: routine.id
            )
        }

        let digest = TrainingHistoryDigest.build(
            appState: state, now: Self.now, calendar: Self.calendar
        )
        // Bench is skipped in six of seven sessions, curl in one. Only the
        // repeated one counts.
        #expect(!digest.avoidedExerciseIds.contains(curl.id))
    }

    // MARK: The brief

    /// History is evidence, not instruction — someone returning from injury has
    /// six weeks of sessions describing a person they are deliberately no
    /// longer training like.
    @Test("Turning history off keeps it out of the prompt entirely")
    func historyCanBeExcluded() {
        var brief = WorkoutBrief()
        brief.historyText = "Usually trains 4 times a week."
        brief.useHistory = false

        #expect(!brief.promptText.contains("Usually trains"))

        brief.useHistory = true
        #expect(brief.promptText.contains("Usually trains"))
    }
}
