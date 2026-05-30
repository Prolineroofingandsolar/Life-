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
 * Active rings receive a soft glow via SVG filter.
 */
export default function ActivityRings({ rings, size = 200 }: { rings: RingData[]; size?: number }) {
  const stroke = size * 0.092
  const gap = stroke * 0.55
  const center = size / 2

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="-rotate-90">
      <defs>
        {/* Soft glow applied to active progress arcs */}
        <filter id="ar-glow" x="-40%" y="-40%" width="180%" height="180%">
          <feGaussianBlur in="SourceGraphic" stdDeviation="2.5" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
        {/* Radial gradient for the centre area — adds depth in dark mode */}
        <radialGradient id="ar-center-depth" cx="50%" cy="50%" r="45%">
          <stop offset="0%" stopColor="white" stopOpacity="0.05" />
          <stop offset="100%" stopColor="white" stopOpacity="0" />
        </radialGradient>
      </defs>

      {/* Subtle centre depth overlay */}
      <circle cx={center} cy={center} r={center * 0.62} fill="url(#ar-center-depth)" />

      {rings.map((ring, i) => {
        const r = center - stroke / 2 - i * (stroke + gap)
        const c = 2 * Math.PI * r
        const pct = Math.max(0, Math.min(1, ring.goal > 0 ? ring.value / ring.goal : 0))
        const hasProgress = pct > 0.01

        return (
          <g key={i}>
            {/* Track ring */}
            <circle
              cx={center}
              cy={center}
              r={r}
              fill="none"
              stroke={ring.color}
              strokeOpacity={0.14}
              strokeWidth={stroke}
            />
            {/* Progress arc with glow when active */}
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
              filter={hasProgress ? 'url(#ar-glow)' : undefined}
            />
          </g>
        )
      })}
    </svg>
  )
}
