/** Local YYYY-MM-DD key for a given date (defaults to now). */
export function dayKey(d: Date = new Date()): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/** "Thursday, 29 May" */
export function longDate(d: Date = new Date()): string {
  return d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })
}

export function greeting(d: Date = new Date()): string {
  const h = d.getHours()
  if (h < 5) return 'Still up'
  if (h < 12) return 'Good morning'
  if (h < 18) return 'Good afternoon'
  return 'Good evening'
}

/** "May 2026" */
export function monthLabel(d: Date = new Date()): string {
  return d.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
}

/**
 * A 6-week grid of dates covering the month `d` is in, starting on Monday.
 * Days outside the month are included so the grid is rectangular; callers can
 * compare `getMonth()` to dim them.
 */
export function monthGrid(d: Date = new Date()): Date[] {
  const first = new Date(d.getFullYear(), d.getMonth(), 1)
  const lead = (first.getDay() + 6) % 7 // Mon=0
  const start = new Date(first)
  start.setDate(first.getDate() - lead)
  return Array.from({ length: 42 }, (_, i) => {
    const x = new Date(start)
    x.setDate(start.getDate() + i)
    return x
  })
}

/** "in 3 days", "today", "tomorrow" for a bill's day-of-month. */
export function billCountdown(dayOfMonth: number, now: Date = new Date()): { days: number; label: string } {
  const year = now.getFullYear()
  const month = now.getMonth()
  // Clamp the day to the number of days in the relevant month.
  const daysThisMonth = new Date(year, month + 1, 0).getDate()
  let target = new Date(year, month, Math.min(dayOfMonth, daysThisMonth))
  const today = new Date(year, month, now.getDate())
  if (target < today) {
    const dThm = new Date(year, month + 2, 0).getDate()
    target = new Date(year, month + 1, Math.min(dayOfMonth, dThm))
  }
  const days = Math.round((target.getTime() - today.getTime()) / 86_400_000)
  const label = days === 0 ? 'Today' : days === 1 ? 'Tomorrow' : `In ${days} days`
  return { days, label }
}
