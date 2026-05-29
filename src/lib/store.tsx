import { createContext, useContext, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import type {
  Bill,
  CareDay,
  Category,
  Exercise,
  ExerciseKind,
  Habit,
  LifeState,
  LoggedSet,
  Routine,
  RoutineExercise,
  Task,
  WorkoutSession,
} from './types'
import { dayKey } from './date'
import { SEED_EXERCISES, SEED_ROUTINES } from './workoutSeed'

const STORAGE_KEY = 'life.v1'

const DEFAULT_STATE: LifeState = {
  tasks: [
    { id: 't1', title: 'Reply to the email I keep avoiding', category: 'work', done: false, createdAt: Date.now() },
    { id: 't2', title: 'Push session — legs', category: 'gym', done: false, createdAt: Date.now() },
    { id: 't3', title: 'Refill water bottle', category: 'personal', done: true, createdAt: Date.now() },
  ],
  bills: [
    { id: 'b1', name: 'Rent', amount: 950, dayOfMonth: 1 },
    { id: 'b2', name: 'Phone', amount: 22, dayOfMonth: 12 },
    { id: 'b3', name: 'Gym membership', amount: 30, dayOfMonth: 15 },
    { id: 'b4', name: 'Spotify', amount: 11.99, dayOfMonth: 20 },
  ],
  care: {},
  careSettings: {
    remindersEnabled: false,
    waterGoal: 8,
    waterIntervalMin: 60,
    mealsGoal: 3,
    breakIntervalMin: 50,
  },
  name: '',
  exercises: SEED_EXERCISES,
  routines: SEED_ROUTINES,
  sessions: [],
  workoutSettings: {
    unit: 'kg',
    defaultRestSec: 90,
    restTimerEnabled: true,
  },
  habits: [
    { id: 'h1', name: 'Read', emoji: '📖', color: '#32ade6', kind: 'build', cadence: 'daily', target: 20, unit: 'pages', createdAt: Date.now() },
    { id: 'h2', name: 'Meditate', emoji: '🧘', color: '#bf5af2', kind: 'build', cadence: 'daily', createdAt: Date.now() },
    { id: 'h3', name: 'Workout', emoji: '💪', color: '#30d158', kind: 'build', cadence: 'weekly', timesPerWeek: 3, createdAt: Date.now() },
    { id: 'h4', name: 'No doomscrolling', emoji: '📵', color: '#ff375f', kind: 'break', cadence: 'daily', createdAt: Date.now() },
  ],
  habitLogs: {},
}

function load(): LifeState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return DEFAULT_STATE
    const parsed = JSON.parse(raw) as Partial<LifeState>
    // Shallow-merge so new fields added later don't break old saves.
    return {
      ...DEFAULT_STATE,
      ...parsed,
      careSettings: { ...DEFAULT_STATE.careSettings, ...(parsed.careSettings ?? {}) },
      workoutSettings: { ...DEFAULT_STATE.workoutSettings, ...(parsed.workoutSettings ?? {}) },
      // Re-seed the library/templates if an older save predates the workout feature.
      exercises: parsed.exercises?.length ? parsed.exercises : DEFAULT_STATE.exercises,
      routines: parsed.routines ?? DEFAULT_STATE.routines,
      sessions: parsed.sessions ?? [],
      // Seed example habits only for saves that predate the habits feature.
      habits: parsed.habits ?? DEFAULT_STATE.habits,
      habitLogs: parsed.habitLogs ?? {},
    }
  } catch {
    return DEFAULT_STATE
  }
}

const EMPTY_DAY: CareDay = { water: 0, meals: 0, lastBreakAt: null }

