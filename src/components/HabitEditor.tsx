import { useState } from 'react'
import { motion } from 'framer-motion'
import { useLife } from '../lib/store'
import { HABIT_COLORS, HABIT_EMOJIS } from '../lib/types'
import type { Habit, HabitCadence, HabitKind } from '../lib/types'
import Sheet from './Sheet'
import { SegmentedControl, Switch, Stepper } from './ui'
import { spring } from '../lib/motion'

const WEEK_ORDER = [1, 2, 3, 4, 5, 6, 0] // Mon → Sun (JS getDay)
const WEEK_LETTERS = ['M', 'T', 'W', 'T', 'F', 'S', 'S']

export default function HabitEditor({
  open,
  onClose,
  habit,
}: {
  open: boolean
  onClose: () => void
  habit?: Habit
}) {
  const { addHabit, updateHabit } = useLife()
  const [name, setName] = useState(habit?.name ?? '')
  const [emoji, setEmoji] = useState(habit?.emoji ?? HABIT_EMOJIS[0])
  const [color, setColor] = useState(habit?.color ?? HABIT_COLORS[0])
  const [kind, setKind] = useState<HabitKind>(habit?.kind ?? 'build')
  const [cadence, setCadence] = useState<HabitCadence>(habit?.cadence ?? 'daily')
  const [weekdays, setWeekdays] = useState<number[]>(habit?.weekdays ?? [1, 2, 3, 4, 5])
  const [timesPerWeek, setTimesPerWeek] = useState(habit?.timesPerWeek ?? 3)
  const [hasTarget, setHasTarget] = useState(habit?.target != null)
  const [target, setTarget] = useState(habit?.target ?? 10)
  const [unit, setUnit] = useState(habit?.unit ?? '')

  const toggleDay = (d: number) =>
    setWeekdays((ws) => (ws.includes(d) ? ws.filter((x) => x !== d) : [...ws, d]))

  const save = () => {
    if (!name.trim()) return
    const base: Omit<Habit, 'id' | 'createdAt'> = {
      name: name.trim(),
      emoji,
      color,
      kind,
      cadence: kind === 'break' ? 'daily' : cadence,
      weekdays: kind === 'build' && cadence === 'weekdays' ? weekdays : undefined,
      timesPerWeek: kind === 'build' && cadence === 'weekly' ? timesPerWeek : undefined,
      target: kind === 'build' && hasTarget ? target : undefined,
      unit: kind === 'build' && hasTarget ? unit.trim() || undefined : undefined,
    }
    if (habit) updateHabit(habit.id, base)
    else addHabit(base)
    onClose()
  }

  return (
    <Sheet open={open} onClose={onClose} title={habit ? 'Edit habit' : 'New habit'}>
      <div className="max-h-[64vh] space-y-4 overflow-y-auto no-scrollbar pb-1">
        {/* Name + chosen emoji */}
        <div className="flex items-center gap-3">
          <span
            className="grid h-12 w-12 shrink-0 place-items-center rounded-full text-2xl"
            style={{ background: color + '28' }}
          >
            {emoji}
          </span>
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={kind === 'break' ? 'Habit to quit' : 'Habit to build'}
            aria-label="Habit name"
            maxLength={60}
            className="w-full rounded-card bg-surface px-4 py-3 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
            style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
          />
        </div>

        <SegmentedControl<HabitKind>
          layoutId="habit-kind"
          value={kind}
          onChange={setKind}
          options={[
            { value: 'build', label: 'Build' },
            { value: 'break', label: 'Quit' },
          ]}
        />

        {/* Emoji */}
        <div>
          <div className="mb-1.5 ml-1 text-footnote font-medium text-label2">Icon</div>
          <div className="grid grid-cols-10 gap-1">
            {HABIT_EMOJIS.map((e) => (
              <button
                key={e}
                onClick={() => setEmoji(e)}
                className={`grid aspect-square place-items-center rounded-lg text-lg ${emoji === e ? 'bg-fill ring-2 ring-accent' : ''}`}
              >
                {e}
              </button>
            ))}
          </div>
        </div>

        {/* Colour */}
        <div>
          <div className="mb-1.5 ml-1 text-footnote font-medium text-label2">Colour</div>
          <div className="flex gap-2">
            {HABIT_COLORS.map((c) => (
              <button
                key={c}
                onClick={() => setColor(c)}
                aria-label={`Colour ${c}`}
                aria-pressed={color === c}
                className={`h-8 w-8 rounded-full ${color === c ? 'ring-2 ring-offset-2 ring-offset-grouped' : ''}`}
                style={{ background: c, boxShadow: color === c ? `0 0 0 2px ${c}` : undefined }}
              />
            ))}
          </div>
        </div>

        {/* Build-only scheduling */}
        {kind === 'build' && (
          <>
            <div>
              <div className="mb-1.5 ml-1 text-footnote font-medium text-label2">How often</div>
              <SegmentedControl<HabitCadence>
                layoutId="habit-cadence"
                value={cadence}
                onChange={setCadence}
                options={[
                  { value: 'daily', label: 'Daily' },
                  { value: 'weekdays', label: 'Days' },
                  { value: 'weekly', label: 'Weekly' },
                ]}
              />
            </div>

            {cadence === 'weekdays' && (
              <div className="flex justify-between">
                {WEEK_ORDER.map((d, i) => {
                  const on = weekdays.includes(d)
                  return (
                    <button
                      key={d}
                      onClick={() => toggleDay(d)}
                      className={`grid h-10 w-10 place-items-center rounded-full text-subhead font-semibold ${on ? 'text-white' : 'bg-fill text-label2'}`}
                      style={on ? { background: color } : undefined}
                    >
                      {WEEK_LETTERS[i]}
                    </button>
                  )
                })}
              </div>
            )}

            {cadence === 'weekly' && (
              <div className="flex items-center justify-between rounded-card bg-surface px-4 py-3 shadow-card">
                <span className="text-body text-label">Times per week</span>
                <div className="flex items-center gap-3">
                  <span className="tabular w-6 text-center text-body text-label2">{timesPerWeek}</span>
                  <Stepper value={timesPerWeek} min={1} max={7} onChange={setTimesPerWeek} />
                </div>
              </div>
            )}

            <div className="rounded-card bg-surface px-4 py-3 shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
              <div className="flex items-center justify-between">
                <span className="text-body text-label">Daily target</span>
                <Switch checked={hasTarget} onChange={setHasTarget} label="Daily target" />
              </div>
              {hasTarget && (
                <div className="mt-3 flex items-center gap-3 border-t border-separator/70 pt-3">
                  <Stepper value={target} min={1} onChange={setTarget} />
                  <span className="tabular w-8 text-center text-body text-label">{target}</span>
                  <input
                    value={unit}
                    onChange={(e) => setUnit(e.target.value)}
                    placeholder="unit (e.g. pages)"
                    aria-label="Unit"
                    maxLength={20}
                    className="min-w-0 flex-1 rounded-lg bg-fill px-3 py-2 text-body text-label placeholder:text-label3 focus:outline-none"
                  />
                </div>
              )}
            </div>
          </>
        )}

        {kind === 'break' && (
          <p className="ml-1 text-footnote text-label2">
            You’ll track days clean. Tap “Slipped” on a day it happens — your streak resets and starts again.
          </p>
        )}
      </div>

      <motion.button
        whileTap={{ scale: 0.97 }}
        transition={spring}
        onClick={save}
        disabled={!name.trim()}
        className="mt-4 w-full rounded-card bg-accent py-3.5 text-headline text-white disabled:opacity-40"
      >
        {habit ? 'Save changes' : 'Add habit'}
      </motion.button>
    </Sheet>
  )
}
