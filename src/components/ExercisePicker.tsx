import { useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { Search, Plus } from 'lucide-react'
import { useLife } from '../lib/store'
import { EXERCISE_KIND_LABEL } from '../lib/types'
import type { ExerciseKind } from '../lib/types'
import Sheet from './Sheet'
import { SegmentedControl } from './ui'
import { spring } from '../lib/motion'

const KINDS: ExerciseKind[] = ['weight', 'bodyweight', 'cardio', 'hold']

export default function ExercisePicker({
  open,
  onClose,
  onPick,
}: {
  open: boolean
  onClose: () => void
  onPick: (exerciseId: string) => void
}) {
  const { state, addCustomExercise } = useLife()
  const [q, setQ] = useState('')
  const [muscleFilter, setMuscleFilter] = useState<string>('All')
  const [creating, setCreating] = useState(false)
  const [newName, setNewName] = useState('')
  const [newKind, setNewKind] = useState<ExerciseKind>('weight')

  const allMuscles = useMemo(() => {
    const seen = new Set<string>()
    state.exercises.forEach((e) => { if (e.muscle) seen.add(e.muscle) })
    return ['All', ...Array.from(seen).sort()]
  }, [state.exercises])

  const results = useMemo(() => {
    const term = q.trim().toLowerCase()
    return state.exercises.filter((e) => {
      if (muscleFilter !== 'All' && e.muscle !== muscleFilter) return false
      if (!term) return true
      return e.name.toLowerCase().includes(term) || e.muscle?.toLowerCase().includes(term)
    })
  }, [q, muscleFilter, state.exercises])

  const pick = (id: string) => {
    onPick(id)
    setQ('')
    setMuscleFilter('All')
    onClose()
  }

  const createAndPick = () => {
    if (!newName.trim()) return
    const id = addCustomExercise(newName, newKind)
    setNewName('')
    setCreating(false)
    pick(id)
  }

  return (
    <Sheet open={open} onClose={onClose} title="Add exercise">
      {creating ? (
        <div className="space-y-3">
          <input
            autoFocus
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="Exercise name"
            className="w-full rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
          />
          <SegmentedControl<ExerciseKind>
            layoutId="new-ex-kind"
            value={newKind}
            onChange={setNewKind}
            options={KINDS.map((k) => ({ value: k, label: EXERCISE_KIND_LABEL[k].split(' ')[0] }))}
          />
          <div className="flex gap-2">
            <motion.button
              whileTap={{ scale: 0.97 }}
              transition={spring}
              onClick={createAndPick}
              disabled={!newName.trim()}
              className="flex-1 rounded-card bg-accent py-3.5 text-headline text-white disabled:opacity-40"
            >
              Create & add
            </motion.button>
            <button
              onClick={() => setCreating(false)}
              className="rounded-card bg-fill px-5 text-callout text-label2"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <>
          {/* Search */}
          <div className="mb-2 flex items-center gap-2 rounded-card bg-surface px-3.5 py-3 shadow-card">
            <Search size={18} className="shrink-0 text-label3" />
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search exercises"
              className="w-full bg-transparent text-body text-label placeholder:text-label3 focus:outline-none"
            />
          </div>

          {/* Muscle group filter chips */}
          <div className="mb-2 flex gap-1.5 overflow-x-auto pb-0.5 no-scrollbar">
            {allMuscles.map((m) => (
              <button
                key={m}
                onClick={() => setMuscleFilter(m)}
                className={`shrink-0 rounded-full px-3 py-1 text-footnote font-medium transition-colors ${
                  muscleFilter === m
                    ? 'bg-accent text-white'
                    : 'bg-fill text-label2'
                }`}
              >
                {m}
              </button>
            ))}
          </div>

          {/* Exercise list */}
          <div className="max-h-[44vh] overflow-y-auto rounded-card bg-surface shadow-card no-scrollbar [&>*+*]:border-t [&>*+*]:border-separator/70">
            {results.map((e) => (
              <button
                key={e.id}
                onClick={() => pick(e.id)}
                className="flex w-full items-center justify-between px-4 py-3 text-left active:bg-fill"
              >
                <span className="text-body text-label">{e.name}</span>
                <span className="ml-3 shrink-0 text-footnote text-label2">
                  {e.muscle ?? EXERCISE_KIND_LABEL[e.kind]}
                </span>
              </button>
            ))}
            {results.length === 0 && (
              <div className="px-4 py-6 text-center text-footnote text-label3">No matches</div>
            )}
          </div>

          <button
            onClick={() => {
              setNewName(q)
              setCreating(true)
            }}
            className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-card border border-dashed border-separator py-3 text-callout text-accent"
          >
            <Plus size={18} /> Create custom exercise
          </button>
        </>
      )}
    </Sheet>
  )
}