interface LifeContextValue {
  state: LifeState
  today: CareDay
  activeSession: WorkoutSession | undefined
  // tasks
  addTask: (title: string, category: Category) => void
  toggleTask: (id: string) => void
  deleteTask: (id: string) => void
  // bills
  addBill: (name: string, amount: number, dayOfMonth: number) => void
  deleteBill: (id: string) => void
  // care
  addWater: (n?: number) => void
  addMeal: () => void
  markBreak: () => void
  setName: (name: string) => void
  setCareSettings: (patch: Partial<LifeState['careSettings']>) => void
  // workout — routines & library
  addRoutine: (name: string, exercises: RoutineExercise[]) => void
  updateRoutine: (id: string, patch: Partial<Omit<Routine, 'id'>>) => void
  deleteRoutine: (id: string) => void
  duplicateRoutine: (id: string) => void
  addCustomExercise: (name: string, kind: ExerciseKind, muscle?: string) => string
  // workout — sessions
  startSession: (routineId?: string) => void
  updateSet: (sessionId: string, exIdx: number, setIdx: number, patch: Partial<LoggedSet>) => void
  toggleSetDone: (sessionId: string, exIdx: number, setIdx: number) => void
  addSet: (sessionId: string, exIdx: number) => void
  removeSet: (sessionId: string, exIdx: number, setIdx: number) => void
  addExerciseToSession: (sessionId: string, exerciseId: string) => void
  removeExerciseFromSession: (sessionId: string, exIdx: number) => void
  renameSession: (sessionId: string, name: string) => void
  finishSession: (sessionId: string) => void
  discardSession: (sessionId: string) => void
  setWorkoutSettings: (patch: Partial<LifeState['workoutSettings']>) => void
  // habits
  addHabit: (habit: Omit<Habit, 'id' | 'createdAt'>) => void
  updateHabit: (id: string, patch: Partial<Omit<Habit, 'id'>>) => void
  deleteHabit: (id: string) => void
  toggleArchiveHabit: (id: string) => void
  /** Set the logged amount for a habit on a given day (YYYY-MM-DD). */
  logHabit: (id: string, dateKey: string, amount: number) => void
  /** Toggle a build habit done/undone today. */
  toggleHabitToday: (id: string) => void
  /** Add to today's amount for a quantified habit (delta may be negative). */
  incHabitToday: (id: string, delta: number) => void
  /** Record a slip for a break habit today. */
  slipHabitToday: (id: string) => void
}

const LifeContext = createContext<LifeContextValue | null>(null)

function uid() {
  return Math.random().toString(36).slice(2, 10)
}

/** Prefilled sets for a routine exercise, sized to its target. */
function buildSets(kind: ExerciseKind | undefined, re: RoutineExercise): LoggedSet[] {
  return Array.from({ length: Math.max(1, re.targetSets) }, () => {
    const set: LoggedSet = { done: false }
    if (kind === 'weight') {
      if (re.targetWeight != null) set.weight = re.targetWeight
      if (re.targetReps != null) set.reps = re.targetReps
    } else if (kind === 'bodyweight') {
      if (re.targetReps != null) set.reps = re.targetReps
    }
    return set
  })
}

