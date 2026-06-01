import type { Exercise, LoggedSet, SessionExercise, WorkoutSession } from './types'
import { dayKey } from './date'

export function exerciseById(exercises: Exercise[], id: string): Exercise | undefined {
  return exercises.find((e) => e.id === id)
}

export function isFinished(s: WorkoutSession): boolean {
  return s.finishedAt != null
}

/** Total weight moved in a session (kg·reps over completed working sets — warmups excluded). */
export function sessionVolume(session: WorkoutSession): number {
  let v = 0
  for (const ex of session.exercises) {
    for (const set of ex.sets) {
      if (set.done && !set.isWarmup && set.weight && set.reps) v += set.weight * set.reps
    }
  }
  return Math.round(v)
}

export function sessionSetCount(session: WorkoutSession): number {
  return session.exercises.reduce(
    (n, ex) => n + ex.sets.filter((s) => s.done && !s.isWarmup).length,
    0,
  )
}

/** Epley estimated one-rep max. */
export function estimated1RM(weight: number, reps: number): number {
  return reps <= 1 ? weight : Math.round(weight * (1 + reps / 30))
}

export interface ExercisePRs {
  bestWeight?: number
  best1RM?: number
  bestReps?: number
  bestDistanceKm?: number
  bestDurationSec?: number
}

function foldSets(sets: LoggedSet[], pr: ExercisePRs) {
  for (const s of sets) {
    if (!s.done || s.isWarmup) continue
    if (s.weight != null) pr.bestWeight = Math.max(pr.bestWeight ?? 0, s.weight)
    if (s.weight != null && s.reps != null) pr.best1RM = Math.max(pr.best1RM ?? 0, estimated1RM(s.weight, s.reps))
    if (s.reps != null) pr.bestReps = Math.max(pr.bestReps ?? 0, s.reps)
    if (s.distanceKm != null) pr.bestDistanceKm = Math.max(pr.bestDistanceKm ?? 0, s.distanceKm)
    if (s.durationSec != null) pr.bestDurationSec = Math.max(pr.bestDurationSec ?? 0, s.durationSec)
  }
}

/** Personal records for one exercise across the given (finished) sessions. */
export function computePRs(sessions: WorkoutSession[], exerciseId: string): ExercisePRs {
  const pr: ExercisePRs = {}
  for (const session of sessions) {
    if (!isFinished(session)) continue
    for (const ex of session.exercises) {
      if (ex.exerciseId === exerciseId) foldSets(ex.sets, pr)
    }
  }
  return pr
}

export interface PRHit {
  exerciseId: string
  label: string
}

/** PRs set by `session` versus all prior finished history. */
export function newPRsForSession(history: WorkoutSession[], session: WorkoutSession, exercises: Exercise[]): PRHit[] {
  const prior = history.filter((s) => s.id !== session.id)
  const hits: PRHit[] = []
  for (const ex of session.exercises) {
    const before = computePRs(prior, ex.exerciseId)
    const now: ExercisePRs = {}
    foldSets(ex.sets, now)
    const name = exerciseById(exercises, ex.exerciseId)?.name ?? 'Exercise'
    if (now.bestWeight != null && now.bestWeight > (before.bestWeight ?? 0)) {
      hits.push({ exerciseId: ex.exerciseId, label: `${name} · ${now.bestWeight} top set` })
    } else if (now.best1RM != null && now.best1RM > (before.best1RM ?? 0)) {
      hits.push({ exerciseId: ex.exerciseId, label: `${name} · est. 1RM ${now.best1RM}` })
    } else if (now.bestReps != null && now.bestReps > (before.bestReps ?? 0) && now.bestWeight == null) {
      hits.push({ exerciseId: ex.exerciseId, label: `${name} · ${now.bestReps} reps` })
    } else if (now.bestDistanceKm != null && now.bestDistanceKm > (before.bestDistanceKm ?? 0)) {
      hits.push({ exerciseId: ex.exerciseId, label: `${name} · ${now.bestDistanceKm} km` })
    }
  }
  return hits
}

