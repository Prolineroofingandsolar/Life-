import { useEffect, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Sun, ListChecks, Dumbbell, Flame, HeartPulse, Wallet } from 'lucide-react'
import { ThemeProvider } from './lib/theme'
import { LifeProvider, useLife } from './lib/store'
import { pageVariants, ease } from './lib/motion'
import TabBar from './components/TabBar'
import type { TabDef } from './components/TabBar'
import ErrorBoundary from './components/ErrorBoundary'
import Today from './screens/Today'
import Tasks from './screens/Tasks'
import Workout from './screens/Workout'
import ActiveWorkout from './screens/ActiveWorkout'
import Habits from './screens/Habits'
import Body from './screens/Body'
import Money from './screens/Money'
import Settings from './screens/Settings'

type Tab = 'today' | 'tasks' | 'train' | 'habits' | 'body' | 'money'

const TABS: TabDef<Tab>[] = [
  { id: 'today', label: 'Today', icon: Sun },
  { id: 'tasks', label: 'Tasks', icon: ListChecks },
  { id: 'train', label: 'Train', icon: Dumbbell },
  { id: 'habits', label: 'Habits', icon: Flame },
  { id: 'body', label: 'Body', icon: HeartPulse },
  { id: 'money', label: 'Money', icon: Wallet },
]

function Shell() {
  const { state, activeSession } = useLife()
  const [tab, setTab] = useState<Tab>('today')
  const [settings, setSettings] = useState(false)
  const [inWorkout, setInWorkout] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)

  const editSession = editId ? state.sessions.find((s) => s.id === editId) : undefined

  // If the active session ends (finished/discarded) while the overlay is open, close it.
  useEffect(() => {
    if (inWorkout && !activeSession) setInWorkout(false)
  }, [inWorkout, activeSession])
  // If a workout being edited is deleted, close the editor.
  useEffect(() => {
    if (editId && !editSession) setEditId(null)
  }, [editId, editSession])

  const overlayOpen = settings || (inWorkout && !!activeSession) || !!editSession

  return (
    <div className="mx-auto flex h-full max-w-app flex-col" style={{ height: '100dvh' }}>
      {/* Frosted-glass status-bar spacer — lives outside the scroll container so
          safe-area padding never fights a fixed height, and sticky headers below
          don't need their own safe-top at all. */}
      <div className="material safe-top shrink-0" />
      <main className="min-h-0 flex-1 overflow-y-auto px-4 pb-6 no-scrollbar">
        <AnimatePresence mode="wait">
          {settings ? (
            <motion.div
              key="settings"
              initial={{ opacity: 0, x: 24 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 24 }}
              transition={{ duration: 0.28, ease }}
            >
              <Settings onClose={() => setSettings(false)} />
            </motion.div>
          ) : editSession ? (
            <motion.div
              key="edit-workout"
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 24 }}
              transition={{ duration: 0.28, ease }}
            >
              <ActiveWorkout session={editSession} mode="edit" onMinimize={() => setEditId(null)} />
            </motion.div>
          ) : inWorkout && activeSession ? (
            <motion.div
              key="active-workout"
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 24 }}
              transition={{ duration: 0.28, ease }}
            >
              <ActiveWorkout session={activeSession} onMinimize={() => setInWorkout(false)} />
            </motion.div>
          ) : (
            <motion.div
              key={tab}
              variants={pageVariants}
              initial="initial"
              animate="animate"
              exit="exit"
              transition={{ duration: 0.22, ease }}
            >
              {tab === 'today' && <Today onOpenSettings={() => setSettings(true)} onOpenTasks={() => setTab('tasks')} />}
              {tab === 'tasks' && <Tasks />}
              {tab === 'train' && <Workout onOpenWorkout={() => setInWorkout(true)} onEditSession={setEditId} />}
              {tab === 'habits' && <Habits />}
              {tab === 'body' && <Body />}
              {tab === 'money' && <Money />}
            </motion.div>
          )}
        </AnimatePresence>
      </main>

      {!overlayOpen && <TabBar tabs={TABS} active={tab} onChange={setTab} />}
    </div>
  )
}

export default function App() {
  return (
    <ErrorBoundary>
      <ThemeProvider>
        <LifeProvider>
          <Shell />
        </LifeProvider>
      </ThemeProvider>
    </ErrorBoundary>
  )
}
