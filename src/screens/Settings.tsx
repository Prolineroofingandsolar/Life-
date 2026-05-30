import { useRef } from 'react'
import { ChevronLeft, User, Dumbbell, Timer, Bell, Download, Upload } from 'lucide-react'
import { motion } from 'framer-motion'
import { useLife } from '../lib/store'
import { useTheme } from '../lib/theme'
import type { ThemeMode } from '../lib/theme'
import type { LifeState } from '../lib/types'
import { SectionLabel, ListGroup, ListRow, SegmentedControl, Switch, Stepper } from '../components/ui'

export default function Settings({ onClose }: { onClose: () => void }) {
  const { state, setName, setWorkoutSettings, loadState } = useLife()
  const { mode, setMode } = useTheme()
  const ws = state.workoutSettings
  const fileRef = useRef<HTMLInputElement>(null)

  const exportData = () => {
    const blob = new Blob([JSON.stringify(state, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `life-backup-${new Date().toISOString().slice(0, 10)}.json`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  }

  const handleImport = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (ev) => {
      try {
        const data = JSON.parse(ev.target?.result as string) as LifeState
        if (typeof data !== 'object' || !data.tasks) throw new Error('Invalid')
        loadState(data)
        alert('Data imported successfully.')
      } catch {
        alert('Could not read backup file. Make sure it is a valid Life export.')
      }
    }
    reader.readAsText(file)
    e.target.value = ''
  }

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
            { value: 'auto',  label: 'Automatic' },
            { value: 'light', label: 'Light' },
            { value: 'dark',  label: 'Dark' },
          ]}
        />
      </div>
      <p className="ml-4 mt-2 text-footnote text-label2">Automatic follows your device's appearance setting.</p>

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

      <SectionLabel>Data</SectionLabel>
      <ListGroup>
        <ListRow
          icon={Download}
          iconColor="rgb(var(--accent))"
          title="Export backup"
          subtitle="Save all your data as a JSON file"
          onClick={exportData}
        />
        <ListRow
          icon={Upload}
          iconColor="#30d158"
          title="Import backup"
          subtitle="Restore from a previously exported file"
          onClick={() => fileRef.current?.click()}
        />
      </ListGroup>
      <p className="ml-4 mt-2 text-footnote text-label2">
        Importing replaces all current data. Export first if you want to keep it.
      </p>
      <input ref={fileRef} type="file" accept=".json" className="hidden" onChange={handleImport} />

      <p className="mt-10 text-center text-caption text-label3">Life · v1</p>
    </div>
  )
}