/** Completed sets for the exercise from the most recent finished session. */
export function lastPerformance(sessions: WorkoutSession[], exerciseId: string): SessionExercise | undefined {
  const done = sessions.filter(isFinished).sort((a, b) => (b.finishedAt ?? 0) - (a.finishedAt ?? 0))
  for (const s of done) {
    const ex = s.exercises.find((e) => e.exerciseId === exerciseId && e.sets.some((set) => set.done))
    if (ex) return ex
  }
  return undefined
}

/**
 * Returns true if this completed set beats the all-time best for the exercise
 * across all prior finished sessions (excluding the current one being logged).
 */
export function isSetPR(
  sessions: WorkoutSession[],
  currentSessionId: string,
  exerciseId: string,
  set: LoggedSet,
): boolean {
  if (!set.done || set.isWarmup) return false
  const prior = computePRs(
    sessions.filter((s) => isFinished(s) && s.id !== currentSessionId),
    exerciseId,
  )
  if (set.weight != null && set.reps != null) {
    const e1rm = estimated1RM(set.weight, set.reps)
    return e1rm > (prior.best1RM ?? 0) || set.weight > (prior.bestWeight ?? 0)
  }
  if (set.reps != null) return set.reps > (prior.bestReps ?? 0)
  if (set.distanceKm != null) return set.distanceKm > (prior.bestDistanceKm ?? 0)
  if (set.durationSec != null) return set.durationSec > (prior.bestDurationSec ?? 0)
  return false
}

/** Short "prev" hint for a set, e.g. "60×8" or "5 km". */
export function setHint(set: LoggedSet | undefined): string {
  if (!set) return '—'
  if (set.weight != null && set.reps != null) return `${set.weight}×${set.reps}`
  if (set.reps != null) return `${set.reps} reps`
  if (set.distanceKm != null) return `${set.distanceKm} km`
  if (set.durationSec != null) return `${set.durationSec}s`
  return '—'
}

/** Current streak: consecutive days (ending today or yesterday) with a finished session. */
export function workoutStreak(sessions: WorkoutSession[]): number {
  const days = new Set(sessions.filter(isFinished).map((s) => s.date))
  if (days.size === 0) return 0
  const today = new Date()
  let cursor = new Date(today)
  if (!days.has(dayKey(cursor))) {
    cursor.setDate(cursor.getDate() - 1)
    if (!days.has(dayKey(cursor))) return 0
  }
  let streak = 0
  while (days.has(dayKey(cursor))) {
    streak++
    cursor.setDate(cursor.getDate() - 1)
  }
  return streak
}

export function sessionsThisWeek(sessions: WorkoutSession[], now = new Date()): WorkoutSession[] {
  const start = startOfWeek(now)
  return sessions.filter((s) => isFinished(s) && new Date(s.startedAt) >= start)
}

export function weeklyVolume(sessions: WorkoutSession[], now = new Date()): number {
  return sessionsThisWeek(sessions, now).reduce((v, s) => v + sessionVolume(s), 0)
}

/** Monday as the start of the week. */
export function startOfWeek(d = new Date()): Date {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  const day = (x.getDay() + 6) % 7 // Mon=0
  x.setDate(x.getDate() - day)
  return x
}

/** Human-readable duration string for a finished session, e.g. "42m" or "1h 12m". */
export function sessionDuration(session: WorkoutSession): string {
  if (!session.finishedAt) return ''
  const mins = Math.round((session.finishedAt - session.startedAt) / 60_000)
  if (mins < 60) return `${mins}m`
  return `${Math.floor(mins / 60)}h ${mins % 60}m`
}

/** Unique muscle groups worked in a session, in order of first appearance. */
export function sessionMuscles(session: WorkoutSession, exercises: Exercise[]): string[] {
  const seen = new Set<string>()
  for (const ex of session.exercises) {
    const muscle = exercises.find((e) => e.id === ex.exerciseId)?.muscle
    if (muscle) seen.add(muscle)
  }
  return Array.from(seen)
}
