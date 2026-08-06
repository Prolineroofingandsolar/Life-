import Testing
import Foundation
@testable import Life

/// Progression, which Gemini has no say in.
///
/// The reason these are rules rather than judgement is that being wrong here has
/// a physical cost: "add 5 kg" to someone who failed their last set is an
/// instruction to attempt a lift they have already shown they cannot do. A rule
/// can be read, tested and argued with. These are the arguments.
struct ProgressionEngineTests {

    static func input(
        repMin: Int = 8,
        repMax: Int = 12,
        sets: [ProgressionEngine.SetResult],
        sessions: Int = 4,
        increment: Double = 2.5
    ) -> ProgressionEngine.Input {
        ProgressionEngine.Input(
            exerciseId: "ex-bench",
            exerciseName: "Bench Press",
            repRangeMin: repMin,
            repRangeMax: repMax,
            lastSession: sets,
            comparableSessions: sessions,
            loadIncrement: increment
        )
    }

    static func set(_ weight: Double, _ reps: Int, done: Bool = true, rpe: Int? = nil, failure: Bool = false)
        -> ProgressionEngine.SetResult {
        .init(weight: weight, reps: reps, completed: done, rpe: rpe, toFailure: failure)
    }

    // MARK: Insufficient information is its own answer

    @Test("One session is not a trend")
    func oneSessionIsNotEnough() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(60, 12), Self.set(60, 12)], sessions: 1)
        )

        // Progressing off a single good day is how someone ends up adding load
        // every session until they can't.
        #expect(proposal.action == .insufficientInformation)
        #expect(proposal.changesAnything == false)
    }

    @Test("No sets recorded says so rather than holding")
    func noSetsIsNotHold() {
        let proposal = ProgressionEngine.propose(Self.input(sets: []))

        // "Hold" and "I don't know" are different statements, and only one of
        // them is honest here.
        #expect(proposal.action == .insufficientInformation)
    }

    // MARK: The load is ahead of the person

    @Test("Unfinished sets mean the load comes down")
    func incompleteSetsReduceLoad() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(80, 8), Self.set(80, 8), Self.set(80, 5, done: false)])
        )

        #expect(proposal.action == .reduceLoad)
        #expect(proposal.proposedWeight == 77.5)
        #expect(proposal.evidence.contains { $0.contains("1 of 3") })
    }

    @Test("Reps below the target range mean the load comes down")
    func belowRangeReducesLoad() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(90, 6), Self.set(90, 5)])
        )

        #expect(proposal.action == .reduceLoad)
        #expect(proposal.proposedWeight == 87.5)
    }

    // MARK: Earning more load

    @Test("Top of the range on every set earns load, and resets the reps")
    func topOfRangeAddsLoad() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(70, 12), Self.set(70, 12), Self.set(70, 12)])
        )

        #expect(proposal.action == .increaseLoad)
        #expect(proposal.proposedWeight == 72.5)
        // Back to the bottom of the range with the new load — the point of a
        // range is that you climb it again.
        #expect(proposal.proposedReps == 8)
    }

    @Test("Top of the range at maximum effort repeats instead of adding")
    func maximalEffortRepeats() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(70, 12, rpe: 10), Self.set(70, 12, rpe: 9)])
        )

        // The reps are there; the capacity isn't yet. Repeating consolidates
        // rather than gambling.
        #expect(proposal.action == .repeatSame)
        #expect(proposal.proposedWeight == 70)
    }

    @Test("A set taken to failure counts as maximum effort even without an RPE")
    func failureCountsAsMaximal() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(70, 12), Self.set(70, 12, failure: true)])
        )

        // Most people never log RPE, so a rule that needed it would never fire.
        #expect(proposal.action == .repeatSame)
    }

    @Test("Inside the range adds a rep, not load")
    func insideRangeAddsARep() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(70, 9), Self.set(70, 9)])
        )

        #expect(proposal.action == .increaseReps)
        #expect(proposal.proposedReps == 10)
        #expect(proposal.proposedWeight == 70)
    }

    @Test("The weakest set decides, not the best one")
    func lowestSetGoverns() {
        // 12, 12, 8 is not a session that earned more load.
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(70, 12), Self.set(70, 12), Self.set(70, 8)])
        )

        #expect(proposal.action == .increaseReps)
        #expect(proposal.proposedReps == 9)
    }

    // MARK: Nothing to load

    @Test("With no load increment, progress is reps rather than weight")
    func bodyweightProgressesByReps() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(0, 12), Self.set(0, 12)], increment: 0)
        )

        // "Add 0 kg" is a card that changes nothing while claiming to.
        #expect(proposal.action == .increaseReps)
        #expect(proposal.proposedReps == 13)
        #expect(proposal.changesAnything)
    }

    @Test("With no load increment, backing off means fewer reps")
    func bodyweightBacksOffByReps() {
        let proposal = ProgressionEngine.propose(
            Self.input(sets: [Self.set(0, 12), Self.set(0, 4, done: false)], increment: 0)
        )

        #expect(proposal.action == .repeatSame)
        #expect(proposal.proposedWeight == 0)
    }

    // MARK: Increments match the equipment

    @Test("Load steps match what the equipment can actually do")
    func incrementsAreRealistic() {
        func exercise(_ equipment: ExerciseEquipment) -> Exercise {
            var e = Exercise(name: "X", muscle: "Chest", kind: .weight)
            e.equipment = equipment
            return e
        }

        // Advising 2.5 kg on a fixed dumbbell rack that jumps in 2s produces a
        // number nobody can act on.
        #expect(ProgressionEngine.increment(for: exercise(.barbell)) == 2.5)
        #expect(ProgressionEngine.increment(for: exercise(.dumbbell)) == 2.0)
        #expect(ProgressionEngine.increment(for: exercise(.kettlebell)) == 4.0)
        #expect(ProgressionEngine.increment(for: exercise(.bodyweight)) == 0)
    }

    // MARK: Every proposal renders

    @Test("Before and after are always both present")
    func beforeAndAfterAlwaysRender() {
        let cases: [[ProgressionEngine.SetResult]] = [
            [Self.set(70, 12), Self.set(70, 12)],
            [Self.set(70, 9)],
            [Self.set(70, 6)],
            [Self.set(70, 12, done: false)],
        ]

        // A preview shows before → after for every outcome, so no case may
        // leave either side unset.
        for sets in cases {
            let proposal = ProgressionEngine.propose(Self.input(sets: sets))
            #expect(proposal.currentReps >= 0)
            #expect(proposal.proposedReps >= 0)
            #expect(!proposal.evidence.isEmpty)
        }
    }
}

