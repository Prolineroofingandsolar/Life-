import Testing
import Foundation
@testable import Life

/// The part that learns.
///
/// Everything else in this app reacts the same way every time. These tests are
/// about the one place where saying no changes what happens next — and about the
/// limits on that, because an app that over-learns is worse than one that
/// doesn't learn at all.
@MainActor
struct TrainingMemoryTests {

    static func state() -> AppState {
        let state = AppState()
        state.sessions = []
        state.routines = []
        state.coachFeedback = []
        var bench = Exercise(name: "Bench press", muscle: "Chest", kind: .weight)
        bench.equipment = .barbell
        var fly = Exercise(name: "Cable fly", muscle: "Chest", kind: .weight)
        fly.equipment = .cable
        state.exercises = [bench, fly]
        return state
    }

    static func feedback(
        _ outcome: CoachFeedbackEntry.Outcome,
        exerciseId: String,
        daysAgo: Int = 1
    ) -> CoachFeedbackEntry {
        CoachFeedbackEntry(
            date: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
            source: .builder,
            outcome: outcome,
            exerciseId: exerciseId
        )
    }

    // MARK: Preferences

    @Test("Accepting an exercise raises its score, dismissing lowers it")
    func feedbackMovesTheScore() {
        let state = Self.state()
        let bench = state.exercises[0].id
        let fly = state.exercises[1].id
        state.coachFeedback = [
            Self.feedback(.accepted, exerciseId: bench),
            Self.feedback(.dismissed, exerciseId: fly),
        ]

        let preferences = TrainingMemory.preferences(appState: state)
        #expect(preferences[bench] == TrainingMemory.feedbackWeight)
        #expect(preferences[fly] == -TrainingMemory.feedbackWeight)
    }

    /// Someone who changed the weight and kept the exercise has endorsed the
    /// exercise, gently.
    @Test("An edit counts for half an acceptance")
    func editsCountForLess() {
        let state = Self.state()
        let bench = state.exercises[0].id
        state.coachFeedback = [Self.feedback(.edited, exerciseId: bench)]

        #expect(TrainingMemory.preferences(appState: state)[bench] == TrainingMemory.feedbackWeight / 2)
    }

    /// Without a cap, an exercise rejected fifteen times could never come back
    /// even after the person changed gyms.
    @Test("Repeated feedback is capped in both directions")
    func adjustmentsAreCapped() {
        let state = Self.state()
        let bench = state.exercises[0].id
        state.coachFeedback = (0..<15).map { Self.feedback(.dismissed, exerciseId: bench, daysAgo: $0 + 1) }

        #expect(TrainingMemory.preferences(appState: state)[bench] == -TrainingMemory.maximumAdjustment)
    }

    /// People change gyms, recover from injuries and change their minds.
    @Test("Feedback older than four months stops counting")
    func oldFeedbackExpires() {
        let state = Self.state()
        let bench = state.exercises[0].id
        state.coachFeedback = [Self.feedback(.dismissed, exerciseId: bench, daysAgo: 200)]

        #expect(TrainingMemory.preferences(appState: state).isEmpty)
        #expect(TrainingMemory.refused(appState: state).isEmpty)
    }

    // MARK: Refusal

    @Test("Two refusals is a mood; three is a decision")
    func refusalThreshold() {
        let state = Self.state()
        let fly = state.exercises[1].id

        state.coachFeedback = [
            Self.feedback(.dismissed, exerciseId: fly, daysAgo: 1),
            Self.feedback(.dismissed, exerciseId: fly, daysAgo: 5),
        ]
        #expect(TrainingMemory.refused(appState: state).isEmpty)

        state.coachFeedback.append(Self.feedback(.dismissed, exerciseId: fly, daysAgo: 9))
        #expect(TrainingMemory.refused(appState: state) == [fly])
    }

