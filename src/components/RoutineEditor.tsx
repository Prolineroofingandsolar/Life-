import { useState } from 'react'
import { motion } from 'framer-motion'
import { Plus, X, ChevronUp, ChevronDown } from 'lucide-react'
import { useLife } from '../lib/store'
import { exerciseById } from '../lib/workout'
import { SEED_ROUTINES } from '../lib/workoutSeed'
import type { Routine, RoutineExercise } from '../lib/types'
import Sheet from './Sheet'
import ExercisePicker from './ExercisePicker'
import { Stepper } from './ui'
import { spring } from '../lib/motion'
import { MuscleTag } from './train/MuscleTag'

const TEMPLATES = SEED_ROUTINES.map((r) => ({
  id: r.id,
  name: r.name,
  exercises: r.exercises,
}))

/** Create or edit a routine. Pass `routine` to edit, omit to create. */
export default function RoutineEditor({
  open,
  onClose,
  routine,
}: {
  open: boolean
  onClose: () => void
  routine?: Routine
}) {
  const { state, addRoutine, updateRoutine } = useLife()
  const [name, setName] = useState(routine?.name ?? '')
  const [items, setItems] = useState<RoutineExercise[]>(routine?.exercises ?? [])
  const [picker, setPicker] = useState(false)
  const [showTemplates, setShowTemplates] = useState(!routine && true)

  const ws = state.workoutSettings
  const isNew = !routine

  const addItem = (exerciseId: string) =>
    setItems((xs) => [...xs, { exerciseId, targetSets: 3, targetReps: 10, restSec: ws.defaultRestSec }])

  const patch = (i: number, p: Partial<RoutineExercise>) =>
    setItems((xs) => xs.map((x, j) => (j === i ? { ...x, ...p } : x)))

  const remove = (i: number) => setItems((xs) => xs.filter((_, j) => j !== i))

  const moveUp = (i: number) => {
    if (i === 0) return
    setItems((xs) => {
      const arr = [...xs]
      ;[arr[i - 1], arr[i]] = [arr[i], arr[i - 1]]
      return arr
    })
  }

  const moveDown = (i: number) => {
    setItems((xs) => {
      if (i >= xs.length - 1) return xs
      const arr = [...xs]
      ;[arr[i], arr[i + 1]] = [arr[i + 1], arr[i]]
      return arr
    })
  }

  const applyTemplate = (tplId: string) => {
    const tpl = TEMPLATES.find((t) => t.id === tplId)
    if (!tpl) return
    setName(tpl.name)
    setItems(tpl.exercises.map((re) => ({ ...re })))
    setShowTemplates(false)
  }

  const save = () => {
    if (items.length === 0) return
    if (routine) {
      updateRoutine(routine.id, { name: name.trim() || routine.name, exercises: items })
    } else {
      addRoutine(name, items)
    }
    onClose()
  }

  const handleClose = () => {
    onClose()
    // Reset state after sheet closes so next open starts fresh
    setTimeout(() => {
      setName(routine?.name ?? '')
      setItems(routine?.exercises ?? [])
      setShowTemplates(!routine)
    }, 350)
  }

  return (
    <Sheet open={open} onClose={handleClose} title={routine ? 'Edit routine' : 'New routine'}>
      {/* Routine name input */}
      <input
        autoFocus={!isNew || !showTemplates}
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Routine name"
        aria-label="Routine name"
        className="mb-3 w-full rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
        style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
      />

      {/* Template picker — new routines only, collapsible */}
      {isNew && (
        <div className="mb-3">
          <button
            onClick={() => setShowTemplates((v) => !v)}
            className="mb-2 flex w-full items-center justify-between text-subhead font-medium text-accent"
          >
            <span>{showTemplates ? 'Templates' : 'Start from a template'}</span>
            <span className="text-label3">{showTemplates ? '▲' : '▼'}</span>
          </button>
          {showTemplates && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, height: 0 }}
              transition={spring}
              className="overflow-hidden"
            >
              <div className="grid grid-cols-2 gap-2 pb-1">
                {TEMPLATES.map((tpl) => (
                  <motion.button
                    key={tpl.id}
                    whileTap={{ scale: 0.95 }}
                    transition={spring}
                    onClick={() => applyTemplate(tpl.id)}
                    className="rounded-card bg-surface px-3 py-2.5 text-left shadow-card"
                    style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
                  >
                    <div className="text-subhead font-semibold text-label">{tpl.name}</div>
                    <div className="mt-0.5 text-caption text-label3">{tpl.exercises.length} exercises</div>
                  </motion.button>
                ))}
              </div>
            </motion.div>
          )}
        </div>
      )}

      {/* Exercise list */}
      <div className="max-h-[42vh] space-y-2 overflow-y-auto no-scrollbar">
        {items.length === 0 ? (
          <div className="rounded-card bg-fill py-6 text-center text-subhead text-label3">
            Add exercises below
          </div>
        ) : (
          items.map((it, i) => {
            const ex = exerciseById(state.exercises, it.exerciseId)
            const showReps = ex?.kind === 'weight' || ex?.kind === 'bodyweight'
            return (
              <div
                key={i}
                className="rounded-card bg-surface shadow-card"
                style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
              >
                {/* Exercise header */}
                <div className="flex items-center gap-2 px-3 pt-3">
                  {/* Reorder buttons */}
                  <div className="flex shrink-0 flex-col">
                    <button
                      onClick={() => moveUp(i)}
                      disabled={i === 0}
                      className="grid h-6 w-6 place-items-center text-label3 disabled:opacity-20 active:scale-90"
                      aria-label="Move up"
                    >
                      <ChevronUp size={16} />
                    </button>
                    <button
                      onClick={() => moveDown(i)}
                      disabled={i === items.length - 1}
                      className="grid h-6 w-6 place-items-center text-label3 disabled:opacity-20 active:scale-90"
                      aria-label="Move down"
                    >
                      <ChevronDown size={16} />
                    </button>
                  </div>

                  {/* Exercise name + muscle */}
                  <div className="min-w-0 flex-1">
                    <div className="text-body font-medium text-label">{ex?.name ?? 'Exercise'}</div>
                    {ex?.muscle && (
                      <div className="mt-0.5">
                        <MuscleTag muscle={ex.muscle} />
                      </div>
                    )}
                  </div>

                  <button
                    onClick={() => remove(i)}
                    aria-label="Remove"
                    className="shrink-0 grid h-8 w-8 place-items-center text-label3 active:scale-90"
                  >
                    <X size={18} />
                  </button>
                </div>

                {/* Set/reps/rest controls */}
                <div className="flex flex-wrap items-center gap-x-4 gap-y-2 px-3 pb-3 pt-2 text-footnote text-label2">
                  <label className="flex items-center gap-2">
                    <span className="w-6">Sets</span>
                    <Stepper value={it.targetSets} min={1} onChange={(v) => patch(i, { targetSets: v })} />
                  </label>
                  {showReps && (
                    <label className="flex items-center gap-2">
                      <span className="w-6">Reps</span>
                      <Stepper value={it.targetReps ?? 10} min={1} onChange={(v) => patch(i, { targetReps: v })} />
                    </label>
                  )}
                  <label className="flex items-center gap-2">
                    <span className="w-6">Rest</span>
                    <Stepper value={it.restSec} min={0} step={15} onChange={(v) => patch(i, { restSec: v })} />
                    <span className="tabular w-8 text-label3">{it.restSec}s</span>
                  </label>
                </div>
              </div>
            )
          })
        )}
      </div>

      {/* Add exercise button */}
      <button
        onClick={() => setPicker(true)}
        className="mt-2 flex w-full items-center justify-center gap-1.5 rounded-card border border-dashed border-separator py-3 text-callout text-accent"
      >
        <Plus size={18} /> Add exercise
      </button>

      {/* Save */}
      <motion.button
        whileTap={{ scale: 0.97 }}
        transition={spring}
        onClick={save}
        disabled={items.length === 0}
        className="mt-3 w-full rounded-card bg-accent py-3.5 text-headline text-white disabled:opacity-40"
      >
        {routine ? 'Save changes' : 'Create routine'}
      </motion.button>

      <ExercisePicker open={picker} onClose={() => setPicker(false)} onPick={addItem} />
    </Sheet>
  )
}