// MARK: - Substitution

/// The candidate list, which Gemini may rank but never extend.
struct SubstitutionEngineTests {

    static var library: [Exercise] { WorkoutResolverTests.library }

    static func request(
        replacing id: String,
        library: [Exercise]? = nil,
        inWorkout: Set<String> = [],
        excluded: Set<BlueprintMuscle> = [],
        equipment: Set<ExerciseEquipment> = [],
        trained: Set<String> = []
    ) -> SubstitutionEngine.Request {
        let all = library ?? Self.library
        return SubstitutionEngine.Request(
            replacing: all.first { $0.id == id }!,
            library: all,
            idsInWorkout: inWorkout,
            excludedMuscles: excluded,
            availableEquipment: equipment,
            trainedIds: trained
        )
    }

    @Test("The exercise being replaced is never its own substitute")
    func neverSuggestsItself() {
        let candidates = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
        #expect(!candidates.contains { $0.exercise.id == "ex-bench" })
    }

    @Test("Exercises already in the workout are not offered")
    func skipsWhatIsAlreadyThere() {
        let candidates = SubstitutionEngine.candidates(
            for: Self.request(replacing: "ex-bench", inWorkout: ["ex-db-press"])
        )
        #expect(!candidates.contains { $0.exercise.id == "ex-db-press" })
    }