    /// The point of the whole layer: a refused exercise stops being offered.
    @Test("A refused exercise is never resolved into a workout")
    func refusedExercisesAreNotOffered() {
        let state = Self.state()
        let bench = state.exercises[0]
        let fly = state.exercises[1]

        let slot = WorkoutSlot(
            muscle: .chest, sets: 3, repMin: 8, repMax: 12, restSeconds: 90
        )
        let blueprint = WorkoutBlueprint(
            name: "Chest", focus: "Chest", slots: [slot], notes: nil
        )

        // Without the memory, the resolver may pick either.
        let neutral = WorkoutResolver.resolve(
            blueprint,
            inputs: WorkoutResolver.Inputs(library: [bench, fly])
        )
        #expect(neutral.items.count == 1)

        // With bench refused, only the other one can appear.
        let learned = WorkoutResolver.resolve(
            blueprint,
            inputs: WorkoutResolver.Inputs(library: [bench, fly], refusedIds: [bench.id])
        )
        #expect(learned.items.first?.exercise.id == fly.id)
    }

    @Test("A preference score changes which exercise wins")
    func preferencesChangeTheChoice() {
        let state = Self.state()
        let bench = state.exercises[0]
        let fly = state.exercises[1]

        let slot = WorkoutSlot(
            muscle: .chest, sets: 3, repMin: 8, repMax: 12, restSeconds: 90
        )
        let blueprint = WorkoutBlueprint(name: "Chest", focus: "Chest", slots: [slot], notes: nil)

        let baseline = WorkoutResolver.resolve(
            blueprint, inputs: WorkoutResolver.Inputs(library: [bench, fly])
        )
        let winner = baseline.items.first?.exercise.id
        let loser = winner == bench.id ? fly.id : bench.id

        // The loser, having been chosen repeatedly by the user, now wins.
        let learned = WorkoutResolver.resolve(
            blueprint,
            inputs: WorkoutResolver.Inputs(
                library: [bench, fly],
                preferences: [loser: TrainingMemory.maximumAdjustment]
            )
        )
        #expect(learned.items.first?.exercise.id == loser)
    }

    // MARK: Increments

