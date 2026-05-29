import { dayKey, monthGrid, monthLabel } from '../lib/date'

const WEEKDAYS = ['M', 'T', 'W', 'T', 'F', 'S', 'S']

/** Month grid highlighting days that have a finished workout. */
export default function TrainCalendar({ trainedDays }: { trainedDays: Set<string> }) {
  const now = new Date()
  const grid = monthGrid(now)
  const todayKey = dayKey(now)

  return (
    <div className="rounded-card bg-surface p-4 shadow-card">
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
          const key = dayKey(d)
          const inMonth = d.getMonth() === now.getMonth()
          const trained = trainedDays.has(key)
          const isToday = key === todayKey
          return (
            <div key={i} className="flex aspect-square items-center justify-center">
              <div
                className={`grid h-8 w-8 place-items-center rounded-full text-footnote ${
                  trained
                    ? 'bg-move font-semibold text-white'
                    : isToday
                      ? 'ring-1 ring-inset ring-accent text-label'
                      : inMonth
                        ? 'text-label2'
                        : 'text-label3/50'
                }`}
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
