import Foundation

// MARK: - Seed Exercises (80+ exercises with equipment & instructions)

enum WorkoutSeed {

    static let exercises: [Exercise] = [

        // MARK: Chest
        Exercise(id: "ex_bench_press",       name: "Bench Press",             muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Lie flat, grip shoulder-width, lower bar to chest and press up explosively."),
        Exercise(id: "ex_incline_bench",     name: "Incline Bench Press",     muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Set bench to 30–45°, press bar from upper chest to lockout."),
        Exercise(id: "ex_decline_bench",     name: "Decline Bench Press",     muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Set bench to –15°, focus on lower chest, keep shoulders retracted."),
        Exercise(id: "ex_db_bench",          name: "Dumbbell Bench Press",    muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Greater range of motion than barbell; touch dumbbells at top."),
        Exercise(id: "ex_db_incline_bench",  name: "Incline Dumbbell Press",  muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Incline bench at 30–45°, dumbbells at chest level, press upward."),
        Exercise(id: "ex_dumbbell_fly",      name: "Dumbbell Fly",            muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Slight elbow bend throughout; stretch at bottom, squeeze at top."),
        Exercise(id: "ex_cable_fly",         name: "Cable Fly",               muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Set cables high, bring hands together in an arc, contract chest hard."),
        Exercise(id: "ex_pec_deck",          name: "Pec Deck",                muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Keep elbows at 90°, squeeze chest fully at the midpoint."),
        Exercise(id: "ex_pushup",            name: "Push-Up",                 muscle: "Chest",     kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Hands slightly wider than shoulders, lower chest to floor, press up."),
        Exercise(id: "ex_chest_dip",         name: "Chest Dip",               muscle: "Chest",     kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Lean forward slightly to shift emphasis to chest over triceps."),

        // MARK: Back
        Exercise(id: "ex_deadlift",          name: "Deadlift",                muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Neutral spine, bar over mid-foot, drive through floor, lockout with hips."),
        Exercise(id: "ex_barbell_row",       name: "Barbell Row",             muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Hinge to 45°, pull bar to lower chest, retract scapula fully."),
        Exercise(id: "ex_pullup",            name: "Pull-Up",                 muscle: "Back",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Dead hang start, pull chest to bar, full elbow extension at bottom."),
        Exercise(id: "ex_chinup",            name: "Chin-Up",                 muscle: "Back",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Underhand grip, supinate wrists at top, more bicep involvement."),
        Exercise(id: "ex_lat_pulldown",      name: "Lat Pulldown",            muscle: "Back",      kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Wide grip, lean back slightly, pull to upper chest, full stretch at top."),
        Exercise(id: "ex_seated_cable_row",  name: "Seated Cable Row",        muscle: "Back",      kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Neutral spine, drive elbows back, squeeze for 1 second at the end."),
        Exercise(id: "ex_db_row",            name: "Dumbbell Row",            muscle: "Back",      kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Brace on bench, pull dumbbell to hip, elbow close to body."),
        Exercise(id: "ex_tbar_row",          name: "T-Bar Row",               muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Straddle bar, chest supported, pull handles to sternum."),
        Exercise(id: "ex_face_pull",         name: "Face Pull",               muscle: "Back",      kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Cable at head height, pull rope to face, externally rotate shoulders."),
        Exercise(id: "ex_shrug",             name: "Barbell Shrug",           muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Lift shoulders straight up; avoid rolling to prevent injury."),
        Exercise(id: "ex_good_morning",      name: "Good Morning",            muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Bar on upper back, hinge at hips with soft knees, keep spine neutral."),

        // MARK: Shoulders
        Exercise(id: "ex_ohp",              name: "Overhead Press",           muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Bar from front rack, press overhead to lockout, slight lean back at top."),
        Exercise(id: "ex_db_ohp",           name: "Dumbbell Shoulder Press",  muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Seated or standing, press dumbbells from ear level to lockout."),
        Exercise(id: "ex_lateral_raise",    name: "Lateral Raise",            muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Slight elbow bend, raise to shoulder height, pause at top."),
        Exercise(id: "ex_front_raise",      name: "Front Raise",              muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Raise one or both dumbbells to eye level, controlled lowering."),
        Exercise(id: "ex_cable_lateral",    name: "Cable Lateral Raise",      muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Cable at low position, raise across body, constant tension throughout."),
        Exercise(id: "ex_arnold_press",     name: "Arnold Press",             muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Start with palms facing you, rotate outward as you press overhead."),
        Exercise(id: "ex_rear_delt_fly",    name: "Rear Delt Fly",            muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Bent over, slight elbow bend, raise elbows wide to shoulder height."),
        Exercise(id: "ex_machine_press",    name: "Machine Shoulder Press",   muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Adjust seat height so handles are at shoulder level before pressing."),

        // MARK: Biceps
        Exercise(id: "ex_barbell_curl",     name: "Barbell Curl",             muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Elbows at sides, curl to chin, lower slowly over 3 seconds."),
        Exercise(id: "ex_dumbbell_curl",    name: "Dumbbell Curl",            muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Alternate arms, supinate wrist at top of each rep."),
        Exercise(id: "ex_hammer_curl",      name: "Hammer Curl",              muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Neutral grip throughout, targets brachialis and brachioradialis."),
        Exercise(id: "ex_preacher_curl",    name: "Preacher Curl",            muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .ezBar,      instructions: "Arms on pad, curl up then control the eccentric fully."),
        Exercise(id: "ex_incline_curl",     name: "Incline Dumbbell Curl",    muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Bench at 60°, arms hang back to stretch the long head."),
        Exercise(id: "ex_cable_curl",       name: "Cable Curl",               muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Constant tension from cable; squeeze at top of each rep."),
        Exercise(id: "ex_concentration_curl", name: "Concentration Curl",     muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Seated, elbow on inner thigh, curl slowly for peak contraction."),

        // MARK: Triceps
        Exercise(id: "ex_skullcrusher",     name: "Skull Crusher",            muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .ezBar,      instructions: "Lower bar to forehead with elbows fixed, extend to lockout."),
        Exercise(id: "ex_tricep_pushdown",  name: "Tricep Pushdown",          muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Rope or bar, elbows fixed at sides, push down to full extension."),
        Exercise(id: "ex_overhead_tricep",  name: "Overhead Tricep Ext",      muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "One or two hands, lower behind head, extend to lockout overhead."),
        Exercise(id: "ex_dip",              name: "Dip",                      muscle: "Triceps",   kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Stay upright to target triceps; lower until upper arms are parallel."),
        Exercise(id: "ex_close_grip_bench", name: "Close-Grip Bench Press",   muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Grip shoulder-width, tuck elbows close to torso throughout."),
        Exercise(id: "ex_tricep_kickback",  name: "Tricep Kickback",          muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Hinge forward, elbow at side, extend fully, squeeze at lockout."),

        // MARK: Legs
        Exercise(id: "ex_squat",            name: "Back Squat",               muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Bar on traps, squat below parallel, drive knees out, chest up."),
        Exercise(id: "ex_front_squat",      name: "Front Squat",              muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Bar on front delts, stay upright, drive elbows up throughout."),
        Exercise(id: "ex_goblet_squat",     name: "Goblet Squat",             muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .kettlebell, instructions: "Hold kettlebell at chest, squat deep, elbows push knees out."),
        Exercise(id: "ex_leg_press",        name: "Leg Press",                muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Feet shoulder-width, lower until 90°, don't lock knees at top."),
        Exercise(id: "ex_rdl",             name: "Romanian Deadlift",         muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Soft knees, hinge at hips, bar stays close to legs, stretch hamstrings."),
        Exercise(id: "ex_db_rdl",          name: "Dumbbell RDL",              muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Same as barbell RDL, greater range if needed due to dumbbell path."),
        Exercise(id: "ex_leg_curl",        name: "Leg Curl",                  muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Full range of motion, squeeze at top, control the negative."),
        Exercise(id: "ex_leg_extension",   name: "Leg Extension",             muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Full extension, squeeze quads at top, slow eccentric."),
        Exercise(id: "ex_hack_squat",      name: "Hack Squat",                muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Feet low on platform for more quad focus, full range of motion."),
        Exercise(id: "ex_lunge",           name: "Lunge",                     muscle: "Legs",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Step forward, lower rear knee to floor, drive through front heel."),
        Exercise(id: "ex_db_lunge",        name: "Dumbbell Lunge",            muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Hold dumbbells at sides, maintain upright torso, alternate legs."),
        Exercise(id: "ex_bulgarian_squat", name: "Bulgarian Split Squat",     muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Rear foot elevated, lower front knee forward, stay tall."),

        // MARK: Glutes
        Exercise(id: "ex_hip_thrust",      name: "Hip Thrust",                muscle: "Glutes",    kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Shoulders on bench, drive hips to full extension, squeeze glutes hard."),
        Exercise(id: "ex_glute_bridge",    name: "Glute Bridge",              muscle: "Glutes",    kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Feet flat on floor, thrust hips up, hold for 1 second at top."),
        Exercise(id: "ex_cable_kickback",  name: "Cable Kickback",            muscle: "Glutes",    kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Ankle strap on cable, kick leg back and up, squeeze glute at top."),
        Exercise(id: "ex_step_up",         name: "Step-Up",                   muscle: "Glutes",    kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Step onto bench, drive through heel, bring trailing leg up."),

        // MARK: Calves
        Exercise(id: "ex_calf_raise",      name: "Standing Calf Raise",       muscle: "Calves",    kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Full range — stretch at bottom, raise to tippy-toe, pause at top."),
        Exercise(id: "ex_seated_calf",     name: "Seated Calf Raise",         muscle: "Calves",    kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Pads on lower thighs, full range of motion, soleus focus."),
        Exercise(id: "ex_donkey_calf",     name: "Donkey Calf Raise",         muscle: "Calves",    kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Bent-over position increases stretch; full range essential."),

        // MARK: Core
        Exercise(id: "ex_plank",           name: "Plank",                     muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Forearms on floor, body straight, squeeze abs and glutes throughout."),
        Exercise(id: "ex_crunch",          name: "Crunch",                    muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Hands behind head, curl shoulders off floor, lower with control."),
        Exercise(id: "ex_ab_wheel",        name: "Ab Wheel Rollout",          muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .other,      instructions: "Kneel, roll forward until hips drop, pull back using abs only."),
        Exercise(id: "ex_cable_crunch",    name: "Cable Crunch",              muscle: "Core",      kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Kneel at cable, flex spine — don't pull with hips."),
        Exercise(id: "ex_hanging_leg",     name: "Hanging Leg Raise",         muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Dead hang, raise legs to 90° without swinging."),
        Exercise(id: "ex_russian_twist",   name: "Russian Twist",             muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Feet raised, rotate torso side to side, keep lower back neutral."),
        Exercise(id: "ex_side_plank",      name: "Side Plank",                muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Forearm on floor, body straight, hold as long as possible each side."),

        // MARK: Cardio
        Exercise(id: "ex_treadmill",       name: "Treadmill Run",             muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .machine,    instructions: "Warm up at easy pace, maintain conversational pace, cool down after."),
        Exercise(id: "ex_cycling",         name: "Cycling",                   muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .machine,    instructions: "Adjust seat height so knee has slight bend at bottom of pedal stroke."),
        Exercise(id: "ex_rowing",          name: "Rowing Machine",            muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .machine,    instructions: "Legs-back-arms on the drive; arms-back-legs on the recovery."),
        Exercise(id: "ex_jump_rope",       name: "Jump Rope",                 muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .other,      instructions: "Stay on balls of feet, small jumps, wrists drive rotation not arms."),
        Exercise(id: "ex_stair_climber",   name: "Stair Climber",             muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .machine,    instructions: "Don't lean on rails; full step through each stride."),
    ]

    // MARK: Routines

    static let routines: [Routine] = [
        Routine(
            id: "routine_push_a",
            name: "Push A",
            exercises: [
                RoutineExercise(id: "re1",  exerciseId: "ex_bench_press",      defaultSets: 4, defaultReps: 8,  defaultWeight: 60,  repRangeMin: 6,  repRangeMax: 8,  restSeconds: 120),
                RoutineExercise(id: "re2",  exerciseId: "ex_incline_bench",    defaultSets: 3, defaultReps: 10, defaultWeight: 50,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                RoutineExercise(id: "re3",  exerciseId: "ex_ohp",              defaultSets: 3, defaultReps: 10, defaultWeight: 40,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                RoutineExercise(id: "re4",  exerciseId: "ex_lateral_raise",    defaultSets: 3, defaultReps: 15, defaultWeight: 10,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                RoutineExercise(id: "re5",  exerciseId: "ex_tricep_pushdown",  defaultSets: 3, defaultReps: 12, defaultWeight: 30,  repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
            ]
        ),
        Routine(
            id: "routine_pull_a",
            name: "Pull A",
            exercises: [
                RoutineExercise(id: "re6",  exerciseId: "ex_deadlift",         defaultSets: 3, defaultReps: 5,  defaultWeight: 100, repRangeMin: 3,  repRangeMax: 5,  restSeconds: 180),
                RoutineExercise(id: "re7",  exerciseId: "ex_barbell_row",      defaultSets: 4, defaultReps: 8,  defaultWeight: 60,  repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                RoutineExercise(id: "re8",  exerciseId: "ex_lat_pulldown",     defaultSets: 3, defaultReps: 10, defaultWeight: 50,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                RoutineExercise(id: "re9",  exerciseId: "ex_seated_cable_row", defaultSets: 3, defaultReps: 12, defaultWeight: 40,  repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                RoutineExercise(id: "re10", exerciseId: "ex_barbell_curl",     defaultSets: 3, defaultReps: 12, defaultWeight: 20,  repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                RoutineExercise(id: "re11", exerciseId: "ex_face_pull",        defaultSets: 3, defaultReps: 15, defaultWeight: 15,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
            ]
        ),
        Routine(
            id: "routine_legs_a",
            name: "Legs A",
            exercises: [
                RoutineExercise(id: "re12", exerciseId: "ex_squat",            defaultSets: 4, defaultReps: 8,  defaultWeight: 80,  repRangeMin: 5,  repRangeMax: 8,  restSeconds: 180),
                RoutineExercise(id: "re13", exerciseId: "ex_leg_press",        defaultSets: 3, defaultReps: 12, defaultWeight: 120, repRangeMin: 10, repRangeMax: 15, restSeconds: 90),
                RoutineExercise(id: "re14", exerciseId: "ex_rdl",              defaultSets: 3, defaultReps: 10, defaultWeight: 60,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                RoutineExercise(id: "re15", exerciseId: "ex_leg_curl",         defaultSets: 3, defaultReps: 12, defaultWeight: 30,  repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                RoutineExercise(id: "re16", exerciseId: "ex_calf_raise",       defaultSets: 4, defaultReps: 15, defaultWeight: 40,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
            ]
        ),
        Routine(
            id: "routine_upper",
            name: "Upper Body",
            exercises: [
                RoutineExercise(id: "re17", exerciseId: "ex_bench_press",      defaultSets: 3, defaultReps: 8,  defaultWeight: 60,  repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                RoutineExercise(id: "re18", exerciseId: "ex_barbell_row",      defaultSets: 3, defaultReps: 8,  defaultWeight: 60,  repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                RoutineExercise(id: "re19", exerciseId: "ex_db_ohp",           defaultSets: 3, defaultReps: 10, defaultWeight: 25,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                RoutineExercise(id: "re20", exerciseId: "ex_lat_pulldown",     defaultSets: 3, defaultReps: 12, defaultWeight: 50,  repRangeMin: 10, repRangeMax: 15, restSeconds: 90),
                RoutineExercise(id: "re21", exerciseId: "ex_dumbbell_curl",    defaultSets: 3, defaultReps: 12, defaultWeight: 15,  repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                RoutineExercise(id: "re22", exerciseId: "ex_skullcrusher",     defaultSets: 3, defaultReps: 12, defaultWeight: 20,  repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
            ]
        ),
        Routine(
            id: "routine_fullbody",
            name: "Full Body",
            exercises: [
                RoutineExercise(id: "re23", exerciseId: "ex_squat",            defaultSets: 3, defaultReps: 8,  defaultWeight: 60,  repRangeMin: 6,  repRangeMax: 10, restSeconds: 150),
                RoutineExercise(id: "re24", exerciseId: "ex_bench_press",      defaultSets: 3, defaultReps: 8,  defaultWeight: 60,  repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                RoutineExercise(id: "re25", exerciseId: "ex_barbell_row",      defaultSets: 3, defaultReps: 8,  defaultWeight: 60,  repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                RoutineExercise(id: "re26", exerciseId: "ex_ohp",              defaultSets: 2, defaultReps: 10, defaultWeight: 35,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                RoutineExercise(id: "re27", exerciseId: "ex_rdl",              defaultSets: 3, defaultReps: 10, defaultWeight: 60,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 120),
                RoutineExercise(id: "re28", exerciseId: "ex_plank",            defaultSets: 3, defaultReps: 1,  defaultWeight: 0,   repRangeMin: 1,  repRangeMax: 1,  restSeconds: 60),
            ]
        ),
    ]

    // MARK: Merge helpers

    /// Merges new seed exercises into the existing list (add missing, update equipment/instructions on existing).
    static func mergeExercises(into existing: [Exercise]) -> [Exercise] {
        var map: [String: Exercise] = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for seed in exercises {
            if var ex = map[seed.id] {
                // Backfill equipment and instructions if they're at default/empty
                if ex.equipment == .barbell && seed.equipment != .barbell { ex.equipment = seed.equipment }
                if ex.instructions.isEmpty { ex.instructions = seed.instructions }
                map[seed.id] = ex
            } else {
                map[seed.id] = seed
            }
        }
        // Preserve order: seed exercises first, then custom exercises appended
        let seedIds = exercises.map(\.id)
        let customExercises = existing.filter { !seedIds.contains($0.id) }
        return exercises.compactMap { map[$0.id] } + customExercises
    }
}
