import { useEffect, useRef } from 'react'
import { motion } from 'framer-motion'
import { Droplets, UtensilsCrossed, Wind, Plus, Settings, ChevronRight, Check } from 'lucide-react'
import { useLife } from '../lib/store'
import { greeting, longDate } from '../lib/date'
import { notify, notificationPermission } from '../lib/notifications'
import FocusTimer from '../components/FocusTimer'
import ActivityRings from '../components/ActivityRings'
import { Card, PressableCard, SectionLabel, IconButton } from '../components/ui'
import HabitRow from '../components/HabitRow'
import { isScheduledOn } from '../lib/habits'
import { spring } from '../lib/motion'
import { CATEGORY_LABEL } from '../lib/types'

const RING_META = [
  { key: 'hydrate', label: 'Hydrate', color: '#32ade6', icon: Droplets },
  { key: 'nourish', label: 'Nourish', color: '#ff9f0a', icon: UtensilsCrossed },
  { key: 'move', label: 'Move', color: '#30d158', icon: Wind },
] as const

export default function Today({ onOpenSettings }: { onOpenSettings: () => void }) {
  const { state, today, addWater, addMeal, markBreak } = useLife()
  const cs = state.careSettings

  const openTasks = state.tasks.filter((t) => !t.done)
  const nextTask = openTasks[0]

  // Habits scheduled for today (build habits due today + all break habits).
  const todayHabits = state.habits.filter((h) => !h.archived && isScheduledOn(h, new Date()))

  // Move ring: full once a break has been taken in the last `breakIntervalMin`.
  const sinceBreakMin = today.lastBreakAt ? (Date.now() - today.lastBreakAt) / 60_000 : Infinity
  const moveValue = sinceBreakMin <= cs.breakIntervalMin ? 1 : 0

  const rings = [
    { value: today.water, goal: cs.waterGoal, color: '#32ade6' },
    { value: today.meals, goal: cs.mealsGoal, color: '#ff9f0a' },
    { value: moveValue, goal: 1, color: '#30d158' },
  ]

  const counts: Record<string, string> = {
    hydrate: `${today.water}/${cs.waterGoal}`,
    nourish: `${today.meals}/${cs.mealsGoal}`,
    move: moveValue ? 'Done' : 'Due',
  }
  const onAdd: Record<string, () => void> = {
    hydrate: () => addWater(1),
    nourish: addMeal,
    move: markBreak,
  }

  // In-app water reminder loop (background delivery needs the installed PWA).
  const lastWaterNudge = useRef<number>(Date.now())
  useEffect(() => {
    if (!cs.remindersEnabled || notificationPermission() !== 'granted') return
    const id = window.setInterval(() => {
      const due = Date.now() - lastWaterNudge.current > cs.waterIntervalMin * 60_000
      if (due && today.water < cs.waterGoal) {
        notify('Time for water', 'Quick sip — then back to it.')
        lastWaterNudge.current = Date.now()
      }
    }, 30_000)
    return () => window.clearInterval(id)
  }, [cs.remindersEnabled, cs.waterIntervalMin, cs.waterGoal, today.water])

  return (
    <div>
      {/* Header */}
      <div className="material safe-top sticky top-0 z-20 -mx-4 flex h-11 items-center justify-between px-4">
        <span className="text-footnote font-medium text-label2">{longDate()}</span>
        <IconButton icon={Settings} label="Settings" onClick={onOpenSettings} />
      </div>
      <div className="mb-6 mt-1">
        <p className="text-subhead text-label2">{greeting()}</p>
        <h1 className="text-largetitle">{state.name ? state.name : 'Today'}</h1>
      </div>

      {/* Activity rings hero */}
      <Card className="mb-1 p-6">
        <div className="flex items-center gap-5">
          <ActivityRings rings={rings} size={150} />
          <div className="flex-1 space-y-2.5">
            {RING_META.map((m) => {
              const done = m.key === 'move' ? moveValue === 1 : false
              return (
                <motion.button
                  key={m.key}
                  whileTap={{ scale: 0.97 }}
                  transition={spring}
                  onClick={onAdd[m.key]}
                  className="flex w-full items-center gap-2.5"
                >
                  <m.icon size={18} strokeWidth={2.4} style={{ color: m.color }} />
                  <div className="flex-1 text-left">
                    <div className="text-subhead font-medium text-label">{m.label}</div>
                    <div className="tabular text-footnote text-label2">{counts[m.key]}</div>
                  </div>
                  <span
                    className="grid h-7 w-7 place-items-center rounded-full text-white"
                    style={{ background: m.color }}
                  >
                    {done ? <Check size={15} strokeWidth={3} /> : <Plus size={15} strokeWidth={3} />}
                  </span>
                </motion.button>
              )
            })}
          </div>
        </div>
      </Card>

      {todayHabits.length > 0 && (
        <>
          <SectionLabel>Habits</SectionLabel>
          <div className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70">
            {todayHabits.map((h) => (
              <HabitRow key={h.id} habit={h} />
            ))}
          </div>
        </>
      )}

      <SectionLabel>Focus</SectionLabel>
      <Card className="py-7">
        <FocusTimer onBreak={markBreak} />
      </Card>

      <SectionLabel>Up next</SectionLabel>
      {nextTask ? (
        <PressableCard className="flex items-center gap-3 px-4 py-3.5">
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-fill text-footnote font-semibold text-label2">
            {CATEGORY_LABEL[nextTask.category].slice(0, 1)}
          </span>
          <div className="min-w-0 flex-1">
            <div className="truncate text-body text-label">{nextTask.title}</div>
            <div className="text-footnote text-label2">
              {openTasks.length} task{openTasks.length === 1 ? '' : 's'} left today
            </div>
          </div>
          <ChevronRight size={18} className="text-label3" />
        </PressableCard>
      ) : (
        <Card className="px-4 py-5 text-center text-subhead text-label2">All caught up — nothing pending.</Card>
      )}
    </div>
  )
}
