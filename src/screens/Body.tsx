import { useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import {
  Bell, Droplets, UtensilsCrossed, Timer, Wind,
  Scale, Trophy, ChevronDown, ChevronUp, Trash2, Heart,
} from 'lucide-react'
import { useLife } from '../lib/store'
import {
  LargeTitleHeader, SectionLabel, ListGroup, ListRow, Switch, Stepper, Card,
} from '../components/ui'
import {
  notificationPermission,
  notificationsSupported,
  requestNotifications,
  notify,
} from '../lib/notifications'
import { computePRs } from '../lib/workout'
import { muscleColor } from '../components/train/MuscleTag'
import MiniChart from '../components/MiniChart'
import { spring } from '../lib/motion'
import { dayKey } from '../lib/date'
import { isHealthKitAvailable, requestHealthKitPermissions, importFromHealthKit } from '../lib/healthkit'
import type { BodyCompEntry } from '../lib/types'

/* ── Weight tracker ──────────────────────────────────────────────────── */

function WeightTracker() {
  const { state, logBodyWeight, deleteWeightEntry } = useLife()
  const ws = state.workoutSettings
  const unit = ws.unit
  const [input, setInput] = useState('')
  const [showAll, setShowAll] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  const log = state.bodyWeightLog
  const sorted = useMemo(() => [...log].sort((a, b) => b.date.localeCompare(a.date)), [log])
  const chartData = useMemo(
    () =>
      [...log]
        .sort((a, b) => a.date.localeCompare(b.date))
        .slice(-20)
        .map((e) => ({ value: e.kg, label: e.date })),
    [log],
  )

  const latest = sorted[0]
  const prev = sorted[1]
  const diff = latest && prev ? +(latest.kg - prev.kg).toFixed(1) : null

  const handleLog = () => {
    const v = parseFloat(input)
    if (isNaN(v) || v <= 0) return
    logBodyWeight(v)
    setInput('')
    inputRef.current?.blur()
  }

  const visibleHistory = showAll ? sorted : sorted.slice(0, 5)

  return (
    <div>
      {/* Current weight card */}
      <Card className="mb-3 p-4">
        <div className="mb-3 flex items-start justify-between">
          <div>
            <div className="text-footnote text-label2">Current weight</div>
            <div className="tabular text-largetitle text-label">
              {latest ? latest.kg : '—'}
              <span className="ml-1 text-title3 text-label2">{unit}</span>
            </div>
            {diff !== null && (
              <div className={`flex items-center gap-1 text-footnote font-medium ${diff > 0 ? 'text-danger' : diff < 0 ? 'text-move' : 'text-label3'}`}>
                {diff > 0 ? <ChevronUp size={13} /> : diff < 0 ? <ChevronDown size={13} /> : null}
                {diff === 0 ? 'No change' : `${Math.abs(diff)} ${unit} from last`}
              </div>
            )}
          </div>
          <span className="grid h-10 w-10 place-items-center rounded-full bg-accent/10">
            <Scale size={20} className="text-accent" />
          </span>
        </div>

        {/* Mini chart */}
        {chartData.length >= 2 && (
          <div className="mb-3">
            <MiniChart data={chartData} color="#30d158" height={56} />
          </div>
        )}

        {/* Log input */}
        <div className="flex gap-2">
          <input
            ref={inputRef}
            inputMode="decimal"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') handleLog() }}
            placeholder={`Weight in ${unit}`}
            className="flex-1 rounded-[10px] bg-fill px-3 py-2.5 text-body text-label placeholder:text-label3 focus:outline-none focus:ring-2 focus:ring-accent/60"
          />
          <motion.button
            whileTap={{ scale: 0.95 }}
            transition={spring}
            onClick={handleLog}
            disabled={!input.trim()}
            className="rounded-[10px] bg-accent px-4 py-2.5 text-subhead font-semibold text-white disabled:opacity-40"
          >
            Log
          </motion.button>
        </div>
      </Card>

      {/* History */}
      {sorted.length > 0 && (
        <div
          className="overflow-hidden rounded-card bg-surface shadow-card"
          style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
        >
          {visibleHistory.map((entry, i) => (
            <div
              key={entry.date}
              className="flex items-center justify-between px-4 py-3 [&+&]:border-t [&+&]:border-separator/60"
            >
              <div>
                <div className="text-body text-label">
                  {new Date(entry.date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: i > 0 && new Date(entry.date).getFullYear() !== new Date(sorted[0].date).getFullYear() ? 'numeric' : undefined })}
                </div>
                {entry.date === dayKey() && (
                  <div className="text-caption text-accent">Today</div>
                )}
              </div>
              <div className="flex items-center gap-3">
                <span className="tabular text-headline text-label">{entry.kg} {unit}</span>
                <button
                  onClick={() => deleteWeightEntry(entry.date)}
                  className="text-label3 active:scale-90"
                  aria-label="Delete entry"
                >
                  <Trash2 size={15} />
                </button>
              </div>
            </div>
          ))}
          {sorted.length > 5 && (
            <button
              onClick={() => setShowAll((x) => !x)}
              className="w-full py-3 text-center text-subhead text-accent"
            >
              {showAll ? 'Show less' : `Show all ${sorted.length} entries`}
            </button>
          )}
        </div>
      )}
    </div>
  )
}

