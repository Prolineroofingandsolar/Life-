import { motion } from 'framer-motion'
import { Clock, Trash2 } from 'lucide-react'
import { MuscleTag } from './MuscleTag'
import { exerciseById, sessionDuration, sessionMuscles, sessionSetCount, sessionVolume } from '../../lib/workout'
import type { Exercise, WorkoutSession } from '../../lib/types'

interface Props {
  session: WorkoutSession
  exercises: Exercise[]
  unit: string
  onTap: () => void
  onDelete: () => void
}

export default function HistoryCard({ session, exercises, unit, onTap, onDelete }: Props) {
  const muscles = sessionMuscles(session, exercises).slice(0, 4)
  const dur = sessionDuration(session)
  const preview = session.exercises
    .map((ex) => exerciseById(exercises, ex.exerciseId)?.name)
    .filter(Boolean).slice(0, 4).join(' · ')

  return (
    <div className="relative overflow-hidden rounded-card">
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
          if (info.offset.x < -72) onDelete()
          else if (Math.abs(info.offset.x) < 5) onTap()
        }}
        className="relative cursor-pointer rounded-card bg-surface p-4 shadow-card"
        style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
      >
        <div className="mb-1.5 flex items-start justify-between gap-2">
          <div className="text-headline text-label">{session.name}</div>
          <div className="shrink-0 text-footnote text-label2">
            {new Date(session.finishedAt ?? session.startedAt).toLocaleDateString('en-GB', {
              day: 'numeric', month: 'short',
            })}
          </div>
        </div>

        <div className="mb-2 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-footnote text-label2">
          {dur && <span className="flex items-center gap-1"><Clock size={11} />{dur}</span>}
          <span>{sessionSetCount(session)} sets</span>
          <span>{sessionVolume(session)} {unit}</span>
        </div>

        {muscles.length > 0 && (
          <div className="mb-2 flex flex-wrap gap-1.5">
            {muscles.map((m) => <MuscleTag key={m} muscle={m} />)}
          </div>
        )}

        {preview && <div className="truncate text-footnote text-label3">{preview}</div>}
      </motion.div>
    </div>
  )
}
