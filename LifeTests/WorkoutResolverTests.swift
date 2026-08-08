import Testing
import Foundation
@testable import Life

/// The resolver, which is where "Gemini cannot invent an exercise" stops being a
/// promise and becomes a property of the code.
///
/// These are deliberately pure — no transport, no `AppState`, no clock. The
/// resolver is the riskiest logic in the training feature and the only part that
/// can be fully verified without a simulator, so it is verified hardest.
///
/// The assertion that matters most is `noExerciseForMuscleDropsTheSlot`: it
/// checks the library array is *unchanged* afterwards. That is the anti-
/// `importFromText` test — the CSV importer appends a custom `Exercise` when a
/// name doesn't match, and nothing on the model path may ever do that.
struct WorkoutResolverTests {

    // MARK: A small, fully-known library

    static func exercise(
        _ id: String,
        _ name: String,
        _ muscle: String,
        equipment: ExerciseEquipment = .barbell,
        movement: MovementType = .compound,
        difficulty: Int = 2
    ) -> Exercise {
        var e = Exercise(id: id, name: name, muscle: muscle, kind: .weight)
        e.equipment = equipment
        e.movementType = movement
        e.difficulty = difficulty
        return e
    }

    /// Twelve exercises, chosen so every branch below has something to bite on:
    /// two chest movements with different equipment, a muscle with exactly one
    /// exercise, and a muscle with none at all (Cardio).
    static let library: [Exercise] = [
        exercise("ex-bench", "Barbell Bench Press", "Chest", equipment: .barbell, difficulty: 2),
        exercise("ex-db-press", "Dumbbell Bench Press", "Chest", equipment: .dumbbell, difficulty: 1),
        exercise("ex-fly", "Cable Fly", "Chest", equipment: .cable, movement: .isolation, difficulty: 1),
        exercise("ex-row", "Barbell Row", "Back", equipment: .barbell, difficulty: 2),
        exercise("ex-pulldown", "Lat Pulldown", "Back", equipment: .cable, difficulty: 1),
        exercise("ex-squat", "Back Squat", "Legs", equipment: .barbell, difficulty: 3),
        exercise("ex-legpress", "Leg Press", "Legs", equipment: .machine, difficulty: 1),
        exercise("ex-curl", "Barbell Curl", "Biceps", equipment: .barbell, movement: .isolation, difficulty: 1),
        exercise("ex-pushdown", "Tricep Pushdown", "Triceps", equipment: .cable, movement: .isolation, difficulty: 1),
        exercise("ex-ohp", "Overhead Press", "Shoulders", equipment: .barbell, difficulty: 2),
        exercise("ex-plank", "Plank", "Core", equipment: .bodyweight, movement: .isolation, difficulty: 1),
        exercise("ex-hipthrust", "Hip Thrust", "Glutes", equipment: .barbell, difficulty: 2),
    ]

    static func inputs(
        library: [Exercise] = WorkoutResolverTests.library,
        history: [String: Double] = [:],
        favourites: Set<String> = [],
        inRoutines: Set<String> = [],
        excluded: Set<BlueprintMuscle> = [],
        equipment: Set<ExerciseEquipment> = []
    ) -> WorkoutResolver.Inputs {
        WorkoutResolver.Inputs(
            library: library,
            history: history,
            favouriteIds: favourites,
            idsInExistingRoutines: inRoutines,
            excludedMuscles: excluded,
            availableEquipment: equipment
        )
    }

    static func slot(
        _ muscle: BlueprintMuscle,
        equipment: ExerciseEquipment? = nil,
        movement: MovementType? = nil,
        sets: Int = 3,
        repMin: Int = 8,
        repMax: Int = 12,
        rest: Int = 90,
        rir: Int? = nil,
        superset: Int? = nil
    ) -> WorkoutSlot {
        WorkoutSlot(
            muscle: muscle, equipment: equipment, movementType: movement,
            sets: sets, repMin: repMin, repMax: repMax,
            restSeconds: rest, rir: rir, supersetGroup: superset
        )
    }

    static func blueprint(_ slots: [WorkoutSlot], name: String = "Upper Body") -> WorkoutBlueprint {
        WorkoutBlueprint(name: name, focus: "Strength", slots: slots, notes: nil)
    }

    // MARK: Determinism

