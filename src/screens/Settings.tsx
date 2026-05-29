import { ChevronLeft, User, Dumbbell, Timer, Bell } from 'lucide-react'
import { motion } from 'framer-motion'
import { useLife } from '../lib/store'
import { useTheme } from '../lib/theme'
import type { ThemeMode } from '../lib/theme'
import { SectionLabel, ListGroup, ListRow, SegmentedControl, Switch, Stepper } from '../components/ui'

export default function Settings({ onClose }: { onClose: () => void }) {
  const { state, setName, setWorkoutSettings } = useLife()
  const { mode, setMode } = useTheme()
  const ws = state.workoutSettings

  return (
    <div>
      <div className="material safe-top sticky top-0 z-20 -mx-4 flex h-11 items-center px-2">
        <motion.button
          whileTap={{ scale: 0.94 }}
          onClick={onClose}
          className="flex items-center gap-0.5 px-2 text-body text-accent"
        >
          <ChevronLeft size={22} />
          Today
        </motion.button>
        <span className="absolute left-1/2 -translate-x-1/2 text-headline">Settings</span>
      </div>

      <h1 className="mb-5 mt-1 text-largetitle">Settings</h1>

      <SectionLabel>Appearance</SectionLabel>
      <div className="rounded-card bg-surface p-3 shadow-card">
        <SegmentedControl<ThemeMode>
          layoutId="theme-mode"
          value={mode}
          onChange={setMode}
          options={[
            { value: 'auto', label: 'Automatic' },
            { value: 'light', label: 'Light' },
            { value: 'dark', label: 'Dark' },
          ]}
        />
      </div>
      <p className="ml-4 mt-2 text-footnote text-label2">Automatic follows your device’s appearance setting.</p>

      <SectionLabel>You</SectionLabel>
      <ListGroup>
        <ListRow
          icon={User}
          iconColor="rgb(var(--accent))"
          title={
            <input
              value={state.name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Your name"
              className="w-full bg-transparent text-body text-label placeholder:text-label3 focus:outline-none"
            />
          }
        />
      </ListGroup>
      <p className="ml-4 mt-2 text-footnote text-label2">Used for your greeting on the Today screen.</p>

      <SectionLabel>Workout</SectionLabel>
      <ListGroup>
        <ListRow
          icon={Dumbbell}
          iconColor="#30d158"
          title="Units"
          trailing={
            <div className="w-32">
              <SegmentedControl<'kg' | 'lb'>
                layoutId="unit"
                value={ws.unit}
                onChange={(v) => setWorkoutSettings({ unit: v })}
                options={[
                  { value: 'kg', label: 'kg' },
                  { value: 'lb', label: 'lb' },
                ]}
              />
            </div>
          }
        />
        <ListRow
          icon={Timer}
          iconColor="rgb(var(--accent))"
          title="Default rest"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-12 text-right text-body text-label2">{ws.defaultRestSec}s</span>
              <Stepper value={ws.defaultRestSec} step={15} min={0} onChange={(v) => setWorkoutSettings({ defaultRestSec: v })} />
            </div>
          }
        />
        <ListRow
          icon={Bell}
          iconColor="#ff9f0a"
          title="Auto rest timer"
          subtitle="Start a countdown after each set"
          trailing={<Switch checked={ws.restTimerEnabled} onChange={(v) => setWorkoutSettings({ restTimerEnabled: v })} />}
        />
      </ListGroup>

      <p className="mt-10 text-center text-caption text-label3">Life · v1</p>
    </div>
  )
}