export function LifeProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<LifeState>(load)
  const todayKey = dayKey()

  // Persist on every change.
  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
  }, [state])

  const today = state.care[todayKey] ?? EMPTY_DAY
  const activeSession = state.sessions.find((s) => s.finishedAt == null)

  const mutateToday = (fn: (d: CareDay) => CareDay) => {
    setState((s) => {
      const cur = s.care[todayKey] ?? EMPTY_DAY
      return { ...s, care: { ...s.care, [todayKey]: fn(cur) } }
    })
  }

  // Immutably update one session by id.
  const mutateSession = (id: string, fn: (s: WorkoutSession) => WorkoutSession) =>
    setState((st) => ({ ...st, sessions: st.sessions.map((s) => (s.id === id ? fn(s) : s)) }))

  const mutateSet = (
    id: string,
    exIdx: number,
    setIdx: number,
    fn: (set: LoggedSet) => LoggedSet,
  ) =>
    mutateSession(id, (s) => ({
      ...s,
      exercises: s.exercises.map((ex, i) =>
        i !== exIdx ? ex : { ...ex, sets: ex.sets.map((set, j) => (j === setIdx ? fn(set) : set)) },
      ),
    }))

  const value = useMemo<LifeContextValue>(
    () => ({
      state,
      today,
      activeSession,
      addTask: (title, category) =>
        setState((s) => ({
          ...s,
          tasks: [{ id: uid(), title: title.trim(), category, done: false, createdAt: Date.now() }, ...s.tasks],
        })),
      toggleTask: (id) =>
        setState((s) => ({ ...s, tasks: s.tasks.map((t) => (t.id === id ? { ...t, done: !t.done } : t)) })),
      deleteTask: (id) => setState((s) => ({ ...s, tasks: s.tasks.filter((t) => t.id !== id) })),
      addBill: (name, amount, dayOfMonth) =>
        setState((s) => ({
          ...s,
          bills: [...s.bills, { id: uid(), name: name.trim(), amount, dayOfMonth }].sort(
            (a, b) => a.dayOfMonth - b.dayOfMonth,
          ),
        })),
      deleteBill: (id) => setState((s) => ({ ...s, bills: s.bills.filter((b) => b.id !== id) })),
      addWater: (n = 1) => mutateToday((d) => ({ ...d, water: Math.max(0, d.water + n) })),
      addMeal: () => mutateToday((d) => ({ ...d, meals: d.meals + 1 })),
      markBreak: () => mutateToday((d) => ({ ...d, lastBreakAt: Date.now() })),
      setName: (name) => setState((s) => ({ ...s, name })),
      setCareSettings: (patch) => setState((s) => ({ ...s, careSettings: { ...s.careSettings, ...patch } })),

      // --- Routines & library ---
      addRoutine: (name, exercises) =>
        setState((s) => ({
          ...s,
          routines: [...s.routines, { id: uid(), name: name.trim() || 'My Routine', exercises, createdAt: Date.now() }],
        })),
      updateRoutine: (id, patch) =>
        setState((s) => ({ ...s, routines: s.routines.map((r) => (r.id === id ? { ...r, ...patch } : r)) })),
      deleteRoutine: (id) => setState((s) => ({ ...s, routines: s.routines.filter((r) => r.id !== id) })),
      duplicateRoutine: (id) =>
        setState((s) => {
          const r = s.routines.find((x) => x.id === id)
          if (!r) return s
          return {
            ...s,
            routines: [
              ...s.routines,
              { ...r, id: uid(), name: `${r.name} copy`, createdAt: Date.now(), sharedFrom: undefined },
            ],
          }
        }),
      addCustomExercise: (name, kind, muscle) => {
        const id = uid()
        setState((s) => ({
          ...s,
          exercises: [...s.exercises, { id, name: name.trim(), kind, muscle, isCustom: true }],
        }))
        return id
      },

      // --- Sessions ---
      startSession: (routineId) =>
        setState((s) => {
          if (s.sessions.some((x) => x.finishedAt == null)) return s // one active at a time
          const routine = routineId ? s.routines.find((r) => r.id === routineId) : undefined
          const exercises = routine
            ? routine.exercises.map((re) => ({
                exerciseId: re.exerciseId,
                sets: buildSets(s.exercises.find((e) => e.id === re.exerciseId)?.kind, re),
              }))
            : []
          const session: WorkoutSession = {
            id: uid(),
            name: routine?.name ?? 'Quick Workout',
            routineId: routine?.id,
            date: dayKey(),
            startedAt: Date.now(),
            exercises,
          }
          return { ...s, sessions: [session, ...s.sessions] }
        }),
      updateSet: (id, exIdx, setIdx, patch) => mutateSet(id, exIdx, setIdx, (set) => ({ ...set, ...patch })),
      toggleSetDone: (id, exIdx, setIdx) => mutateSet(id, exIdx, setIdx, (set) => ({ ...set, done: !set.done })),
      addSet: (id, exIdx) =>
        mutateSession(id, (s) => ({
          ...s,
          exercises: s.exercises.map((ex, i) => {
            if (i !== exIdx) return ex
            const last = ex.sets[ex.sets.length - 1]
            const clone: LoggedSet = { done: false }
            if (last?.weight != null) clone.weight = last.weight
            if (last?.reps != null) clone.reps = last.reps
            return { ...ex, sets: [...ex.sets, clone] }
          }),
        })),
      removeSet: (id, exIdx, setIdx) =>
        mutateSession(id, (s) => ({
          ...s,
          exercises: s.exercises.map((ex, i) =>
            i !== exIdx ? ex : { ...ex, sets: ex.sets.filter((_, j) => j !== setIdx) },
          ),
        })),
      addExerciseToSession: (id, exerciseId) =>
        mutateSession(id, (s) => ({ ...s, exercises: [...s.exercises, { exerciseId, sets: [{ done: false }] }] })),
      removeExerciseFromSession: (id, exIdx) =>
        mutateSession(id, (s) => ({ ...s, exercises: s.exercises.filter((_, i) => i !== exIdx) })),
      renameSession: (id, name) => mutateSession(id, (s) => ({ ...s, name: name || s.name })),
      finishSession: (id) => mutateSession(id, (s) => ({ ...s, finishedAt: Date.now() })),
      discardSession: (id) => setState((s) => ({ ...s, sessions: s.sessions.filter((x) => x.id !== id) })),
      setWorkoutSettings: (patch) => setState((s) => ({ ...s, workoutSettings: { ...s.workoutSettings, ...patch } })),

      // --- Habits ---
      addHabit: (habit) =>
        setState((s) => ({ ...s, habits: [...s.habits, { ...habit, id: uid(), createdAt: Date.now() }] })),
      updateHabit: (id, patch) =>
        setState((s) => ({ ...s, habits: s.habits.map((h) => (h.id === id ? { ...h, ...patch } : h)) })),
      deleteHabit: (id) =>
        setState((s) => {
          const logs = { ...s.habitLogs }
          delete logs[id]
          return { ...s, habits: s.habits.filter((h) => h.id !== id), habitLogs: logs }
        }),
      toggleArchiveHabit: (id) =>
        setState((s) => ({ ...s, habits: s.habits.map((h) => (h.id === id ? { ...h, archived: !h.archived } : h)) })),
      logHabit: (id, dateKey, amount) =>
        setState((s) => ({
          ...s,
          habitLogs: { ...s.habitLogs, [id]: { ...(s.habitLogs[id] ?? {}), [dateKey]: Math.max(0, amount) } },
        })),
      toggleHabitToday: (id) =>
        setState((s) => {
          const h = s.habits.find((x) => x.id === id)
          if (!h) return s
          const cur = s.habitLogs[id]?.[todayKey] ?? 0
          const tgt = h.target ?? 1
          const next = cur >= tgt ? 0 : tgt
          return { ...s, habitLogs: { ...s.habitLogs, [id]: { ...(s.habitLogs[id] ?? {}), [todayKey]: next } } }
        }),
      incHabitToday: (id, delta) =>
        setState((s) => {
          const cur = s.habitLogs[id]?.[todayKey] ?? 0
          return {
            ...s,
            habitLogs: { ...s.habitLogs, [id]: { ...(s.habitLogs[id] ?? {}), [todayKey]: Math.max(0, cur + delta) } },
          }
        }),
      slipHabitToday: (id) =>
        setState((s) => {
          const cur = s.habitLogs[id]?.[todayKey] ?? 0
          return { ...s, habitLogs: { ...s.habitLogs, [id]: { ...(s.habitLogs[id] ?? {}), [todayKey]: cur + 1 } } }
        }),
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [state, today, todayKey, activeSession],
  )

  const ref = useRef(state)
  ref.current = state

  return <LifeContext.Provider value={value}>{children}</LifeContext.Provider>
}

export function useLife() {
  const ctx = useContext(LifeContext)
  if (!ctx) throw new Error('useLife must be used within LifeProvider')
  return ctx
}

export type { Bill, Exercise, Habit, Routine, Task, WorkoutSession }
