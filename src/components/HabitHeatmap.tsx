import { dayKey, monthGrid, monthLabel } from '../lib/date'
import { isScheduledOn, isSuccessOn } from '../lib/habits'
import type { Habit, HabitLogs } from '../lib/types'

const WEEKDAYS = ['M', 'T', 'W', 'T', 'F', 'S', 'S']
// monthGrid starts on Monday; JS getDay 1..0. We render Mon-first headers.

export default function HabitHeatmap({ habit, logs }: { habit: Habit; logs: HabitLogs }) {
  const now = new Date()
  const grid = monthGrid(now)
  const todayKey = dayKey(now)

  return (
    <div className="rounded-card bg-surface p-4 shadow-card">
      <div className="mb-3 text-headline text-label">{monthLabel(now)}</div>
      <div className="mb-1 grid grid-cols-7 gap-1">
        {WEEKDAYS.map((d, i) => (
          <div key={i} className="text-center text-caption font-medium text-label3">{d}</div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1">
        {grid.map((d, i) => {
          const key = dayKey(d)
          const inMonth = d.getMonth() === now.getMonth()
          const future = d > now
          const scheduled = isScheduledOn(habit, d)
          const success = !future && isSuccessOn(habit, logs, d)
          const missed = !future && habit.kind === 'build' && scheduled && !success
          const slip = !future && habit.kind === 'break' && !success
          const isToday = key === todayKey

          let cls = 'text-label3/40'
          const style: React.CSSProperties = {}
          if (success && (scheduled || habit.kind === 'break')) {
            style.background = habit.color
            cls = 'font-semibold text-white'
          } else if (slip) {
            style.background = 'rgb(255 55 95 / 0.18)'
            cls = 'text-danger'
          } else if (missed) {
            cls = 'text-label3'
          } else if (inMonth) {
            cls = 'text-label3'
          }

          return (
            <div key={i} className="flex aspect-square items-center justify-center">
              <div
                className={`grid h-8 w-8 place-items-center rounded-full text-footnote ${cls} ${
                  isToday && !success ? 'ring-1 ring-inset ring-accent' : ''
                } ${!inMonth ? 'opacity-30' : ''}`}
                style={style}
              >
                {d.getDate()}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