    @Test("The same blueprint and library always give the same workout")
    func resolutionIsDeterministic() {
        let plan = Self.blueprint([
            Self.slot(.chest), Self.slot(.back), Self.slot(.legs), Self.slot(.core),
        ])

        // Run it repeatedly. Every other test here is worthless if this isn't
        // true — and the tie-break on id is the only thing making it so, since
        // two equally-scored exercises would otherwise resolve in array order.
        let first = WorkoutResolver.resolve(plan, inputs: Self.inputs())
        for _ in 0..<5 {
            #expect(WorkoutResolver.resolve(plan, inputs: Self.inputs()) == first)
        }
    }

    // MARK: Never inventing an exercise

    @Test("A muscle with no exercises drops the slot and leaves the library alone")
    func noExerciseForMuscleDropsTheSlot() {
        // Cardio is deliberately absent and has no related-muscle fallback.
        let plan = Self.blueprint([
            Self.slot(.chest), Self.slot(.back), Self.slot(.cardio), Self.slot(.core),
        ])
        let inputs = Self.inputs()
        let libraryBefore = inputs.library

        let workout = WorkoutResolver.resolve(plan, inputs: inputs)

        #expect(workout.items.count == 3)
        #expect(!workout.items.contains { $0.slotMuscle == .cardio })
        #expect(workout.notes.contains(.noExerciseForMuscle(.cardio)))

        // The assertion this whole file exists for. `importFromText` appends a
        // custom Exercise on a name miss; nothing on the model path may.
        #expect(inputs.library == libraryBefore)
        #expect(inputs.library.count == 12)
    }

    @Test("Every resolved exercise id is one that was in the library")
    func everyPickIsReal() {
        let plan = Self.blueprint([
            Self.slot(.chest), Self.slot(.back), Self.slot(.legs),
            Self.slot(.shoulders), Self.slot(.biceps), Self.slot(.triceps),
        ])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())
        let realIds = Set(Self.library.map(\.id))

