export const MUSCLE_COLOR: Record<string, string> = {
  Chest:        '#ff6b35',
  Back:         '#30d158',
  Legs:         '#32ade6',
  Glutes:       '#ff375f',
  Shoulders:    '#bf5af2',
  Biceps:       '#ff9f0a',
  Triceps:      '#ff453a',
  Core:         '#64d2ff',
  Traps:        '#5e5ce6',
  'Full Body':  '#94a3b8',
  Cardio:       '#34c759',
  Arms:         '#ff9f0a',
}

export function muscleColor(m: string): string {
  return MUSCLE_COLOR[m] ?? '#8888aa'
}

export function MuscleTag({ muscle }: { muscle: string }) {
  const color = muscleColor(muscle)
  return (
    <span
      className="rounded-full px-2 py-0.5 text-caption font-medium"
      style={{ background: color + '22', color }}
    >
      {muscle}
    </span>
  )
}
