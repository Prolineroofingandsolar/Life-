import { useState } from 'react'
import type { ReactNode } from 'react'
import { motion } from 'framer-motion'
import { Play, Plus, Flame, Dumbbell, MoreHorizontal, Pencil, Copy, Trash2, ChevronRight } from 'lucide-react'
import { useLife } from '../lib/store'
import {
  exerciseById,
  isFinished,
  sessionSetCount,
  sessionVolume,
  sessionsThisWeek,
  weeklyVolume,
  workoutStreak,
} from '../lib/workout'
import type { Routine, WorkoutSession } from '../lib/types'
import { LargeTitleHeader, IconButton, SectionLabel, Card, PressableCard, ListGroup, ListRow, EmptyState } from '../components/ui'
import TrainCalendar from '../components/TrainCalendar'
import MiniChart from '../components/MiniChart'
import RoutineEditor from '../components/RoutineEditor'
import Sheet from '../components/Sheet'
import { spring } from '../lib/motion'

function Stat({ value, label, icon }: { value: string; label: string; icon: ReactNode }) {
  return (
    <Card className="flex-1 p-3.5">
      <div className="mb-1 text-label2">{icon}</div>
      <div className="tabular text-title3 text-label">{value}</div>
      <div className="text-footnote text-label2">{label}</div>
    </Card>
  )
}

