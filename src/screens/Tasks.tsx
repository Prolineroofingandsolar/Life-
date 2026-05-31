import { useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Briefcase, Dumbbell, Leaf, Trash2, Plus, Check, ListTodo, Pencil } from 'lucide-react'
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

function TaskRow({
  task,
  onToggle,
  onDelete,
  onEdit,
}: {
  task: Task
  onToggle: () => void
  onDelete: () => void
  onEdit: () => void
}) {
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
        <button onClick={onEdit} className="min-w-0 flex-1 text-left">
          <span className={`text-body ${task.done ? 'text-label3 line-through' : 'text-label'}`}>
            {task.title}
          </span>
          {task.dueDate && !task.done && (
            <div className="mt-0.5 text-caption font-medium" style={{ color: DUE_COLOR[task.dueDate] }}>
              {DUE_LABEL[task.dueDate]}
            </div>
          )}
        </button>
        <button
          onClick={onEdit}
          aria-label="Edit task"
          className="shrink-0 p-1 text-label3 active:text-accent"
        >
          <Icon size={17} style={{ color: CAT_COLOR[task.category] }} />
        </button>
      </motion.div>
    </motion.div>
  )
}

function TaskGroup({ label, tasks, onToggle, onDelete, onEdit }: {
  label: string
  tasks: Task[]
  onToggle: (id: string) => void
  onDelete: (task: Task) => void
  onEdit: (task: Task) => void
}) {
  if (tasks.length === 0) return null
  return (
    <>
      <SectionLabel>{label}</SectionLabel>
      <motion.div layout className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70">
        <AnimatePresence initial={false}>
          {tasks.map((t) => (
            <TaskRow key={t.id} task={t} onToggle={() => onToggle(t.id)} onDelete={() => onDelete(t)} onEdit={() => onEdit(t)} />
          ))}
        </AnimatePresence>
      </motion.div>
    </>
  )
}

export default function Tasks() {
  const { state, addTask, updateTask, toggleTask, deleteTask, restoreTask } = useLife()
  const [filter, setFilter] = useState<Category | 'all'>('all')

  // Add sheet
  const [sheet, setSheet] = useState(false)
  const [draft, setDraft] = useState('')
  const [draftCat, setDraftCat] = useState<Category>('work')
  const [draftDue, setDraftDue] = useState<DueDate>('today')

  // Edit sheet
  const [editTask, setEditTask] = useState<Task | null>(null)
  const [editTitle, setEditTitle] = useState('')
  const [editCat, setEditCat] = useState<Category>('work')
  const [editDue, setEditDue] = useState<DueDate>('today')

  // Undo
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

  const openEdit = (task: Task) => {
    setEditTask(task)
    setEditTitle(task.title)
    setEditCat(task.category)
    setEditDue(task.dueDate ?? 'someday')
  }

  const submitEdit = () => {
    if (!editTask || !editTitle.trim()) return
    updateTask(editTask.id, { title: editTitle.trim(), category: editCat, dueDate: editDue })
    setEditTask(null)
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
  const groupCount = [todayTasks, tomorrowTasks, laterTasks].filter((g) => g.length > 0).length

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
            groupCount > 1 ? (
              <>
                <TaskGroup label="Today"    tasks={todayTasks}    onToggle={toggleTask} onDelete={handleDelete} onEdit={openEdit} />
                <TaskGroup label="Tomorrow" tasks={tomorrowTasks} onToggle={toggleTask} onDelete={handleDelete} onEdit={openEdit} />
                <TaskGroup label="Later"    tasks={laterTasks}    onToggle={toggleTask} onDelete={handleDelete} onEdit={openEdit} />
              </>
            ) : (
              <motion.div layout className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70">
                <AnimatePresence initial={false}>
                  {open.map((t) => (
                    <TaskRow key={t.id} task={t} onToggle={() => toggleTask(t.id)} onDelete={() => handleDelete(t)} onEdit={() => openEdit(t)} />
                  ))}
                </AnimatePresence>
              </motion.div>
            )
          ) : null}

          {done.length > 0 && (
            <>
              <SectionLabel>Completed · {done.length}</SectionLabel>
              <motion.div layout className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70">
                <AnimatePresence initial={false}>
                  {done.map((t) => (
                    <TaskRow key={t.id} task={t} onToggle={() => toggleTask(t.id)} onDelete={() => handleDelete(t)} onEdit={() => openEdit(t)} />
                  ))}
                </AnimatePresence>
              </motion.div>
            </>
          )}
        </>
      )}

      {(hasOpen || done.length > 0) && (
        <p className="mt-4 text-center text-caption text-label3">Tap a task to edit · Swipe left to delete</p>
      )}

      {/* Add-task sheet */}
      <Sheet open={sheet} onClose={() => setSheet(false)} title="New task">
        <input
          autoFocus
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && submit()}
          placeholder="What needs doing?"
          aria-label="Task title"
          className="w-full rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
          style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
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

      {/* Edit-task sheet */}
      <Sheet open={!!editTask} onClose={() => setEditTask(null)} title="Edit task">
        <input
          autoFocus
          value={editTitle}
          onChange={(e) => setEditTitle(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && submitEdit()}
          placeholder="Task title"
          aria-label="Task title"
          className="w-full rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
          style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
        />
        <div className="mt-3">
          <SegmentedControl<DueDate>
            layoutId="edit-task-due"
            value={editDue}
            onChange={setEditDue}
            options={[
              { value: 'today',    label: 'Today' },
              { value: 'tomorrow', label: 'Tomorrow' },
              { value: 'someday',  label: 'Later' },
            ]}
          />
        </div>
        <div className="mt-3">
          <SegmentedControl<Category>
            layoutId="edit-task-cat"
            value={editCat}
            onChange={setEditCat}
            options={CATS.map((c) => ({ value: c, label: CATEGORY_LABEL[c] }))}
          />
        </div>
        <div className="mt-4 flex gap-2">
          <motion.button
            whileTap={{ scale: 0.97 }}
            transition={spring}
            onClick={submitEdit}
            className="flex-1 rounded-card bg-gradient-accent py-3.5 text-headline text-white disabled:opacity-40"
            disabled={!editTitle.trim()}
          >
            Save
          </motion.button>
          {editTask && (
            <motion.button
              whileTap={{ scale: 0.97 }}
              transition={spring}
              onClick={() => {
                if (editTask) handleDelete(editTask)
                setEditTask(null)
              }}
              className="grid w-14 place-items-center rounded-card bg-fill text-danger"
              aria-label="Delete task"
            >
              <Trash2 size={18} />
            </motion.button>
          )}
        </div>
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