    @Test("Same muscle and movement ranks above a distant relative")
    func closestMatchRanksFirst() {
        let candidates = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))

        // Dumbbell bench is the same muscle and the same compound pattern.
        #expect(candidates.first?.exercise.id == "ex-db-press")
        #expect(candidates.first?.reasons.contains { $0.contains("chest") } == true)
    }

    @Test("An unrelated muscle is never a candidate")
    func unrelatedMusclesAreExcluded() {
        let candidates = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))

        // A calf raise is not a substitute for a bench press however
        // conveniently it might score.
        #expect(!candidates.contains { $0.exercise.muscle == "Legs" })
        #expect(!candidates.contains { $0.exercise.muscle == "Back" })
    }

    @Test("An excluded muscle cannot be reached through a substitution")
    func exclusionsHold() {
        let candidates = SubstitutionEngine.candidates(
            for: Self.request(replacing: "ex-bench", excluded: [.triceps, .shoulders])
        )

        // A model that ignores an exclusion must not be able to route round it
        // by suggesting a swap.
        #expect(!candidates.contains { $0.exercise.muscle == "Triceps" })
        #expect(!candidates.contains { $0.exercise.muscle == "Shoulders" })
    }

    @Test("Unavailable equipment is filtered, not merely penalised")
    func equipmentIsAHardFilter() {
        let candidates = SubstitutionEngine.candidates(
            for: Self.request(replacing: "ex-bench", equipment: [.dumbbell])
        )
        #expect(candidates.allSatisfy { $0.exercise.equipment == .dumbbell })
    }

    @Test("Familiarity lifts a candidate you've actually trained")
    func familiarityCounts() {
        let untrained = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
        let trained = SubstitutionEngine.candidates(
            for: Self.request(replacing: "ex-bench", trained: ["ex-fly"])
        )

        let untrainedFlyScore = untrained.first { $0.exercise.id == "ex-fly" }?.score ?? 0
        let trainedFlyScore = trained.first { $0.exercise.id == "ex-fly" }?.score ?? 0
        #expect(trainedFlyScore > untrainedFlyScore)
    }

    @Test("Differences are stated, not hidden")
    func differencesAreSurfaced() {
        let candidates = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
        let fly = candidates.first { $0.exercise.id == "ex-fly" }

        // Swapping a compound for an isolation exercise changes what the
        // session is. The user should be told before, not discover after.
        #expect(fly != nil)
        #expect(fly?.differences.contains { $0.contains("Isolation") } == true)
    }

    @Test("The list is bounded")
    func listIsBounded() {
        let candidates = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
        #expect(candidates.count <= SubstitutionEngine.maximumCandidates)
    }

    @Test("Ordering is deterministic")
    func orderingIsStable() {
        let first = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
        for _ in 0..<5 {
            let again = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
            #expect(first.map(\.exercise.id) == again.map(\.exercise.id))
        }
    }

    // MARK: Applying a swap

    @Test("A carried-over load is reset, because it means nothing on a new movement")
    func loadResetsOnSubstitution() {
        let candidates = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
        var prescription = RoutineExercise(exerciseId: "ex-bench")
        prescription.defaultWeight = 80

        let updated = SubstitutionEngine.substituted(
            prescription,
            with: candidates.first!,
            replacing: Self.library.first { $0.id == "ex-bench" }!
        )

        // 80 kg on a barbell bench is not 80 kg on a dumbbell press, and
        // carrying it across is at best meaningless.
        #expect(updated.defaultWeight == 0)
        #expect(updated.exerciseId == candidates.first!.exercise.id)
    }

    @Test("Swapping a compound for an isolation exercise moves the rep range")
    func repRangeFollowsTheMovement() {
        let candidates = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
        guard let fly = candidates.first(where: { $0.exercise.id == "ex-fly" }) else {
            Issue.record("expected the cable fly to be a candidate")
            return
        }

        var prescription = RoutineExercise(exerciseId: "ex-bench")
        prescription.repRangeMin = 6
        prescription.repRangeMax = 8

        let updated = SubstitutionEngine.substituted(
            prescription, with: fly,
            replacing: Self.library.first { $0.id == "ex-bench" }!
        )

        // Eight reps of a compound and eight of an isolation exercise are not
        // the same ask.
        #expect(updated.repRangeMin >= 10)
        #expect(updated.repRangeMax >= 15)
    }

    @Test("Sets and rest carry over unchanged")
    func setsAndRestSurvive() {
        let candidates = SubstitutionEngine.candidates(for: Self.request(replacing: "ex-bench"))
        var prescription = RoutineExercise(exerciseId: "ex-bench")
        prescription.defaultSets = 5
        prescription.restSeconds = 180

        let updated = SubstitutionEngine.substituted(
            prescription, with: candidates.first!,
            replacing: Self.library.first { $0.id == "ex-bench" }!
        )

        #expect(updated.defaultSets == 5)
        #expect(updated.restSeconds == 180)
    }
}

