import { useState } from 'react'
import { motion } from 'framer-motion'
import { Plus, X } from 'lucide-react'
import { useLife } from '../lib/store'
import { exerciseById } from '../lib/workout'
import type { Routine, RoutineExercise } from '../lib/types'
import Sheet from './Sheet'
import ExercisePicker from './ExercisePicker'
import { Stepper } from './ui'
import { spring } from '../lib/motion'

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

  const ws = state.workoutSettings

  const addItem = (exerciseId: string) =>
    setItems((xs) => [...xs, { exerciseId, targetSets: 3, targetReps: 10, restSec: ws.defaultRestSec }])
  const patch = (i: number, p: Partial<RoutineExercise>) =>
    setItems((xs) => xs.map((x, j) => (j === i ? { ...x, ...p } : x)))
  const remove = (i: number) => setItems((xs) => xs.filter((_, j) => j !== i))

  const save = () => {
    if (routine) updateRoutine(routine.id, { name: name.trim() || routine.name, exercises: items })
    else addRoutine(name, items)
    onClose()
  }

  return (
    <Sheet open={open} onClose={onClose} title={routine ? 'Edit routine' : 'New routine'}>
      <input
        autoFocus
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Routine name"
        aria-label="Routine name"
        className="mb-3 w-full rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
        style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
      />

      <div className="max-h-[46vh] space-y-2 overflow-y-auto no-scrollbar">
        {items.map((it, i) => {
          const ex = exerciseById(state.exercises, it.exerciseId)
          const showReps = ex?.kind === 'weight' || ex?.kind === 'bodyweight'
          return (
            <div key={i} className="rounded-card bg-surface p-3 shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
              <div className="mb-2 flex items-center justify-between">
                <span className="text-body text-label">{ex?.name ?? 'Exercise'}</span>
                <button onClick={() => remove(i)} aria-label="Remove" className="text-label3 active:scale-90">
                  <X size={18} />
                </button>
              </div>
              <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-footnote text-label2">
                <label className="flex items-center gap-2">
                  Sets
                  <Stepper value={it.targetSets} min={1} onChange={(v) => patch(i, { targetSets: v })} />
                </label>
                {showReps && (
                  <label className="flex items-center gap-2">
                    Reps
                    <Stepper value={it.targetReps ?? 10} min={1} onChange={(v) => patch(i, { targetReps: v })} />
                  </label>
                )}
                <label className="flex items-center gap-2">
                  Rest
                  <Stepper value={it.restSec} min={0} step={15} onChange={(v) => patch(i, { restSec: v })} />
                  <span className="tabular w-8">{it.restSec}s</span>
                </label>
              </div>
            </div>
          )
        })}
      </div>

      <button
        onClick={() => setPicker(true)}
        className="mt-2 flex w-full items-center justify-center gap-1.5 rounded-card border border-dashed border-separator py-3 text-callout text-accent"
      >
        <Plus size={18} /> Add exercise
      </button>

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
