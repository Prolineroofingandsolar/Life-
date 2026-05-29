import { useEffect, useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ChevronDown, Check, Plus, Trash2, X, Trophy } from 'lucide-react'
import { useLife } from '../lib/store'
import { exerciseById, lastPerformance, newPRsForSession, sessionSetCount, sessionVolume, setHint } from '../lib/workout'
import type { PRHit } from '../lib/workout'
import type { ExerciseKind, LoggedSet, WorkoutSession } from '../lib/types'
import ExercisePicker from '../components/ExercisePicker'
import RestTimer from '../components/RestTimer'
import Sheet from '../components/Sheet'
import { spring } from '../lib/motion'

function elapsedLabel(ms: number) {
  const s = Math.floor(ms / 1000)
  const m = Math.floor(s / 60)
  return `${m}:${String(s % 60).padStart(2, '0')}`
}

/** Editable inline number cell. */
function NumCell({
  value,
  onChange,
  placeholder,
}: {
  value: number | undefined
  onChange: (v: number | undefined) => void
  placeholder: string
}) {
  return (
    <input
      inputMode="decimal"
      value={value ?? ''}
      placeholder={placeholder}
      onChange={(e) => {
        const v = e.target.value.trim()
        onChange(v === '' ? undefined : Number(v))
      }}
      className="w-full rounded-[8px] bg-fill py-2 text-center text-body text-label placeholder:text-label3 focus:outline-none focus:ring-2 focus:ring-accent/60"
    />
  )
}

const COLS: Record<ExerciseKind, string[]> = {
  weight: ['Set', 'Prev', 'kg', 'Reps', ''],
  bodyweight: ['Set', 'Prev', 'Reps', ''],
  cardio: ['Set', 'Prev', 'km', 'Min', ''],
  hold: ['Set', 'Prev', 'Sec', ''],
}

