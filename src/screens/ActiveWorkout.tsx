import { useEffect, useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ChevronDown, Check, Plus, X, Trophy, Link2, Trash2 } from 'lucide-react'
import { useLife } from '../lib/store'
import { exerciseById, isSetPR, lastPerformance, newPRsForSession, sessionSetCount, sessionVolume, setHint } from '../lib/workout'
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
        if (v === '') { onChange(undefined); return }
        const n = parseFloat(v)
        if (!isNaN(n) && n >= 0) onChange(n)
      }}
      className="w-full rounded-[8px] bg-fill py-2 text-center text-body text-label placeholder:text-label3 focus:outline-none focus:ring-2 focus:ring-accent/60"
    />
  )
}

const COLS: Record<ExerciseKind, string[]> = {
  weight:     ['Set', 'Prev', 'kg', 'Reps', ''],
  bodyweight: ['Set', 'Prev', 'Reps', ''],
  cardio:     ['Set', 'Prev', 'km', 'Min', ''],
  hold:       ['Set', 'Prev', 'Sec', ''],
}

/** Display label for a set: counts non-drop sets; drop sets show ↓ */
function setLabel(sets: LoggedSet[], idx: number): string {
  if (sets[idx].isDropSet) return '↓'
  return String(sets.slice(0, idx + 1).filter((s) => !s.isDropSet).length)
}

function gridCols(kind: ExerciseKind): string {
  switch (kind) {
    case 'weight':     return '40px 52px 1fr 1fr 44px'
    case 'cardio':     return '40px 52px 1fr 1fr 44px'
    case 'bodyweight': return '40px 64px 1fr 44px'
    case 'hold':       return '40px 64px 1fr 44px'
  }
}

