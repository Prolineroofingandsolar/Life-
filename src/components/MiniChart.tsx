/** Tiny inline SVG bar chart — no chart library. */
export default function MiniChart({
  data,
  height = 64,
  color = 'rgb(var(--accent))',
}: {
  data: { label?: string; value: number }[]
  height?: number
  color?: string
}) {
  if (data.length === 0) {
    return <div className="py-6 text-center text-footnote text-label3">No data yet</div>
  }
  const max = Math.max(...data.map((d) => d.value), 1)
  const gap = 6
  const w = 280
  const barW = (w - gap * (data.length - 1)) / data.length

  return (
    <svg viewBox={`0 0 ${w} ${height}`} className="w-full" preserveAspectRatio="none">
      {data.map((d, i) => {
        const h = Math.max(2, (d.value / max) * (height - 4))
        return (
          <rect
            key={i}
            x={i * (barW + gap)}
            y={height - h}
            width={barW}
            height={h}
            rx={Math.min(4, barW / 2)}
            fill={color}
            opacity={i === data.length - 1 ? 1 : 0.45}
          />
        )
      })}
    </svg>
  )
}