/* ── PR / Lift records ───────────────────────────────────────────────── */

function LiftRecords() {
  const { state } = useLife()
  const ws = state.workoutSettings
  const unit = ws.unit
  const [muscleFilter, setMuscleFilter] = useState('All')

  const finished = useMemo(() => state.sessions.filter((s) => s.finishedAt != null), [state.sessions])

  const rows = useMemo(() => {
    type Row = { name: string; muscle: string; weight: number; reps: number; e1rm: number }
    const out: Row[] = []
    for (const ex of state.exercises) {
      const pr = computePRs(finished, ex.id)
      if (pr.bestWeight != null && pr.bestReps != null) {
        out.push({
          name: ex.name,
          muscle: ex.muscle ?? '',
          weight: pr.bestWeight,
          reps: pr.bestReps,
          e1rm: pr.best1RM ?? pr.bestWeight,
        })
      }
    }
    return out.sort((a, b) => b.e1rm - a.e1rm)
  }, [finished, state.exercises])

  const allMuscles = useMemo(() => {
    const seen = new Set<string>()
    rows.forEach((r) => { if (r.muscle) seen.add(r.muscle) })
    return ['All', ...Array.from(seen).sort()]
  }, [rows])

  const filtered = muscleFilter === 'All' ? rows : rows.filter((r) => r.muscle === muscleFilter)

  const grouped = useMemo(() => {
    const map = new Map<string, typeof rows>()
    for (const row of filtered) {
      const key = row.muscle || 'Other'
      if (!map.has(key)) map.set(key, [])
      map.get(key)!.push(row)
    }
    return map
  }, [filtered])

  if (rows.length === 0) {
    return (
      <div className="flex flex-col items-center py-12 text-center">
        <div className="mb-3 text-4xl">🏆</div>
        <p className="text-headline text-label">No records yet</p>
        <p className="mt-1 max-w-xs text-subhead text-label2">
          Log some workouts and your best lifts will appear here.
        </p>
      </div>
    )
  }

  return (
    <div>
      {/* Muscle filter chips */}
      <div className="mb-3 flex gap-1.5 overflow-x-auto pb-0.5 no-scrollbar">
        {allMuscles.map((m) => (
          <button
            key={m}
            onClick={() => setMuscleFilter(m)}
            className={`shrink-0 rounded-full px-3 py-1 text-footnote font-medium transition-colors ${
              muscleFilter === m ? 'bg-accent text-white' : 'bg-fill text-label2'
            }`}
          >
            {m}
          </button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <p className="py-8 text-center text-subhead text-label2">No records for this muscle group yet.</p>
      ) : (
        <div className="space-y-4">
          {Array.from(grouped.entries()).map(([muscle, items]) => (
            <div key={muscle}>
              <div className="mb-2 ml-1 flex items-center gap-2">
                <span className="h-1.5 w-1.5 rounded-full" style={{ background: muscleColor(muscle) }} />
                <span
                  className="text-footnote font-semibold uppercase tracking-wider"
                  style={{ color: muscleColor(muscle) }}
                >
                  {muscle}
                </span>
              </div>
              <div
                className="overflow-hidden rounded-card bg-surface shadow-card"
                style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
              >
                {items.map((pr, i) => (
                  <div
                    key={pr.name + i}
                    className="flex items-center gap-3 px-4 py-3 [&+&]:border-t [&+&]:border-separator/60"
                  >
                    <span
                      className="grid h-8 w-8 shrink-0 place-items-center rounded-full"
                      style={{ background: 'rgb(var(--nourish, 255 159 10) / 0.15)' }}
                    >
                      <Trophy size={14} className="text-nourish" fill="currentColor" />
                    </span>
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-body text-label">{pr.name}</div>
                      <div className="text-caption text-label3">~{pr.e1rm} {unit} est. 1RM</div>
                    </div>
                    <div className="shrink-0 text-right">
                      <div className="tabular text-headline text-label">{pr.weight} {unit}</div>
                      <div className="text-caption text-label2">{pr.reps} reps</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

/* ── Body Composition ───────────────────────────────────────────────── */

type CompMetric = { key: keyof Omit<BodyCompEntry, 'date'>; label: string; unit: string; color: string }

const COMP_METRICS: CompMetric[] = [
  { key: 'bodyFatPct', label: 'Body Fat', unit: '%', color: '#ff9f0a' },
  { key: 'leanMassKg', label: 'Lean Mass', unit: 'kg', color: '#30d158' },
  { key: 'bmi', label: 'BMI', unit: '', color: '#32ade6' },
]

function BodyComposition() {
  const { state, mergeBodyCompEntries } = useLife()
  const log = state.bodyCompLog
  const [importing, setImporting] = useState(false)
  const [importMsg, setImportMsg] = useState('')
  const [activeMetric, setActiveMetric] = useState<CompMetric>(COMP_METRICS[0])

  const sorted = useMemo(() => [...log].sort((a, b) => b.date.localeCompare(a.date)), [log])

  const chartData = useMemo(() => {
    return [...log]
      .sort((a, b) => a.date.localeCompare(b.date))
      .slice(-30)
      .filter((e) => e[activeMetric.key] != null)
      .map((e) => ({ value: e[activeMetric.key] as number, label: e.date }))
  }, [log, activeMetric])

  const latest = sorted.find((e) => e[activeMetric.key] != null)
  const latestVal = latest ? latest[activeMetric.key] : null

  const handleImport = async () => {
    setImporting(true)
    setImportMsg('')
    try {
      const ok = await requestHealthKitPermissions()
      if (!ok) { setImportMsg('Permission denied.'); setImporting(false); return }
      const data = await importFromHealthKit(365)
      const byDate = new Map<string, BodyCompEntry>()
      for (const s of data.bodyFat) {
        const e = byDate.get(s.date) ?? { date: s.date }
        e.bodyFatPct = Math.round(s.value * 1000) / 10
        byDate.set(s.date, e)
      }
      for (const s of data.leanMass) {
        const e = byDate.get(s.date) ?? { date: s.date }
        e.leanMassKg = s.value
        byDate.set(s.date, e)
      }
      for (const s of data.bmi) {
        const e = byDate.get(s.date) ?? { date: s.date }
        e.bmi = s.value
        byDate.set(s.date, e)
      }
      const entries = Array.from(byDate.values())
      mergeBodyCompEntries(entries)
      setImportMsg(`Imported ${entries.length} records.`)
    } catch {
      setImportMsg('Import failed. Make sure HealthKit is enabled.')
    }
    setImporting(false)
  }

  const available = isHealthKitAvailable()

  return (
    <div>
      {available && (
        <Card className="mb-3 p-4">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-body font-semibold text-label">Apple Health</div>
              <div className="text-footnote text-label2">Sync Renpho data via Health app</div>
            </div>
            <motion.button
              whileTap={{ scale: 0.95 }}
              transition={spring}
              onClick={handleImport}
              disabled={importing}
              className="flex items-center gap-1.5 rounded-[10px] bg-[#ff375f] px-3 py-2 text-subhead font-semibold text-white disabled:opacity-40"
            >
              <Heart size={14} fill="currentColor" />
              {importing ? 'Importing…' : 'Import'}
            </motion.button>
          </div>
          {importMsg && <p className="mt-2 text-footnote text-label2">{importMsg}</p>}
        </Card>
      )}

      {/* Metric picker */}
      <div className="mb-3 flex gap-1.5">
        {COMP_METRICS.map((m) => (
          <button
            key={m.key}
            onClick={() => setActiveMetric(m)}
            className="relative flex-1 rounded-[10px] py-2 text-footnote font-medium transition-colors"
            style={{
              background: activeMetric.key === m.key ? m.color + '22' : 'rgb(var(--fill))',
              color: activeMetric.key === m.key ? m.color : 'rgb(var(--label3))',
            }}
          >
            {m.label}
          </button>
        ))}
      </div>

      {/* Current value card */}
      <Card className="mb-3 p-4">
        <div className="mb-1 text-footnote text-label2">{activeMetric.label}</div>
        <div className="tabular text-largetitle text-label">
          {latestVal != null ? latestVal : '—'}
          {latestVal != null && <span className="ml-1 text-title3 text-label2">{activeMetric.unit}</span>}
        </div>
        {chartData.length >= 2 && (
          <div className="mt-3">
            <MiniChart data={chartData} color={activeMetric.color} height={56} />
          </div>
        )}
        {log.length === 0 && (
          <p className="mt-2 text-footnote text-label2">
            {available ? 'Tap Import to pull data from Apple Health.' : 'No data yet.'}
          </p>
        )}
      </Card>

      {/* History */}
      {sorted.filter((e) => e[activeMetric.key] != null).length > 0 && (
        <div className="overflow-hidden rounded-card bg-surface shadow-card" style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}>
          {sorted.filter((e) => e[activeMetric.key] != null).slice(0, 10).map((entry) => (
            <div key={entry.date} className="flex items-center justify-between px-4 py-3 [&+&]:border-t [&+&]:border-separator/60">
              <div className="text-body text-label">
                {new Date(entry.date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}
              </div>
              <span className="tabular text-headline text-label">
                {entry[activeMetric.key]}{activeMetric.unit}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

/* ── Screen ──────────────────────────────────────────────────────────── */

export default function Body() {
  const { state, setCareSettings } = useLife()
  const cs = state.careSettings
  const [perm, setPerm] = useState(notificationPermission())
  const [bodyTab, setBodyTab] = useState<'weight' | 'composition' | 'records'>('weight')

  const enableReminders = async () => {
    const p = await requestNotifications()
    setPerm(p)
    if (p === 'granted') {
      setCareSettings({ remindersEnabled: true })
      notify('Reminders on', "I'll nudge you to drink, eat and take breaks.")
    }
  }

  return (
    <div>
      <LargeTitleHeader title="Body" />
      <p className="-mt-1 mb-4 text-subhead text-label2">Track your physique and lift records.</p>

      {/* ── Body tabs ── */}
      <div className="mb-4 flex gap-1 rounded-[12px] bg-fill p-1">
        {[
          { id: 'weight' as const, label: 'Weight', icon: Scale },
          { id: 'composition' as const, label: 'Composition', icon: Heart },
          { id: 'records' as const, label: 'Lifts', icon: Trophy },
        ].map((t) => {
          const Icon = t.icon
          const active = bodyTab === t.id
          return (
            <button
              key={t.id}
              onClick={() => setBodyTab(t.id)}
              className="relative flex flex-1 items-center justify-center gap-1.5 rounded-[9px] py-2.5"
            >
              {active && (
                <motion.span
                  layoutId="body-tab-bg"
                  transition={spring}
                  className="absolute inset-0 rounded-[9px] bg-surface shadow-sm"
                />
              )}
              <Icon size={15} className={`relative z-10 ${active ? 'text-accent' : 'text-label3'}`} />
              <span className={`relative z-10 text-subhead font-medium ${active ? 'text-label' : 'text-label3'}`}>
                {t.label}
              </span>
            </button>
          )
        })}
      </div>

      <AnimatePresence mode="wait">
        {bodyTab === 'weight' && (
          <motion.div
            key="weight"
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.18 }}
          >
            <WeightTracker />
          </motion.div>
        )}
        {bodyTab === 'composition' && (
          <motion.div
            key="composition"
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.18 }}
          >
            <BodyComposition />
          </motion.div>
        )}
        {bodyTab === 'records' && (
          <motion.div
            key="records"
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.18 }}
          >
            <LiftRecords />
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── Reminders & Daily goals ── */}
      <SectionLabel>Reminders</SectionLabel>
      {!notificationsSupported() ? (
        <ListGroup>
          <ListRow icon={Bell} iconColor="rgb(var(--accent))" title="Not supported" subtitle="This browser can't show notifications." />
        </ListGroup>
      ) : perm === 'granted' ? (
        <ListGroup>
          <ListRow
            icon={Bell}
            iconColor="rgb(var(--accent))"
            title="Nudges"
            subtitle="Water, meals & breaks while the app is open"
            trailing={<Switch checked={cs.remindersEnabled} onChange={(v) => setCareSettings({ remindersEnabled: v })} />}
          />
        </ListGroup>
      ) : (
        <ListGroup>
          <ListRow
            icon={Bell}
            iconColor="rgb(var(--accent))"
            title={<span className="text-accent">Enable reminders</span>}
            subtitle="Let Life nudge you to drink, eat & step away"
            onClick={enableReminders}
          />
        </ListGroup>
      )}
      <p className="ml-4 mt-2 text-footnote text-label2">On iPhone, add Life to your Home Screen first, then enable.</p>

      <SectionLabel>Daily goals</SectionLabel>
      <ListGroup>
        <ListRow
          icon={Droplets}
          iconColor="#32ade6"
          title="Water"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-16 text-right text-body text-label2">{cs.waterGoal} glasses</span>
              <Stepper value={cs.waterGoal} min={1} max={20} onChange={(v) => setCareSettings({ waterGoal: v })} />
            </div>
          }
        />
        <ListRow
          icon={UtensilsCrossed}
          iconColor="#ff9f0a"
          title="Meals"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-16 text-right text-body text-label2">{cs.mealsGoal} meals</span>
              <Stepper value={cs.mealsGoal} min={1} max={8} onChange={(v) => setCareSettings({ mealsGoal: v })} />
            </div>
          }
        />
      </ListGroup>

      <SectionLabel>Reminder timing</SectionLabel>
      <ListGroup>
        <ListRow
          icon={Timer}
          iconColor="#32ade6"
          title="Water every"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-14 text-right text-body text-label2">{cs.waterIntervalMin} min</span>
              <Stepper value={cs.waterIntervalMin} step={15} min={15} onChange={(v) => setCareSettings({ waterIntervalMin: v })} />
            </div>
          }
        />
        <ListRow
          icon={Wind}
          iconColor="#30d158"
          title="Break every"
          trailing={
            <div className="flex items-center gap-3">
              <span className="tabular w-14 text-right text-body text-label2">{cs.breakIntervalMin} min</span>
              <Stepper value={cs.breakIntervalMin} step={10} min={20} onChange={(v) => setCareSettings({ breakIntervalMin: v })} />
            </div>
          }
        />
      </ListGroup>

      <div className="h-4" />
    </div>
  )
}