    @Test("With no history, the increment is the equipment default")
    func incrementFallsBack() {
        let state = Self.state()
        let bench = state.exercises[0]

        #expect(
            TrainingMemory.increment(for: bench, appState: state)
                == ProgressionEngine.increment(for: bench)
        )
    }

    /// The app ships with 2.5 kg for every barbell in the world. Someone with
    /// microplates deserves better than that.
    @Test("Three successful jumps of 1.25kg teaches a 1.25kg increment")
    func incrementIsLearned() {
        let state = Self.state()
        let bench = state.exercises[0]

        let weights: [Double] = [60, 61.25, 62.5, 63.75]
        state.sessions = weights.enumerated().map { index, weight in
            var set = LoggedSet(weight: weight, reps: 8)
            set.done = true
            var performed = SessionExercise(exerciseId: bench.id)
            performed.sets = [set, set]
            var session = WorkoutSession(name: "S\(index)")
            let finished = Date().addingTimeInterval(-Double(weights.count - index) * 7 * 86_400)
            session.startedAt = finished.addingTimeInterval(-3_000)
            session.finishedAt = finished
            session.exercises = [performed]
            return session
        }

        #expect(TrainingMemory.increment(for: bench, appState: state) == 1.25)
    }

    /// A logging slip that records 100 kg as 10 kg would otherwise teach the app
    /// that this person progresses in 90 kg steps.
    @Test("An implausible jump is ignored rather than learned")
    func absurdIncrementsAreRejected() {
        let state = Self.state()
        let bench = state.exercises[0]

        let weights: [Double] = [10, 100, 200, 300]
        state.sessions = weights.enumerated().map { index, weight in
            var set = LoggedSet(weight: weight, reps: 8)
            set.done = true
            var performed = SessionExercise(exerciseId: bench.id)
            performed.sets = [set, set]
            var session = WorkoutSession(name: "S\(index)")
            let finished = Date().addingTimeInterval(-Double(weights.count - index) * 7 * 86_400)
            session.startedAt = finished.addingTimeInterval(-3_000)
            session.finishedAt = finished
            session.exercises = [performed]
            return session
        }

        #expect(
            TrainingMemory.increment(for: bench, appState: state)
                == ProgressionEngine.increment(for: bench)
        )
    }

    // MARK: Pace

    @Test("Without enough sessions, the pace is the shipped default")
    func paceFallsBack() {
        let state = Self.state()
        let pace = TrainingMemory.pace(appState: state)

        #expect(pace.factor == 1.0)
        // Not learned is not the same as no difference — the view says so, and
        // this is the flag it reads.
        #expect(pace.isLearned == false)
    }

    // MARK: Recording

    @Test("Recording feedback appends one entry and keeps the log bounded")
    func recordingIsBounded() {
        let state = Self.state()
        let bench = state.exercises[0].id

        state.recordFeedback(.accepted, source: .builder, exerciseId: bench)
        #expect(state.coachFeedback.count == 1)
        #expect(state.coachFeedback.first?.outcome == .accepted)

        for _ in 0..<600 {
            state.recordFeedback(.dismissed, source: .builder, exerciseId: bench)
        }
        // A preference signal, not an audit log.
        #expect(state.coachFeedback.count == 500)
    }

    // MARK: Persistence

    /// Old snapshots have no `coachFeedback` key. It must decode to empty rather
    /// than throwing — `load()` reads a decode failure as first launch and seeds
    /// defaults over the user's data.
    @Test("A snapshot from before the memory existed still decodes")
    func backwardCompatibleDecoding() throws {
        let json = #"{"tasks":[],"userName":"Will"}"#
        let snapshot = try JSONDecoder().decode(StateSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.coachFeedback == nil)
        #expect(snapshot.userName == "Will")
    }

    @Test("Feedback survives a snapshot round trip")
    func feedbackRoundTrips() throws {
        var snapshot = StateSnapshot()
        snapshot.coachFeedback = [
            CoachFeedbackEntry(source: .progression, outcome: .edited, exerciseId: "x")
        ]

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(StateSnapshot.self, from: data)

        #expect(decoded.coachFeedback?.count == 1)
        #expect(decoded.coachFeedback?.first?.outcome == .edited)
        #expect(decoded.coachFeedback?.first?.exerciseId == "x")
    }

    /// Feedback given on one device is still true on the other, and losing it
    /// would quietly un-learn a preference.
    @Test("Merging two devices keeps both sides' feedback")
    func mergeUnionsFeedback() {
        var mine = StateSnapshot()
        mine.coachFeedback = [
            CoachFeedbackEntry(id: "a", source: .builder, outcome: .accepted, exerciseId: "x")
        ]
        var theirs = StateSnapshot()
        theirs.coachFeedback = [
            CoachFeedbackEntry(id: "b", source: .builder, outcome: .dismissed, exerciseId: "y")
        ]

        let merged = StateSnapshot.merged(preferring: mine, with: theirs)
        #expect(merged.coachFeedback?.count == 2)
    }

    // MARK: What leaves the device

    @Test("The learned prompt text names no exercise")
    func promptTextIsAnonymous() {
        let state = Self.state()
        let fly = state.exercises[1].id
        state.coachFeedback = (0..<4).map {
            Self.feedback(.dismissed, exerciseId: fly, daysAgo: $0 + 1)
        }

        let text = TrainingMemory.promptText(appState: state) ?? ""
        #expect(text.contains("1 exercise(s)"))
        #expect(!text.contains("Cable fly"))
        #expect(!text.contains(fly))
    }

    @Test("With nothing learned, nothing is sent")
    func nothingLearnedSendsNothing() {
        #expect(TrainingMemory.promptText(appState: Self.state()) == nil)
    }
}