        for item in workout.items {
            #expect(realIds.contains(item.exercise.id))
            #expect(item.prescription.exerciseId == item.exercise.id)
        }
    }

    @Test("A session named after a real exercise is renamed")
    func sessionNameCannotBeAMovement() {
        let plan = Self.blueprint(
            [Self.slot(.chest), Self.slot(.back), Self.slot(.legs)],
            name: "Barbell Bench Press"
        )
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        // The server checks the slots; only this side holds the library, so only
        // this side can catch a *session* named after a movement.
        #expect(workout.name != "Barbell Bench Press")
        #expect(workout.notes.contains(.nameLookedLikeAnExercise("Barbell Bench Press")))
    }

    // MARK: Equipment

    @Test("A slot's equipment preference is honoured when it can be")
    func equipmentPreferenceIsHonoured() {
        let plan = Self.blueprint([Self.slot(.chest, equipment: .dumbbell)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        #expect(workout.items.first?.exercise.id == "ex-db-press")
        #expect(workout.items.first?.substitutedEquipment == false)
    }

    @Test("Unavailable equipment substitutes, and says so")
    func equipmentSubstitutionIsFlagged() {
        // Kettlebells: nothing in the library has them.
        let plan = Self.blueprint([Self.slot(.chest, equipment: .kettlebell)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        #expect(workout.items.count == 1)
        // Substituted rather than dropped — the person still wants to train
        // their chest — but never silently. They asked for kettlebells for a
        // reason and the preview shows a badge.
        #expect(workout.items.first?.substitutedEquipment == true)
        #expect(workout.notes.contains {
            if case .equipmentUnavailable(_, .kettlebell, _) = $0 { return true }
            return false
        })
    }

    @Test("Equipment the user doesn't own is a hard filter, not a preference")
    func unavailableEquipmentIsExcludedEntirely() {
        // Training at home with dumbbells only. A cable fly is not a near miss.
        let plan = Self.blueprint([Self.slot(.chest), Self.slot(.back)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs(equipment: [.dumbbell]))

        #expect(workout.items.allSatisfy { $0.exercise.equipment == .dumbbell })
        // Back has no dumbbell exercise in the fixture, so that slot goes.
        #expect(workout.notes.contains(.noExerciseForMuscle(.back)))
    }

    // MARK: Duplicates and exclusions

    @Test("Two slots for the same muscle give two different exercises")
    func duplicateSlotsPickDifferentExercises() {
        let plan = Self.blueprint([Self.slot(.chest), Self.slot(.chest), Self.slot(.back)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        let ids = workout.items.map(\.exercise.id)
        #expect(ids.count == Set(ids).count)
        #expect(workout.items.filter { $0.slotMuscle == .chest }.count == 2)
    }

    @Test("A repeated slot with nothing left to pick is dropped, not duplicated")
    func exhaustedMusclesDropTheRepeat() {
        let onlyOneChest = [
            Self.exercise("ex-bench", "Barbell Bench Press", "Chest"),
            Self.exercise("ex-row", "Barbell Row", "Back"),
            Self.exercise("ex-squat", "Back Squat", "Legs"),
        ]
        let plan = Self.blueprint([
            Self.slot(.chest), Self.slot(.chest), Self.slot(.back), Self.slot(.legs),
        ])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs(library: onlyOneChest))

        // A shorter honest session beats the same exercise listed twice.
        #expect(workout.items.count == 3)
        #expect(workout.notes.contains(.slotDroppedAsDuplicate(.chest)))
    }

    @Test("An excluded muscle is refused even when the model asks for it")
    func excludedMusclesAreRefused() {
        let plan = Self.blueprint([Self.slot(.chest), Self.slot(.legs), Self.slot(.back)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs(excluded: [.legs]))

        // The prompt asks; this enforces. A model that ignores an exclusion must
        // not be able to put a squat in front of someone with a bad knee.
        #expect(!workout.items.contains { $0.slotMuscle == .legs })
        #expect(workout.notes.contains(.slotDroppedAsExcluded(.legs)))
    }

    @Test("A missing muscle borrows from a related one rather than giving up")
    func relatedMuscleFallback() {
        let noGlutes = Self.library.filter { $0.muscle != "Glutes" }
        let plan = Self.blueprint([Self.slot(.glutes), Self.slot(.chest), Self.slot(.back)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs(library: noGlutes))

        // Legs train glutes. Borrowing is better than an empty slot — but the
        // swap is stated, not hidden.
        #expect(workout.items.count == 3)
        #expect(workout.notes.contains(.borrowedFromRelated(requested: .glutes, used: .legs)))
    }

    // MARK: Clamping model output

    @Test("Absurd numbers from the model are clamped, not trusted")
    func numbersAreClamped() {
        let plan = Self.blueprint([
            Self.slot(.chest, sets: 99, repMin: 1, repMax: 999, rest: 9999, rir: 40),
        ])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())
        let prescription = workout.items.first!.prescription

        // A schema constrains generation; it does not guarantee the result.
        // Same belt-and-braces as the water proposal's min(max(count, 1), 8).
        #expect(prescription.defaultSets == 6)
        #expect(prescription.repRangeMax == 50)
        #expect(prescription.restSeconds == 300)
        #expect(workout.items.first?.rir == 5)
    }

    @Test("A rep range that runs backwards is repaired, not rejected")
    func backwardsRepRangeIsRepaired() {
        let plan = Self.blueprint([Self.slot(.chest, repMin: 20, repMax: 5)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())
        let prescription = workout.items.first!.prescription

        #expect(prescription.repRangeMin <= prescription.repRangeMax)
        #expect(prescription.repRangeMin == 20)
        #expect(prescription.repRangeMax == 20)
    }

    // MARK: Supersets

    @Test("Slots sharing a superset number share a group id")
    func supersetsAreGrouped() {
        let plan = Self.blueprint([
            Self.slot(.biceps, superset: 1),
            Self.slot(.triceps, superset: 1),
            Self.slot(.chest, superset: 2),
            Self.slot(.back),
        ])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        let groups = workout.items.map(\.prescription.supersetGroupId)
        #expect(groups[0] != nil)
        #expect(groups[0] == groups[1])
        #expect(groups[2] != groups[0])
        #expect(groups[3] == nil)
    }

    // MARK: History

    @Test("A known working weight becomes the starting load")
    func historySuppliesStartingWeight() {
        let plan = Self.blueprint([Self.slot(.chest, equipment: .barbell)])
        let workout = WorkoutResolver.resolve(
            plan, inputs: Self.inputs(history: ["ex-bench": 72.5])
        )

        // The one number the app can supply and the model cannot.
        #expect(workout.items.first?.prescription.defaultWeight == 72.5)
    }

    @Test("With no history the starting load stays at zero")
    func noHistoryMeansNoGuessedWeight() {
        let plan = Self.blueprint([Self.slot(.chest)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        // A starting weight guessed from nothing is a number someone gets under
        // a bar with. RIR carries the effort instead.
        #expect(workout.items.first?.prescription.defaultWeight == 0)
    }

    @Test("A movement they have trained beats one they haven't, all else equal")
    func historyBreaksTiesTowardsFamiliarity() {
        // Both chest barbell/dumbbell candidates; history should pull the
        // dumbbell one up past the default ordering.
        let plan = Self.blueprint([Self.slot(.chest)])
        let withHistory = WorkoutResolver.resolve(
            plan, inputs: Self.inputs(history: ["ex-db-press": 30])
        )
        #expect(withHistory.items.first?.exercise.id == "ex-db-press")
    }

    // MARK: Viability and duration

    @Test("Fewer than three exercises is not a viable workout")
    func tooFewItemsIsNotViable() {
        let tiny = [Self.exercise("ex-bench", "Barbell Bench Press", "Chest")]
        let plan = Self.blueprint([Self.slot(.chest), Self.slot(.back)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs(library: tiny))

        #expect(workout.items.count == 1)
        #expect(workout.isViable == false)
    }

    @Test("Duration is computed from the prescription, not taken from the model")
    func durationIsComputed() {
        // 3 sets x (10 reps x 3s + 90s rest) = 360s, plus 60s overhead = 7 min.
        let plan = Self.blueprint([Self.slot(.chest, sets: 3, repMin: 10, repMax: 10, rest: 90)])
        let workout = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        #expect(workout.estimatedMinutes == 7)
    }

    @Test("A longer session estimates longer")
    func durationScalesWithWork() {
        let short = Self.blueprint([Self.slot(.chest, sets: 2, rest: 60)])
        let long = Self.blueprint([
            Self.slot(.chest, sets: 5, rest: 180), Self.slot(.back, sets: 5, rest: 180),
        ])

        let shortWorkout = WorkoutResolver.resolve(short, inputs: Self.inputs())
        let longWorkout = WorkoutResolver.resolve(long, inputs: Self.inputs())
        #expect(longWorkout.estimatedMinutes > shortWorkout.estimatedMinutes)
    }

    // MARK: Plans

    @Test("A plan resolves each session and schedules the weekdays it named")
    func planResolvesAndSchedules() {
        let plan = PlanBlueprint(
            name: "Upper / Lower",
            weeks: 4,
            sessions: [
                PlanSession(key: "upper", blueprint: Self.blueprint(
                    [Self.slot(.chest), Self.slot(.back), Self.slot(.shoulders)], name: "Upper"
                )),
                PlanSession(key: "lower", blueprint: Self.blueprint(
                    [Self.slot(.legs), Self.slot(.glutes), Self.slot(.core)], name: "Lower"
                )),
            ],
            weekdays: [
                PlanWeekday(weekday: 1, sessionKey: "upper"),
                PlanWeekday(weekday: 3, sessionKey: "lower"),
                PlanWeekday(weekday: 5, sessionKey: "upper"),
            ],
            progression: "Add a rep each week."
        )

        let resolved = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        #expect(resolved.sessions.count == 2)
        #expect(resolved.schedule == [1: "upper", 3: "lower", 5: "upper"])
        #expect(resolved.weeks == 4)
        #expect(resolved.sessionCount == 12)
        #expect(resolved.isViable)
    }

    @Test("A weekday naming a session that doesn't exist is dropped")
    func danglingSessionKeysAreDropped() {
        let plan = PlanBlueprint(
            name: "Broken",
            weeks: 2,
            sessions: [
                PlanSession(key: "upper", blueprint: Self.blueprint(
                    [Self.slot(.chest), Self.slot(.back), Self.slot(.shoulders)]
                )),
            ],
            weekdays: [
                PlanWeekday(weekday: 1, sessionKey: "upper"),
                PlanWeekday(weekday: 3, sessionKey: "ghost"),
            ],
            progression: nil
        )

        let resolved = WorkoutResolver.resolve(plan, inputs: Self.inputs())

        // Checked server-side too, but both sides of the reference are in the
        // response and this side is what actually schedules.
        #expect(resolved.schedule == [1: "upper"])
    }

    @Test("Sessions on consecutive days avoid repeating the same movement")
    func adjacentDaysAvoidRepeats() {
        // Two chest sessions back to back. Monday should take one chest
        // exercise, Tuesday a different one.
        let session = Self.blueprint([Self.slot(.chest), Self.slot(.back), Self.slot(.core)])
        let plan = PlanBlueprint(
            name: "Back to back",
            weeks: 1,
            sessions: [
                PlanSession(key: "a", blueprint: session),
                PlanSession(key: "b", blueprint: session),
            ],
            weekdays: [
                PlanWeekday(weekday: 1, sessionKey: "a"),
                PlanWeekday(weekday: 2, sessionKey: "b"),
            ],
            progression: nil
        )

        let resolved = WorkoutResolver.resolve(plan, inputs: Self.inputs())
        let chestA = resolved.sessions[0].workout.items.first { $0.slotMuscle == .chest }
        let chestB = resolved.sessions[1].workout.items.first { $0.slotMuscle == .chest }

        #expect(chestA != nil)
        #expect(chestB != nil)
        #expect(chestA?.exercise.id != chestB?.exercise.id)
    }

    @Test("The same missing muscle across four sessions is reported once")
    func planNotesAreDeduplicated() {
        let session = Self.blueprint([Self.slot(.cardio), Self.slot(.chest), Self.slot(.back)])
        let plan = PlanBlueprint(
            name: "Repeats",
            weeks: 1,
            sessions: (1...4).map { PlanSession(key: "s\($0)", blueprint: session) },
            weekdays: (1...4).map { PlanWeekday(weekday: $0, sessionKey: "s\($0)") },
            progression: nil
        )

        let resolved = WorkoutResolver.resolve(plan, inputs: Self.inputs())
        let missingNotes = resolved.notes.filter { $0 == .noExerciseForMuscle(.cardio) }

        // A fact repeated is still one fact.
        #expect(missingNotes.count == 1)
    }

    @Test("Weeks are clamped to something schedulable")
    func planWeeksAreClamped() {
        let session = Self.blueprint([Self.slot(.chest), Self.slot(.back), Self.slot(.core)])
        let absurd = PlanBlueprint(
            name: "Forever", weeks: 500,
            sessions: [PlanSession(key: "a", blueprint: session)],
            weekdays: [PlanWeekday(weekday: 1, sessionKey: "a")],
            progression: nil
        )

        #expect(WorkoutResolver.resolve(absurd, inputs: Self.inputs()).weeks == 12)
    }

    // MARK: Decoding is strict

    @Test("An unknown muscle throws rather than defaulting")
    func unknownMuscleThrows() throws {
        let json = """
        {"muscle":"Forearms","sets":3,"repMin":8,"repMax":12,"restSeconds":90}
        """.data(using: .utf8)!

        // A default here would silently produce a workout for a body part nobody
        // asked about. Throwing sends it back for one repair attempt instead.
        #expect(throws: BlueprintError.self) {
            try JSONDecoder().decode(WorkoutSlot.self, from: json)
        }
    }

    @Test("An unknown equipment value throws")
    func unknownEquipmentThrows() {
        let json = """
        {"muscle":"Chest","equipment":"resistanceSled","sets":3,
         "repMin":8,"repMax":12,"restSeconds":90}
        """.data(using: .utf8)!

        #expect(throws: BlueprintError.self) {
            try JSONDecoder().decode(WorkoutSlot.self, from: json)
        }
    }

    @Test("A well-formed slot decodes")
    func validSlotDecodes() throws {
        let json = """
        {"muscle":"Chest","equipment":"dumbbell","movementType":"compound",
         "sets":4,"repMin":8,"repMax":10,"restSeconds":120,"rir":2}
        """.data(using: .utf8)!

        let slot = try JSONDecoder().decode(WorkoutSlot.self, from: json)
        #expect(slot.muscle == .chest)
        #expect(slot.equipment == .dumbbell)
        #expect(slot.movementType == .compound)
        #expect(slot.rir == 2)
    }

    // MARK: The three vocabularies agree

    @Test("Every muscle in the seeded library is one the blueprint can express")
    func seedAndBlueprintVocabulariesMatch() {
        // Nothing in the compiler keeps `WorkoutSeed`, `BlueprintMuscle` and
        // `functions/src/workoutSchema.ts` in step. A muscle the seed uses but
        // the blueprint cannot name is a muscle the coach can never program for,
        // and the symptom is "it keeps forgetting my calves" rather than an
        // error anyone would notice.
        let seeded = Set(WorkoutSeed.exercises.map(\.muscle))
        let expressible = Set(BlueprintMuscle.allCases.map(\.rawValue))

        #expect(seeded.subtracting(expressible).isEmpty,
                "seed uses muscles the blueprint cannot name: \(seeded.subtracting(expressible))")
        #expect(expressible.subtracting(seeded).isEmpty,
                "blueprint names muscles nothing is seeded for: \(expressible.subtracting(seeded))")
    }
}
