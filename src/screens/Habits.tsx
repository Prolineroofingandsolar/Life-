import { useState } from 'react'
import { motion } from 'framer-motion'
import { Plus, Flame, Pencil, Trash2, Archive, ArchiveRestore, Trophy } from 'lucide-react'
import { useLife } from '../lib/store'
import { bestStreak, cadenceLabel, currentStreak, isPendingToday, isScheduledOn } from '../lib/habits'
import type { Habit } from '../lib/types'
import { LargeTitleHeader, IconButton, SectionLabel, Card, EmptyState } from '../components/ui'
import HabitRow from '../components/HabitRow'
import HabitHeatmap from '../components/HabitHeatmap'
import HabitEditor from '../components/HabitEditor'
import Sheet from '../components/Sheet'
import { listItem, spring } from '../lib/motion'
import { AnimatePresence } from 'framer-motion'

function Ring({ progress, size = 56 }: { progress: number; size?: number }) {
  const sw = 5
  const r = (size - sw) / 2
  const c = 2 * Math.PI * r
  return (
    <svg width={size} height={size} className="-rotate-90">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="rgb(var(--accent))" strokeOpacity={0.18} strokeWidth={sw} />
      <motion.circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke="rgb(var(--accent))"
        strokeWidth={sw}
        strokeLinecap="round"
        strokeDasharray={c}
        initial={false}
        animate={{ strokeDashoffset: c * (1 - progress) }}
        transition={spring}
      />
    </svg>
  )
}

export default function Habits() {
  const { state, deleteHabit, toggleArchiveHabit } = useLife()
  const [editor, setEditor] = useState<{ open: boolean; habit?: Habit }>({ open: false })
  const [detailId, setDetailId] = useState<string | null>(null)

  const today = new Date()
  const active = state.habits.filter((h) => !h.archived)
  const archived = state.habits.filter((h) => h.archived)
  const detail = state.habits.find((h) => h.id === detailId)

  // Today's build-habit completion for the summary ring.
  const todayBuild = active.filter((h) => h.kind === 'build' && isScheduledOn(h, today))
  const remaining = todayBuild.filter((h) => isPendingToday(h, state.habitLogs, today)).length
  const doneCount = todayBuild.length - remaining
  const progress = todayBuild.length ? doneCount / todayBuild.length : 0
  const breakHabits = active.filter((h) => h.kind === 'break')

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
          >
            <AnimatePresence initial={false}>
              {active.map((h) => (
                <motion.div key={h.id} variants={listItem} initial="initial" animate="animate" exit="exit" layout>
                  <HabitRow habit={h} onOpen={() => setDetailId(h.id)} />
                </motion.div>
              ))}
            </AnimatePresence>
          </motion.div>
        </>
      )}

      {archived.length > 0 && (
        <>
          <SectionLabel>Archived</SectionLabel>
          <div className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70">
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

      {/* Detail */}
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
              <div className="flex-1 rounded-card bg-surface p-4 text-center shadow-card">
                <div className="mb-0.5 flex items-center justify-center gap-1">
                  <Flame size={16} className="text-nourish" />
                  <span className="tabular text-title2 text-label">{currentStreak(detail, state.habitLogs, today)}</span>
                </div>
                <div className="text-footnote text-label2">{detail.kind === 'break' ? 'days clean' : 'current streak'}</div>
              </div>
              <div className="flex-1 rounded-card bg-surface p-4 text-center shadow-card">
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
                aria-label="Archive"
                className="grid w-12 place-items-center rounded-card bg-fill text-label2 active:scale-95"
              >
                {detail.archived ? <ArchiveRestore size={18} /> : <Archive size={18} />}
              </button>
              <button
                onClick={() => {
                  if (confirm(`Delete “${detail.name}” and its history?`)) {
                    deleteHabit(detail.id)
                    setDetailId(null)
                  }
                }}
                aria-label="Delete"
                className="grid w-12 place-items-center rounded-card bg-fill text-danger active:scale-95"
              >
                <Trash2 size={18} />
              </button>
            </div>
          </div>
        )}
      </Sheet>
    </div>
  )
}
