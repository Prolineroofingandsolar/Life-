import { motion } from 'framer-motion'
import { Check, Flame, Minus, Plus, ShieldX } from 'lucide-react'
import { useLife } from '../lib/store'
import { dayKey } from '../lib/date'
import {
  amountOn,
  cadenceLabel,
  currentStreak,
  isSuccessOn,
  progressOn,
  targetFor,
  weekDoneCount,
} from '../lib/habits'
import type { Habit } from '../lib/types'
import { spring } from '../lib/motion'

function Ring({ progress, color, size = 44 }: { progress: number; color: string; size?: number }) {
  const sw = 3
  const r = (size - sw) / 2
  const c = 2 * Math.PI * r
  return (
    <svg width={size} height={size} className="-rotate-90">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeOpacity={0.2} strokeWidth={sw} />
      <motion.circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke={color}
        strokeWidth={sw}
        strokeLinecap="round"
        strokeDasharray={c}
        initial={false}
        animate={{ strokeDashoffset: c * (1 - Math.max(0, Math.min(1, progress))) }}
        transition={spring}
      />
    </svg>
  )
}

export default function HabitRow({ habit, onOpen }: { habit: Habit; onOpen?: () => void }) {
  const { logHabit, toggleHabitToday, incHabitToday, slipHabitToday } = useLife()
  const { state } = useLife()
  const logs = state.habitLogs
  const today = new Date()
  const key = dayKey(today)
  const amt = amountOn(logs, habit.id, key)
  const streak = currentStreak(habit, logs, today)

  const isBreak = habit.kind === 'break'
  const isQuant = !isBreak && habit.target != null
  const isWeekly = !isBreak && habit.cadence === 'weekly'
  const doneToday = !isBreak && (isWeekly ? weekDoneCount(habit, logs, today) >= (habit.timesPerWeek ?? 1) : isSuccessOn(habit, logs, today))
  const slippedToday = isBreak && amt > 0

  const ringProgress = isBreak ? 1 : isQuant ? progressOn(habit, logs, today) : doneToday ? 1 : 0

  const subtitle = isBreak
    ? `${streak} day${streak === 1 ? '' : 's'} clean`
    : isQuant
      ? `${amt}/${targetFor(habit)} ${habit.unit ?? ''}`.trim()
      : isWeekly
        ? `${weekDoneCount(habit, logs, today)}/${habit.timesPerWeek} this week`
        : cadenceLabel(habit)

  return (
    <div className="flex items-center gap-3 px-4 py-3">
      <button onClick={onOpen} className="relative grid place-items-center" aria-label={habit.name}>
        <Ring progress={ringProgress} color={isBreak ? (slippedToday ? '#ff375f' : habit.color) : habit.color} />
        <span className="absolute text-lg">{habit.emoji}</span>
      </button>

      <button onClick={onOpen} className="min-w-0 flex-1 text-left">
        <div className={`truncate text-body ${doneToday ? 'text-label2' : 'text-label'}`}>{habit.name}</div>
        <div className="flex items-center gap-1 text-footnote text-label2">
          {streak > 0 && <Flame size={12} className="text-nourish" />}
          <span className="truncate">{subtitle}</span>
        </div>
      </button>

      {/* Right control */}
      {isBreak ? (
        slippedToday ? (
          <button
            onClick={() => logHabit(habit.id, key, 0)}
            className="rounded-full bg-danger/15 px-3 py-1.5 text-footnote font-medium text-danger active:scale-95"
          >
            Slipped · undo
          </button>
        ) : (
          <motion.button
            whileTap={{ scale: 0.92 }}
            onClick={() => slipHabitToday(habit.id)}
            className="flex items-center gap-1 rounded-full bg-fill px-3 py-1.5 text-footnote font-medium text-label2 active:scale-95"
          >
            <ShieldX size={14} /> Slipped
          </motion.button>
        )
      ) : isQuant ? (
        <div className="flex items-center gap-1.5">
          <motion.button
            whileTap={{ scale: 0.88 }}
            onClick={() => incHabitToday(habit.id, -1)}
            aria-label="decrease"
            className="grid h-8 w-8 place-items-center rounded-full bg-fill text-label2"
          >
            <Minus size={16} />
          </motion.button>
          <motion.button
            whileTap={{ scale: 0.88 }}
            onClick={() => incHabitToday(habit.id, 1)}
            aria-label="increase"
            className="grid h-8 w-8 place-items-center rounded-full text-white"
            style={{ background: habit.color }}
          >
            <Plus size={16} />
          </motion.button>
        </div>
      ) : (
        <motion.button
          whileTap={{ scale: 0.85 }}
          transition={spring}
          onClick={() => toggleHabitToday(habit.id)}
          aria-label={doneToday ? 'Mark not done' : 'Mark done'}
          className="grid h-9 w-9 place-items-center rounded-full border-2"
          style={{
            borderColor: habit.color,
            background: doneToday ? habit.color : 'transparent',
            color: doneToday ? '#fff' : 'transparent',
          }}
        >
          <Check size={18} strokeWidth={3} />
        </motion.button>
      )}
    </div>
  )
}
