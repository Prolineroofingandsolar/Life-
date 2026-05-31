import type { Exercise, Routine } from './types'

/**
 * Built-in exercise library. IDs are stable strings so routines (and future
 * shared routines) can reference them portably.
 */
export const SEED_EXERCISES: Exercise[] = [
  // ── Chest ───────────────────────────────────────────────────────────────
  { id: 'bench-press',       name: 'Barbell Bench Press',      kind: 'weight',     muscle: 'Chest' },
  { id: 'incline-db-press',  name: 'Incline Dumbbell Press',   kind: 'weight',     muscle: 'Chest' },
  { id: 'db-bench-press',    name: 'Dumbbell Bench Press',     kind: 'weight',     muscle: 'Chest' },
  { id: 'incline-bench',     name: 'Incline Barbell Press',    kind: 'weight',     muscle: 'Chest' },
  { id: 'decline-bench',     name: 'Decline Bench Press',      kind: 'weight',     muscle: 'Chest' },
  { id: 'chest-fly',         name: 'Cable Chest Fly',          kind: 'weight',     muscle: 'Chest' },
  { id: 'low-cable-fly',     name: 'Low Cable Fly',            kind: 'weight',     muscle: 'Chest' },
  { id: 'pec-dec',           name: 'Pec Deck Machine',         kind: 'weight',     muscle: 'Chest' },
  { id: 'push-up',           name: 'Push-up',                  kind: 'bodyweight', muscle: 'Chest' },
  { id: 'dip',               name: 'Chest Dip',                kind: 'bodyweight', muscle: 'Chest' },

  // ── Back ────────────────────────────────────────────────────────────────
  { id: 'deadlift',          name: 'Deadlift',                 kind: 'weight',     muscle: 'Back' },
  { id: 'rack-pull',         name: 'Rack Pull',                kind: 'weight',     muscle: 'Back' },
  { id: 'barbell-row',       name: 'Barbell Row',              kind: 'weight',     muscle: 'Back' },
  { id: 't-bar-row',         name: 'T-Bar Row',                kind: 'weight',     muscle: 'Back' },
  { id: 'single-arm-db-row', name: 'Single Arm Dumbbell Row',  kind: 'weight',     muscle: 'Back' },
  { id: 'lat-pulldown',      name: 'Lat Pulldown',             kind: 'weight',     muscle: 'Back' },
  { id: 'seated-row',        name: 'Seated Cable Row',         kind: 'weight',     muscle: 'Back' },
  { id: 'cable-row-wide',    name: 'Wide Grip Cable Row',      kind: 'weight',     muscle: 'Back' },
  { id: 'straight-arm-pulldown', name: 'Straight Arm Pulldown', kind: 'weight',   muscle: 'Back' },
  { id: 'db-pullover',       name: 'Dumbbell Pullover',        kind: 'weight',     muscle: 'Back' },
  { id: 'pull-up',           name: 'Pull-up',                  kind: 'bodyweight', muscle: 'Back' },
  { id: 'chin-up',           name: 'Chin-up',                  kind: 'bodyweight', muscle: 'Back' },

  // ── Traps ───────────────────────────────────────────────────────────────
  { id: 'shrug',             name: 'Barbell Shrug',            kind: 'weight',     muscle: 'Traps' },
  { id: 'db-shrug',          name: 'Dumbbell Shrug',           kind: 'weight',     muscle: 'Traps' },
  { id: 'farmers-carry',     name: 'Farmer\'s Carry',          kind: 'weight',     muscle: 'Traps' },

  // ── Shoulders ───────────────────────────────────────────────────────────
  { id: 'ohp',               name: 'Overhead Press',           kind: 'weight',     muscle: 'Shoulders' },
  { id: 'db-shoulder-press', name: 'Dumbbell Shoulder Press',  kind: 'weight',     muscle: 'Shoulders' },
  { id: 'arnold-press',      name: 'Arnold Press',             kind: 'weight',     muscle: 'Shoulders' },
  { id: 'lateral-raise',     name: 'Lateral Raise',            kind: 'weight',     muscle: 'Shoulders' },
  { id: 'cable-lateral-raise', name: 'Cable Lateral Raise',    kind: 'weight',     muscle: 'Shoulders' },
  { id: 'front-raise',       name: 'Front Raise',              kind: 'weight',     muscle: 'Shoulders' },
  { id: 'rear-delt-fly',     name: 'Rear Delt Fly',            kind: 'weight',     muscle: 'Shoulders' },
  { id: 'face-pull',         name: 'Face Pull',                kind: 'weight',     muscle: 'Shoulders' },
  { id: 'upright-row',       name: 'Upright Row',              kind: 'weight',     muscle: 'Shoulders' },

  // ── Biceps ──────────────────────────────────────────────────────────────
  { id: 'barbell-curl',      name: 'Barbell Curl',             kind: 'weight',     muscle: 'Biceps' },
  { id: 'db-curl',           name: 'Dumbbell Curl',            kind: 'weight',     muscle: 'Biceps' },
  { id: 'hammer-curl',       name: 'Hammer Curl',              kind: 'weight',     muscle: 'Biceps' },
  { id: 'preacher-curl',     name: 'Preacher Curl',            kind: 'weight',     muscle: 'Biceps' },
  { id: 'concentration-curl', name: 'Concentration Curl',      kind: 'weight',     muscle: 'Biceps' },
  { id: 'cable-curl',        name: 'Cable Curl',               kind: 'weight',     muscle: 'Biceps' },
  { id: 'incline-db-curl',   name: 'Incline Dumbbell Curl',    kind: 'weight',     muscle: 'Biceps' },
  { id: 'spider-curl',       name: 'Spider Curl',              kind: 'weight',     muscle: 'Biceps' },

  // ── Triceps ─────────────────────────────────────────────────────────────
  { id: 'tricep-pushdown',   name: 'Tricep Pushdown',          kind: 'weight',     muscle: 'Triceps' },
  { id: 'skullcrusher',      name: 'Skullcrusher',             kind: 'weight',     muscle: 'Triceps' },
  { id: 'close-grip-bench',  name: 'Close Grip Bench Press',   kind: 'weight',     muscle: 'Triceps' },
  { id: 'overhead-tricep-ext', name: 'Overhead Tricep Extension', kind: 'weight',  muscle: 'Triceps' },
  { id: 'cable-overhead-ext', name: 'Cable Overhead Extension', kind: 'weight',    muscle: 'Triceps' },
  { id: 'tricep-dip',        name: 'Tricep Dip',               kind: 'bodyweight', muscle: 'Triceps' },
  { id: 'diamond-push-up',   name: 'Diamond Push-up',          kind: 'bodyweight', muscle: 'Triceps' },

  // ── Legs ────────────────────────────────────────────────────────────────
  { id: 'back-squat',        name: 'Barbell Back Squat',       kind: 'weight',     muscle: 'Legs' },
  { id: 'front-squat',       name: 'Front Squat',              kind: 'weight',     muscle: 'Legs' },
  { id: 'goblet-squat',      name: 'Goblet Squat',             kind: 'weight',     muscle: 'Legs' },
  { id: 'hack-squat',        name: 'Hack Squat',               kind: 'weight',     muscle: 'Legs' },
  { id: 'leg-press',         name: 'Leg Press',                kind: 'weight',     muscle: 'Legs' },
  { id: 'romanian-deadlift', name: 'Romanian Deadlift',        kind: 'weight',     muscle: 'Legs' },
  { id: 'bulgarian-split-squat', name: 'Bulgarian Split Squat', kind: 'weight',    muscle: 'Legs' },
  { id: 'step-up',           name: 'Step Up',                  kind: 'weight',     muscle: 'Legs' },
  { id: 'leg-curl',          name: 'Leg Curl',                 kind: 'weight',     muscle: 'Legs' },
  { id: 'leg-extension',     name: 'Leg Extension',            kind: 'weight',     muscle: 'Legs' },
  { id: 'calf-raise',        name: 'Calf Raise',               kind: 'weight',     muscle: 'Legs' },
  { id: 'seated-calf-raise', name: 'Seated Calf Raise',        kind: 'weight',     muscle: 'Legs' },
  { id: 'lunge',             name: 'Walking Lunge',            kind: 'bodyweight', muscle: 'Legs' },
  { id: 'pistol-squat',      name: 'Pistol Squat',             kind: 'bodyweight', muscle: 'Legs' },
  { id: 'wall-sit',          name: 'Wall Sit',                 kind: 'hold',       muscle: 'Legs' },

  // ── Glutes ──────────────────────────────────────────────────────────────
  { id: 'hip-thrust',        name: 'Barbell Hip Thrust',       kind: 'weight',     muscle: 'Glutes' },
  { id: 'glute-bridge',      name: 'Glute Bridge',             kind: 'bodyweight', muscle: 'Glutes' },
  { id: 'cable-kickback',    name: 'Cable Glute Kickback',     kind: 'weight',     muscle: 'Glutes' },
  { id: 'kb-swing',          name: 'Kettlebell Swing',         kind: 'weight',     muscle: 'Glutes' },
  { id: 'adductor-machine',  name: 'Adductor Machine',         kind: 'weight',     muscle: 'Glutes' },
  { id: 'abductor-machine',  name: 'Abductor Machine',         kind: 'weight',     muscle: 'Glutes' },

  // ── Core ────────────────────────────────────────────────────────────────
  { id: 'plank',             name: 'Plank',                    kind: 'hold',       muscle: 'Core' },
  { id: 'side-plank',        name: 'Side Plank',               kind: 'hold',       muscle: 'Core' },
  { id: 'hollow-hold',       name: 'Hollow Hold',              kind: 'hold',       muscle: 'Core' },
  { id: 'hanging-leg-raise', name: 'Hanging Leg Raise',        kind: 'bodyweight', muscle: 'Core' },
  { id: 'leg-raise',         name: 'Lying Leg Raise',          kind: 'bodyweight', muscle: 'Core' },
  { id: 'v-up',              name: 'V-Up',                     kind: 'bodyweight', muscle: 'Core' },
  { id: 'crunch',            name: 'Crunch',                   kind: 'bodyweight', muscle: 'Core' },
  { id: 'ab-rollout',        name: 'Ab Rollout',               kind: 'bodyweight', muscle: 'Core' },
  { id: 'dead-bug',          name: 'Dead Bug',                 kind: 'bodyweight', muscle: 'Core' },
  { id: 'dragon-flag',       name: 'Dragon Flag',              kind: 'bodyweight', muscle: 'Core' },
  { id: 'cable-crunch',      name: 'Cable Crunch',             kind: 'weight',     muscle: 'Core' },
  { id: 'russian-twist',     name: 'Russian Twist',            kind: 'weight',     muscle: 'Core' },
  { id: 'wood-chop',         name: 'Cable Wood Chop',          kind: 'weight',     muscle: 'Core' },

  // ── Full Body ────────────────────────────────────────────────────────────
  { id: 'clean-press',       name: 'Clean & Press',            kind: 'weight',     muscle: 'Full Body' },
  { id: 'thruster',          name: 'Thruster',                 kind: 'weight',     muscle: 'Full Body' },
  { id: 'burpee',            name: 'Burpee',                   kind: 'bodyweight', muscle: 'Full Body' },
  { id: 'turkish-get-up',    name: 'Turkish Get-Up',           kind: 'weight',     muscle: 'Full Body' },
  { id: 'man-maker',         name: 'Man Maker',                kind: 'weight',     muscle: 'Full Body' },

  // ── Cardio ──────────────────────────────────────────────────────────────
  { id: 'run',               name: 'Run',                      kind: 'cardio',     muscle: 'Cardio' },
  { id: 'cycle',             name: 'Cycling',                  kind: 'cardio',     muscle: 'Cardio' },
  { id: 'row-erg',           name: 'Rowing Machine',           kind: 'cardio',     muscle: 'Cardio' },
  { id: 'incline-walk',      name: 'Incline Treadmill Walk',   kind: 'cardio',     muscle: 'Cardio' },
  { id: 'elliptical',        name: 'Elliptical',               kind: 'cardio',     muscle: 'Cardio' },
  { id: 'assault-bike',      name: 'Assault Bike',             kind: 'cardio',     muscle: 'Cardio' },
  { id: 'swim',              name: 'Swimming',                 kind: 'cardio',     muscle: 'Cardio' },
  { id: 'jump-rope',         name: 'Jump Rope',                kind: 'hold',       muscle: 'Cardio' },
  { id: 'stair-master',      name: 'Stair Master',             kind: 'hold',       muscle: 'Cardio' },
  { id: 'box-jump',          name: 'Box Jump',                 kind: 'bodyweight', muscle: 'Cardio' },
]