// MARK: - Machine matching

/// Turning a photographed machine into an exercise — the one place model output
/// may become a permanent record.
///
/// The matching is pure, so it is testable without a camera. The rule that
/// matters most is the last one: a miss produces a *draft*, never a write.
struct MachineMatcherTests {

    static var library: [Exercise] { WorkoutResolverTests.library }

    static func identification(
        _ name: String,
        muscle: BlueprintMuscle = .chest,
        equipment: ExerciseEquipment = .machine,
        confidence: Int = 80
    ) -> MachineIdentification {
        MachineIdentification(name: name, muscle: muscle, equipment: equipment, confidence: confidence)
    }

    @Test("An exact name match finds the library exercise")
    func exactNameMatches() {
        let outcome = MachineMatcher.match(
            Self.identification("Barbell Bench Press", equipment: .barbell),
            library: Self.library
        )
        #expect(outcome == .matched(Self.library.first { $0.id == "ex-bench" }!))
    }

    @Test("Punctuation and case don't prevent a match")
    func matchingIsNormalised() {
        let outcome = MachineMatcher.match(
            Self.identification("barbell bench-press", equipment: .barbell),
            library: Self.library
        )
        if case .matched(let exercise) = outcome {
            #expect(exercise.id == "ex-bench")
        } else {
            Issue.record("expected a match")
        }
    }

    @Test("A library name inside a longer scanned name still matches")
    func containmentMatchesInTheSafeDirection() {
        // "Cybex Lat Pulldown Machine" contains "Lat Pulldown".
        let outcome = MachineMatcher.match(
            Self.identification("Cybex Lat Pulldown Machine", muscle: .back, equipment: .cable),
            library: Self.library
        )
        if case .matched(let exercise) = outcome {
            #expect(exercise.id == "ex-pulldown")
        } else {
            Issue.record("expected a match")
        }
    }

    @Test("A short fragment does not match indiscriminately")
    func shortFragmentsDoNotMatch() {
        // "Row" appears inside three library names. Matching on it would pick
        // one at random and put the wrong exercise in a workout.
        let outcome = MachineMatcher.match(
            Self.identification("Row", muscle: .back, equipment: .machine),
            library: Self.library
        )
        if case .draft = outcome {
            // Correct — ambiguous, so it asks.
        } else {
            Issue.record("a three-letter fragment should not resolve to an exercise")
        }
    }

    @Test("Muscle and equipment together can resolve a single candidate")
    func shapeMatchesWhenUnambiguous() {
        // Exactly one Legs + machine exercise in the fixture library.
        let outcome = MachineMatcher.match(
            Self.identification("Unknown Leg Machine", muscle: .legs, equipment: .machine),
            library: Self.library
        )
        if case .matched(let exercise) = outcome {
            #expect(exercise.id == "ex-legpress")
        } else {
            Issue.record("expected the leg press")
        }
    }

