import Foundation

// MARK: - Seed Exercises

enum WorkoutSeed {

    static let exercises: [Exercise] = [
        // Chest
        Exercise(id: "ex_bench_press",         name: "Bench Press",           muscle: "Chest",     kind: .weight),
        Exercise(id: "ex_incline_bench",        name: "Incline Bench Press",   muscle: "Chest",     kind: .weight),
        Exercise(id: "ex_decline_bench",        name: "Decline Bench Press",   muscle: "Chest",     kind: .weight),
        Exercise(id: "ex_dumbbell_fly",         name: "Dumbbell Fly",          muscle: "Chest",     kind: .weight),
        Exercise(id: "ex_pushup",               name: "Push-Up",               muscle: "Chest",     kind: .bodyweight),

        // Back
        Exercise(id: "ex_deadlift",             name: "Deadlift",              muscle: "Back",      kind: .weight),
        Exercise(id: "ex_barbell_row",          name: "Barbell Row",           muscle: "Back",      kind: .weight),
        Exercise(id: "ex_pullup",               name: "Pull-Up",               muscle: "Back",      kind: .bodyweight),
        Exercise(id: "ex_lat_pulldown",         name: "Lat Pulldown",          muscle: "Back",      kind: .weight),
        Exercise(id: "ex_seated_cable_row",     name: "Seated Cable Row",      muscle: "Back",      kind: .weight),

        // Shoulders
        Exercise(id: "ex_ohp",                  name: "Overhead Press",        muscle: "Shoulders", kind: .weight),
        Exercise(id: "ex_lateral_raise",        name: "Lateral Raise",         muscle: "Shoulders", kind: .weight),
        Exercise(id: "ex_front_raise",          name: "Front Raise",           muscle: "Shoulders", kind: .weight),
        Exercise(id: "ex_face_pull",            name: "Face Pull",             muscle: "Shoulders", kind: .weight),

        // Biceps
        Exercise(id: "ex_barbell_curl",         name: "Barbell Curl",          muscle: "Biceps",    kind: .weight),
        Exercise(id: "ex_dumbbell_curl",        name: "Dumbbell Curl",         muscle: "Biceps",    kind: .weight),
        Exercise(id: "ex_hammer_curl",          name: "Hammer Curl",           muscle: "Biceps",    kind: .weight),

        // Triceps
        Exercise(id: "ex_skullcrusher",         name: "Skull Crusher",         muscle: "Triceps",   kind: .weight),
        Exercise(id: "ex_tricep_pushdown",      name: "Tricep Pushdown",       muscle: "Triceps",   kind: .weight),
        Exercise(id: "ex_overhead_tricep",      name: "Overhead Tricep Ext",   muscle: "Triceps",   kind: .weight),
        Exercise(id: "ex_dip",                  name: "Dip",                   muscle: "Triceps",   kind: .bodyweight),

        // Legs
        Exercise(id: "ex_squat",                name: "Squat",                 muscle: "Legs",      kind: .weight),
        Exercise(id: "ex_leg_press",            name: "Leg Press",             muscle: "Legs",      kind: .weight),
        Exercise(id: "ex_rdl",                  name: "Romanian Deadlift",     muscle: "Legs",      kind: .weight),
        Exercise(id: "ex_leg_curl",             name: "Leg Curl",              muscle: "Legs",      kind: .weight),
        Exercise(id: "ex_calf_raise",           name: "Calf Raise",            muscle: "Legs",      kind: .weight),
        Exercise(id: "ex_lunge",                name: "Lunge",                 muscle: "Legs",      kind: .bodyweight),

        // Core
        Exercise(id: "ex_plank",                name: "Plank",                 muscle: "Core",      kind: .bodyweight),
        Exercise(id: "ex_crunch",               name: "Crunch",                muscle: "Core",      kind: .bodyweight),

        // Cardio
        Exercise(id: "ex_treadmill",            name: "Treadmill Run",         muscle: "Cardio",    kind: .cardio),
    ]

    static let routines: [Routine] = [
        Routine(
            id: "routine_push_a",
            name: "Push A",
            exercises: [
                RoutineExercise(id: "re1", exerciseId: "ex_bench_press",    defaultSets: 4, defaultReps: 8,  defaultWeight: 60),
                RoutineExercise(id: "re2", exerciseId: "ex_incline_bench",  defaultSets: 3, defaultReps: 10, defaultWeight: 50),
                RoutineExercise(id: "re3", exerciseId: "ex_ohp",            defaultSets: 3, defaultReps: 10, defaultWeight: 40),
                RoutineExercise(id: "re4", exerciseId: "ex_lateral_raise",  defaultSets: 3, defaultReps: 15, defaultWeight: 10),
                RoutineExercise(id: "re5", exerciseId: "ex_tricep_pushdown",defaultSets: 3, defaultReps: 12, defaultWeight: 30),
            ]
        ),
        Routine(
            id: "routine_pull_a",
            name: "Pull A",
            exercises: [
                RoutineExercise(id: "re6",  exerciseId: "ex_deadlift",         defaultSets: 3, defaultReps: 5,  defaultWeight: 100),
                RoutineExercise(id: "re7",  exerciseId: "ex_barbell_row",      defaultSets: 4, defaultReps: 8,  defaultWeight: 60),
                RoutineExercise(id: "re8",  exerciseId: "ex_lat_pulldown",     defaultSets: 3, defaultReps: 10, defaultWeight: 50),
                RoutineExercise(id: "re9",  exerciseId: "ex_seated_cable_row", defaultSets: 3, defaultReps: 12, defaultWeight: 40),
                RoutineExercise(id: "re10", exerciseId: "ex_barbell_curl",     defaultSets: 3, defaultReps: 12, defaultWeight: 20),
                RoutineExercise(id: "re11", exerciseId: "ex_face_pull",        defaultSets: 3, defaultReps: 15, defaultWeight: 15),
            ]
        ),
        Routine(
            id: "routine_legs_a",
            name: "Legs A",
            exercises: [
                RoutineExercise(id: "re12", exerciseId: "ex_squat",     defaultSets: 4, defaultReps: 8,  defaultWeight: 80),
                RoutineExercise(id: "re13", exerciseId: "ex_leg_press", defaultSets: 3, defaultReps: 12, defaultWeight: 120),
                RoutineExercise(id: "re14", exerciseId: "ex_rdl",       defaultSets: 3, defaultReps: 10, defaultWeight: 60),
                RoutineExercise(id: "re15", exerciseId: "ex_leg_curl",  defaultSets: 3, defaultReps: 12, defaultWeight: 30),
                RoutineExercise(id: "re16", exerciseId: "ex_calf_raise",defaultSets: 4, defaultReps: 15, defaultWeight: 40),
            ]
        ),
    ]

    /// Returns the seed exercises list with any new entries merged in (by id),
    /// preserving existing custom exercises and any modified defaults.
    static func mergeExercises(into existing: [Exercise]) -> [Exercise] {
        var result = existing
        let existingIds = Set(existing.map(\.id))
        for ex in exercises where !existingIds.contains(ex.id) {
            result.append(ex)
        }
        return result
    }
}
