import { useEffect, useRef, useState } from 'react'
import { motion } from 'framer-motion'
import { Pause, Play, RotateCcw } from 'lucide-react'
import { notify } from '../lib/notifications'
import { spring } from '../lib/motion'
import { SegmentedControl } from './ui'

type Phase = 'focus' | 'break'

/**
 * A focus timer built for hyperfocus: when a block ends it actively nudges you
 * to stand up, drink, and breathe — the thing ADHD brains skip.
 */
export default function FocusTimer({ onBreak }: { onBreak?: () => void }) {
  const [focusMin, setFocusMin] = useState(25)
  const breakMin = 5
  const [phase, setPhase] = useState<Phase>('focus')
  const [remaining, setRemaining] = useState(focusMin * 60)
  const [running, setRunning] = useState(false)
  const tick = useRef<number | null>(null)

  useEffect(() => {
    if (!running && phase === 'focus') setRemaining(focusMin * 60)
  }, [focusMin, running, phase])

  useEffect(() => {
    if (!running) return
    tick.current = window.setInterval(() => setRemaining((r) => r - 1), 1000)
    return () => {
      if (tick.current) window.clearInterval(tick.current)
    }
  }, [running])

  useEffect(() => {
    if (remaining > 0) return
    if (phase === 'focus') {
      notify('Focus block done', 'Stand up, drink some water, look away from the screen.')
      onBreak?.()
      setPhase('break')
      setRemaining(breakMin * 60)
    } else {
      notify('Break over', 'Ready for another round?')
      setPhase('focus')
      setRemaining(focusMin * 60)
      setRunning(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [remaining])

  const total = (phase === 'focus' ? focusMin : breakMin) * 60
  const pct = Math.max(0, Math.min(1, remaining / total))
  const mm = String(Math.floor(Math.max(0, remaining) / 60)).padStart(2, '0')
  const ss = String(Math.max(0, remaining) % 60).padStart(2, '0')
  const color = phase === 'focus' ? 'rgb(var(--accent))' : '#30d158'

  const R = 88
  const C = 2 * Math.PI * R
  const reset = () => {
    setRunning(false)
    setPhase('focus')
    setRemaining(focusMin * 60)
  }

  return (
    <div className="flex flex-col items-center">
      <div className="relative h-56 w-56">
        <svg
          viewBox="0 0 200 200"
          className={`h-full w-full -rotate-90 ${
            running ? 'dark:[filter:drop-shadow(0_0_14px_rgb(var(--accent)/0.45))]' : ''
          }`}
        >
          <circle cx="100" cy="100" r={R} fill="none" stroke="rgb(var(--separator))" strokeOpacity={0.5} strokeWidth="10" />
          <motion.circle
            cx="100"
            cy="100"
            r={R}
            fill="none"
            stroke={color}
            strokeWidth="10"
            strokeLinecap="round"
            strokeDasharray={C}
            initial={false}
            animate={{ strokeDashoffset: C * (1 - pct) }}
            transition={{ duration: running ? 1 : 0.4, ease: 'linear' }}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-caption font-medium uppercase tracking-widest text-label2">
            {phase === 'focus' ? 'Focus' : 'Break'}
          </span>
          <span className="tabular text-[44px] font-semibold leading-none text-label">
            {mm}:{ss}
          </span>
        </div>
      </div>

      {phase === 'focus' && !running && (
        <div className="mt-5 w-44">
          <SegmentedControl<string>
            layoutId="focus-preset"
            value={String(focusMin)}
            onChange={(v) => setFocusMin(Number(v))}
            options={[
              { value: '15', label: '15' },
              { value: '25', label: '25' },
              { value: '50', label: '50' },
            ]}
          />
        </div>
      )}

      <div className="mt-6 flex items-center gap-3">
        <motion.button
          whileTap={{ scale: 0.94 }}
          transition={spring}
          onClick={() => setRunning((r) => !r)}
          className="flex items-center gap-2 rounded-full bg-accent px-8 py-3.5 text-headline text-white"
        >
          {running ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" />}
          {running ? 'Pause' : remaining < total ? 'Resume' : 'Start'}
        </motion.button>
        <motion.button
          whileTap={{ scale: 0.94 }}
          transition={spring}
          onClick={reset}
          aria-label="Reset timer"
          className="grid h-[52px] w-[52px] place-items-center rounded-full bg-fill text-label2"
        >
          <RotateCcw size={20} />
        </motion.button>
      </div>
    </div>
  )
}
