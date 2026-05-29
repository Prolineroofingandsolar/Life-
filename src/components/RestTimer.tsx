import { useEffect, useRef, useState } from 'react'
import { motion } from 'framer-motion'
import { Plus, X } from 'lucide-react'
import { notify } from '../lib/notifications'
import { spring } from '../lib/motion'

const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.max(0, s) % 60).padStart(2, '0')}`

/**
 * Sticky rest countdown shown after a set is completed during a workout.
 * Auto-dismisses (and nudges) when it reaches zero. Mount with a unique `key`
 * per rest so it restarts cleanly.
 */
export default function RestTimer({ seconds, onClose }: { seconds: number; onClose: () => void }) {
  const [total, setTotal] = useState(seconds)
  const [remaining, setRemaining] = useState(seconds)
  const fired = useRef(false)

  useEffect(() => {
    const id = window.setInterval(() => setRemaining((r) => r - 1), 1000)
    return () => window.clearInterval(id)
  }, [])

  useEffect(() => {
    if (remaining <= 0 && !fired.current) {
      fired.current = true
      notify('Rest over', 'Next set — let’s go.')
      onClose()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [remaining])

  const pct = Math.max(0, Math.min(1, remaining / total))

  return (
    <motion.div
      initial={{ y: 80, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      exit={{ y: 80, opacity: 0 }}
      transition={spring}
      className="material safe-bottom fixed inset-x-0 bottom-0 z-40 mx-auto max-w-app border-t border-separator/60 px-4 pb-2 pt-3"
    >
      <div className="flex items-center gap-3">
        <span className="text-footnote font-medium uppercase tracking-wide text-label2">Rest</span>
        <span className="tabular text-title3 text-label">{fmt(remaining)}</span>
        <div className="flex-1" />
        <motion.button
          whileTap={{ scale: 0.92 }}
          onClick={() => {
            setTotal((t) => t + 15)
            setRemaining((r) => r + 15)
          }}
          className="flex items-center gap-1 rounded-full bg-fill px-3 py-1.5 text-subhead font-medium text-label"
        >
          <Plus size={15} /> 15s
        </motion.button>
        <motion.button
          whileTap={{ scale: 0.92 }}
          onClick={onClose}
          className="flex items-center gap-1 rounded-full bg-accent px-3 py-1.5 text-subhead font-medium text-white"
        >
          <X size={15} /> Skip
        </motion.button>
      </div>
      <div className="mt-2 h-1 w-full overflow-hidden rounded-full bg-fill">
        <div className="h-full rounded-full bg-accent transition-[width] duration-1000 ease-linear" style={{ width: `${pct * 100}%` }} />
      </div>
    </motion.div>
  )
}