export default function ActiveWorkout({
  session,
  onMinimize,
  mode = 'active',
}: {
  session: WorkoutSession
  onMinimize: () => void
  mode?: 'active' | 'edit'
}) {
  const {
    state,
    updateSet,
    toggleSetDone,
    addSet,
    addDropSet,
    removeSet,
    addExerciseToSession,
    removeExerciseFromSession,
    linkAsSuperset,
    unlinkSuperset,
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
    if (editing || set.done || !ws.restTimerEnabled) return

    // No rest if the immediately next set in this exercise is a drop set
    const nextSet = session.exercises[exIdx].sets[setIdx + 1]
    if (nextSet?.isDropSet) return

    // No rest if the next exercise is the second half of a superset
    const sid = session.exercises[exIdx].supersetId
    if (sid && session.exercises[exIdx + 1]?.supersetId === sid) return

    setRest({ key: Date.now(), seconds: restSecFor(exerciseId) })
  }

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
    const msg = editing
      ? 'Delete this workout? It will be removed from your history.'
      : 'Discard this workout? Nothing will be saved.'
    if (confirm(msg)) {
      discardSession(session.id)
      onMinimize()
    }
  }

  const prFlags = useMemo(
    () =>
      session.exercises.map((ex) =>
        ex.sets.map((set) => isSetPR(state.sessions, session.id, ex.exerciseId, set)),
      ),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [session.exercises, state.sessions, session.id],
  )

  // Group consecutive exercises that share the same supersetId.
  const exerciseGroups = useMemo(() => {
    const groups: Array<{ indices: number[]; supersetId?: string }> = []
    session.exercises.forEach((ex, i) => {
      const sid = ex.supersetId
      if (sid && groups.length > 0 && groups[groups.length - 1].supersetId === sid) {
        groups[groups.length - 1].indices.push(i)
      } else {
        groups.push({ indices: [i], supersetId: sid ?? undefined })
      }
    })
    return groups
  }, [session.exercises])

  const unitLabel = ws.unit
  const liveVolume = useMemo(() => sessionVolume(session), [session])
  const subLine = editing
    ? `${new Date(session.finishedAt ?? session.startedAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })} · ${sessionSetCount(session)} sets · ${liveVolume} ${unitLabel}`
    : `${elapsedLabel(now - session.startedAt)} · ${sessionSetCount(session)} sets · ${liveVolume} ${unitLabel}`

  /** Renders the inner content of one exercise (header + set grid + buttons). */
  const renderExercise = (exIdx: number, inSuperset: boolean) => {
    const ex = session.exercises[exIdx]
    const meta = exerciseById(state.exercises, ex.exerciseId)
    const kind = meta?.kind ?? 'weight'
    const cols = COLS[kind]
    const prev = lastPerformance(state.sessions, ex.exerciseId)
    const isLinked = !!ex.supersetId
    const canLink = !isLinked && exIdx < session.exercises.length - 1

    const content = (
      <>
        {/* Exercise header */}
        <div className="mb-2 flex items-center justify-between">
          <div>
            <div className="text-headline text-label">{meta?.name ?? 'Exercise'}</div>
            {meta?.muscle && <div className="text-footnote text-label2">{meta.muscle}</div>}
          </div>
          <div className="flex items-center gap-1.5">
            {!editing && (
              <button
                onClick={() =>
                  isLinked
                    ? unlinkSuperset(session.id, exIdx)
                    : canLink && linkAsSuperset(session.id, exIdx, exIdx + 1)
                }
                disabled={!isLinked && !canLink}
                aria-label={isLinked ? 'Unlink superset' : 'Link as superset with next exercise'}
                title={isLinked ? 'Unlink superset' : 'Superset with next exercise'}
                className={`grid h-8 w-8 place-items-center rounded-full transition-colors ${
                  isLinked ? 'bg-accent/15 text-accent' : 'text-label3'
                } disabled:opacity-25`}
              >
                <Link2 size={16} strokeWidth={2} />
              </button>
            )}
            <button
              onClick={() => removeExerciseFromSession(session.id, exIdx)}
              aria-label="Remove exercise"
              className="grid h-8 w-8 place-items-center text-label3 active:scale-90"
            >
              <X size={20} />
            </button>
          </div>
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
          {ex.sets.map((set, setIdx) => {
            const isDrop = !!set.isDropSet
            const canDelete = ex.sets.length > 1
            return (
              <div key={setIdx} className="relative overflow-hidden rounded-[10px]">
                {/* Swipe-to-delete background */}
                {canDelete && (
                  <div className="absolute inset-y-0 right-0 flex items-center bg-danger pl-4 pr-3 text-white">
                    <Trash2 size={14} />
                  </div>
                )}
                <motion.div
                  drag={canDelete ? 'x' : false}
                  dragConstraints={{ left: -72, right: 0 }}
                  dragElastic={{ left: 0.5, right: 0 }}
                  dragMomentum={false}
                  dragSnapToOrigin
                  onDragEnd={(_, info) => { if (canDelete && info.offset.x < -52) removeSet(session.id, exIdx, setIdx) }}
                  className="relative rounded-[10px] bg-surface"
                >
                <div
                  className={`grid items-center gap-2 rounded-[10px] px-1 py-1 ${
                    set.done
                      ? isDrop ? 'bg-accent/10' : 'bg-move/10'
                      : isDrop ? 'bg-accent/5' : ''
                  }`}
                  style={{ gridTemplateColumns: gridCols(kind) }}
                >
                {/* Set number label */}
                <div
                  className={`text-center text-callout font-semibold ${isDrop ? 'text-accent' : 'text-label2'}`}
                >
                  {setLabel(ex.sets, setIdx)}
                </div>

                <div className="text-center text-footnote text-label3">
                  {setHint(prev?.sets[setIdx])}
                </div>

                {kind === 'weight' && (
                  <>
                    <NumCell value={set.weight} placeholder="0" onChange={(v) => updateSet(session.id, exIdx, setIdx, { weight: v })} />
                    <NumCell value={set.reps}   placeholder="0" onChange={(v) => updateSet(session.id, exIdx, setIdx, { reps: v })} />
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

                {/* Done checkbox */}
                <div className="relative flex items-center justify-center">
                  <motion.button
                    whileTap={{ scale: 0.85 }}
                    transition={spring}
                    onPointerDown={(e) => e.stopPropagation()}
                    onClick={() => onToggle(exIdx, setIdx, ex.exerciseId, set)}
                    aria-label="Complete set"
                    className={`grid h-8 w-8 place-items-center rounded-[8px] border-2 ${
                      set.done
                        ? isDrop
                          ? 'border-accent bg-accent text-white'
                          : 'border-move bg-move text-white'
                        : 'border-label3 text-transparent'
                    }`}
                  >
                    <Check size={16} strokeWidth={3} />
                  </motion.button>
                  {prFlags[exIdx]?.[setIdx] && (
                    <span className="pointer-events-none absolute -right-1.5 -top-1.5">
                      <Trophy size={12} className="text-nourish" fill="currentColor" />
                    </span>
                  )}
                </div>
                </div>
                </motion.div>
              </div>
            )
          })}
        </div>

        {/* Add / drop / remove set buttons */}
        <div className="mt-2 flex gap-2">
          <button
            onClick={() => addSet(session.id, exIdx)}
            className="flex-1 rounded-[10px] bg-fill py-2 text-subhead font-medium text-label2 active:scale-[0.99]"
          >
            + Add set
          </button>
          <button
            onClick={() => addDropSet(session.id, exIdx)}
            className="rounded-[10px] bg-accent/10 px-4 py-2 text-subhead font-medium text-accent active:scale-[0.99]"
          >
            ↓ Drop
          </button>
        </div>
      </>
    )

    // Non-superset: content is the card itself
    if (!inSuperset) {
      return (
        <div
          key={exIdx}
          className="rounded-card bg-surface p-4 shadow-card"
          style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
        >
          {content}
        </div>
      )
    }

    // Inside a superset group: just padded content, no card wrapper
    return <div key={exIdx} className="p-4">{content}</div>
  }

  return (
    <div className="min-h-full">
      {/* Top bar */}
      <div className="material safe-top sticky top-0 z-20 -mx-4">
        <div className="flex h-14 items-center gap-3 px-4">
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
      </div>

      <div className="space-y-4 pb-40 pt-4">
        {exerciseGroups.map((group, gi) => {
          if (!group.supersetId || group.indices.length < 2) {
            return renderExercise(group.indices[0], false)
          }

          // Superset group — shared card with accent header
          const supersetId = group.supersetId
          return (
            <div
              key={supersetId + gi}
              className="overflow-hidden rounded-card bg-surface shadow-card"
              style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
            >
              <div
                className="flex items-center gap-2 px-4 py-2"
                style={{ background: 'rgb(var(--accent) / 0.08)' }}
              >
                <Link2 size={13} className="text-accent" strokeWidth={2.2} />
                <span className="text-caption font-semibold uppercase tracking-wider text-accent">
                  Superset
                </span>
              </div>
              {group.indices.map((exIdx, i) => (
                <div key={exIdx} className={i > 0 ? 'border-t border-separator/60' : ''}>
                  {renderExercise(exIdx, true)}
                </div>
              ))}
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

      <ExercisePicker
        open={picker}
        onClose={() => setPicker(false)}
        onPick={(id) => addExerciseToSession(session.id, id)}
      />

      <AnimatePresence>
        {rest && <RestTimer key={rest.key} seconds={rest.seconds} onClose={() => setRest(null)} />}
      </AnimatePresence>

      {/* Finish summary sheet */}
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
