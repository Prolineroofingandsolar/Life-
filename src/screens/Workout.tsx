import { useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import {
  Play, Plus, Flame, Dumbbell, MoreHorizontal, Pencil, Copy,
  Trash2, ChevronRight, Clock, Trophy, BarChart2, Zap,
} from 'lucide-react'
import { useLife } from '../lib/store'
import {
  computePRs,
  exerciseById,
  isFinished,
  sessionDuration,
  sessionMuscles,
  sessionSetCount,
  sessionVolume,
  sessionsThisWeek,
  weeklyVolume,
  workoutStreak,
} from '../lib/workout'
import type { Exercise, Routine, WorkoutSession } from '../lib/types'
import {
  LargeTitleHeader,
  IconButton,
  SectionLabel,
  Card,
  PressableCard,
  EmptyState,
} from '../components/ui'
import TrainCalendar from '../components/TrainCalendar'
import MiniChart from '../components/MiniChart'
import RoutineEditor from '../components/RoutineEditor'
import Sheet from '../components/Sheet'
import Toast from '../components/Toast'
import { listItem, spring } from '../lib/motion'

/* ── Muscle colour palette ─────────────────────────────────────────────── */

const MUSCLE_COLOR: Record<string, string> = {
  Chest:        '#ff6b35',
  Back:         '#30d158',
  Legs:         '#32ade6',
  Glutes:       '#ff375f',
  Shoulders:    '#bf5af2',
  Biceps:       '#ff9f0a',
  Triceps:      '#ff453a',
  Core:         '#64d2ff',
  Traps:        '#5e5ce6',
  'Full Body':  '#94a3b8',
  Cardio:       '#34c759',
  Arms:         '#ff9f0a',
}

function muscleColor(m: string) { return MUSCLE_COLOR[m] ?? '#8888aa' }

function MuscleTag({ muscle }: { muscle: string }) {
  const color = muscleColor(muscle)
  return (
    <span
      className="rounded-full px-2 py-0.5 text-caption font-medium"
      style={{ background: color + '22', color }}
    >
      {muscle}
    </span>
  )
}

/* ── Helpers ─────────────────────────────────────────────────────────────── */

function estimateRoutineDuration(r: Routine): number {
  let secs = 0
  for (const re of r.exercises) secs += re.targetSets * ((re.targetReps ?? 10) * 3 + re.restSec)
  return Math.max(1, Math.round(secs / 60))
}

function routineMuscles(r: Routine, exercises: Exercise[]): string[] {
  const seen = new Set<string>()
  r.exercises.forEach((re) => {
    const muscle = exerciseById(exercises, re.exerciseId)?.muscle
    if (muscle) seen.add(muscle)
  })
  return Array.from(seen).slice(0, 5)
}

function Stat({ value, label, icon }: { value: string; label: string; icon: ReactNode }) {
  return (
    <Card className="flex-1 p-3 text-center">
      <div className="mb-1 flex justify-center text-label2">{icon}</div>
      <div className="tabular text-title3 text-label">{value}</div>
      <div className="text-caption text-label2">{label}</div>
    </Card>
  )
}

/* ── Screen ─────────────────────────────────────────────────────────────── */

export default function Workout({
  onOpenWorkout,
  onEditSession,
}: {
  onOpenWorkout: () => void
  onEditSession: (id: string) => void
}) {
  const { state, activeSession, startSession, deleteRoutine, duplicateRoutine, restoreRoutine, discardSession } = useLife()
  const [editor, setEditor] = useState<{ open: boolean; routine?: Routine }>({ open: false })
  const [actions, setActions] = useState<Routine | null>(null)
  const [detail, setDetail]   = useState<WorkoutSession | null>(null)
  const [historyAll, setHistoryAll] = useState(false)

  // Undo state for routines
  const [deletedRoutine, setDeletedRoutine] = useState<Routine | null>(null)
  const routineUndoTimer = useRef<number | null>(null)

  // Undo state for sessions
  const [deletedSession, setDeletedSession] = useState<WorkoutSession | null>(null)
  const sessionUndoTimer = useRef<number | null>(null)

  const ws = state.workoutSettings
  const finished = useMemo(() => state.sessions.filter(isFinished), [state.sessions])
  const history  = useMemo(() => [...finished].sort((a, b) => (b.finishedAt ?? 0) - (a.finishedAt ?? 0)), [finished])
  const trainedDays = useMemo(() => new Set(finished.map((s) => s.date)), [finished])

  const streak   = workoutStreak(state.sessions)
  const weekCount = sessionsThisWeek(state.sessions).length
  const weekVol  = weeklyVolume(state.sessions)

  const volumeTrend = useMemo(
    () => [...history].reverse().slice(-10).map((s) => ({ value: sessionVolume(s) })),
    [history],
  )

  const topPRs = useMemo(() => {
    type Row = { name: string; muscle: string; weight: number; reps: number; e1rm: number }
    const rows: Row[] = []
    for (const ex of state.exercises) {
      const pr = computePRs(finished, ex.id)
      if (pr.bestWeight != null && pr.bestReps != null) {
        rows.push({ name: ex.name, muscle: ex.muscle ?? '', weight: pr.bestWeight, reps: pr.bestReps, e1rm: pr.best1RM ?? pr.bestWeight })
      }
    }
    return rows.sort((a, b) => b.e1rm - a.e1rm).slice(0, 6)
  }, [finished, state.exercises])

  const start = (routineId?: string) => {
    if (!activeSession) startSession(routineId)
    onOpenWorkout()
  }

  const handleDeleteRoutine = (r: Routine) => {
    deleteRoutine(r.id)
    setDeletedRoutine(r)
    if (routineUndoTimer.current) clearTimeout(routineUndoTimer.current)
    routineUndoTimer.current = window.setTimeout(() => setDeletedRoutine(null), 4000)
  }

  const handleDeleteSession = (s: WorkoutSession) => {
    discardSession(s.id)
    setDetail(null)
    setDeletedSession(s)
    if (sessionUndoTimer.current) clearTimeout(sessionUndoTimer.current)
    sessionUndoTimer.current = window.setTimeout(() => setDeletedSession(null), 4000)
  }

  const visibleHistory = historyAll ? history : history.slice(0, 5)

  return (
    <div>
      <LargeTitleHeader
        title="Train"
        trailing={<IconButton icon={Plus} label="New routine" accent onClick={() => setEditor({ open: true })} />}
      />

      {/* ── Active workout banner ── */}
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

      {/* ── Stats ── */}
      <div className="mt-1 flex gap-2">
        <Stat value={String(weekCount)} label="this week"  icon={<Dumbbell size={16} />} />
        <Stat value={String(streak)}   label="day streak" icon={<Flame size={16} />} />
        <Stat
          value={weekVol >= 1000 ? `${(weekVol / 1000).toFixed(1)}k` : String(weekVol)}
          label={`${ws.unit} vol`}
          icon={<BarChart2 size={16} />}
        />
      </div>

      {volumeTrend.length >= 2 && (
        <Card className="mt-3 p-4">
          <div className="mb-2 text-footnote font-semibold text-label2">
            Volume — last {volumeTrend.length} sessions
          </div>
          <MiniChart data={volumeTrend} />
        </Card>
      )}

      {/* ── Quick start ── */}
      <motion.button
        whileTap={{ scale: 0.98 }}
        transition={spring}
        onClick={() => start()}
        className="mt-3 flex w-full items-center justify-center gap-2 rounded-card border border-dashed border-accent/50 py-3.5 text-headline text-accent"
        style={{ background: 'rgb(var(--accent) / 0.06)' }}
      >
        <Zap size={18} fill="currentColor" /> Start empty workout
      </motion.button>

      {/* ── Routines ── */}
      <SectionLabel>Routines</SectionLabel>

      {state.routines.length === 0 ? (
        <EmptyState icon={Dumbbell} title="No routines yet" subtitle="Tap + to build your first routine." />
      ) : (
        <div className="space-y-3">
          <AnimatePresence initial={false}>
            {state.routines.map((r) => {
              const muscles = routineMuscles(r, state.exercises)
              const dur = estimateRoutineDuration(r)
              const preview = r.exercises
                .map((re) => exerciseById(state.exercises, re.exerciseId)?.name)
                .filter(Boolean).slice(0, 4).join(' · ')

              return (
                <motion.div
                  key={r.id}
                  variants={listItem}
                  exit="exit"
                  layout
                  className="relative overflow-hidden rounded-card"
                >
                  {/* Swipe-to-delete background */}
                  <div className="absolute inset-y-0 right-0 flex items-center rounded-r-card bg-danger pl-6 pr-5 text-white">
                    <Trash2 size={20} />
                  </div>
                  <motion.div
                    drag="x"
                    dragConstraints={{ left: -96, right: 0 }}
                    dragElastic={{ left: 0.5, right: 0 }}
                    dragMomentum={false}
                    dragSnapToOrigin
                    onDragEnd={(_, info) => { if (info.offset.x < -72) handleDeleteRoutine(r) }}
                    className="relative rounded-card bg-surface p-4 shadow-card"
                    style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
                  >
                    {/* Header */}
                    <div className="mb-2 flex items-start gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="text-headline text-label">{r.name}</div>
                        <div className="mt-0.5 flex items-center gap-1.5 text-footnote text-label2">
                          <span>{r.exercises.length} exercise{r.exercises.length !== 1 ? 's' : ''}</span>
                          <span>·</span>
                          <Clock size={11} />
                          <span>~{dur}m</span>
                        </div>
                      </div>
                      <div className="flex shrink-0 items-center gap-1.5">
                        <button
                          onPointerDown={(e) => e.stopPropagation()}
                          onClick={() => setActions(r)}
                          className="grid h-8 w-8 place-items-center text-label3 active:scale-90"
                          aria-label="More options"
                        >
                          <MoreHorizontal size={20} />
                        </button>
                        <motion.button
                          whileTap={{ scale: 0.93 }}
                          transition={spring}
                          onPointerDown={(e) => e.stopPropagation()}
                          onClick={() => start(r.id)}
                          className="flex items-center gap-1.5 rounded-full bg-accent px-4 py-1.5 text-subhead font-semibold text-white"
                        >
                          <Play size={13} fill="currentColor" /> Start
                        </motion.button>
                      </div>
                    </div>

                    {muscles.length > 0 && (
                      <div className="mb-2 flex flex-wrap gap-1.5">
                        {muscles.map((m) => <MuscleTag key={m} muscle={m} />)}
                      </div>
                    )}

                    <div className="truncate text-footnote text-label3">{preview}</div>
                  </motion.div>
                </motion.div>
              )
            })}
          </AnimatePresence>
          <p className="text-center text-caption text-label3">Swipe left to delete</p>
        </div>
      )}

      {/* ── Personal Records ── */}
      {topPRs.length > 0 && (
        <>
          <SectionLabel>Personal Records</SectionLabel>
          <div
            className="overflow-hidden rounded-card bg-surface shadow-card"
            style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
          >
            {topPRs.map((pr, i) => (
              <div
                key={i}
                className="flex items-center gap-3 px-4 py-3 [&+&]:border-t [&+&]:border-separator/60"
              >
                <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full"
                  style={{ background: 'rgb(var(--nourish, 255 159 10) / 0.15)' }}>
                  <Trophy size={15} className="text-nourish" fill="currentColor" />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-body text-label">{pr.name}</div>
                  <div className="text-footnote text-label2">{pr.muscle}</div>
                </div>
                <div className="shrink-0 text-right">
                  <div className="tabular text-headline text-label">{pr.weight} {ws.unit}</div>
                  <div className="text-caption text-label2">{pr.reps} reps · ~{pr.e1rm} {ws.unit}</div>
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      {/* ── History ── */}
      <SectionLabel>History</SectionLabel>

      {history.length === 0 ? (
        <EmptyState icon={Dumbbell} title="No workouts yet" subtitle="Complete a session and it'll show up here." />
      ) : (
        <div className="space-y-3">
          <AnimatePresence initial={false}>
            {visibleHistory.map((s) => {
              const muscles  = sessionMuscles(s, state.exercises).slice(0, 4)
              const dur      = sessionDuration(s)
              const preview  = s.exercises
                .map((ex) => exerciseById(state.exercises, ex.exerciseId)?.name)
                .filter(Boolean).slice(0, 4).join(' · ')

              return (
                <motion.div
                  key={s.id}
                  variants={listItem}
                  exit="exit"
                  layout
                  className="relative overflow-hidden rounded-card"
                >
                  {/* Swipe-to-delete background */}
                  <div className="absolute inset-y-0 right-0 flex items-center rounded-r-card bg-danger pl-6 pr-5 text-white">
                    <Trash2 size={20} />
                  </div>
                  <motion.div
                    drag="x"
                    dragConstraints={{ left: -96, right: 0 }}
                    dragElastic={{ left: 0.5, right: 0 }}
                    dragMomentum={false}
                    dragSnapToOrigin
                    onDragEnd={(_, info) => {
                      if (info.offset.x < -72) handleDeleteSession(s)
                      else if (Math.abs(info.offset.x) < 5) setDetail(s)
                    }}
                    className="relative rounded-card bg-surface p-4 shadow-card"
                    style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
                  >
                    <div className="mb-1.5 flex items-start justify-between gap-2">
                      <div className="text-headline text-label">{s.name}</div>
                      <div className="shrink-0 text-footnote text-label2">
                        {new Date(s.finishedAt ?? s.startedAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}
                      </div>
                    </div>

                    <div className="mb-2 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-footnote text-label2">
                      {dur && <span className="flex items-center gap-1"><Clock size={11} />{dur}</span>}
                      <span>{sessionSetCount(s)} sets</span>
                      <span>{sessionVolume(s)} {ws.unit}</span>
                    </div>

                    {muscles.length > 0 && (
                      <div className="mb-2 flex flex-wrap gap-1.5">
                        {muscles.map((m) => <MuscleTag key={m} muscle={m} />)}
                      </div>
                    )}

                    <div className="truncate text-footnote text-label3">{preview}</div>
                  </motion.div>
                </motion.div>
              )
            })}
          </AnimatePresence>

          {history.length > 5 && (
            <button
              onClick={() => setHistoryAll((x) => !x)}
              className="w-full py-2 text-center text-subhead text-accent"
            >
              {historyAll ? 'Show less' : `Show all ${history.length} workouts`}
            </button>
          )}
          <p className="text-center text-caption text-label3">Tap to view · Swipe left to delete</p>
        </div>
      )}

      {/* ── Calendar ── */}
      <SectionLabel>Calendar</SectionLabel>
      <TrainCalendar trainedDays={trainedDays} />
      <div className="h-4" />

      {/* ── Routine editor ── */}
      <RoutineEditor open={editor.open} routine={editor.routine} onClose={() => setEditor({ open: false })} />

      {/* ── Routine actions sheet (edit / duplicate only) ── */}
      <Sheet open={!!actions} onClose={() => setActions(null)} title={actions?.name}>
        {actions && (
          <div className="space-y-2">
            <button
              onClick={() => { setEditor({ open: true, routine: actions }); setActions(null) }}
              className="flex w-full items-center gap-3 rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card"
              style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
            >
              <Pencil size={18} className="text-label2" /> Edit
            </button>
            <button
              onClick={() => { duplicateRoutine(actions.id); setActions(null) }}
              className="flex w-full items-center gap-3 rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card"
              style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
            >
              <Copy size={18} className="text-label2" /> Duplicate
            </button>
          </div>
        )}
      </Sheet>

      {/* ── Session detail sheet ── */}
      <Sheet open={!!detail} onClose={() => setDetail(null)} title={detail?.name}>
        {detail && (
          <div className="space-y-3">
            <div className="flex gap-2">
              {[
                { value: sessionDuration(detail) || '—', label: 'duration' },
                { value: String(sessionSetCount(detail)),  label: 'sets'     },
                { value: `${sessionVolume(detail)}`,       label: `${ws.unit} vol` },
              ].map(({ value, label }) => (
                <div key={label} className="flex-1 rounded-card bg-surface p-3 text-center shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
                  <div className="tabular text-title3 text-label">{value}</div>
                  <div className="text-caption text-label2">{label}</div>
                </div>
              ))}
            </div>

            {detail.exercises.map((ex, i) => {
              const meta = exerciseById(state.exercises, ex.exerciseId)
              const done = ex.sets.filter((s) => s.done)
              if (done.length === 0) return null
              return (
                <div key={i} className="rounded-card bg-surface p-3 shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
                  <div className="mb-2 flex items-center justify-between">
                    <div className="text-headline text-label">{meta?.name ?? 'Exercise'}</div>
                    {meta?.muscle && <MuscleTag muscle={meta.muscle} />}
                  </div>
                  <div className="space-y-1">
                    {done.map((s, j) => (
                      <div key={j} className="flex items-center gap-3 text-footnote">
                        <span className="w-6 text-label3">S{j + 1}</span>
                        <span className="tabular text-label">
                          {s.weight != null && s.reps != null
                            ? `${s.weight} ${ws.unit} × ${s.reps} reps`
                            : s.reps != null       ? `${s.reps} reps`
                            : s.distanceKm != null  ? `${s.distanceKm} km`
                            : s.durationSec != null ? `${s.durationSec}s`
                            : '✓'}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )
            })}

            <motion.button
              whileTap={{ scale: 0.97 }}
              transition={spring}
              onClick={() => { onEditSession(detail.id); setDetail(null) }}
              className="w-full rounded-card bg-accent py-3 text-headline text-white"
            >
              <span className="flex items-center justify-center gap-2">
                <Pencil size={17} /> Edit workout
              </span>
            </motion.button>
          </div>
        )}
      </Sheet>

      <AnimatePresence>
        {deletedRoutine && (
          <Toast
            message={`"${deletedRoutine.name}" deleted`}
            onUndo={() => restoreRoutine(deletedRoutine)}
            onDismiss={() => setDeletedRoutine(null)}
          />
        )}
        {deletedSession && (
          <Toast
            message="Workout deleted"
            onDismiss={() => setDeletedSession(null)}
          />
        )}
      </AnimatePresence>
    </div>
  )
}
