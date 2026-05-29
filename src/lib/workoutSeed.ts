import type { Exercise, Routine } from './types'

/**
 * Built-in exercise library. IDs are stable strings so routines (and future
 * shared routines) can reference them portably.
 */
export const SEED_EXERCISES: Exercise[] = [
  // Chest
  { id: 'bench-press', name: 'Barbell Bench Press', kind: 'weight', muscle: 'Chest' },
  { id: 'incline-db-press', name: 'Incline Dumbbell Press', kind: 'weight', muscle: 'Chest' },
  { id: 'chest-fly', name: 'Cable Chest Fly', kind: 'weight', muscle: 'Chest' },
  { id: 'push-up', name: 'Push-up', kind: 'bodyweight', muscle: 'Chest' },
  { id: 'dip', name: 'Dip', kind: 'bodyweight', muscle: 'Chest' },
  // Back
  { id: 'deadlift', name: 'Deadlift', kind: 'weight', muscle: 'Back' },
  { id: 'barbell-row', name: 'Barbell Row', kind: 'weight', muscle: 'Back' },
  { id: 'lat-pulldown', name: 'Lat Pulldown', kind: 'weight', muscle: 'Back' },
  { id: 'seated-row', name: 'Seated Cable Row', kind: 'weight', muscle: 'Back' },
  { id: 'pull-up', name: 'Pull-up', kind: 'bodyweight', muscle: 'Back' },
  { id: 'chin-up', name: 'Chin-up', kind: 'bodyweight', muscle: 'Back' },
  // Legs
  { id: 'back-squat', name: 'Barbell Back Squat', kind: 'weight', muscle: 'Legs' },
  { id: 'front-squat', name: 'Front Squat', kind: 'weight', muscle: 'Legs' },
  { id: 'leg-press', name: 'Leg Press', kind: 'weight', muscle: 'Legs' },
  { id: 'romanian-deadlift', name: 'Romanian Deadlift', kind: 'weight', muscle: 'Legs' },
  { id: 'leg-curl', name: 'Leg Curl', kind: 'weight', muscle: 'Legs' },
  { id: 'leg-extension', name: 'Leg Extension', kind: 'weight', muscle: 'Legs' },
  { id: 'calf-raise', name: 'Calf Raise', kind: 'weight', muscle: 'Legs' },
  { id: 'lunge', name: 'Walking Lunge', kind: 'bodyweight', muscle: 'Legs' },
  { id: 'pistol-squat', name: 'Pistol Squat', kind: 'bodyweight', muscle: 'Legs' },
  // Shoulders
  { id: 'ohp', name: 'Overhead Press', kind: 'weight', muscle: 'Shoulders' },
  { id: 'db-shoulder-press', name: 'Dumbbell Shoulder Press', kind: 'weight', muscle: 'Shoulders' },
  { id: 'lateral-raise', name: 'Lateral Raise', kind: 'weight', muscle: 'Shoulders' },
  { id: 'face-pull', name: 'Face Pull', kind: 'weight', muscle: 'Shoulders' },
  // Arms
  { id: 'barbell-curl', name: 'Barbell Curl', kind: 'weight', muscle: 'Arms' },
  { id: 'db-curl', name: 'Dumbbell Curl', kind: 'weight', muscle: 'Arms' },
  { id: 'tricep-pushdown', name: 'Tricep Pushdown', kind: 'weight', muscle: 'Arms' },
  { id: 'skullcrusher', name: 'Skullcrusher', kind: 'weight', muscle: 'Arms' },
  // Core
  { id: 'plank', name: 'Plank', kind: 'hold', muscle: 'Core' },
  { id: 'hanging-leg-raise', name: 'Hanging Leg Raise', kind: 'bodyweight', muscle: 'Core' },
  { id: 'cable-crunch', name: 'Cable Crunch', kind: 'weight', muscle: 'Core' },
  { id: 'side-plank', name: 'Side Plank', kind: 'hold', muscle: 'Core' },
  // Cardio
  { id: 'run', name: 'Run', kind: 'cardio', muscle: 'Cardio' },
  { id: 'cycle', name: 'Cycling', kind: 'cardio', muscle: 'Cardio' },
  { id: 'row-erg', name: 'Rowing Machine', kind: 'cardio', muscle: 'Cardio' },
  { id: 'incline-walk', name: 'Incline Treadmill Walk', kind: 'cardio', muscle: 'Cardio' },
  { id: 'jump-rope', name: 'Jump Rope', kind: 'hold', muscle: 'Cardio' },
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
    exercises: [r('back-squat', 4, 6, 150), r('romanian-deadlift', 3, 10), r('leg-extension', 3, 12, 60), r('leg-curl', 3, 12, 60), r('calf-raise', 4, 15, 45), r('plank', 3, undefined, 45)],
  },
  {
    id: 'tpl-fullbody',
    name: 'Full Body',
    createdAt: 0,
    exercises: [r('back-squat', 3, 8, 120), r('bench-press', 3, 8, 120), r('barbell-row', 3, 8, 120), r('ohp', 3, 10), r('plank', 3, undefined, 45)],
  },
]