export default function Workout({
  onOpenWorkout,
  onEditSession,
}: {
  onOpenWorkout: () => void
  onEditSession: (id: string) => void
}) {
  const { state, activeSession, startSession, deleteRoutine, duplicateRoutine, discardSession } = useLife()
  const [editor, setEditor] = useState<{ open: boolean; routine?: Routine }>({ open: false })
  const [actions, setActions] = useState<Routine | null>(null)
  const [detail, setDetail] = useState<WorkoutSession | null>(null)

  const ws = state.workoutSettings
  const finished = state.sessions.filter(isFinished)
  const history = [...finished].sort((a, b) => (b.finishedAt ?? 0) - (a.finishedAt ?? 0))
  const trainedDays = new Set(finished.map((s) => s.date))
  const streak = workoutStreak(state.sessions)
  const weekCount = sessionsThisWeek(state.sessions).length
  const weekVol = weeklyVolume(state.sessions)

  const start = (routineId?: string) => {
    if (!activeSession) startSession(routineId)
    onOpenWorkout()
  }

  // Volume of the last few finished sessions (oldest → newest) for the trend chart.
  const volumeTrend = [...history].reverse().slice(-8).map((s) => ({ value: sessionVolume(s) }))

  const exercisePreview = (r: Routine) =>
    r.exercises
      .map((re) => exerciseById(state.exercises, re.exerciseId)?.name)
      .filter(Boolean)
      .slice(0, 3)
      .join(' · ')

  return (
    <div>
      <LargeTitleHeader
        title="Train"
        trailing={<IconButton icon={Plus} label="New routine" accent onClick={() => setEditor({ open: true })} />}
      />

      {activeSession && (
        <PressableCard onClick={onOpenWorkout} className="mb-4 mt-1 flex items-center gap-3 bg-accent p-4">
          <span className="grid h-10 w-10 place-items-center rounded-full bg-white/20 text-white">
            <Play size={20} fill="currentColor" />
          </span>
          <div className="flex-1">
            <div className="text-headline text-white">Resume workout</div>
            <div className="text-footnote text-white/80">{activeSession.name} in progress</div>
          </div>
          <ChevronRight size={18} className="text-white/80" />
        </PressableCard>
      )}

      {/* Stats */}
      <div className="mb-2 mt-1 flex gap-3">
        <Stat value={String(weekCount)} label="this week" icon={<Dumbbell size={18} />} />
        <Stat value={String(streak)} label="day streak" icon={<Flame size={18} />} />
        <Stat value={`${weekVol}`} label={`${ws.unit} this wk`} icon={<span className="text-footnote font-bold">Σ</span>} />
      </div>

      {volumeTrend.length >= 2 && (
        <Card className="mt-3 p-4">
          <div className="mb-2 text-footnote font-medium text-label2">Volume trend</div>
          <MiniChart data={volumeTrend} />
        </Card>
      )}

      {/* Start */}
      <motion.button
        whileTap={{ scale: 0.98 }}
        transition={spring}
        onClick={() => start()}
        className="mt-3 flex w-full items-center justify-center gap-2 rounded-card bg-accent py-4 text-headline text-white"
      >
        <Play size={20} fill="currentColor" /> Start empty workout
      </motion.button>

      <SectionLabel>Routines</SectionLabel>
      <div className="space-y-2">
        {state.routines.map((r) => (
          <div key={r.id} className="flex items-center gap-2">
            <PressableCard onClick={() => start(r.id)} className="flex flex-1 items-center gap-3 p-4">
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-[10px] bg-fill text-accent">
                <Dumbbell size={20} />
              </span>
              <div className="min-w-0 flex-1">
                <div className="text-headline text-label">{r.name}</div>
                <div className="truncate text-footnote text-label2">
                  {r.exercises.length} exercises · {exercisePreview(r)}
                </div>
              </div>
              <Play size={18} className="shrink-0 text-accent" fill="currentColor" />
            </PressableCard>
            <IconButton icon={MoreHorizontal} label="Routine options" onClick={() => setActions(r)} />
          </div>
        ))}
      </div>

      <SectionLabel>History</SectionLabel>
      {history.length === 0 ? (
        <EmptyState icon={Dumbbell} title="No workouts yet" subtitle="Start one above — your sessions and PRs will show up here." />
      ) : (
        <ListGroup>
          {history.slice(0, 12).map((s) => (
            <ListRow
              key={s.id}
              title={s.name}
              subtitle={`${new Date(s.finishedAt ?? s.startedAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })} · ${sessionSetCount(s)} sets · ${sessionVolume(s)} ${ws.unit}`}
              trailing={<ChevronRight size={18} className="text-label3" />}
              onClick={() => setDetail(s)}
            />
          ))}
        </ListGroup>
      )}

      <SectionLabel>Calendar</SectionLabel>
      <TrainCalendar trainedDays={trainedDays} />
      <div className="h-4" />

      {/* Routine editor */}
      <RoutineEditor open={editor.open} routine={editor.routine} onClose={() => setEditor({ open: false })} />

      {/* Routine actions */}
      <Sheet open={!!actions} onClose={() => setActions(null)} title={actions?.name}>
        {actions && (
          <div className="space-y-2">
            <button
              onClick={() => { setEditor({ open: true, routine: actions }); setActions(null) }}
              className="flex w-full items-center gap-3 rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card"
            >
              <Pencil size={18} className="text-label2" /> Edit
            </button>
            <button
              onClick={() => { duplicateRoutine(actions.id); setActions(null) }}
              className="flex w-full items-center gap-3 rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card"
            >
              <Copy size={18} className="text-label2" /> Duplicate
            </button>
            <button
              onClick={() => { deleteRoutine(actions.id); setActions(null) }}
              className="flex w-full items-center gap-3 rounded-card bg-surface px-4 py-3.5 text-body text-danger shadow-card"
            >
              <Trash2 size={18} /> Delete
            </button>
          </div>
        )}
      </Sheet>

      {/* Session detail */}
      <Sheet open={!!detail} onClose={() => setDetail(null)} title={detail?.name}>
        {detail && (
          <div className="space-y-3">
            <div className="text-footnote text-label2">
              {new Date(detail.finishedAt ?? detail.startedAt).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })}
              {' · '}{sessionSetCount(detail)} sets · {sessionVolume(detail)} {ws.unit}
            </div>
            {detail.exercises.map((ex, i) => {
              const meta = exerciseById(state.exercises, ex.exerciseId)
              const done = ex.sets.filter((s) => s.done)
              if (done.length === 0) return null
              return (
                <div key={i} className="rounded-card bg-surface p-3 shadow-card">
                  <div className="mb-1 text-headline text-label">{meta?.name}</div>
                  <div className="flex flex-wrap gap-x-3 gap-y-1 text-footnote text-label2">
                    {done.map((s, j) => (
                      <span key={j} className="tabular">
                        {s.weight != null && s.reps != null
                          ? `${s.weight}×${s.reps}`
                          : s.reps != null
                            ? `${s.reps}`
                            : s.distanceKm != null
                              ? `${s.distanceKm}km`
                              : s.durationSec != null
                                ? `${s.durationSec}s`
                                : '✓'}
                      </span>
                    ))}
                  </div>
                </div>
              )
            })}

            <div className="flex gap-2 pt-1">
              <motion.button
                whileTap={{ scale: 0.97 }}
                transition={spring}
                onClick={() => { onEditSession(detail.id); setDetail(null) }}
                className="flex flex-1 items-center justify-center gap-2 rounded-card bg-accent py-3 text-headline text-white"
              >
                <Pencil size={17} /> Edit workout
              </motion.button>
              <button
                onClick={() => {
                  if (confirm('Delete this workout? It will be removed from your history.')) {
                    discardSession(detail.id)
                    setDetail(null)
                  }
                }}
                aria-label="Delete workout"
                className="grid w-14 place-items-center rounded-card bg-fill text-danger active:scale-95"
              >
                <Trash2 size={18} />
              </button>
            </div>
          </div>
        )}
      </Sheet>
    </div>
  )
}
