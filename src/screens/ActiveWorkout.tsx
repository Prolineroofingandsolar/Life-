import { useEffect, useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion, Reorder, useDragControls } from 'framer-motion'
import { ChevronDown, Check, Plus, X, Trophy, Link2, Trash2, RefreshCw, GripVertical, AlertTriangle } from 'lucide-react'
import { useLife } from '../lib/store'
import {
  exerciseById, isSetPR, lastPerformance, newPRsForSession,
  sessionMuscles, sessionSetCount, sessionVolume, setHint,
} from '../lib/workout'
import type { PRHit } from '../lib/workout'
import type { ExerciseKind, LoggedSet, SessionExercise, WorkoutSession } from '../lib/types'
import ExercisePicker from '../components/ExercisePicker'
import RestTimer from '../components/RestTimer'
import Sheet from '../components/Sheet'
import { spring } from '../lib/motion'
import { MuscleTag } from '../components/train/MuscleTag'

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
      onPointerDown={(e) => e.stopPropagation()}
      onTouchStart={(e) => e.stopPropagation()}
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

function setLabel(sets: LoggedSet[], idx: number): string {
  const set = sets[idx]
  if (set.isWarmup) return 'W'
  if (set.isDropSet) return '↓'
  return String(sets.slice(0, idx + 1).filter((s) => !s.isDropSet && !s.isWarmup).length)
}

function gridCols(kind: ExerciseKind): string {
  switch (kind) {
    case 'weight':     return '40px 52px 1fr 1fr 44px'
    case 'cardio':     return '40px 52px 1fr 1fr 44px'
    case 'bodyweight': return '40px 64px 1fr 44px'
    case 'hold':       return '40px 64px 1fr 44px'
  }
}

/* ── Exercise group type ──────────────────────────────────────────────── */

type ExGroup = { exercises: SessionExercise[]; supersetId?: string; id: string }

function buildGroups(exercises: SessionExercise[]): ExGroup[] {
  const groups: ExGroup[] = []
  exercises.forEach((ex, i) => {
    const sid = ex.supersetId
    if (sid && groups.length > 0 && groups.at(-1)?.supersetId === sid) {
      groups.at(-1)!.exercises.push(ex)
    } else {
      groups.push({ exercises: [ex], supersetId: sid ?? undefined, id: `${ex.exerciseId}-${i}` })
    }
  })
  return groups
}

/* ── Finish summary ───────────────────────────────────────────────────── */

function FinishSummary({
  session,
  sets,
  volume,
  prs,
  unit,
  exercises: allEx,
  onSave,
  onContinue,
}: {
  session: WorkoutSession
  sets: number
  volume: number
  prs: PRHit[]
  unit: string
  exercises: ReturnType<typeof useLife>['state']['exercises']
  onSave: () => void
  onContinue: () => void
}) {
  const dur = (() => {
    const mins = Math.round((Date.now() - session.startedAt) / 60_000)
    if (mins < 60) return `${mins}m`
    return `${Math.floor(mins / 60)}h ${mins % 60}m`
  })()
  const muscles = sessionMuscles(session, allEx)

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-3 gap-2">
        {[
          { value: dur, label: 'duration' },
          { value: String(sets), label: 'sets' },
          { value: `${volume}`, label: `${unit} vol` },
        ].map(({ value, label }) => (
          <div
            key={label}
            className="rounded-card bg-surface p-3 text-center shadow-card"
            style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
          >
            <div className="tabular text-title3 text-label">{value}</div>
            <div className="text-caption text-label2">{label}</div>
          </div>
        ))}
      </div>

      {muscles.length > 0 && (
        <div>
          <div className="mb-1.5 text-footnote font-medium text-label2">Muscles trained</div>
          <div className="flex flex-wrap gap-1.5">
            {muscles.map((m) => <MuscleTag key={m} muscle={m} />)}
          </div>
        </div>
      )}

      {prs.length > 0 && (
        <div
          className="rounded-card bg-surface p-4 shadow-card"
          style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
        >
          <div className="mb-2 flex items-center gap-2 text-headline text-label">
            <Trophy size={18} className="text-nourish" /> New personal records
          </div>
          <div className="space-y-1">
            {prs.map((p, i) => (
              <div key={i} className="text-subhead text-label2">{p.label}</div>
            ))}
          </div>
        </div>
      )}

      <motion.button
        whileTap={{ scale: 0.97 }}
        transition={spring}
        onClick={onSave}
        className="w-full rounded-card bg-accent py-3.5 text-headline text-white"
      >
        Save workout
      </motion.button>
      <button
        onClick={onContinue}
        className="w-full py-2.5 text-center text-subhead font-medium text-label2"
      >
        Continue editing
      </button>
    </div>
  )
}

