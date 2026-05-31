import { dayKey, monthGrid, monthLabel } from '../lib/date'
import type { Bill } from '../lib/types'

const WEEKDAYS = ['M', 'T', 'W', 'T', 'F', 'S', 'S']

/** Day-of-month a bill actually lands on this month (clamped to month length). */
function billDay(b: Bill, daysInMonth: number): number {
  return Math.min(b.dayOfMonth, daysInMonth)
}

/**
 * Month calendar that marks the days direct debits leave the account.
 * Tapping a marked day calls onSelectDay with that day's bills.
 */
export default function BillCalendar({
  bills,
  onSelectDay,
}: {
  bills: Bill[]
  onSelectDay: (day: number, bills: Bill[]) => void
}) {
  const now = new Date()
  const grid = monthGrid(now)
  const todayKey = dayKey(now)
  const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()

  const billsOnDay = (date: number) => bills.filter((b) => billDay(b, daysInMonth) === date)

  return (
    <div className="rounded-card bg-surface p-4 shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
      <div className="mb-3 text-headline text-label">{monthLabel(now)}</div>
      <div className="mb-1 grid grid-cols-7 gap-1">
        {WEEKDAYS.map((d, i) => (
          <div key={i} className="text-center text-caption font-medium text-label3">
            {d}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1">
        {grid.map((d, i) => {
          const inMonth = d.getMonth() === now.getMonth()
          const due = inMonth ? billsOnDay(d.getDate()) : []
          const has = due.length > 0
          const isToday = dayKey(d) === todayKey
          return (
            <button
              key={i}
              disabled={!has}
              onClick={() => onSelectDay(d.getDate(), due)}
              aria-label={has ? `${d.getDate()}: ${due.length} payment${due.length > 1 ? 's' : ''}` : undefined}
              className="flex aspect-square items-center justify-center"
            >
              <div
                className={`relative grid h-9 w-9 place-items-center rounded-full text-footnote ${
                  has
                    ? 'bg-accent font-semibold text-white'
                    : isToday
                      ? 'text-label ring-1 ring-inset ring-accent'
                      : inMonth
                        ? 'text-label2'
                        : 'text-label3/40'
                }`}
              >
                {d.getDate()}
                {due.length > 1 && (
                  <span className="absolute -bottom-1 left-1/2 -translate-x-1/2 text-[9px] leading-none text-white">
                    {due.length}
                  </span>
                )}
              </div>
            </button>
          )
        })}
      </div>
      {bills.length > 0 && (
        <div className="mt-3 flex items-center gap-1.5 text-caption text-label2">
          <span className="inline-block h-2.5 w-2.5 rounded-full bg-accent" /> payment day · tap to see what’s due
        </div>
      )}
    </div>
  )
}
