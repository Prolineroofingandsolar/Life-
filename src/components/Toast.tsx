import { useEffect } from 'react'
import { motion } from 'framer-motion'
import { spring } from '../lib/motion'

interface ToastProps {
  message: string
  undoLabel?: string
  onUndo?: () => void
  onDismiss: () => void
}

/** Bottom notification with optional Undo. Auto-dismisses after 4 seconds. */
export default function Toast({ message, undoLabel = 'Undo', onUndo, onDismiss }: ToastProps) {
  useEffect(() => {
    const t = window.setTimeout(onDismiss, 4000)
    return () => clearTimeout(t)
  }, [onDismiss])

  return (
    <motion.div
      initial={{ opacity: 0, y: 24, scale: 0.96 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: 16, scale: 0.97 }}
      transition={spring}
      className="fixed inset-x-4 bottom-[88px] z-50 mx-auto max-w-app"
    >
      <div
        className="flex items-center gap-3 rounded-xl2 px-4 py-3.5"
        style={{
          background: 'rgb(var(--surface-2))',
          boxShadow: '0 4px 32px rgb(0 0 0 / 0.22), 0 0 0 0.5px rgb(var(--separator) / 0.6)',
        }}
      >
        <span className="flex-1 text-subhead text-label">{message}</span>
        {onUndo && (
          <button
            onClick={() => { onUndo(); onDismiss() }}
            className="text-subhead font-semibold text-accent"
          >
            {undoLabel}
          </button>
        )}
      </div>
    </motion.div>
  )
}
