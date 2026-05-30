import { useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Briefcase, Dumbbell, Leaf, Trash2, Plus, Check, ListTodo } from 'lucide-react'
import type { ComponentType } from 'react'
import type { LucideProps } from 'lucide-react'
import { useLife } from '../lib/store'
import { LargeTitleHeader, SegmentedControl, IconButton, EmptyState, SectionLabel } from '../components/ui'
import Sheet from '../components/Sheet'
import Toast from '../components/Toast'
import { listItem, spring } from '../lib/motion'
import { CATEGORY_LABEL } from '../lib/types'
import type { Category, DueDate, Task } from '../lib/types'

const CATS: Category[] = ['work', 'gym', 'personal']
const CAT_ICON: Record<Category, ComponentType<LucideProps>> = {
  work: Briefcase,
  gym: Dumbbell,
  personal: Leaf,
}
const CAT_COLOR: Record<Category, string> = {
  work: 'rgb(var(--accent))',
  gym: '#30d158',
  personal: '#ff9f0a',
}
const DUE_LABEL: Record<DueDate, string> = { today: 'Today', tomorrow: 'Tomorrow', someday: 'Later' }
const DUE_COLOR: Record<DueDate, string> = {
  today: 'rgb(var(--accent))',
  tomorrow: 'rgb(var(--label-2))',
  someday: 'rgb(var(--label-3))',
}

function TaskRow({ task, onToggle, onDelete }: { task: Task; onToggle: () => void; onDelete: () => void }) {
  const Icon = CAT_ICON[task.category]
  return (
    <motion.div variants={listItem} exit="exit" layout className="relative overflow-hidden">
      <div className="absolute inset-y-0 right-0 flex items-center bg-danger pl-6 pr-5 text-white">
        <Trash2 size={20} />
      </div>
      <motion.div
        drag="x"
        dragConstraints={{ left: -96, right: 0 }}
        dragElastic={{ left: 0.5, right: 0 }}
        dragSnapToOrigin
        onDragEnd={(_, info) => { if (info.offset.x < -72) onDelete() }}
        className="relative flex items-center gap-3 bg-surface px-4 py-3"
      >
        <motion.button
          whileTap={{ scale: 0.85 }}
          transition={spring}
          onClick={onToggle}
          aria-label={task.done ? 'Reopen task' : 'Complete task'}
          className={`grid h-[26px] w-[26px] shrink-0 place-items-center rounded-full border-2 ${
            task.done ? 'border-move bg-move text-white' : 'border-label3'
          }`}
        >
          {task.done && <Check size={15} strokeWidth={3} />}
        </motion.button>
        <div className="min-w-0 flex-1">
          <span className={`text-body ${task.done ? 'text-label3 line-through' : 'text-label'}`}>
            {task.title}
          </span>
          {task.dueDate && !task.done && (
            <div className="mt-0.5 text-caption font-medium" style={{ color: DUE_COLOR[task.dueDate] }}>
              {DUE_LABEL[task.dueDate]}
            </div>
          )}
        </div>
        <Icon size={17} style={{ color: CAT_COLOR[task.category] }} />
      </motion.div>
    </motion.div>
  )
}

function TaskGroup({ label, tasks, onToggle, onDelete }: {
  label: string
  tasks: Task[]
  onToggle: (id: string) => void
  onDelete: (task: Task) => void
}) {
  if (tasks.length === 0) return null
  return (
    <>
      <SectionLabel>{label}</SectionLabel>
      <motion.div layout className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70">
        <AnimatePresence initial={false}>
          {tasks.map((t) => (
            <TaskRow key={t.id} task={t} onToggle={() => onToggle(t.id)} onDelete={() => onDelete(t)} />
          ))}
        </AnimatePresence>
      </motion.div>
    </>
  )
}

