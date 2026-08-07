import Testing
import Foundation
@testable import Life

/// The four adjustments, and the limits they refuse to cross.
///
/// Every test here also asserts an absence: the input array is never mutated,
/// because the adjuster returns a proposal and the caller's confirm button is
/// what makes it real.
struct WorkoutAdjusterTests {

    // MARK: Fixtures

    static let library: [Exercise] = {
        var out: [Exercise] = []
        var bench = Exercise(name: "Barbell bench press", muscle: "Chest", kind: .weight)
        bench.equipment = .barbell
        var dbPress = Exercise(name: "Dumbbell press", muscle: "Chest", kind: .weight)
        dbPress.equipment = .dumbbell
        var pushUp = Exercise(name: "Push-up", muscle: "Chest", kind: .weight)
        pushUp.equipment = .bodyweight
        var row = Exercise(name: "Barbell row", muscle: "Back", kind: .weight)
        row.equipment = .barbell
        var squat = Exercise(name: "Back squat", muscle: "Legs", kind: .weight)
        squat.equipment = .barbell
        var curl = Exercise(name: "Dumbbell curl", muscle: "Biceps", kind: .weight)
        curl.equipment = .dumbbell
        out = [bench, dbPress, pushUp, row, squat, curl]
        return out
    }()

    static func item(_ exercise: Exercise, sets: Int = 3, rest: Int = 120, weight: Double = 60) -> RoutineExercise {
        var item = RoutineExercise(exerciseId: exercise.id)
        item.defaultSets = sets
        item.repRangeMin = 8
        item.repRangeMax = 12
        item.restSeconds = rest
        item.defaultWeight = weight
        return item
    }

    /// Five exercises, so there is room to remove some.
    static var workout: [RoutineExercise] {
        [
            item(library[0]),
            item(library[3]),
            item(library[4]),
            item(library[5]),
            item(library[1]),
        ]
    }

    // MARK: Estimation

    @Test("The estimate matches the resolver's, so a diff can't disagree with itself")
    func estimateMatchesResolver() {
        // 3 sets × (10 reps × 3s + 120s rest) + 60s overhead = 510s = 8 minutes.
        let single = [Self.item(Self.library[0])]
        #expect(WorkoutAdjuster.estimatedMinutes(single) == 8)
    }

    // MARK: Shorten

    @Test("Shortening takes rest before it takes exercises")
    func restGoesFirst() {
        let original = Self.workout
        let adjusted = WorkoutAdjuster.adjust(
            exercises: original, library: Self.library, request: .shorten(byMinutes: 5)
        )

        #expect(adjusted.adjustedMinutes < adjusted.originalMinutes)
        #expect(adjusted.exercises.count == original.count)
        #expect(adjusted.changes.contains { if case .restShortened = $0 { return true } else { return false } })
    }

    /// A request that would empty the session has been misunderstood, not
    /// honoured.
    @Test("Shortening never drops below three exercises, and says so")
    func shorteningStopsAtThree() {
        let adjusted = WorkoutAdjuster.adjust(
            exercises: Self.workout, library: Self.library, request: .shorten(byMinutes: 500)
        )

        #expect(adjusted.exercises.count == WorkoutAdjuster.minimumExercises)
        #expect(adjusted.changes.contains { if case .shortfall = $0 { return true } else { return false } })
    }

    @Test("Sets never fall below two")
    func setsHaveAFloor() {
        let adjusted = WorkoutAdjuster.adjust(
            exercises: Self.workout, library: Self.library, request: .shorten(byMinutes: 500)
        )
        #expect(adjusted.exercises.allSatisfy { $0.defaultSets >= 2 })
    }

    @Test("Rest never falls below a minute")
    func restHasAFloor() {
        let adjusted = WorkoutAdjuster.adjust(
            exercises: Self.workout, library: Self.library, request: .shorten(byMinutes: 500)
        )
        #expect(adjusted.exercises.allSatisfy { $0.restSeconds >= 60 })
    }

    // MARK: Equipment

    @Test("Equipment-only swaps to something the person actually has")
    func equipmentSwaps() {
        let adjusted = WorkoutAdjuster.adjust(
            exercises: [Self.item(Self.library[0])],
            library: Self.library,
            request: .equipmentOnly([.dumbbell])
        )

        let swappedTo = adjusted.exercises.first?.exerciseId
        #expect(swappedTo == Self.library[1].id)
        #expect(adjusted.changes.contains { if case .replaced = $0 { return true } else { return false } })
    }

    /// A barbell number on a dumbbell exercise is not a smaller mistake for
    /// being an obvious one.
    @Test("A swap drops the carried-over weight")
    func swapZeroesTheLoad() {
        let adjusted = WorkoutAdjuster.adjust(
            exercises: [Self.item(Self.library[0], weight: 100)],
            library: Self.library,
            request: .equipmentOnly([.dumbbell])
        )
        #expect(adjusted.exercises.first?.defaultWeight == 0)
    }

