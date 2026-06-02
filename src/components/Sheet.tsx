import { useEffect, useRef, useState, type ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ease } from '../lib/motion'

/**
 * iOS-style bottom sheet: slides up over a dimmed, blurred backdrop and can be
 * flung/dragged down to dismiss.
 *
 * iOS-specific fixes applied here:
 * 1. Visual Viewport API detects the software keyboard height so the sheet
 *    slides up above the keyboard when an input is focused.
 * 2. Non-passive touchmove on the backdrop prevents the background page from
 *    scrolling while the sheet is open (a common WKWebView/Capacitor leak).
 * 3. Bottom padding correctly adds safe-area-inset-bottom on top of the fixed
 *    padding so content is never hidden behind the home indicator.
 * 4. max-height cap prevents the sheet from extending off the top of the screen.
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
  const [kbHeight, setKbHeight] = useState(0)
  const backdropRef = useRef<HTMLDivElement>(null)

  // Track keyboard height via Visual Viewport API.
  // In Capacitor's WKWebView the layout viewport does NOT shrink when the
  // keyboard appears, so we must detect it ourselves and push the sheet up.
  useEffect(() => {
    if (!open) {
      setKbHeight(0)
      return
    }
    const vv = window.visualViewport
    if (!vv) return
    const update = () => {
      const h = Math.max(0, window.innerHeight - vv.height - vv.offsetTop)
      setKbHeight(h)
    }
    vv.addEventListener('resize', update)
    vv.addEventListener('scroll', update)
    update()
    return () => {
      vv.removeEventListener('resize', update)
      vv.removeEventListener('scroll', update)
    }
  }, [open])

  // Prevent the backdrop from letting touch-scroll leak to the page behind it.
  // Must be a non-passive listener so that preventDefault() is honoured by iOS.
  useEffect(() => {
    if (!open) return
    const el = backdropRef.current
    if (!el) return
    const block = (e: TouchEvent) => e.preventDefault()
    el.addEventListener('touchmove', block, { passive: false })
    return () => el.removeEventListener('touchmove', block)
  }, [open])

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 flex items-end justify-center"
          // paddingBottom shifts the sheet up by exactly the keyboard height so
          // inputs are never obscured on iPhone.
          style={{ paddingBottom: kbHeight }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.25 }}
        >
          <div
            ref={backdropRef}
            className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            onClick={onClose}
            aria-hidden="true"
          />
          <motion.div
            role="dialog"
            aria-modal="true"
            aria-label={title ?? 'Sheet'}
            className="relative w-full max-w-app rounded-t-sheet bg-grouped px-4 pt-2 shadow-sheet"
            style={{
              // When keyboard is visible, skip the safe-area inset (we're
              // floating above the keyboard, not near the home indicator).
              paddingBottom: kbHeight > 0
                ? '1.5rem'
                : 'calc(1.5rem + env(safe-area-inset-bottom))',
              // Cap height so the sheet never extends above visible content.
              maxHeight: kbHeight > 0
                ? `calc(${window.innerHeight - kbHeight}px - 4rem)`
                : '85vh',
              overflowY: 'auto',
              // Prevent scroll momentum from jumping to the page behind the sheet.
              overscrollBehavior: 'contain',
            }}
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
