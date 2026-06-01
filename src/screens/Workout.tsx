import { useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import {
  Plus, Flame, Dumbbell, BarChart2, Zap, Play, ChevronRight,
  Search, X, Pencil, Clock, Trophy, CalendarDays,
} from 'lucide-react'
import { useLife } from '../lib/store'
import {
  exerciseById, isFinished,
  sessionDuration, sessionMuscles, sessionSetCount, sessionVolume,
  sessionsThisWeek, weeklyVolume, workoutStreak,
} from '../lib/workout'
import type { Routine, WorkoutSession } from '../lib/types'
import { LargeTitleHeader, IconButton, Card, EmptyState } from '../components/ui'
import TrainCalendar from '../components/TrainCalendar'
import RoutineEditor from '../components/RoutineEditor'
import Sheet from '../components/Sheet'
import Toast from '../components/Toast'
import { spring, listItem } from '../lib/motion'
import RoutineCard from '../components/train/RoutineCard'
import HistoryCard from '../components/train/HistoryCard'
import PRSection from '../components/train/PRSection'
import { muscleColor } from '../components/train/MuscleTag'

type TrainTab = 'routines' | 'history' | 'prs' | 'calendar'

/* ── Session detail sheet ───────────────────────────────────────────────── */

function SessionDetail({
  session,
  unit,
  exercises: allEx,
  onEdit,
  onDelete,
}: {
  session: WorkoutSession
  unit: string
  exercises: ReturnType<typeof useLife>['state']['exercises']
  onEdit: () => void
  onDelete: () => void
}) {
  const muscles = sessionMuscles(session, allEx).slice(0, 6)
  return (
    <div className="space-y-3">
      {/* Stats row */}
      <div className="flex gap-2">
        {[
          { value: sessionDuration(session) || '—', label: 'duration' },
          { value: String(sessionSetCount(session)), label: 'sets' },
          { value: `${sessionVolume(session)}`, label: `${unit} vol` },
        ].map(({ value, label }) => (
          <div
            key={label}
            className="flex-1 rounded-card bg-surface p-3 text-center shadow-card"
            style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
          >
            <div className="tabular text-title3 text-label">{value}</div>
            <div className="text-caption text-label2">{label}</div>
          </div>
        ))}
      </div>

      {/* Muscles */}
      {muscles.length > 0 && (
        <div className="flex flex-wrap gap-1.5 px-1">
          {muscles.map((m) => (
            <span
              key={m}
              className="rounded-full px-2.5 py-1 text-footnote font-medium"
              style={{ background: muscleColor(m) + '22', color: muscleColor(m) }}
            >
              {m}
            </span>
          ))}
        </div>
      )}

      {/* Exercise breakdown */}
      {session.exercises.map((ex, i) => {
        const meta = exerciseById(allEx, ex.exerciseId)
        const done = ex.sets.filter((s) => s.done)
        if (done.length === 0) return null
        return (
          <div
            key={i}
            className="rounded-card bg-surface p-3 shadow-card"
            style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
          >
            <div className="mb-2 text-headline text-label">{meta?.name ?? 'Exercise'}</div>
            <div className="space-y-1">
              {done.map((s, j) => (
                <div key={j} className="flex items-center gap-3 text-footnote">
                  <span className="w-6 text-label3">S{j + 1}</span>
                  <span className="tabular text-label">
                    {s.weight != null && s.reps != null
                      ? `${s.weight} ${unit} × ${s.reps} reps`
                      : s.reps != null        ? `${s.reps} reps`
                      : s.distanceKm != null  ? `${s.distanceKm} km`
                      : s.durationSec != null ? `${s.durationSec}s`
                      : '✓'}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )
      })}

      {/* Actions */}
      <motion.button
        whileTap={{ scale: 0.97 }}
        transition={spring}
        onClick={onEdit}
        className="w-full rounded-card bg-accent py-3 text-headline text-white"
      >
        <span className="flex items-center justify-center gap-2">
          <Pencil size={17} /> Edit workout
        </span>
      </motion.button>

      <button
        onClick={onDelete}
        className="w-full py-2 text-center text-subhead text-danger"
      >
        Delete workout
      </button>
    </div>
  )
}

/* ── Screen ─────────────────────────────────────────────────────────────── */

export default function Workout({
  onOpenWorkout,
  onEditSession,
}: {
  onOpenWorkout: () => void
  onEditSession: (id: string) => void
}) {
  const {
    state, activeSession,
    startSession, deleteRoutine, restoreRoutine,
    discardSession,
  } = useLife()

  const [tab, setTab] = useState<TrainTab>('routines')
  const [query, setQuery] = useState('')
  const [muscleFilter, setMuscleFilter] = useState('All')
  const [editor, setEditor] = useState<{ open: boolean; routine?: Routine }>({ open: false })
  const [detail, setDetail] = useState<WorkoutSession | null>(null)

  // Undo state
  const [deletedRoutine, setDeletedRoutine] = useState<Routine | null>(null)
  const [deletedSession, setDeletedSession] = useState<WorkoutSession | null>(null)
  const routineUndoTimer = useRef<number | null>(null)
  const sessionUndoTimer = useRef<number | null>(null)

  const ws = state.workoutSettings

  const finished = useMemo(() => state.sessions.filter(isFinished), [state.sessions])
  const history = useMemo(
    () => [...finished].sort((a, b) => (b.finishedAt ?? 0) - (a.finishedAt ?? 0)),
    [finished],
  )
  const trainedDays = useMemo(() => new Set(finished.map((s) => s.date)), [finished])

  const streak   = workoutStreak(state.sessions)
  const weekCount = sessionsThisWeek(state.sessions).length
  const weekVol  = weeklyVolume(state.sessions)

  // Unique muscles across all finished sessions for PR filter
  const allPRMuscles = useMemo(() => {
    const seen = new Set<string>()
    state.exercises.forEach((e) => { if (e.muscle) seen.add(e.muscle) })
    return ['All', ...Array.from(seen).sort()]
  }, [state.exercises])

  const start = (routineId?: string) => {
    if (!activeSession) startSession(routineId)
    onOpenWorkout()
  }

  const handleDeleteRoutine = (r: Routine) => {
    deleteRoutine(r.id)
    setDeletedRoutine(r)
    if (routineUndoTimer.current) clearTimeout(routineUndoTimer.current)
    routineUndoTimer.current = window.setTimeout(() => setDeletedRoutine(null), 4000)
  }

  const handleDeleteSession = (s: WorkoutSession) => {
    discardSession(s.id)
    setDetail(null)
    setDeletedSession(s)
    if (sessionUndoTimer.current) clearTimeout(sessionUndoTimer.current)
    sessionUndoTimer.current = window.setTimeout(() => setDeletedSession(null), 4000)
  }

  // Filtered routines
  const filteredRoutines = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return state.routines
    return state.routines.filter((r) =>
      r.name.toLowerCase().includes(q) ||
      r.exercises.some((re) => exerciseById(state.exercises, re.exerciseId)?.name.toLowerCase().includes(q))
    )
  }, [query, state.routines, state.exercises])

  // Filtered history
  const filteredHistory = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return history
    return history.filter((s) =>
      s.name.toLowerCase().includes(q) ||
      s.exercises.some((ex) => exerciseById(state.exercises, ex.exerciseId)?.name.toLowerCase().includes(q))
    )
  }, [query, history, state.exercises])

  const tabs: { id: TrainTab; label: string; icon: typeof Dumbbell }[] = [
    { id: 'routines',  label: 'Routines',  icon: Dumbbell },
    { id: 'history',   label: 'History',   icon: Clock },
    { id: 'prs',       label: 'PRs',       icon: Trophy },
    { id: 'calendar',  label: 'Calendar',  icon: CalendarDays },
  ]

  const showSearch = tab === 'routines' || tab === 'history'

  return (
    <div>
      <LargeTitleHeader
        title="Train"
        trailing={
          <IconButton
            icon={Plus}
            label="New routine"
            accent
            onClick={() => setEditor({ open: true })}
          />
        }
      />

      {/* ── Stats row ── */}
      <div className="mt-1 flex gap-2">
        <Card className="flex-1 p-3 text-center">
          <div className="mb-0.5 flex justify-center text-label2"><Dumbbell size={15} /></div>
          <div className="tabular text-title3 text-label">{weekCount}</div>
          <div className="text-caption text-label2">this week</div>
        </Card>
        <Card className="flex-1 p-3 text-center">
          <div className="mb-0.5 flex justify-center text-label2"><Flame size={15} /></div>
          <div className="tabular text-title3 text-label">{streak}</div>
          <div className="text-caption text-label2">day streak</div>
        </Card>
        <Card className="flex-1 p-3 text-center">
          <div className="mb-0.5 flex justify-center text-label2"><BarChart2 size={15} /></div>
          <div className="tabular text-title3 text-label">
            {weekVol >= 1000 ? `${(weekVol / 1000).toFixed(1)}k` : String(weekVol)}
          </div>
          <div className="text-caption text-label2">{ws.unit} vol</div>
        </Card>
      </div>

      {/* ── Start workout card ── */}
      <div className="mt-3">
        {activeSession ? (
          <motion.button
            whileTap={{ scale: 0.98 }}
            transition={spring}
            onClick={onOpenWorkout}
            className="flex w-full items-center gap-3 rounded-card bg-accent p-4 text-left"
          >
            <span className="grid h-10 w-10 place-items-center rounded-full bg-white/20 text-white">
              <Play size={20} fill="currentColor" />
            </span>
            <div className="flex-1">
              <div className="text-headline text-white">Resume workout</div>
              <div className="text-footnote text-white/80">{activeSession.name} in progress</div>
            </div>
            <ChevronRight size={18} className="text-white/80" />
          </motion.button>
        ) : (
          <div className="grid grid-cols-2 gap-2">
            <motion.button
              whileTap={{ scale: 0.97 }}
              transition={spring}
              onClick={() => start()}
              className="flex flex-col items-center gap-2 rounded-card py-4"
              style={{
                background: 'rgb(var(--accent) / 0.08)',
                border: '1.5px dashed rgb(var(--accent) / 0.45)',
              }}
            >
              <Zap size={22} className="text-accent" fill="currentColor" />
              <span className="text-subhead font-semibold text-accent">Empty workout</span>
            </motion.button>
            <motion.button
              whileTap={{ scale: 0.97 }}
              transition={spring}
              onClick={() => setTab('routines')}
              className="flex flex-col items-center gap-2 rounded-card bg-surface py-4 shadow-card"
              style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
            >
              <Dumbbell size={22} className="text-label2" />
              <span className="text-subhead font-semibold text-label">Choose routine</span>
            </motion.button>
          </div>
        )}
      </div>

      {/* ── Tab bar ── */}
      <div className="mt-4 flex gap-1 rounded-[12px] bg-fill p-1">
        {tabs.map((t) => {
          const Icon = t.icon
          const active = tab === t.id
          return (
            <button
              key={t.id}
              onClick={() => { setTab(t.id); setQuery('') }}
              className="relative flex flex-1 flex-col items-center gap-0.5 rounded-[9px] py-2 transition-colors"
            >
              {active && (
                <motion.span
                  layoutId="train-tab-bg"
                  transition={spring}
                  className="absolute inset-0 rounded-[9px] bg-surface shadow-sm"
                />
              )}
              <Icon size={16} className={`relative z-10 ${active ? 'text-accent' : 'text-label3'}`} />
              <span className={`relative z-10 text-caption font-medium ${active ? 'text-accent' : 'text-label3'}`}>
                {t.label}
              </span>
            </button>
          )
        })}
      </div>

      {/* ── Search bar (Routines + History tabs) ── */}
      <AnimatePresence>
        {showSearch && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={spring}
            className="overflow-hidden"
          >
            <div
              className="mt-3 flex items-center gap-2 rounded-card bg-surface px-3.5 py-2.5 shadow-card"
              style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
            >
              <Search size={16} className="shrink-0 text-label3" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={tab === 'routines' ? 'Search routines…' : 'Search history…'}
                className="w-full bg-transparent text-body text-label placeholder:text-label3 focus:outline-none"
              />
              {query && (
                <button onClick={() => setQuery('')} className="shrink-0 text-label3">
                  <X size={16} />
                </button>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── PR muscle filter (PRs tab) ── */}
      <AnimatePresence>
        {tab === 'prs' && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={spring}
            className="overflow-hidden"
          >
            <div className="mt-3 flex gap-1.5 overflow-x-auto pb-0.5 no-scrollbar">
              {allPRMuscles.map((m) => (
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
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── Tab content ── */}
      <div className="mt-3 pb-8">
        <AnimatePresence mode="wait">
          {tab === 'routines' && (
            <motion.div
              key="routines"
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ duration: 0.18 }}
            >
              {filteredRoutines.length === 0 ? (
                query ? (
                  <EmptyState icon={Search} title="No matches" subtitle={`No routines match "${query}".`} />
                ) : (
                  <EmptyState
                    icon={Dumbbell}
                    title="No routines yet"
                    subtitle="Tap + above to build your first routine, or choose a template."
                  />
                )
              ) : (
                <div className="space-y-3">
                  <AnimatePresence initial={false}>
                    {filteredRoutines.map((r) => (
                      <motion.div key={r.id} variants={listItem} exit="exit" layout>
                        <RoutineCard
                          routine={r}
                          exercises={state.exercises}
                          onStart={() => start(r.id)}
                          onEdit={() => setEditor({ open: true, routine: r })}
                          onDelete={() => handleDeleteRoutine(r)}
                        />
                      </motion.div>
                    ))}
                  </AnimatePresence>
                  <p className="text-center text-caption text-label3">Swipe left to delete</p>
                </div>
              )}
            </motion.div>
          )}

          {tab === 'history' && (
            <motion.div
              key="history"
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ duration: 0.18 }}
            >
              {filteredHistory.length === 0 ? (
                query ? (
                  <EmptyState icon={Search} title="No matches" subtitle={`No workouts match "${query}".`} />
                ) : (
                  <EmptyState
                    icon={Dumbbell}
                    title="No workouts yet"
                    subtitle="Complete a session and it'll appear here."
                  />
                )
              ) : (
                <div className="space-y-3">
                  <AnimatePresence initial={false}>
                    {filteredHistory.map((s) => (
                      <motion.div key={s.id} variants={listItem} exit="exit" layout>
                        <HistoryCard
                          session={s}
                          exercises={state.exercises}
                          unit={ws.unit}
                          onTap={() => setDetail(s)}
                          onDelete={() => handleDeleteSession(s)}
                        />
                      </motion.div>
                    ))}
                  </AnimatePresence>
                  <p className="text-center text-caption text-label3">Tap to view · Swipe left to delete</p>
                </div>
              )}
            </motion.div>
          )}

          {tab === 'prs' && (
            <motion.div
              key="prs"
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ duration: 0.18 }}
            >
              <PRSection
                sessions={state.sessions}
                exercises={state.exercises}
                unit={ws.unit}
                muscleFilter={muscleFilter}
              />
            </motion.div>
          )}

          {tab === 'calendar' && (
            <motion.div
              key="calendar"
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ duration: 0.18 }}
            >
              <TrainCalendar trainedDays={trainedDays} />
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* ── Routine editor sheet ── */}
      <RoutineEditor
        open={editor.open}
        routine={editor.routine}
        onClose={() => setEditor({ open: false })}
      />

      {/* ── Session detail sheet ── */}
      <Sheet open={!!detail} onClose={() => setDetail(null)} title={detail?.name}>
        {detail && (
          <SessionDetail
            session={detail}
            unit={ws.unit}
            exercises={state.exercises}
            onEdit={() => { onEditSession(detail.id); setDetail(null) }}
            onDelete={() => handleDeleteSession(detail)}
          />
        )}
      </Sheet>

      {/* ── Toasts ── */}
      <AnimatePresence>
        {deletedRoutine && (
          <Toast
            message={`"${deletedRoutine.name}" deleted`}
            onUndo={() => restoreRoutine(deletedRoutine)}
            onDismiss={() => setDeletedRoutine(null)}
          />
        )}
        {deletedSession && (
          <Toast
            message="Workout deleted"
            onDismiss={() => setDeletedSession(null)}
          />
        )}
      </AnimatePresence>
    </div>
  )
}