    @Test("Two candidates of the same shape are a guess, so it asks instead")
    func ambiguousShapeProducesADraft() {
        var extra = WorkoutResolverTests.exercise(
            "ex-hacksquat", "Hack Squat", "Legs", equipment: .machine
        )
        extra.isCustom = true

        let outcome = MachineMatcher.match(
            Self.identification("Unknown Leg Machine", muscle: .legs, equipment: .machine),
            library: Self.library + [extra]
        )
        if case .draft = outcome {
            // Correct. A guess here adds the wrong exercise to a workout.
        } else {
            Issue.record("two candidates should not resolve to one")
        }
    }

    @Test("A miss produces a draft, and the draft is not an entry")
    func missProducesADraftNotARecord() {
        let library = Self.library
        let outcome = MachineMatcher.match(
            Self.identification("Reverse Hyper", muscle: .glutes, equipment: .machine),
            library: library
        )

        guard case .draft(let draft) = outcome else {
            Issue.record("expected a draft")
            return
        }
        #expect(draft.name == "Reverse Hyper")
        // The whole point. `importFromText` appends an Exercise mid-parse;
        // nothing on this path may.
        #expect(library.count == Self.library.count)
    }

    @Test("A drafted exercise is always marked custom")
    func draftsAreCustom() {
        let exercise = MachineMatcher.draftExercise(
            from: Self.identification("Reverse Hyper", muscle: .glutes)
        )
        // So an exercise that arrived by camera stays distinguishable from a
        // seeded one for as long as it exists.
        #expect(exercise.isCustom)
        #expect(exercise.muscle == "Glutes")
    }

    @Test("A bodyweight identification becomes a bodyweight exercise")
    func bodyweightKindFollowsEquipment() {
        let exercise = MachineMatcher.draftExercise(
            from: Self.identification("Dip Station", muscle: .triceps, equipment: .bodyweight)
        )
        #expect(exercise.kind == .bodyweight)
    }

    @Test("An unknown muscle from the model throws rather than defaulting")
    func unknownMuscleThrows() {
        let json = """
        {"name":"Something","muscle":"Forearms","equipment":"machine","confidence":80}
        """.data(using: .utf8)!

        #expect(throws: BlueprintError.self) {
            try JSONDecoder().decode(MachineIdentification.self, from: json)
        }
    }

    @Test("A well-formed identification decodes")
    func validIdentificationDecodes() throws {
        let json = """
        {"name":"Lat Pulldown","muscle":"Back","equipment":"cable",
         "movementType":"compound","confidence":92}
        """.data(using: .utf8)!

        let identification = try JSONDecoder().decode(MachineIdentification.self, from: json)
        #expect(identification.muscle == .back)
        #expect(identification.equipment == .cable)
        #expect(identification.confidence == 92)
    }
}

// MARK: - Builder conversation

/// The interview that produces a brief.
///
/// The app asks and Gemini builds, which is what makes these testable at all —
/// the script is data, so the flow can be checked without a view or a network.
struct BuilderConversationTests {

    @Test("A workout doesn't ask about scheduling, and a programme does")
    func scriptsDifferByKind() {
        let workout = BuilderConversation.script(for: .workout)
        let plan = BuilderConversation.script(for: .plan)

        #expect(!workout.contains(.daysPerWeek))
        #expect(!workout.contains(.weeks))
        #expect(plan.contains(.daysPerWeek))
        #expect(plan.contains(.weeks))
        // How you feel today says nothing about week three.
        #expect(workout.contains(.energy))
        #expect(!plan.contains(.energy))
    }

    @Test("Both scripts ask what equipment is available")
    func everyScriptAsksAboutEquipment() {
        // The one field the resolver cannot work without. A model steering its
        // own interview would sometimes skip it; a fixed script can't.
        #expect(BuilderConversation.script(for: .workout).contains(.equipment))
        #expect(BuilderConversation.script(for: .plan).contains(.equipment))
    }

