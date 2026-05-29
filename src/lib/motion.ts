import { useReducedMotion } from 'framer-motion'
import type { Transition, Variants } from 'framer-motion'

/** Apple-like spring — quick, lightly damped, no overshoot wobble. */
export const spring: Transition = { type: 'spring', stiffness: 420, damping: 32, mass: 0.9 }
export const softSpring: Transition = { type: 'spring', stiffness: 260, damping: 26 }

/** Standard iOS easing curve for non-spring transitions. */
export const ease = [0.32, 0.72, 0, 1] as const

/** Tap/press feedback for buttons & cards. */
export const pressable = {
  whileTap: { scale: 0.96 },
  transition: spring,
}

/** Fade-through used for switching tabs. */
export const pageVariants: Variants = {
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -8 },
}

/** Staggered list container + item. */
export const listContainer: Variants = {
  animate: { transition: { staggerChildren: 0.04 } },
}
export const listItem: Variants = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0, transition: softSpring },
  exit: { opacity: 0, height: 0, marginBottom: 0, transition: { duration: 0.2 } },
}

export { useReducedMotion }
