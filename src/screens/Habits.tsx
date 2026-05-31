import { useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Plus, Flame, Pencil, Trash2, Archive, ArchiveRestore, Trophy } from 'lucide-react'
import { useLife } from '../lib/store'
import { bestStreak, cadenceLabel, currentStreak, isPendingToday, isScheduledOn } from '../lib/habits'
import type { Habit } from '../lib/types'
import { LargeTitleHeader, IconButton, SectionLabel, Card, EmptyState } from '../components/ui'
import HabitRow from '../components/HabitRow'
import HabitHeatmap from '../components/HabitHeatmap'
import HabitEditor from '../components/HabitEditor'
import Sheet from '../components/Sheet'
import Toast from '../components/Toast'
import { listItem, spring } from '../lib/motion'

function Ring({ progress, size = 56 }: { progress: number; size?: number }) {
  const sw = 5
  const r = (size - sw) / 2
  const c = 2 * Math.PI * r
  return (
    <svg width={size} height={size} className="-rotate-90" aria-hidden="true">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="rgb(var(--accent))" strokeOpacity={0.18} strokeWidth={sw} />
      <motion.circle
        cx={size / 2} cy={size / 2} r={r} fill="none"
        stroke="rgb(var(--accent))" strokeWidth={sw} strokeLinecap="round"
        strokeDasharray={c} initial={false}
        animate={{ strokeDashoffset: c * (1 - progress) }} transition={spring}
      />
    </svg>
  )
}

function SwipableHabitRow({
  habit,
  onOpen,
  onDelete,
}: {
  habit: Habit
  onOpen: () => void
  onDelete: () => void
}) {
  return (
    <motion.div variants={listItem} exit="exit" layout className="relative overflow-hidden">
      <div className="absolute inset-y-0 right-0 flex items-center bg-danger pl-6 pr-5 text-white">
        <Trash2 size={20} />
      </div>
      <motion.div
        drag="x"
        dragConstraints={{ left: -96, right: 0 }}
        dragElastic={{ left: 0.5, right: 0 }}
        dragMomentum={false}
        dragSnapToOrigin
        onDragEnd={(_, info) => { if (info.offset.x < -72) onDelete() }}
        className="relative bg-surface"
      >
        <HabitRow habit={habit} onOpen={onOpen} />
      </motion.div>
    </motion.div>
  )
}

