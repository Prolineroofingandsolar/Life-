import type { Habit, HabitLogs } from './types'
import { dayKey } from './date'
import { startOfWeek } from './workout'

export const WEEKDAY_LETTERS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'] // index = JS getDay (0=Sun)
export const WEEKDAY_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

export function targetFor(h: Habit): number {
  return h.target ?? 1
}

export function amountOn(logs: HabitLogs, id: string, key: string): number {
  return logs[id]?.[key] ?? 0
}

/** Is the habit meant to be acted on this date? (break habits = every day.) */
export function isScheduledOn(h: Habit, d: Date): boolean {
  if (h.kind === 'break') return true
  switch (h.cadence) {
    case 'daily':
      return true
    case 'weekly':
      return true // any day counts toward the weekly target
    case 'weekdays':
      return (h.weekdays ?? []).includes(d.getDay())
  }
}

/** For build habits: target met that day. For break: stayed clean (no slip). */
export function isSuccessOn(h: Habit, logs: HabitLogs, d: Date): boolean {
  const amt = amountOn(logs, h.id, dayKey(d))
  if (h.kind === 'break') return amt === 0
  return amt >= targetFor(h)
}

export function progressOn(h: Habit, logs: HabitLogs, d: Date): number {
  const amt = amountOn(logs, h.id, dayKey(d))
  return Math.max(0, Math.min(1, amt / targetFor(h)))
}

/** Count of successful days in the current week (for weekly cadence). */
export function weekDoneCount(h: Habit, logs: HabitLogs, now = new Date()): number {
  const start = startOfWeek(now)
  let n = 0
  for (let i = 0; i < 7; i++) {
    const d = new Date(start)
    d.setDate(start.getDate() + i)
    if (d > now) break
    if (isSuccessOn(h, logs, d)) n++
  }
  return n
}

/** Whether the habit still needs attention today (not yet satisfied). */
export function isPendingToday(h: Habit, logs: HabitLogs, now = new Date()): boolean {
  if (!isScheduledOn(h, now)) return false
  if (h.kind === 'break') return false // break habits aren't "checked off"
  if (h.cadence === 'weekly') return weekDoneCount(h, logs, now) < (h.timesPerWeek ?? 1)
  return !isSuccessOn(h, logs, now)
}

const DAY = 86_400_000

function startOfDay(t: number | Date): number {
  const d = new Date(t)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

/**
 * Current streak.
 * - break: consecutive clean days ending today (bounded by when the habit was created).
 * - build daily/weekdays: consecutive scheduled days hit (today may still be pending).
 * - build weekly: consecutive weeks the target was met (current week counts only if met).
 */
export function currentStreak(h: Habit, logs: HabitLogs, now = new Date()): number {
  const createdDay = startOfDay(h.createdAt)

  if (h.kind === 'break') {
    // Count clean days back to (and including) the day it was created.
    let streak = 0
    for (let i = 0; i < 3660; i++) {
      const d = new Date(now.getTime() - i * DAY)
      if (startOfDay(d) < createdDay) break
      if (isSuccessOn(h, logs, d)) streak++
      else break // a slip ends the run immediately (incl. today)
    }
    return streak
  }

  if (h.cadence === 'daily') {
    let streak = 0
    for (let i = 0; i < 3660; i++) {
      const d = new Date(now.getTime() - i * DAY)
      if (startOfDay(d) < createdDay) break
      if (isSuccessOn(h, logs, d)) streak++
      else if (i === 0) continue // today still pending — don't break
      else break
    }
    return streak
  }

  if (h.cadence === 'weekdays') {
    let streak = 0
    for (let i = 0; i < 3660; i++) {
      const d = new Date(now.getTime() - i * DAY)
      if (startOfDay(d) < createdDay) break
      if (!isScheduledOn(h, d)) continue
      if (isSuccessOn(h, logs, d)) streak++
      else if (i === 0) continue
      else break
    }
    return streak
  }

  // weekly
  const times = h.timesPerWeek ?? 1
  let streak = 0
  for (let w = 0; w < 520; w++) {
    const ref = new Date(now.getTime() - w * 7 * DAY)
    const count = weekDoneCount(h, logs, w === 0 ? now : endOfWeek(ref))
    if (count >= times) streak++
    else if (w === 0) continue // current week still in progress
    else break
  }
  return streak
}

function endOfWeek(d: Date): Date {
  const s = startOfWeek(d)
  const e = new Date(s)
  e.setDate(s.getDate() + 6)
  return e
}

/** Best historical streak (days for daily/weekdays/break; weeks for weekly). */
export function bestStreak(h: Habit, logs: HabitLogs, now = new Date()): number {
  const keys = Object.keys(logs[h.id] ?? {})
  if (h.kind !== 'break' && keys.length === 0) return currentStreak(h, logs, now)

  if (h.cadence === 'weekly') {
    // Scan back ~2 years of weeks.
    let best = 0
    let run = 0
    for (let w = 104; w >= 0; w--) {
      const ref = new Date(now.getTime() - w * 7 * DAY)
      const count = weekDoneCount(h, logs, w === 0 ? now : endOfWeek(ref))
      if (count >= (h.timesPerWeek ?? 1)) {
        run++
        best = Math.max(best, run)
      } else if (w !== 0) run = 0
    }
    return best
  }

  const createdDay = startOfDay(h.createdAt)
  let best = 0
  let run = 0
  for (let i = 730; i >= 0; i--) {
    const d = new Date(now.getTime() - i * DAY)
    if (startOfDay(d) < createdDay) continue // before the habit existed
    if (h.kind !== 'break' && !isScheduledOn(h, d)) continue
    if (isSuccessOn(h, logs, d)) {
      run++
      best = Math.max(best, run)
    } else if (i !== 0) {
      run = 0
    }
  }
  return best
}

/** Days since the last slip for a break habit (same as its current streak). */
export function daysClean(h: Habit, logs: HabitLogs, now = new Date()): number {
  return currentStreak(h, logs, now)
}

/** Short schedule description, e.g. "Daily", "Mon, Wed, Fri", "3× / week". */
export function cadenceLabel(h: Habit): string {
  if (h.kind === 'break') return 'Avoid daily'
  if (h.cadence === 'daily') return 'Daily'
  if (h.cadence === 'weekly') return `${h.timesPerWeek ?? 1}× / week`
  const days = (h.weekdays ?? []).slice().sort((a, b) => a - b)
  if (days.length === 7) return 'Daily'
  return days.map((d) => WEEKDAY_SHORT[d]).join(', ') || 'No days'
}