const r = (exerciseId: string, targetSets: number, targetReps?: number, restSec = 90) => ({
  exerciseId,
  targetSets,
  targetReps,
  restSec,
})

/** Starter routine templates referencing the seed library. */
export const SEED_ROUTINES: Routine[] = [
  {
    id: 'tpl-push',
    name: 'Push Day',
    createdAt: 0,
    exercises: [r('bench-press', 4, 8, 120), r('ohp', 3, 8), r('incline-db-press', 3, 10), r('lateral-raise', 3, 15, 60), r('tricep-pushdown', 3, 12, 60)],
  },
  {
    id: 'tpl-pull',
    name: 'Pull Day',
    createdAt: 0,
    exercises: [r('deadlift', 3, 5, 150), r('pull-up', 3, 8), r('barbell-row', 3, 10), r('seated-row', 3, 12), r('barbell-curl', 3, 12, 60), r('face-pull', 3, 15, 60)],
  },
  {
    id: 'tpl-legs',
    name: 'Leg Day',
    createdAt: 0,
    exercises: [r('back-squat', 4, 6, 150), r('romanian-deadlift', 3, 8), r('leg-press', 3, 12), r('leg-curl', 3, 12, 60), r('calf-raise', 4, 15, 45)],
  },
  {
    id: 'tpl-upper',
    name: 'Upper Body',
    createdAt: 0,
    exercises: [r('bench-press', 4, 8, 120), r('barbell-row', 4, 8, 120), r('ohp', 3, 10), r('lat-pulldown', 3, 12), r('db-curl', 3, 12, 60), r('tricep-pushdown', 3, 12, 60)],
  },
  {
    id: 'tpl-lower',
    name: 'Lower Body',
    createdAt: 0,
    exercises: [r('back-squat', 4, 6, 150), r('romanian-deadlift', 3, 10), r('hip-thrust', 3, 10, 90), r('leg-extension', 3, 12, 60), r('leg-curl', 3, 12, 60), r('calf-raise', 4, 15, 45)],
  },
  {
    id: 'tpl-fullbody',
    name: 'Full Body',
    createdAt: 0,
    exercises: [r('back-squat', 3, 8, 120), r('bench-press', 3, 8, 120), r('barbell-row', 3, 8, 120), r('ohp', 3, 10), r('plank', 3, undefined, 45)],
  },
]
