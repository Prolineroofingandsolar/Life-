export type Category = 'work' | 'gym' | 'personal'

export type DueDate = 'today' | 'tomorrow' | 'someday'

export interface Task {
  id: string
  title: string
  category: Category
  dueDate?: DueDate
  done: boolean
  createdAt: number
}

export interface Bill {
  id: string
  name: string
  amount: number
  /** Day of the month the direct debit leaves (1–31). */
  dayOfMonth: number
}

/** Per-day record of body-care actions. Keyed by YYYY-MM-DD. */
export interface CareDay {
  water: number
  meals: number
  lastBreakAt: number | null
}

export interface CareSettings {
  remindersEnabled: boolean
  waterGoal: number
  waterIntervalMin: number
  mealsGoal: number
  breakIntervalMin: number
}

/* ------------------------------ Workout ------------------------------ */

export type ExerciseKind = 'weight' | 'bodyweight' | 'cardio' | 'hold'

export const EXERCISE_KIND_LABEL: Record<ExerciseKind, string> = {
  weight: 'Weights',
  bodyweight: 'Bodyweight',
  cardio: 'Cardio',
  hold: 'Timed hold',
}

export interface Exercise {
  id: string
  name: string
  kind: ExerciseKind
  /** Primary muscle / group, e.g. 'Chest', 'Back', 'Legs', 'Core', 'Cardio'. */
  muscle?: string
  isCustom?: boolean
}

/** A planned exercise inside a routine. */
export interface RoutineExercise {
  exerciseId: string
  targetSets: number
  targetReps?: number
  targetWeight?: number
  restSec: number
}

export interface Routine {
  id: string
  name: string
  exercises: RoutineExercise[]
  createdAt: number
  /** Buddy seam (reserved): set when imported from a shared code. */
  sharedFrom?: string
}

/** One logged set. Fields used depend on the exercise kind. */
export interface LoggedSet {
  reps?: number
  weight?: number
  distanceKm?: number
  durationSec?: number
  done: boolean
  /** When true this set immediately follows the previous one with no rest (drop set). */
  isDropSet?: boolean
}

export interface SessionExercise {
  exerciseId: string
  sets: LoggedSet[]
  /** Exercises sharing the same supersetId are performed back-to-back without rest. */
  supersetId?: string
}

export interface WorkoutSession {
  id: string
  name: string
  routineId?: string
  /** YYYY-MM-DD the session belongs to. */
  date: string
  startedAt: number
  /** Undefined while the session is in progress. */
  finishedAt?: number
  exercises: SessionExercise[]
}

export interface WorkoutSettings {
  unit: 'kg' | 'lb'
  defaultRestSec: number
  restTimerEnabled: boolean
}

/* ------------------------------- Habits ------------------------------- */

/** 'build' = a habit to do; 'break' = a habit to quit/avoid. */
export type HabitKind = 'build' | 'break'

/** daily = every day; weekdays = specific days; weekly = X times per week. */
export type HabitCadence = 'daily' | 'weekdays' | 'weekly'

export interface Habit {
  id: string
  name: string
  emoji: string
  color: string
  kind: HabitKind
  cadence: HabitCadence
  /** For cadence 'weekdays': JS day indices (0=Sun … 6=Sat). */
  weekdays?: number[]
  /** For cadence 'weekly': how many times per week. */
  timesPerWeek?: number
  /** Quantified target per day (e.g. 20 pages). Undefined = simple check. */
  target?: number
  unit?: string
  createdAt: number
  archived?: boolean
}

/** habitId -> (YYYY-MM-DD -> amount logged that day). For 'break' habits, amount > 0 means a slip. */
export type HabitLogs = Record<string, Record<string, number>>

export interface LifeState {
  tasks: Task[]
  bills: Bill[]
  /** date -> care record */
  care: Record<string, CareDay>
  careSettings: CareSettings
  /** When the user last opened the app, used for the greeting. */
  name: string
  // Workout
  exercises: Exercise[]
  routines: Routine[]
  sessions: WorkoutSession[]
  workoutSettings: WorkoutSettings
  // Habits
  habits: Habit[]
  habitLogs: HabitLogs
}

export const HABIT_COLORS = ['#5e5ce6', '#32ade6', '#30d158', '#ff9f0a', '#ff375f', '#ff2d92', '#bf5af2', '#64d2ff']

export const HABIT_EMOJIS = [
  '📖', '🏃', '🧘', '💪', '🥗', '💊', '😴', '💧', '✍️', '🎸',
  '🧠', '☀️', '🚶', '🦷', '🧹', '📵', '🚭', '🍷', '🍔', '🛌',
]

export const CATEGORY_LABEL: Record<Category, string> = {
  work: 'Work',
  gym: 'Gym',
  personal: 'Personal',
}

export const CATEGORY_EMOJI: Record<Category, string> = {
  work: '💼',
  gym: '🏋️',
  personal: '🌱',
}