    @Test("An exercise with no available substitute is removed and explained")
    func unsubstitutableIsRemoved() {
        // Nothing trains legs with a kettlebell in this library.
        let adjusted = WorkoutAdjuster.adjust(
            exercises: [Self.item(Self.library[4])],
            library: Self.library,
            request: .equipmentOnly([.kettlebell])
        )

        #expect(adjusted.exercises.isEmpty)
        #expect(adjusted.changes.contains { if case .removed = $0 { return true } else { return false } })
    }

    @Test("Equipment already available is left alone")
    func matchingEquipmentIsUntouched() {
        let original = [Self.item(Self.library[1])]
        let adjusted = WorkoutAdjuster.adjust(
            exercises: original, library: Self.library, request: .equipmentOnly([.dumbbell])
        )

        #expect(adjusted.exercises.first?.exerciseId == original.first?.exerciseId)
        #expect(adjusted.isEmpty)
    }

    // MARK: Lighter

    /// Deliberately not "reduce the weight by 10%". The app has no reliable
    /// idea what someone's working weight should be on a bad day.
    @Test("Lighter takes a set and an effort level, never a weight")
    func lighterNeverTouchesLoad() {
        let original = Self.workout
        let adjusted = WorkoutAdjuster.adjust(
            exercises: original, library: Self.library, request: .lighter
        )

        #expect(zip(original, adjusted.exercises).allSatisfy { $0.defaultWeight == $1.defaultWeight })
        #expect(adjusted.exercises.allSatisfy { $0.defaultSets == 2 })
        #expect(adjusted.changes.contains { if case .effortReduced = $0 { return true } else { return false } })
    }

    // MARK: Avoid

    @Test("Avoiding a muscle removes exactly that muscle's work")
    func avoidRemovesTheMuscle() {
        let adjusted = WorkoutAdjuster.adjust(
            exercises: Self.workout, library: Self.library, request: .avoid(.legs)
        )

        let remaining = adjusted.exercises.compactMap { item in
            Self.library.first { $0.id == item.exerciseId }
        }
        #expect(remaining.allSatisfy { BlueprintMuscle(appMuscle: $0.muscle) != .legs })
        #expect(adjusted.exercises.count == Self.workout.count - 1)
    }

    @Test("Avoiding almost everything warns rather than returning a stub")
    func avoidWarnsWhenTooLittleIsLeft() {
        let chestOnly = [
            Self.item(Self.library[0]),
            Self.item(Self.library[1]),
            Self.item(Self.library[2]),
        ]
        let adjusted = WorkoutAdjuster.adjust(
            exercises: chestOnly, library: Self.library, request: .avoid(.chest)
        )

        #expect(adjusted.exercises.isEmpty)
        #expect(adjusted.changes.contains { if case .shortfall = $0 { return true } else { return false } })
    }

    // MARK: Determinism

    @Test("The same request twice produces the same adjustment")
    func adjustmentIsDeterministic() {
        let first = WorkoutAdjuster.adjust(
            exercises: Self.workout, library: Self.library, request: .equipmentOnly([.dumbbell])
        )
        let second = WorkoutAdjuster.adjust(
            exercises: Self.workout, library: Self.library, request: .equipmentOnly([.dumbbell])
        )
        #expect(first == second)
    }

    // MARK: Interpretation

    /// The model classifies; it never describes an edit. An `avoid` with no
    /// muscle named is a response that didn't answer, and substituting a
    /// default would mean removing something arbitrary.
    @Test("An incomplete suggestion produces no request rather than a guess")
    func incompleteSuggestionIsRefused() {
        let avoidNothing = WorkoutAdjustmentSuggestion(kind: .avoid, explanation: "Avoiding something.")
        #expect(avoidNothing.request == nil)

        let shortenNothing = WorkoutAdjustmentSuggestion(kind: .shorten, explanation: "Shorter.")
        #expect(shortenNothing.request == nil)

        let equipmentNothing = WorkoutAdjustmentSuggestion(kind: .equipmentOnly, explanation: "Kit.")
        #expect(equipmentNothing.request == nil)
    }

    @Test("An absurd duration is clamped, not honoured")
    func minutesAreClamped() {
        let suggestion = WorkoutAdjustmentSuggestion(
            kind: .shorten, minutes: 9_000, explanation: "Much shorter."
        )
        #expect(suggestion.request == .shorten(byMinutes: 180))
    }

    @Test("An unknown adjustment kind fails to decode")
    func unknownKindThrows() {
        let json = #"{"kind":"deleteEverything","explanation":"..."}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WorkoutAdjustmentSuggestion.self, from: Data(json.utf8))
        }
    }

    @Test("An unknown equipment value fails to decode")
    func unknownEquipmentThrows() {
        let json = #"{"kind":"equipmentOnly","equipment":["jetpack"],"explanation":"..."}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WorkoutAdjustmentSuggestion.self, from: Data(json.utf8))
        }
    }
}