export default function Habits() {
  const { state, deleteHabit, toggleArchiveHabit, restoreHabit } = useLife()
  const [editor, setEditor] = useState<{ open: boolean; habit?: Habit }>({ open: false })
  const [detailId, setDetailId] = useState<string | null>(null)
  const [deletedHabit, setDeletedHabit] = useState<{ habit: Habit; logs: Record<string, number> | undefined } | null>(null)
  const undoTimer = useRef<number | null>(null)

  const today = new Date()
  const active = state.habits.filter((h) => !h.archived)
  const archived = state.habits.filter((h) => h.archived)
  const detail = state.habits.find((h) => h.id === detailId)

  const todayBuild = active.filter((h) => h.kind === 'build' && isScheduledOn(h, today))
  const remaining = todayBuild.filter((h) => isPendingToday(h, state.habitLogs, today)).length
  const doneCount = todayBuild.length - remaining
  const progress = todayBuild.length ? doneCount / todayBuild.length : 0
  const breakHabits = active.filter((h) => h.kind === 'break')

  const handleDelete = (habit: Habit) => {
    const logs = state.habitLogs[habit.id]
    deleteHabit(habit.id)
    setDeletedHabit({ habit, logs })
    if (undoTimer.current) clearTimeout(undoTimer.current)
    undoTimer.current = window.setTimeout(() => setDeletedHabit(null), 4000)
  }

  const handleUndo = () => {
    if (deletedHabit) restoreHabit(deletedHabit.habit, deletedHabit.logs)
  }

  return (
    <div>
      <LargeTitleHeader
        title="Habits"
        trailing={<IconButton icon={Plus} label="New habit" accent onClick={() => setEditor({ open: true })} />}
      />

      {active.length === 0 ? (
        <EmptyState icon={Flame} title="No habits yet" subtitle="Tap + to build a good habit — or quit a bad one." />
      ) : (
        <>
          {/* Today summary */}
          <Card className="mb-5 mt-1 flex items-center gap-4 p-4">
            <div className="relative grid place-items-center">
              <Ring progress={progress} />
              <span className="tabular absolute text-headline text-label">{Math.round(progress * 100)}%</span>
            </div>
            <div className="flex-1">
              <div className="text-headline text-label">
                {todayBuild.length === 0
                  ? 'Nothing due today'
                  : remaining === 0
                    ? 'All done today 🎉'
                    : `${doneCount} of ${todayBuild.length} done`}
              </div>
              <div className="text-footnote text-label2">
                {remaining > 0 ? `${remaining} habit${remaining === 1 ? '' : 's'} left` : 'Keep the streaks alive'}
                {breakHabits.length > 0 && ` · ${breakHabits.length} to avoid`}
              </div>
            </div>
          </Card>

          <SectionLabel>Habits</SectionLabel>
          <motion.div
            layout
            className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70"
            style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
          >
            <AnimatePresence initial={false}>
              {active.map((h) => (
                <SwipableHabitRow
                  key={h.id}
                  habit={h}
                  onOpen={() => setDetailId(h.id)}
                  onDelete={() => handleDelete(h)}
                />
              ))}
            </AnimatePresence>
          </motion.div>
          <p className="mt-2 text-center text-caption text-label3">Swipe left to delete</p>
        </>
      )}

      {archived.length > 0 && (
        <>
          <SectionLabel>Archived</SectionLabel>
          <div className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
            {archived.map((h) => (
              <div key={h.id} className="flex items-center gap-3 px-4 py-3">
                <span className="text-lg opacity-60">{h.emoji}</span>
                <span className="flex-1 text-body text-label2">{h.name}</span>
                <button onClick={() => toggleArchiveHabit(h.id)} className="text-footnote font-medium text-accent">
                  Restore
                </button>
              </div>
            ))}
          </div>
        </>
      )}

      <div className="h-4" />

      <HabitEditor open={editor.open} habit={editor.habit} onClose={() => setEditor({ open: false })} />

      {/* Detail sheet */}
      <Sheet open={!!detail} onClose={() => setDetailId(null)} title={undefined}>
        {detail && (
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <span className="grid h-14 w-14 place-items-center rounded-full text-3xl" style={{ background: detail.color + '28' }}>
                {detail.emoji}
              </span>
              <div>
                <div className="text-title3 text-label">{detail.name}</div>
                <div className="text-footnote text-label2">
                  {detail.kind === 'break' ? 'Quitting' : cadenceLabel(detail)}
                </div>
              </div>
            </div>

            <div className="flex gap-3">
              <div className="flex-1 rounded-card bg-surface p-4 text-center shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
                <div className="mb-0.5 flex items-center justify-center gap-1">
                  <Flame size={16} className="text-nourish" />
                  <span className="tabular text-title2 text-label">{currentStreak(detail, state.habitLogs, today)}</span>
                </div>
                <div className="text-footnote text-label2">{detail.kind === 'break' ? 'days clean' : 'current streak'}</div>
              </div>
              <div className="flex-1 rounded-card bg-surface p-4 text-center shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
                <div className="mb-0.5 flex items-center justify-center gap-1">
                  <Trophy size={15} className="text-nourish" />
                  <span className="tabular text-title2 text-label">{bestStreak(detail, state.habitLogs, today)}</span>
                </div>
                <div className="text-footnote text-label2">best</div>
              </div>
            </div>

            <HabitHeatmap habit={detail} logs={state.habitLogs} />

            <div className="flex gap-2">
              <motion.button
                whileTap={{ scale: 0.97 }}
                transition={spring}
                onClick={() => { setEditor({ open: true, habit: detail }); setDetailId(null) }}
                className="flex flex-1 items-center justify-center gap-2 rounded-card bg-accent py-3 text-headline text-white"
              >
                <Pencil size={17} /> Edit
              </motion.button>
              <button
                onClick={() => { toggleArchiveHabit(detail.id); setDetailId(null) }}
                aria-label={detail.archived ? 'Restore habit' : 'Archive habit'}
                className="grid w-12 place-items-center rounded-card bg-fill text-label2 active:scale-95"
              >
                {detail.archived ? <ArchiveRestore size={18} /> : <Archive size={18} />}
              </button>
            </div>
          </div>
        )}
      </Sheet>

      <AnimatePresence>
        {deletedHabit && (
          <Toast
            message={`"${deletedHabit.habit.name}" deleted`}
            onUndo={handleUndo}
            onDismiss={() => setDeletedHabit(null)}
          />
        )}
      </AnimatePresence>
    </div>
  )
}
