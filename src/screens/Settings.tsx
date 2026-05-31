import { useRef, useState } from 'react'
import { ChevronLeft, User, Dumbbell, Timer, Bell, Download, Upload } from 'lucide-react'
import { AnimatePresence, motion } from 'framer-motion'
import { useLife } from '../lib/store'
import { useTheme } from '../lib/theme'
import type { ThemeMode } from '../lib/theme'
import type { LifeState } from '../lib/types'
import { SectionLabel, ListGroup, ListRow, SegmentedControl, Switch, Stepper } from '../components/ui'
import Toast from '../components/Toast'

export default function Settings({ onClose }: { onClose: () => void }) {
  const { state, setName, setWorkoutSettings, loadState } = useLife()
  const { mode, setMode } = useTheme()
  const ws = state.workoutSettings
  const fileRef = useRef<HTMLInputElement>(null)
  const [toast, setToast] = useState<string | null>(null)

  const showToast = (msg: string) => {
    setToast(msg)
  }

  const exportData = () => {
    try {
      const blob = new Blob([JSON.stringify(state, null, 2)], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `life-backup-${new Date().toISOString().slice(0, 10)}.json`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
      showToast('Backup exported successfully')
    } catch {
      showToast('Export failed — please try again')
    }
  }

  const handleImport = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (file.size > 10 * 1024 * 1024) {
      showToast('File too large — max 10 MB')
      e.target.value = ''
      return
    }
    const reader = new FileReader()
    reader.onload = (ev) => {
      try {
        const data = JSON.parse(ev.target?.result as string) as LifeState
        if (typeof data !== 'object' || data === null || !Array.isArray(data.tasks)) {
          throw new Error('Invalid backup format')
        }
        loadState(data)
        showToast('Data imported successfully')
      } catch {
        showToast('Could not read file — make sure it is a valid Life backup')
      }
    }
    reader.onerror = () => showToast('Could not read file')
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
          aria-label="Back to Today"
        >
          <ChevronLeft size={22} />
          Today
        </motion.button>
        <span className="absolute left-1/2 -translate-x-1/2 text-headline" aria-hidden>Settings</span>
      </div>

      <h1 className="mb-5 mt-1 text-largetitle">Settings</h1>

      <SectionLabel>Appearance</SectionLabel>
      <div className="rounded-card bg-surface p-3 shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
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
              aria-label="Your name"
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
              <Stepper value={ws.defaultRestSec} step={15} min={0} max={600} onChange={(v) => setWorkoutSettings({ defaultRestSec: v })} />
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

      <AnimatePresence>
        {toast && (
          <Toast
            message={toast}
            onDismiss={() => setToast(null)}
          />
        )}
      </AnimatePresence>
    </div>
  )
}