    @Test("Tapping a chip sets the value")
    func chipsSetValues() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(answer: "", chips: ["strength"], for: .goal, to: &brief)
        #expect(brief.goal == .strength)
    }

    @Test("A number in prose is understood")
    func freeTextNumbersParse() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(answer: "about 40 minutes", chips: [], for: .duration, to: &brief)

        // Refusing this because it wasn't one of the chips would be the app
        // being difficult on purpose.
        #expect(brief.availableMinutes == 40)
    }

    @Test("A goal named in prose is understood")
    func freeTextGoalsParse() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(answer: "I want to get stronger", chips: [], for: .goal, to: &brief)
        #expect(brief.goal == .strength)
    }

    @Test("Absurd numbers are clamped rather than accepted")
    func numbersAreClamped() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(answer: "600", chips: [], for: .duration, to: &brief)
        #expect(brief.availableMinutes == 180)

        BuilderConversation.apply(answer: "40", chips: [], for: .daysPerWeek, to: &brief)
        #expect(brief.daysPerWeek == 6)

        BuilderConversation.apply(answer: "99", chips: [], for: .weeks, to: &brief)
        #expect(brief.weeks == 12)
    }

    @Test("Text that doesn't parse is kept rather than dropped")
    func unparseableTextSurvives() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(
            answer: "my left shoulder is sore", chips: ["dumbbell"], for: .equipment, to: &brief
        )

        // Someone who says that while answering the equipment question has said
        // something that matters, and the builder should hear it.
        #expect(brief.availableEquipment == [.dumbbell])
        #expect(brief.text.contains("shoulder"))
    }

    @Test("Notes accumulate in the order they were said")
    func notesAccumulate() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(answer: "bad knee", chips: [], for: .avoid, to: &brief)
        BuilderConversation.apply(answer: "race in June", chips: [], for: .anythingElse, to: &brief)

        #expect(brief.text.contains("bad knee"))
        #expect(brief.text.contains("race in June"))
    }

    @Test("Multiple chips all land")
    func multipleChipsApply() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(
            answer: "", chips: ["dumbbell", "bodyweight"], for: .equipment, to: &brief
        )
        #expect(brief.availableEquipment == [.dumbbell, .bodyweight])
    }

    @Test("Exclusions from the conversation reach the brief")
    func exclusionsApply() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(answer: "", chips: ["Legs", "Calves"], for: .avoid, to: &brief)
        #expect(brief.avoidMuscles == [.legs, .calves])
    }

    @Test("The coach says the answer back in the app's own words")
    func acknowledgementsRepeatTheAnswer() {
        var brief = WorkoutBrief()
        BuilderConversation.apply(answer: "45", chips: [], for: .duration, to: &brief)

        // This is how someone catches "45" being read as 45 weeks before a
        // programme gets built on it.
        let ack = BuilderConversation.acknowledgement(for: .duration, brief: brief)
        #expect(ack?.contains("45") == true)
        #expect(ack?.contains("minutes") == true)
    }

    @Test("Skipping equipment says a full gym is assumed")
    func skippingEquipmentIsExplained() {
        let brief = WorkoutBrief()
        let ack = BuilderConversation.acknowledgement(for: .equipment, brief: brief)
        #expect(ack?.contains("full gym") == true)
    }

    @Test("Every step in every script has a question")
    func everyStepIsAnswerable() {
        for kind in [BuilderConversation.BuilderKind.workout, .plan] {
            for stepKind in BuilderConversation.script(for: kind) {
                let step = BuilderConversation.step(stepKind, for: kind)
                #expect(!step.question.isEmpty)
                // A step with no chips must accept typing, or it's a dead end.
                #expect(!step.chips.isEmpty || step.allowsFreeText)
            }
        }
    }
}
