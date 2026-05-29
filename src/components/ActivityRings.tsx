import { motion } from 'framer-motion'
import { ease } from '../lib/motion'

export interface RingData {
  value: number
  goal: number
  color: string
}

/**
 * Concentric progress rings in the style of Apple's Activity app.
 * `rings[0]` is the outermost. Each animates to its fill on change.
 */
export default function ActivityRings({ rings, size = 200 }: { rings: RingData[]; size?: number }) {
  const stroke = size * 0.092
  const gap = stroke * 0.55
  const center = size / 2

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90">
      {rings.map((ring, i) => {
        const r = center - stroke / 2 - i * (stroke + gap)
        const c = 2 * Math.PI * r
        const pct = Math.max(0, Math.min(1, ring.goal > 0 ? ring.value / ring.goal : 0))
        return (
          <g key={i}>
            <circle cx={center} cy={center} r={r} fill="none" stroke={ring.color} strokeOpacity={0.18} strokeWidth={stroke} />
            <motion.circle
              cx={center}
              cy={center}
              r={r}
              fill="none"
              stroke={ring.color}
              strokeWidth={stroke}
              strokeLinecap="round"
              strokeDasharray={c}
              initial={false}
              animate={{ strokeDashoffset: c * (1 - pct) }}
              transition={{ duration: 0.9, ease }}
            />
          </g>
        )
      })}
    </svg>
  )
}
