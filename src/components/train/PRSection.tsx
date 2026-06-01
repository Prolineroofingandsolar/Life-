import { Trophy } from 'lucide-react'
import { muscleColor } from './MuscleTag'
import { computePRs } from '../../lib/workout'
import type { Exercise, WorkoutSession } from '../../lib/types'

interface PRRow {
  name: string
  muscle: string
  weight: number
  reps: number
  e1rm: number
}

interface Props {
  sessions: WorkoutSession[]
  exercises: Exercise[]
  unit: string
  muscleFilter: string
}

export default function PRSection({ sessions, exercises, unit, muscleFilter }: Props) {
  const finished = sessions.filter((s) => s.finishedAt != null)

  const rows: PRRow[] = []
  for (const ex of exercises) {
    const pr = computePRs(finished, ex.id)
    if (pr.bestWeight != null && pr.bestReps != null) {
      rows.push({
        name: ex.name,
        muscle: ex.muscle ?? '',
        weight: pr.bestWeight,
        reps: pr.bestReps,
        e1rm: pr.best1RM ?? pr.bestWeight,
      })
    }
  }
  rows.sort((a, b) => b.e1rm - a.e1rm)

  const filtered = muscleFilter === 'All' ? rows : rows.filter((r) => r.muscle === muscleFilter)

  if (rows.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-center">
        <div className="mb-3 text-5xl">🏆</div>
        <p className="text-headline text-label">No PRs yet</p>
        <p className="mt-1 max-w-xs text-subhead text-label2">
          Complete workouts and log your sets to set personal records.
        </p>
      </div>
    )
  }

  if (filtered.length === 0) {
    return (
      <div className="py-12 text-center text-subhead text-label2">
        No PRs for this muscle group yet.
      </div>
    )
  }

  // Group by muscle
  const grouped = new Map<string, PRRow[]>()
  for (const row of filtered) {
    const key = row.muscle || 'Other'
    if (!grouped.has(key)) grouped.set(key, [])
    grouped.get(key)!.push(row)
  }

  return (
    <div className="space-y-4">
      {Array.from(grouped.entries()).map(([muscle, items]) => (
        <div key={muscle}>
          <div className="mb-2 ml-1 flex items-center gap-2">
            <span
              className="h-1.5 w-1.5 rounded-full"
              style={{ background: muscleColor(muscle) }}
            />
            <span
              className="text-footnote font-semibold uppercase tracking-wider"
              style={{ color: muscleColor(muscle) }}
            >
              {muscle}
            </span>
          </div>
          <div
            className="overflow-hidden rounded-card bg-surface shadow-card"
            style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
          >
            {items.map((pr, i) => (
              <div
                key={pr.name + i}
                className="flex items-center gap-3 px-4 py-3 [&+&]:border-t [&+&]:border-separator/60"
              >
                <span
                  className="grid h-8 w-8 shrink-0 place-items-center rounded-full"
                  style={{ background: 'rgb(var(--nourish, 255 159 10) / 0.15)' }}
                >
                  <Trophy size={14} className="text-nourish" fill="currentColor" />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-body text-label">{pr.name}</div>
                  <div className="text-caption text-label3">~{pr.e1rm} {unit} est. 1RM</div>
                </div>
                <div className="shrink-0 text-right">
                  <div className="tabular text-headline text-label">{pr.weight} {unit}</div>
                  <div className="text-caption text-label2">{pr.reps} reps</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
