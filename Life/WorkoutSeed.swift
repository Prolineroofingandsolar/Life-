import Foundation

// MARK: - Seed Exercises (80+ exercises with equipment, instructions, difficulty & movement type)

enum WorkoutSeed {

    static let exercises: [Exercise] = [

        // MARK: Chest
        Exercise(id: "ex_bench_press",       name: "Bench Press",             muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Lie flat, grip shoulder-width, lower bar to chest and press up explosively.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_incline_bench",     name: "Incline Bench Press",     muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Set bench to 30–45°, press bar from upper chest to lockout.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_decline_bench",     name: "Decline Bench Press",     muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Set bench to –15°, focus on lower chest, keep shoulders retracted.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_db_bench",          name: "Dumbbell Bench Press",    muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Greater range of motion than barbell; touch dumbbells at top.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_db_incline_bench",  name: "Incline Dumbbell Press",  muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Incline bench at 30–45°, dumbbells at chest level, press upward.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_dumbbell_fly",      name: "Dumbbell Fly",            muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Slight elbow bend throughout; stretch at bottom, squeeze at top.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_cable_fly",         name: "Cable Fly",               muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Set cables high, bring hands together in an arc, contract chest hard.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_pec_deck",          name: "Pec Deck",                muscle: "Chest",     kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Keep elbows at 90°, squeeze chest fully at the midpoint.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_pushup",            name: "Push-Up",                 muscle: "Chest",     kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Hands slightly wider than shoulders, lower chest to floor, press up.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_chest_dip",         name: "Chest Dip",               muscle: "Chest",     kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Lean forward slightly to shift emphasis to chest over triceps.", difficulty: 2, movementType: .compound),

        // MARK: Back
        Exercise(id: "ex_deadlift",          name: "Deadlift",                muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Neutral spine, bar over mid-foot, drive through floor, lockout with hips.", difficulty: 3, movementType: .compound),
        Exercise(id: "ex_barbell_row",       name: "Barbell Row",             muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Hinge to 45°, pull bar to lower chest, retract scapula fully.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_pullup",            name: "Pull-Up",                 muscle: "Back",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Dead hang start, pull chest to bar, full elbow extension at bottom.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_chinup",            name: "Chin-Up",                 muscle: "Back",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Underhand grip, supinate wrists at top, more bicep involvement.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_lat_pulldown",      name: "Lat Pulldown",            muscle: "Back",      kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Wide grip, lean back slightly, pull to upper chest, full stretch at top.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_seated_cable_row",  name: "Seated Cable Row",        muscle: "Back",      kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Neutral spine, drive elbows back, squeeze for 1 second at the end.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_db_row",            name: "Dumbbell Row",            muscle: "Back",      kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Brace on bench, pull dumbbell to hip, elbow close to body.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_tbar_row",          name: "T-Bar Row",               muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Straddle bar, chest supported, pull handles to sternum.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_face_pull",         name: "Face Pull",               muscle: "Back",      kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Cable at head height, pull rope to face, externally rotate shoulders.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_shrug",             name: "Barbell Shrug",           muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Lift shoulders straight up; avoid rolling to prevent injury.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_good_morning",      name: "Good Morning",            muscle: "Back",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Bar on upper back, hinge at hips with soft knees, keep spine neutral.", difficulty: 2, movementType: .compound),

        // MARK: Shoulders
        Exercise(id: "ex_ohp",              name: "Overhead Press",           muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Bar from front rack, press overhead to lockout, slight lean back at top.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_db_ohp",           name: "Dumbbell Shoulder Press",  muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Seated or standing, press dumbbells from ear level to lockout.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_lateral_raise",    name: "Lateral Raise",            muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Slight elbow bend, raise to shoulder height, pause at top.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_front_raise",      name: "Front Raise",              muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Raise one or both dumbbells to eye level, controlled lowering.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_cable_lateral",    name: "Cable Lateral Raise",      muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Cable at low position, raise across body, constant tension throughout.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_arnold_press",     name: "Arnold Press",             muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Start with palms facing you, rotate outward as you press overhead.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_rear_delt_fly",    name: "Rear Delt Fly",            muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Bent over, slight elbow bend, raise elbows wide to shoulder height.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_machine_press",    name: "Machine Shoulder Press",   muscle: "Shoulders", kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Adjust seat height so handles are at shoulder level before pressing.", difficulty: 1, movementType: .compound),

        // MARK: Biceps
        Exercise(id: "ex_barbell_curl",     name: "Barbell Curl",             muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Elbows at sides, curl to chin, lower slowly over 3 seconds.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_dumbbell_curl",    name: "Dumbbell Curl",            muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Alternate arms, supinate wrist at top of each rep.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_hammer_curl",      name: "Hammer Curl",              muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Neutral grip throughout, targets brachialis and brachioradialis.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_preacher_curl",    name: "Preacher Curl",            muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .ezBar,      instructions: "Arms on pad, curl up then control the eccentric fully.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_incline_curl",     name: "Incline Dumbbell Curl",    muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Bench at 60°, arms hang back to stretch the long head.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_cable_curl",       name: "Cable Curl",               muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Constant tension from cable; squeeze at top of each rep.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_concentration_curl", name: "Concentration Curl",     muscle: "Biceps",    kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Seated, elbow on inner thigh, curl slowly for peak contraction.", difficulty: 1, movementType: .isolation),

        // MARK: Triceps
        Exercise(id: "ex_skullcrusher",     name: "Skull Crusher",            muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .ezBar,      instructions: "Lower bar to forehead with elbows fixed, extend to lockout.", difficulty: 2, movementType: .isolation),
        Exercise(id: "ex_tricep_pushdown",  name: "Tricep Pushdown",          muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Rope or bar, elbows fixed at sides, push down to full extension.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_overhead_tricep",  name: "Overhead Tricep Ext",      muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "One or two hands, lower behind head, extend to lockout overhead.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_dip",              name: "Dip",                      muscle: "Triceps",   kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Stay upright to target triceps; lower until upper arms are parallel.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_close_grip_bench", name: "Close-Grip Bench Press",   muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Grip shoulder-width, tuck elbows close to torso throughout.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_tricep_kickback",  name: "Tricep Kickback",          muscle: "Triceps",   kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Hinge forward, elbow at side, extend fully, squeeze at lockout.", difficulty: 1, movementType: .isolation),

        // MARK: Legs
        Exercise(id: "ex_squat",            name: "Back Squat",               muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Bar on traps, squat below parallel, drive knees out, chest up.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_front_squat",      name: "Front Squat",              muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Bar on front delts, stay upright, drive elbows up throughout.", difficulty: 3, movementType: .compound),
        Exercise(id: "ex_goblet_squat",     name: "Goblet Squat",             muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .kettlebell, instructions: "Hold kettlebell at chest, squat deep, elbows push knees out.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_leg_press",        name: "Leg Press",                muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Feet shoulder-width, lower until 90°, don't lock knees at top.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_rdl",             name: "Romanian Deadlift",         muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Soft knees, hinge at hips, bar stays close to legs, stretch hamstrings.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_db_rdl",          name: "Dumbbell RDL",              muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Same as barbell RDL, greater range if needed due to dumbbell path.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_leg_curl",        name: "Leg Curl",                  muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Full range of motion, squeeze at top, control the negative.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_leg_extension",   name: "Leg Extension",             muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Full extension, squeeze quads at top, slow eccentric.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_hack_squat",      name: "Hack Squat",                muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Feet low on platform for more quad focus, full range of motion.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_lunge",           name: "Lunge",                     muscle: "Legs",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Step forward, lower rear knee to floor, drive through front heel.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_db_lunge",        name: "Dumbbell Lunge",            muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Hold dumbbells at sides, maintain upright torso, alternate legs.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_bulgarian_squat", name: "Bulgarian Split Squat",     muscle: "Legs",      kind: .weight,     isCustom: false, equipment: .dumbbell,   instructions: "Rear foot elevated, lower front knee forward, stay tall.", difficulty: 2, movementType: .compound),

        // MARK: Glutes
        Exercise(id: "ex_hip_thrust",      name: "Hip Thrust",                muscle: "Glutes",    kind: .weight,     isCustom: false, equipment: .barbell,    instructions: "Shoulders on bench, drive hips to full extension, squeeze glutes hard.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_glute_bridge",    name: "Glute Bridge",              muscle: "Glutes",    kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Feet flat on floor, thrust hips up, hold for 1 second at top.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_cable_kickback",  name: "Cable Kickback",            muscle: "Glutes",    kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Ankle strap on cable, kick leg back and up, squeeze glute at top.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_step_up",         name: "Step-Up",                   muscle: "Glutes",    kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Step onto bench, drive through heel, bring trailing leg up.", difficulty: 1, movementType: .compound),

        // MARK: Calves
        Exercise(id: "ex_calf_raise",      name: "Standing Calf Raise",       muscle: "Calves",    kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Full range — stretch at bottom, raise to tippy-toe, pause at top.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_seated_calf",     name: "Seated Calf Raise",         muscle: "Calves",    kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Pads on lower thighs, full range of motion, soleus focus.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_donkey_calf",     name: "Donkey Calf Raise",         muscle: "Calves",    kind: .weight,     isCustom: false, equipment: .machine,    instructions: "Bent-over position increases stretch; full range essential.", difficulty: 1, movementType: .isolation),

        // MARK: Core
        Exercise(id: "ex_plank",           name: "Plank",                     muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Forearms on floor, body straight, squeeze abs and glutes throughout.", difficulty: 1, movementType: .compound),
        Exercise(id: "ex_crunch",          name: "Crunch",                    muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Hands behind head, curl shoulders off floor, lower with control.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_ab_wheel",        name: "Ab Wheel Rollout",          muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .other,      instructions: "Kneel, roll forward until hips drop, pull back using abs only.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_cable_crunch",    name: "Cable Crunch",              muscle: "Core",      kind: .weight,     isCustom: false, equipment: .cable,      instructions: "Kneel at cable, flex spine — don't pull with hips.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_hanging_leg",     name: "Hanging Leg Raise",         muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Dead hang, raise legs to 90° without swinging.", difficulty: 2, movementType: .compound),
        Exercise(id: "ex_russian_twist",   name: "Russian Twist",             muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Feet raised, rotate torso side to side, keep lower back neutral.", difficulty: 1, movementType: .isolation),
        Exercise(id: "ex_side_plank",      name: "Side Plank",                muscle: "Core",      kind: .bodyweight, isCustom: false, equipment: .bodyweight, instructions: "Forearm on floor, body straight, hold as long as possible each side.", difficulty: 1, movementType: .compound),

        // MARK: Cardio
        Exercise(id: "ex_treadmill",       name: "Treadmill Run",             muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .machine,    instructions: "Warm up at easy pace, maintain conversational pace, cool down after.", difficulty: 1, movementType: .cardio),
        Exercise(id: "ex_cycling",         name: "Cycling",                   muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .machine,    instructions: "Adjust seat height so knee has slight bend at bottom of pedal stroke.", difficulty: 1, movementType: .cardio),
        Exercise(id: "ex_rowing",          name: "Rowing Machine",            muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .machine,    instructions: "Legs-back-arms on the drive; arms-back-legs on the recovery.", difficulty: 1, movementType: .cardio),
        Exercise(id: "ex_jump_rope",       name: "Jump Rope",                 muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .other,      instructions: "Stay on balls of feet, small jumps, wrists drive rotation not arms.", difficulty: 1, movementType: .cardio),
        Exercise(id: "ex_stair_climber",   name: "Stair Climber",             muscle: "Cardio",    kind: .cardio,     isCustom: false, equipment: .machine,    instructions: "Don't lean on rails; full step through each stride.", difficulty: 1, movementType: .cardio),
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

    // MARK: Program Templates

    struct WorkoutProgram: Identifiable {
        let id: String
        let name: String
        let icon: String
        let description: String
        let difficulty: String
        let daysPerWeek: Int
        let routines: [Routine]
    }

    static let programTemplates: [WorkoutProgram] = [
        // PPL
        WorkoutProgram(
            id: "prog_ppl",
            name: "Push / Pull / Legs",
            icon: "figure.strengthtraining.traditional",
            description: "Classic 3-day split targeting push muscles, pull muscles, and legs separately.",
            difficulty: "Intermediate",
            daysPerWeek: 3,
            routines: [
                Routine(id: "tmpl_ppl_push", name: "PPL — Push", exercises: [
                    RoutineExercise(exerciseId: "ex_bench_press",     defaultSets: 4, defaultReps: 8,  defaultWeight: 60, repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                    RoutineExercise(exerciseId: "ex_incline_bench",   defaultSets: 3, defaultReps: 10, defaultWeight: 50, repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_ohp",             defaultSets: 3, defaultReps: 10, defaultWeight: 40, repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_lateral_raise",   defaultSets: 3, defaultReps: 15, defaultWeight: 10, repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_cable_fly",       defaultSets: 3, defaultReps: 12, defaultWeight: 15, repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_tricep_pushdown", defaultSets: 3, defaultReps: 12, defaultWeight: 30, repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_skullcrusher",    defaultSets: 3, defaultReps: 12, defaultWeight: 20, repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                ]),
                Routine(id: "tmpl_ppl_pull", name: "PPL — Pull", exercises: [
                    RoutineExercise(exerciseId: "ex_deadlift",         defaultSets: 3, defaultReps: 5,  defaultWeight: 100, repRangeMin: 3, repRangeMax: 5,  restSeconds: 180),
                    RoutineExercise(exerciseId: "ex_pullup",           defaultSets: 3, defaultReps: 8,  defaultWeight: 0,   repRangeMin: 6, repRangeMax: 10, restSeconds: 120),
                    RoutineExercise(exerciseId: "ex_lat_pulldown",     defaultSets: 3, defaultReps: 10, defaultWeight: 50,  repRangeMin: 8, repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_seated_cable_row", defaultSets: 3, defaultReps: 12, defaultWeight: 40,  repRangeMin: 10,repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_face_pull",        defaultSets: 3, defaultReps: 15, defaultWeight: 15,  repRangeMin: 12,repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_barbell_curl",     defaultSets: 3, defaultReps: 12, defaultWeight: 20,  repRangeMin: 10,repRangeMax: 15, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_hammer_curl",      defaultSets: 3, defaultReps: 12, defaultWeight: 12,  repRangeMin: 10,repRangeMax: 15, restSeconds: 60),
                ]),
                Routine(id: "tmpl_ppl_legs", name: "PPL — Legs", exercises: [
                    RoutineExercise(exerciseId: "ex_squat",           defaultSets: 4, defaultReps: 8,  defaultWeight: 80,  repRangeMin: 5,  repRangeMax: 8,  restSeconds: 180),
                    RoutineExercise(exerciseId: "ex_leg_press",       defaultSets: 3, defaultReps: 12, defaultWeight: 120, repRangeMin: 10, repRangeMax: 15, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_rdl",             defaultSets: 3, defaultReps: 10, defaultWeight: 60,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_leg_curl",        defaultSets: 3, defaultReps: 12, defaultWeight: 30,  repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_leg_extension",   defaultSets: 3, defaultReps: 15, defaultWeight: 40,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_calf_raise",      defaultSets: 4, defaultReps: 15, defaultWeight: 40,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                ]),
            ]
        ),
        // Upper / Lower
        WorkoutProgram(
            id: "prog_upperlower",
            name: "Upper / Lower Split",
            icon: "arrow.up.and.down.circle.fill",
            description: "4-day split alternating upper and lower body sessions for optimal frequency.",
            difficulty: "Intermediate",
            daysPerWeek: 4,
            routines: [
                Routine(id: "tmpl_ul_upper_a", name: "Upper A — Strength", exercises: [
                    RoutineExercise(exerciseId: "ex_bench_press",   defaultSets: 4, defaultReps: 5,  defaultWeight: 70, repRangeMin: 4, repRangeMax: 6,  restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_barbell_row",   defaultSets: 4, defaultReps: 5,  defaultWeight: 60, repRangeMin: 4, repRangeMax: 6,  restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_ohp",           defaultSets: 3, defaultReps: 8,  defaultWeight: 40, repRangeMin: 6, repRangeMax: 8,  restSeconds: 120),
                    RoutineExercise(exerciseId: "ex_pullup",        defaultSets: 3, defaultReps: 8,  defaultWeight: 0,  repRangeMin: 6, repRangeMax: 10, restSeconds: 120),
                    RoutineExercise(exerciseId: "ex_barbell_curl",  defaultSets: 3, defaultReps: 10, defaultWeight: 20, repRangeMin: 8, repRangeMax: 12, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_skullcrusher",  defaultSets: 3, defaultReps: 10, defaultWeight: 20, repRangeMin: 8, repRangeMax: 12, restSeconds: 60),
                ]),
                Routine(id: "tmpl_ul_lower_a", name: "Lower A — Strength", exercises: [
                    RoutineExercise(exerciseId: "ex_squat",         defaultSets: 4, defaultReps: 5,  defaultWeight: 80,  repRangeMin: 4,  repRangeMax: 6,  restSeconds: 180),
                    RoutineExercise(exerciseId: "ex_rdl",           defaultSets: 3, defaultReps: 8,  defaultWeight: 60,  repRangeMin: 6,  repRangeMax: 8,  restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_leg_press",     defaultSets: 3, defaultReps: 10, defaultWeight: 120, repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_leg_curl",      defaultSets: 3, defaultReps: 12, defaultWeight: 30,  repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_calf_raise",    defaultSets: 4, defaultReps: 15, defaultWeight: 40,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                ]),
                Routine(id: "tmpl_ul_upper_b", name: "Upper B — Volume", exercises: [
                    RoutineExercise(exerciseId: "ex_incline_bench",   defaultSets: 4, defaultReps: 10, defaultWeight: 50, repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_lat_pulldown",    defaultSets: 4, defaultReps: 10, defaultWeight: 50, repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_db_ohp",          defaultSets: 3, defaultReps: 12, defaultWeight: 20, repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_seated_cable_row",defaultSets: 3, defaultReps: 12, defaultWeight: 40, repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_dumbbell_curl",   defaultSets: 3, defaultReps: 12, defaultWeight: 12, repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_tricep_pushdown", defaultSets: 3, defaultReps: 12, defaultWeight: 25, repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_lateral_raise",   defaultSets: 3, defaultReps: 15, defaultWeight: 8,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                ]),
                Routine(id: "tmpl_ul_lower_b", name: "Lower B — Volume", exercises: [
                    RoutineExercise(exerciseId: "ex_hack_squat",      defaultSets: 4, defaultReps: 10, defaultWeight: 80,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_db_rdl",          defaultSets: 3, defaultReps: 12, defaultWeight: 30,  repRangeMin: 10, repRangeMax: 15, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_bulgarian_squat", defaultSets: 3, defaultReps: 10, defaultWeight: 20,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_leg_extension",   defaultSets: 3, defaultReps: 15, defaultWeight: 40,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_calf_raise",      defaultSets: 4, defaultReps: 20, defaultWeight: 40,  repRangeMin: 15, repRangeMax: 25, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_hip_thrust",      defaultSets: 3, defaultReps: 12, defaultWeight: 60,  repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                ]),
            ]
        ),
        // Beginner Full Body
        WorkoutProgram(
            id: "prog_beginner",
            name: "Beginner Full Body",
            icon: "star.fill",
            description: "3-day full-body programme for beginners. Builds strength on the big lifts.",
            difficulty: "Beginner",
            daysPerWeek: 3,
            routines: [
                Routine(id: "tmpl_beg_a", name: "Beginner A", exercises: [
                    RoutineExercise(exerciseId: "ex_squat",         defaultSets: 3, defaultReps: 5,  defaultWeight: 40, repRangeMin: 4, repRangeMax: 6,  restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_bench_press",   defaultSets: 3, defaultReps: 5,  defaultWeight: 40, repRangeMin: 4, repRangeMax: 6,  restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_barbell_row",   defaultSets: 3, defaultReps: 5,  defaultWeight: 40, repRangeMin: 4, repRangeMax: 6,  restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_plank",         defaultSets: 3, defaultReps: 1,  defaultWeight: 0,  repRangeMin: 1, repRangeMax: 1,  restSeconds: 60),
                ]),
                Routine(id: "tmpl_beg_b", name: "Beginner B", exercises: [
                    RoutineExercise(exerciseId: "ex_squat",         defaultSets: 3, defaultReps: 5,  defaultWeight: 40, repRangeMin: 4, repRangeMax: 6,  restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_ohp",           defaultSets: 3, defaultReps: 5,  defaultWeight: 25, repRangeMin: 4, repRangeMax: 6,  restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_deadlift",      defaultSets: 1, defaultReps: 5,  defaultWeight: 60, repRangeMin: 4, repRangeMax: 6,  restSeconds: 180),
                    RoutineExercise(exerciseId: "ex_plank",         defaultSets: 3, defaultReps: 1,  defaultWeight: 0,  repRangeMin: 1, repRangeMax: 1,  restSeconds: 60),
                ]),
            ]
        ),
        // Women's Glute Focus
        WorkoutProgram(
            id: "prog_glute",
            name: "Women's Glute Focus",
            icon: "figure.walk",
            description: "Targets glutes, hamstrings and legs with progressive overload for shape and strength.",
            difficulty: "Beginner–Intermediate",
            daysPerWeek: 3,
            routines: [
                Routine(id: "tmpl_glute_a", name: "Glute Day A", exercises: [
                    RoutineExercise(exerciseId: "ex_hip_thrust",      defaultSets: 4, defaultReps: 10, defaultWeight: 40,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_squat",           defaultSets: 3, defaultReps: 10, defaultWeight: 40,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_rdl",             defaultSets: 3, defaultReps: 12, defaultWeight: 30,  repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_cable_kickback",  defaultSets: 3, defaultReps: 15, defaultWeight: 10,  repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_leg_curl",        defaultSets: 3, defaultReps: 12, defaultWeight: 20,  repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                ]),
                Routine(id: "tmpl_glute_b", name: "Glute Day B", exercises: [
                    RoutineExercise(exerciseId: "ex_bulgarian_squat", defaultSets: 3, defaultReps: 10, defaultWeight: 10,  repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_glute_bridge",    defaultSets: 4, defaultReps: 15, defaultWeight: 0,   repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_db_rdl",          defaultSets: 3, defaultReps: 12, defaultWeight: 15,  repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_step_up",         defaultSets: 3, defaultReps: 12, defaultWeight: 10,  repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_cable_kickback",  defaultSets: 3, defaultReps: 15, defaultWeight: 8,   repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                ]),
                Routine(id: "tmpl_glute_c", name: "Lower Body Sculpt", exercises: [
                    RoutineExercise(exerciseId: "ex_leg_press",       defaultSets: 4, defaultReps: 12, defaultWeight: 80,  repRangeMin: 10, repRangeMax: 15, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_hip_thrust",      defaultSets: 3, defaultReps: 12, defaultWeight: 50,  repRangeMin: 10, repRangeMax: 15, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_lunge",           defaultSets: 3, defaultReps: 10, defaultWeight: 0,   repRangeMin: 8,  repRangeMax: 12, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_leg_curl",        defaultSets: 3, defaultReps: 12, defaultWeight: 20,  repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_calf_raise",      defaultSets: 3, defaultReps: 20, defaultWeight: 0,   repRangeMin: 15, repRangeMax: 25, restSeconds: 45),
                ]),
            ]
        ),
        // Arnold Split
        WorkoutProgram(
            id: "prog_arnold",
            name: "Arnold Split",
            icon: "bolt.fill",
            description: "Arnold Schwarzenegger's 6-day split training each muscle group twice per week.",
            difficulty: "Advanced",
            daysPerWeek: 6,
            routines: [
                Routine(id: "tmpl_arn_chest_back", name: "Arnold — Chest & Back", exercises: [
                    RoutineExercise(exerciseId: "ex_bench_press",       defaultSets: 4, defaultReps: 8,  defaultWeight: 70, repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                    RoutineExercise(exerciseId: "ex_incline_bench",     defaultSets: 3, defaultReps: 10, defaultWeight: 55, repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_dumbbell_fly",      defaultSets: 3, defaultReps: 12, defaultWeight: 15, repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_pullup",            defaultSets: 4, defaultReps: 8,  defaultWeight: 0,  repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                    RoutineExercise(exerciseId: "ex_barbell_row",       defaultSets: 4, defaultReps: 8,  defaultWeight: 60, repRangeMin: 6,  repRangeMax: 10, restSeconds: 120),
                    RoutineExercise(exerciseId: "ex_seated_cable_row",  defaultSets: 3, defaultReps: 12, defaultWeight: 45, repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                ]),
                Routine(id: "tmpl_arn_shoulders_arms", name: "Arnold — Shoulders & Arms", exercises: [
                    RoutineExercise(exerciseId: "ex_arnold_press",      defaultSets: 4, defaultReps: 10, defaultWeight: 20, repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_lateral_raise",     defaultSets: 3, defaultReps: 15, defaultWeight: 10, repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_rear_delt_fly",     defaultSets: 3, defaultReps: 15, defaultWeight: 10, repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_barbell_curl",      defaultSets: 3, defaultReps: 10, defaultWeight: 25, repRangeMin: 8,  repRangeMax: 12, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_hammer_curl",       defaultSets: 3, defaultReps: 10, defaultWeight: 15, repRangeMin: 8,  repRangeMax: 12, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_skullcrusher",      defaultSets: 3, defaultReps: 10, defaultWeight: 20, repRangeMin: 8,  repRangeMax: 12, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_tricep_pushdown",   defaultSets: 3, defaultReps: 12, defaultWeight: 25, repRangeMin: 10, repRangeMax: 15, restSeconds: 60),
                ]),
                Routine(id: "tmpl_arn_legs", name: "Arnold — Legs", exercises: [
                    RoutineExercise(exerciseId: "ex_squat",             defaultSets: 5, defaultReps: 8,  defaultWeight: 80, repRangeMin: 6,  repRangeMax: 10, restSeconds: 150),
                    RoutineExercise(exerciseId: "ex_leg_press",         defaultSets: 3, defaultReps: 12, defaultWeight: 130,repRangeMin: 10, repRangeMax: 15, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_rdl",               defaultSets: 3, defaultReps: 10, defaultWeight: 60, repRangeMin: 8,  repRangeMax: 12, restSeconds: 90),
                    RoutineExercise(exerciseId: "ex_leg_curl",          defaultSets: 3, defaultReps: 12, defaultWeight: 30, repRangeMin: 10, repRangeMax: 15, restSeconds: 75),
                    RoutineExercise(exerciseId: "ex_leg_extension",     defaultSets: 3, defaultReps: 15, defaultWeight: 40, repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                    RoutineExercise(exerciseId: "ex_calf_raise",        defaultSets: 5, defaultReps: 15, defaultWeight: 50, repRangeMin: 12, repRangeMax: 20, restSeconds: 60),
                ]),
            ]
        ),
    ]

    // MARK: Merge helpers

    static func mergeExercises(into existing: [Exercise]) -> [Exercise] {
        var map: [String: Exercise] = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for seed in exercises {
            if var ex = map[seed.id] {
                if ex.equipment == .barbell && seed.equipment != .barbell { ex.equipment = seed.equipment }
                if ex.instructions.isEmpty { ex.instructions = seed.instructions }
                if ex.movementType == .compound && seed.movementType != .compound { ex.movementType = seed.movementType }
                map[seed.id] = ex
            } else {
                map[seed.id] = seed
            }
        }
        let seedIds = exercises.map(\.id)
        let customExercises = existing.filter { !seedIds.contains($0.id) }
        return exercises.compactMap { map[$0.id] } + customExercises
    }
}
