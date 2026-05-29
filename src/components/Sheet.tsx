import type { ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ease } from '../lib/motion'

/**
 * iOS-style bottom sheet: slides up over a dimmed, blurred backdrop and can be
 * flung/dragged down to dismiss.
 */
export default function Sheet({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean
  onClose: () => void
  title?: string
  children: ReactNode
}) {
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 flex items-end justify-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.25 }}
        >
          <div
            className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            onClick={onClose}
            aria-hidden
          />
          <motion.div
            className="safe-bottom relative w-full max-w-app rounded-t-sheet bg-grouped px-4 pb-6 pt-2 shadow-sheet"
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ duration: 0.34, ease }}
            drag="y"
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0, bottom: 0.6 }}
            onDragEnd={(_, info) => {
              if (info.offset.y > 120 || info.velocity.y > 700) onClose()
            }}
          >
            <div className="mx-auto mb-3 h-1.5 w-10 rounded-full bg-label3/60" />
            {title && <h2 className="mb-3 px-1 text-title3 text-label">{title}</h2>}
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