export default function ActiveWorkout({
  session,
  onMinimize,
  mode = 'active',
}: {
  session: WorkoutSession
  onMinimize: () => void
  /** 'active' = live logging with rest timer + finish summary; 'edit' = revise a past workout. */
  mode?: 'active' | 'edit'
}) {
  const {
    state,
    updateSet,
    toggleSetDone,
    addSet,
    removeSet,
    addExerciseToSession,
    removeExerciseFromSession,
    renameSession,
    finishSession,
    discardSession,
  } = useLife()
  const ws = state.workoutSettings
  const editing = mode === 'edit'

  const [now, setNow] = useState(Date.now())
  const [picker, setPicker] = useState(false)
  const [rest, setRest] = useState<{ key: number; seconds: number } | null>(null)
  const [summary, setSummary] = useState<{ volume: number; sets: number; prs: PRHit[] } | null>(null)

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

  const restSecFor = (exerciseId: string) => {
    if (session.routineId) {
      const r = state.routines.find((x) => x.id === session.routineId)
      const re = r?.exercises.find((e) => e.exerciseId === exerciseId)
      if (re?.restSec) return re.restSec
    }
    return ws.defaultRestSec
  }

  const onToggle = (exIdx: number, setIdx: number, exerciseId: string, set: LoggedSet) => {
    toggleSetDone(session.id, exIdx, setIdx)
    // Becoming done starts a rest; un-checking does not. No rest while editing history.
    if (!editing && !set.done && ws.restTimerEnabled) {
      setRest({ key: Date.now(), seconds: restSecFor(exerciseId) })
    }
  }

  // Show the recap first; the session stays in progress (so this overlay stays
  // mounted) until the user dismisses the summary, which commits the finish.
  const finish = () => {
    const prs = newPRsForSession(state.sessions, session, state.exercises)
    setSummary({ volume: sessionVolume(session), sets: sessionSetCount(session), prs })
  }

  const commitFinish = () => {
    finishSession(session.id)
    setSummary(null)
    onMinimize()
  }

  const discard = () => {
    const msg = editing ? 'Delete this workout? It will be removed from your history.' : 'Discard this workout? Nothing will be saved.'
    if (confirm(msg)) {
      discardSession(session.id)
      onMinimize()
    }
  }

  const unitLabel = ws.unit
  const liveVolume = useMemo(() => sessionVolume(session), [session])
  const subLine = editing
    ? `${new Date(session.finishedAt ?? session.startedAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })} · ${sessionSetCount(session)} sets · ${liveVolume} ${unitLabel}`
    : `${elapsedLabel(now - session.startedAt)} · ${sessionSetCount(session)} sets · ${liveVolume} ${unitLabel}`

  return (
    <div className="min-h-full">
      {/* Top bar */}
      <div className="material safe-top sticky top-0 z-20 -mx-4 flex h-14 items-center gap-3 px-4">
        <motion.button whileTap={{ scale: 0.9 }} onClick={onMinimize} aria-label="Back" className="text-label2">
          <ChevronDown size={26} />
        </motion.button>
        <div className="min-w-0 flex-1">
          {editing ? (
            <input
              value={session.name}
              onChange={(e) => renameSession(session.id, e.target.value)}
              className="w-full bg-transparent text-headline leading-tight text-label focus:outline-none"
              aria-label="Workout name"
            />
          ) : (
            <div className="text-headline leading-tight text-label">{session.name}</div>
          )}
          <div className="tabular text-footnote text-label2">{subLine}</div>
        </div>
        <motion.button
          whileTap={{ scale: 0.95 }}
          transition={spring}
          onClick={editing ? onMinimize : finish}
          className="rounded-full bg-move px-5 py-2 text-subhead font-semibold text-white"
        >
          {editing ? 'Done' : 'Finish'}
        </motion.button>
      </div>

      <div className="space-y-4 pb-40 pt-4">
        {session.exercises.map((ex, exIdx) => {
          const meta = exerciseById(state.exercises, ex.exerciseId)
          const kind = meta?.kind ?? 'weight'
          const cols = COLS[kind]
          const prev = lastPerformance(state.sessions, ex.exerciseId)
          return (
            <div key={exIdx} className="rounded-card bg-surface p-4 shadow-card">
              <div className="mb-2 flex items-center justify-between">
                <div>
                  <div className="text-headline text-label">{meta?.name ?? 'Exercise'}</div>
                  {meta?.muscle && <div className="text-footnote text-label2">{meta.muscle}</div>}
                </div>
                <button
                  onClick={() => removeExerciseFromSession(session.id, exIdx)}
                  aria-label="Remove exercise"
                  className="text-label3 active:scale-90"
                >
                  <X size={20} />
                </button>
              </div>

              {/* Column headers */}
              <div
                className="mb-1 grid items-center gap-2 px-1 text-caption font-medium uppercase tracking-wide text-label3"
                style={{ gridTemplateColumns: gridCols(kind) }}
              >
                {cols.map((c, i) => (
                  <div key={i} className={i === 0 ? '' : 'text-center'}>
                    {c}
                  </div>
                ))}
              </div>

              {/* Set rows */}
              <div className="space-y-1.5">
                {ex.sets.map((set, setIdx) => (
                  <div
                    key={setIdx}
                    className={`grid items-center gap-2 rounded-[10px] px-1 py-1 ${set.done ? 'bg-move/10' : ''}`}
                    style={{ gridTemplateColumns: gridCols(kind) }}
                  >
                    <div className="pl-1 text-callout font-semibold text-label2">{setIdx + 1}</div>
                    <div className="text-center text-footnote text-label3">{setHint(prev?.sets[setIdx])}</div>

                    {kind === 'weight' && (
                      <>
                        <NumCell value={set.weight} placeholder="0" onChange={(v) => updateSet(session.id, exIdx, setIdx, { weight: v })} />
                        <NumCell value={set.reps} placeholder="0" onChange={(v) => updateSet(session.id, exIdx, setIdx, { reps: v })} />
                      </>
                    )}
                    {kind === 'bodyweight' && (
                      <NumCell value={set.reps} placeholder="0" onChange={(v) => updateSet(session.id, exIdx, setIdx, { reps: v })} />
                    )}
                    {kind === 'cardio' && (
                      <>
                        <NumCell value={set.distanceKm} placeholder="0" onChange={(v) => updateSet(session.id, exIdx, setIdx, { distanceKm: v })} />
                        <NumCell
                          value={set.durationSec != null ? Math.round(set.durationSec / 60) : undefined}
                          placeholder="0"
                          onChange={(v) => updateSet(session.id, exIdx, setIdx, { durationSec: v != null ? v * 60 : undefined })}
                        />
                      </>
                    )}
                    {kind === 'hold' && (
                      <NumCell value={set.durationSec} placeholder="0" onChange={(v) => updateSet(session.id, exIdx, setIdx, { durationSec: v })} />
                    )}

                    <div className="flex items-center justify-center gap-1">
                      <motion.button
                        whileTap={{ scale: 0.85 }}
                        transition={spring}
                        onClick={() => onToggle(exIdx, setIdx, ex.exerciseId, set)}
                        aria-label="Complete set"
                        className={`grid h-8 w-8 place-items-center rounded-[8px] border-2 ${
                          set.done ? 'border-move bg-move text-white' : 'border-label3 text-transparent'
                        }`}
                      >
                        <Check size={16} strokeWidth={3} />
                      </motion.button>
                    </div>
                  </div>
                ))}
              </div>

              <div className="mt-2 flex gap-2">
                <button
                  onClick={() => addSet(session.id, exIdx)}
                  className="flex-1 rounded-[10px] bg-fill py-2 text-subhead font-medium text-label2 active:scale-[0.99]"
                >
                  + Add set
                </button>
                {ex.sets.length > 1 && (
                  <button
                    onClick={() => removeSet(session.id, exIdx, ex.sets.length - 1)}
                    aria-label="Remove last set"
                    className="grid w-11 place-items-center rounded-[10px] bg-fill text-label3 active:scale-95"
                  >
                    <Trash2 size={17} />
                  </button>
                )}
              </div>
            </div>
          )
        })}

        <button
          onClick={() => setPicker(true)}
          className="flex w-full items-center justify-center gap-1.5 rounded-card border border-dashed border-separator py-3.5 text-callout font-medium text-accent"
        >
          <Plus size={18} /> Add exercise
        </button>

        <button onClick={discard} className="w-full py-2 text-center text-subhead text-danger">
          {editing ? 'Delete workout' : 'Discard workout'}
        </button>
      </div>

      <ExercisePicker open={picker} onClose={() => setPicker(false)} onPick={(id) => addExerciseToSession(session.id, id)} />

      <AnimatePresence>
        {rest && <RestTimer key={rest.key} seconds={rest.seconds} onClose={() => setRest(null)} />}
      </AnimatePresence>

      {/* Finish summary */}
      <Sheet open={!!summary} onClose={commitFinish} title="Workout complete">
        {summary && (
          <div>
            <div className="mb-4 flex gap-3">
              <div className="flex-1 rounded-card bg-surface p-4 text-center shadow-card">
                <div className="tabular text-title2 text-label">{summary.sets}</div>
                <div className="text-footnote text-label2">sets</div>
              </div>
              <div className="flex-1 rounded-card bg-surface p-4 text-center shadow-card">
                <div className="tabular text-title2 text-label">{summary.volume}</div>
                <div className="text-footnote text-label2">{unitLabel} volume</div>
              </div>
            </div>
            {summary.prs.length > 0 && (
              <div className="mb-4 rounded-card bg-surface p-4 shadow-card">
                <div className="mb-2 flex items-center gap-2 text-headline text-label">
                  <Trophy size={18} className="text-nourish" /> New personal records
                </div>
                <div className="space-y-1">
                  {summary.prs.map((p, i) => (
                    <div key={i} className="text-subhead text-label2">
                      {p.label}
                    </div>
                  ))}
                </div>
              </div>
            )}
            <motion.button
              whileTap={{ scale: 0.97 }}
              transition={spring}
              onClick={commitFinish}
              className="w-full rounded-card bg-accent py-3.5 text-headline text-white"
            >
              Done
            </motion.button>
          </div>
        )}
      </Sheet>
    </div>
  )
}

/** CSS grid template per exercise kind: [set][prev][inputs…][check]. */
function gridCols(kind: ExerciseKind): string {
  switch (kind) {
    case 'weight':
      return '32px 52px 1fr 1fr 44px'
    case 'cardio':
      return '32px 52px 1fr 1fr 44px'
    case 'bodyweight':
      return '32px 64px 1fr 44px'
    case 'hold':
      return '32px 64px 1fr 44px'
  }
}
