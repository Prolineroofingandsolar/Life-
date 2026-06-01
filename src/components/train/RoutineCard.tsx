import { motion } from 'framer-motion'
import { Play, Clock, Pencil, Trash2 } from 'lucide-react'
import { MuscleTag } from './MuscleTag'
import { spring } from '../../lib/motion'
import { exerciseById } from '../../lib/workout'
import type { Exercise, Routine } from '../../lib/types'

interface Props {
  routine: Routine
  exercises: Exercise[]
  onStart: () => void
  onEdit: () => void
  onDelete: () => void
}

function estimateDuration(r: Routine): number {
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

export default function RoutineCard({ routine, exercises, onStart, onEdit, onDelete }: Props) {
  const muscles = routineMuscles(routine, exercises)
  const dur = estimateDuration(routine)
  const totalSets = routine.exercises.reduce((n, re) => n + re.targetSets, 0)

  return (
    <div className="relative overflow-hidden rounded-card">
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
        onDragEnd={(_, info) => { if (info.offset.x < -72) onDelete() }}
        className="relative rounded-card bg-surface shadow-card"
        style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
      >
        <div className="p-4">
          {/* Header */}
          <div className="mb-2">
            <div className="text-headline text-label">{routine.name}</div>
            <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-footnote text-label2">
              <span>{routine.exercises.length} exercise{routine.exercises.length !== 1 ? 's' : ''}</span>
              <span>·</span>
              <span>{totalSets} sets</span>
              <span>·</span>
              <Clock size={11} className="inline-block" />
              <span>~{dur}m</span>
            </div>
          </div>

          {/* Muscles */}
          {muscles.length > 0 && (
            <div className="mb-3 flex flex-wrap gap-1.5">
              {muscles.map((m) => <MuscleTag key={m} muscle={m} />)}
            </div>
          )}

          {/* Actions */}
          <div className="flex gap-2">
            <motion.button
              whileTap={{ scale: 0.93 }}
              transition={spring}
              onPointerDown={(e) => e.stopPropagation()}
              onClick={onStart}
              className="flex flex-1 items-center justify-center gap-1.5 rounded-[10px] bg-accent py-2.5 text-subhead font-semibold text-white"
            >
              <Play size={14} fill="currentColor" /> Start
            </motion.button>
            <motion.button
              whileTap={{ scale: 0.93 }}
              transition={spring}
              onPointerDown={(e) => e.stopPropagation()}
              onClick={onEdit}
              className="flex items-center justify-center gap-1.5 rounded-[10px] bg-fill px-4 py-2.5 text-subhead font-medium text-label2"
            >
              <Pencil size={14} /> Edit
            </motion.button>
          </div>
        </div>
      </motion.div>
    </div>
  )
}