/* ── Drag handle ──────────────────────────────────────────────────────── */

function DragHandle({ controls }: { controls: ReturnType<typeof useDragControls> }) {
  return (
    <button
      className="flex h-10 w-8 touch-none items-center justify-center text-label3"
      onPointerDown={(e) => { e.preventDefault(); controls.start(e) }}
      aria-label="Drag to reorder"
    >
      <GripVertical size={18} strokeWidth={1.8} />
    </button>
  )
}

/* ── Single exercise group item (Reorder.Item wrapper) ─────────────────── */

function ExGroupItem({
  group,
  allExercises,
  sessions,
  prFlags,
  exIndices,
  editing,
  onToggle,
  onReplace,
  onRemove,
  onLinkSuperset,
  onAddSet,
  onAddWarmup,
  onAddDrop,
  onRemoveSet,
  onUpdateSet,
}: {
  group: ExGroup
  allExercises: ReturnType<typeof useLife>['state']['exercises']
  sessions: WorkoutSession[]
  prFlags: boolean[][]
  exIndices: number[]
  editing: boolean
  onToggle: (exIdx: number, setIdx: number, exerciseId: string, set: LoggedSet) => void
  onReplace: (exIdx: number) => void
  onRemove: (exIdx: number) => void
  onLinkSuperset: (exIdx: number) => void
  onAddSet: (exIdx: number) => void
  onAddWarmup: (exIdx: number) => void
  onAddDrop: (exIdx: number) => void
  onRemoveSet: (exIdx: number, setIdx: number) => void
  onUpdateSet: (exIdx: number, setIdx: number, patch: Partial<LoggedSet>) => void
}) {
  const controls = useDragControls()
  const isSuperset = group.exercises.length > 1

  const renderExerciseContent = (ex: SessionExercise, exIdx: number) => {
    const meta = exerciseById(allExercises, ex.exerciseId)
    const kind = meta?.kind ?? 'weight'
    const cols = COLS[kind]
    const prev = lastPerformance(sessions, ex.exerciseId)
    const isLinked = !!ex.supersetId
    const canLink = !isLinked

    return (
      <div key={exIdx} className={isSuperset ? 'p-4' : ''}>
        {/* Header */}
        <div className="mb-3 flex items-start gap-1">
          {!isSuperset && <DragHandle controls={controls} />}
          <div className="min-w-0 flex-1">
            <div className="text-headline text-label">{meta?.name ?? 'Exercise'}</div>
            {meta?.muscle && <div className="mt-1"><MuscleTag muscle={meta.muscle} /></div>}
          </div>
          <div className="flex shrink-0 items-center gap-0.5">
            <button
              onClick={() => onReplace(exIdx)}
              aria-label="Replace exercise"
              className="grid h-8 w-8 place-items-center text-label3 active:scale-90"
            >
              <RefreshCw size={14} strokeWidth={2} />
            </button>
            {!editing && !isSuperset && (
              <button
                onClick={() => onLinkSuperset(exIdx)}
                disabled={!canLink}
                aria-label="Superset with next exercise"
                className="grid h-8 w-8 place-items-center text-label3 disabled:opacity-25 active:scale-90"
              >
                <Link2 size={15} strokeWidth={2} />
              </button>
            )}
            <button
              onClick={() => onRemove(exIdx)}
              aria-label="Remove exercise"
              className="grid h-8 w-8 place-items-center text-label3 active:scale-90"
            >
              <X size={19} />
            </button>
          </div>
        </div>

        {/* Column headers */}
        <div
          className="mb-1 grid items-center gap-2 px-1 text-caption font-medium uppercase tracking-wide text-label3"
          style={{ gridTemplateColumns: gridCols(kind) }}
        >
          {cols.map((c, i) => (
            <div key={i} className={i === 0 ? '' : 'text-center'}>{c}</div>
          ))}
        </div>

        {/* Set rows */}
        <div className="space-y-1.5">
          {ex.sets.map((set, setIdx) => {
            const isDrop = !!set.isDropSet
            const isWarmup = !!set.isWarmup
            const canDelete = ex.sets.length > 1

            const rowBg = set.done
              ? isWarmup ? 'bg-amber-500/10' : isDrop ? 'bg-accent/10' : 'bg-move/10'
              : isWarmup ? 'bg-amber-500/5' : isDrop ? 'bg-accent/5' : ''

            const labelColor = isWarmup
              ? 'text-amber-500'
              : isDrop ? 'text-accent' : 'text-label2'

            return (
              <div key={setIdx} className="relative overflow-hidden rounded-[10px]">
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
                  onDragEnd={(_, info) => {
                    if (canDelete && info.offset.x < -52) onRemoveSet(exIdx, setIdx)
                  }}
                  className="relative rounded-[10px] bg-surface"
                >
                  <div
                    className={`grid items-center gap-2 rounded-[10px] px-1 py-1 ${rowBg}`}
                    style={{ gridTemplateColumns: gridCols(kind) }}
                  >
                    <div className={`text-center text-callout font-semibold ${labelColor}`}>
                      {setLabel(ex.sets, setIdx)}
                    </div>

                    <div className="text-center text-footnote text-label3">
                      {setHint(prev?.sets[setIdx])}
                    </div>

                    {kind === 'weight' && (
                      <>
                        <NumCell value={set.weight} placeholder="0" onChange={(v) => onUpdateSet(exIdx, setIdx, { weight: v })} />
                        <NumCell value={set.reps}   placeholder="0" onChange={(v) => onUpdateSet(exIdx, setIdx, { reps: v })} />
                      </>
                    )}
                    {kind === 'bodyweight' && (
                      <NumCell value={set.reps} placeholder="0" onChange={(v) => onUpdateSet(exIdx, setIdx, { reps: v })} />
                    )}
                    {kind === 'cardio' && (
                      <>
                        <NumCell value={set.distanceKm} placeholder="0" onChange={(v) => onUpdateSet(exIdx, setIdx, { distanceKm: v })} />
                        <NumCell
                          value={set.durationSec != null ? Math.round(set.durationSec / 60) : undefined}
                          placeholder="0"
                          onChange={(v) => onUpdateSet(exIdx, setIdx, { durationSec: v != null ? v * 60 : undefined })}
                        />
                      </>
                    )}
                    {kind === 'hold' && (
                      <NumCell value={set.durationSec} placeholder="0" onChange={(v) => onUpdateSet(exIdx, setIdx, { durationSec: v })} />
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
                            ? isWarmup ? 'border-amber-500 bg-amber-500 text-white'
                            : isDrop   ? 'border-accent bg-accent text-white'
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

        {/* Set action buttons */}
        <div className="mt-2 flex gap-1.5">
          <button
            onClick={() => onAddSet(exIdx)}
            className="flex-1 rounded-[10px] bg-fill py-2.5 text-subhead font-medium text-label2 active:scale-[0.99]"
          >
            + Set
          </button>
          <button
            onClick={() => onAddWarmup(exIdx)}
            className="rounded-[10px] px-3 py-2.5 text-subhead font-medium text-amber-500 active:scale-[0.99]"
            style={{ background: 'rgb(245 158 11 / 0.1)' }}
          >
            W Warm-up
          </button>
          <button
            onClick={() => onAddDrop(exIdx)}
            className="rounded-[10px] bg-accent/10 px-3 py-2.5 text-subhead font-medium text-accent active:scale-[0.99]"
          >
            ↓ Drop
          </button>
        </div>
      </div>
    )
  }

  if (!isSuperset) {
    return (
      <Reorder.Item
        value={group}
        dragListener={false}
        dragControls={controls}
        className="rounded-card bg-surface shadow-card"
        style={{ border: '0.5px solid rgb(var(--separator) / 0.5)', listStyle: 'none' }}
      >
        <div className="p-4">
          {renderExerciseContent(group.exercises[0], exIndices[0])}
        </div>
      </Reorder.Item>
    )
  }

  return (
    <Reorder.Item
      value={group}
      dragListener={false}
      dragControls={controls}
      className="overflow-hidden rounded-card bg-surface shadow-card"
      style={{ border: '0.5px solid rgb(var(--separator) / 0.5)', listStyle: 'none' }}
    >
      {/* Superset header */}
      <div
        className="flex items-center gap-2 px-4 py-2"
        style={{ background: 'rgb(var(--accent) / 0.08)' }}
      >
        <DragHandle controls={controls} />
        <Link2 size={13} className="text-accent" strokeWidth={2.2} />
        <span className="text-caption font-semibold uppercase tracking-wider text-accent">Superset</span>
      </div>
      {group.exercises.map((ex, i) => (
        <div key={exIndices[i]} className={i > 0 ? 'border-t border-separator/60' : ''}>
          {renderExerciseContent(ex, exIndices[i])}
        </div>
      ))}
    </Reorder.Item>
  )
}

/* ── Main component ───────────────────────────────────────────────────── */

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
    addWarmupSet,
    removeSet,
    addExerciseToSession,
    removeExerciseFromSession,
    replaceExerciseInSession,
    reorderExercisesInSession,
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
  const [replacingIdx, setReplacingIdx] = useState<number | null>(null)
  const [rest, setRest] = useState<{ key: number; seconds: number } | null>(null)
  const [summary, setSummary] = useState<{ volume: number; sets: number; prs: PRHit[] } | null>(null)
  const [discardOpen, setDiscardOpen] = useState(false)

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [])

  /* ── Drag-to-reorder state ── */
  // exerciseStructureKey only changes when exercises are added/removed/replaced
  const exerciseStructureKey = useMemo(
    () => session.exercises.map((e) => `${e.exerciseId}|${e.supersetId ?? ''}`).join(','),
    [session.exercises],
  )

  const storeGroups = useMemo(() => buildGroups(session.exercises), [exerciseStructureKey]) // eslint-disable-line react-hooks/exhaustive-deps

  const [groups, setGroups] = useState<ExGroup[]>(storeGroups)
  const isDraggingRef = useRef(false)

  useEffect(() => {
    if (!isDraggingRef.current) setGroups(storeGroups)
  }, [storeGroups])

  const handleGroupReorder = (newGroups: ExGroup[]) => {
    setGroups(newGroups)
    const newExercises = newGroups.flatMap((g) => g.exercises)
    reorderExercisesInSession(session.id, newExercises)
  }

  /* ── Lookup: group → original exercise indices ── */
  const groupToIndices = useMemo(() => {
    const map = new Map<string, number[]>()
    let idx = 0
    for (const group of storeGroups) {
      map.set(group.id, group.exercises.map((_, i) => idx + i))
      idx += group.exercises.length
    }
    return map
  }, [storeGroups])

  /* ── PR flags ── */
  const prFlags = useMemo(
    () =>
      session.exercises.map((ex) =>
        ex.sets.map((set) => isSetPR(state.sessions, session.id, ex.exerciseId, set)),
      ),
    [session.exercises, state.sessions, session.id], // eslint-disable-line react-hooks/exhaustive-deps
  )

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
    if (editing || set.done || !ws.restTimerEnabled || set.isWarmup) return

    const nextSet = session.exercises[exIdx].sets[setIdx + 1]
    if (nextSet?.isDropSet) return

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

  const doDiscard = () => {
    discardSession(session.id)
    setDiscardOpen(false)
    onMinimize()
  }

  const unitLabel = ws.unit
  const liveVolume = useMemo(() => sessionVolume(session), [session])
  const subLine = editing
    ? `${new Date(session.finishedAt ?? session.startedAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })} · ${sessionSetCount(session)} sets · ${liveVolume} ${unitLabel}`
    : `${elapsedLabel(now - session.startedAt)} · ${sessionSetCount(session)} sets · ${liveVolume} ${unitLabel}`

  return (
    <div className="min-h-full">
      {/* Top bar */}
      <div className="material sticky top-0 z-20 -mx-4">
        <div className="flex h-14 items-center gap-3 px-4">
          <motion.button whileTap={{ scale: 0.9 }} onClick={onMinimize} aria-label="Minimise" className="text-label2">
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

      {/* Exercise list with drag reorder */}
      <div className="pb-40 pt-4">
        {session.exercises.length === 0 && (
          <div className="flex flex-col items-center py-12 text-center">
            <div className="mb-3 text-4xl">🏋️</div>
            <p className="text-headline text-label">No exercises yet</p>
            <p className="mt-1 text-subhead text-label2">Tap "Add exercise" below to get started.</p>
          </div>
        )}

        <Reorder.Group
          axis="y"
          values={groups}
          onReorder={handleGroupReorder}
          className="space-y-4"
          style={{ listStyle: 'none', padding: 0, margin: 0 }}
        >
          {groups.map((group) => {
            const indices = groupToIndices.get(group.id) ?? group.exercises.map((_, i) => i)
            return (
              <ExGroupItem
                key={group.id}
                group={group}
                allExercises={state.exercises}
                sessions={state.sessions}
                prFlags={prFlags}
                exIndices={indices}
                editing={editing}
                onToggle={onToggle}
                onReplace={(exIdx) => setReplacingIdx(exIdx)}
                onRemove={(exIdx) => removeExerciseFromSession(session.id, exIdx)}
                onLinkSuperset={(exIdx) => {
                  const nextIdx = exIdx + 1
                  if (nextIdx < session.exercises.length) {
                    const linked = !!session.exercises[exIdx].supersetId
                    linked
                      ? unlinkSuperset(session.id, exIdx)
                      : linkAsSuperset(session.id, exIdx, nextIdx)
                  }
                }}
                onAddSet={(exIdx) => addSet(session.id, exIdx)}
                onAddWarmup={(exIdx) => addWarmupSet(session.id, exIdx)}
                onAddDrop={(exIdx) => addDropSet(session.id, exIdx)}
                onRemoveSet={(exIdx, setIdx) => removeSet(session.id, exIdx, setIdx)}
                onUpdateSet={(exIdx, setIdx, patch) => updateSet(session.id, exIdx, setIdx, patch)}
              />
            )
          })}
        </Reorder.Group>

        {/* Bottom actions */}
        <div className="mt-4 flex gap-2">
          <button
            onClick={() => setPicker(true)}
            className="flex flex-1 items-center justify-center gap-1.5 rounded-card border border-dashed border-separator py-3.5 text-callout font-medium text-accent"
          >
            <Plus size={18} /> Add exercise
          </button>
          {!editing && (
            <motion.button
              whileTap={{ scale: 0.97 }}
              transition={spring}
              onClick={finish}
              className="flex items-center gap-1.5 rounded-card bg-move px-5 py-3.5 text-callout font-semibold text-white"
            >
              Finish
            </motion.button>
          )}
        </div>

        {/* Cancel / delete */}
        <button
          onClick={() => setDiscardOpen(true)}
          className="mt-2 w-full py-3 text-center text-subhead text-danger"
        >
          {editing ? 'Delete workout' : 'Cancel workout'}
        </button>
      </div>

      {/* Exercise pickers */}
      <ExercisePicker
        open={picker}
        onClose={() => setPicker(false)}
        onPick={(id) => addExerciseToSession(session.id, id)}
      />
      <ExercisePicker
        open={replacingIdx !== null}
        onClose={() => setReplacingIdx(null)}
        onPick={(id) => {
          if (replacingIdx !== null) replaceExerciseInSession(session.id, replacingIdx, id)
          setReplacingIdx(null)
        }}
      />

      {/* Rest timer */}
      <AnimatePresence>
        {rest && <RestTimer key={rest.key} seconds={rest.seconds} onClose={() => setRest(null)} />}
      </AnimatePresence>

      {/* Finish summary */}
      <Sheet open={!!summary} onClose={() => setSummary(null)} title="Workout summary">
        {summary && (
          <FinishSummary
            session={session}
            sets={summary.sets}
            volume={summary.volume}
            prs={summary.prs}
            unit={unitLabel}
            exercises={state.exercises}
            onSave={commitFinish}
            onContinue={() => setSummary(null)}
          />
        )}
      </Sheet>

      {/* Discard confirmation sheet */}
      <Sheet open={discardOpen} onClose={() => setDiscardOpen(false)} title={editing ? 'Delete workout?' : 'Cancel workout?'}>
        <div className="space-y-3">
          <div className="flex items-start gap-3 rounded-card bg-danger/10 p-3">
            <AlertTriangle size={20} className="mt-0.5 shrink-0 text-danger" />
            <p className="text-subhead text-label">
              {editing
                ? 'This will permanently delete this workout from your history. This cannot be undone.'
                : 'This will discard your current workout. All sets logged so far will be lost.'}
            </p>
          </div>
          <motion.button
            whileTap={{ scale: 0.97 }}
            transition={spring}
            onClick={doDiscard}
            className="w-full rounded-card bg-danger py-3.5 text-headline text-white"
          >
            {editing ? 'Delete workout' : 'Discard workout'}
          </motion.button>
          <button
            onClick={() => setDiscardOpen(false)}
            className="w-full py-2.5 text-center text-subhead font-medium text-label2"
          >
            Keep going
          </button>
        </div>
      </Sheet>
    </div>
  )
}