export default function Tasks() {
  const { state, addTask, toggleTask, deleteTask, restoreTask } = useLife()
  const [filter, setFilter] = useState<Category | 'all'>('all')
  const [sheet, setSheet] = useState(false)
  const [draft, setDraft] = useState('')
  const [draftCat, setDraftCat] = useState<Category>('work')
  const [draftDue, setDraftDue] = useState<DueDate>('today')
  const [deletedTask, setDeletedTask] = useState<Task | null>(null)
  const undoTimer = useRef<number | null>(null)

  const visible = state.tasks.filter((t) => filter === 'all' || t.category === filter)
  const open = visible.filter((t) => !t.done)
  const done = visible.filter((t) => t.done)

  const todayTasks    = open.filter((t) => t.dueDate === 'today')
  const tomorrowTasks = open.filter((t) => t.dueDate === 'tomorrow')
  const laterTasks    = open.filter((t) => t.dueDate === 'someday' || !t.dueDate)

  const submit = () => {
    if (!draft.trim()) return
    addTask(draft, draftCat, draftDue)
    setDraft('')
    setSheet(false)
  }

  const handleDelete = (task: Task) => {
    deleteTask(task.id)
    setDeletedTask(task)
    if (undoTimer.current) clearTimeout(undoTimer.current)
    undoTimer.current = window.setTimeout(() => setDeletedTask(null), 4000)
  }

  const handleUndo = () => {
    if (deletedTask) restoreTask(deletedTask)
  }

  const hasOpen = open.length > 0

  return (
    <div>
      <LargeTitleHeader
        title="Tasks"
        trailing={<IconButton icon={Plus} label="Add task" accent onClick={() => setSheet(true)} />}
      />

      <div className="mb-4 mt-3">
        <SegmentedControl<Category | 'all'>
          layoutId="task-filter"
          value={filter}
          onChange={setFilter}
          options={[
            { value: 'all', label: 'All' },
            ...CATS.map((c) => ({ value: c, label: CATEGORY_LABEL[c] })),
          ]}
        />
      </div>

      {!hasOpen && done.length === 0 ? (
        <EmptyState icon={ListTodo} title="Nothing here yet" subtitle="Tap + to capture a task before the thought escapes." />
      ) : (
        <>
          {hasOpen ? (
            <>
              <TaskGroup label="Today"    tasks={todayTasks}    onToggle={toggleTask} onDelete={handleDelete} />
              <TaskGroup label="Tomorrow" tasks={tomorrowTasks} onToggle={toggleTask} onDelete={handleDelete} />
              <TaskGroup label="Later"    tasks={laterTasks}    onToggle={toggleTask} onDelete={handleDelete} />
            </>
          ) : null}

          {done.length > 0 && (
            <>
              <SectionLabel>Completed · {done.length}</SectionLabel>
              <motion.div layout className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70">
                <AnimatePresence initial={false}>
                  {done.map((t) => (
                    <TaskRow key={t.id} task={t} onToggle={() => toggleTask(t.id)} onDelete={() => handleDelete(t)} />
                  ))}
                </AnimatePresence>
              </motion.div>
            </>
          )}
        </>
      )}

      <p className="mt-4 text-center text-caption text-label3">Swipe a task left to delete</p>

      {/* Add-task sheet */}
      <Sheet open={sheet} onClose={() => setSheet(false)} title="New task">
        <input
          autoFocus
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && submit()}
          placeholder="What needs doing?"
          className="w-full rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
        />
        <div className="mt-3">
          <SegmentedControl<DueDate>
            layoutId="task-due"
            value={draftDue}
            onChange={setDraftDue}
            options={[
              { value: 'today',    label: 'Today' },
              { value: 'tomorrow', label: 'Tomorrow' },
              { value: 'someday',  label: 'Later' },
            ]}
          />
        </div>
        <div className="mt-3">
          <SegmentedControl<Category>
            layoutId="new-task-cat"
            value={draftCat}
            onChange={setDraftCat}
            options={CATS.map((c) => ({ value: c, label: CATEGORY_LABEL[c] }))}
          />
        </div>
        <motion.button
          whileTap={{ scale: 0.97 }}
          transition={spring}
          onClick={submit}
          className="mt-4 w-full rounded-card bg-gradient-accent py-3.5 text-headline text-white disabled:opacity-40"
          disabled={!draft.trim()}
        >
          Add task
        </motion.button>
      </Sheet>

      <AnimatePresence>
        {deletedTask && (
          <Toast
            message="Task deleted"
            onUndo={handleUndo}
            onDismiss={() => setDeletedTask(null)}
          />
        )}
      </AnimatePresence>
    </div>
  )
}
