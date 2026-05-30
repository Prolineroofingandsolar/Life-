import { useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Plus, Trash2, Wallet, Pencil } from 'lucide-react'
import { useLife } from '../lib/store'
import { LargeTitleHeader, IconButton, EmptyState, SectionLabel } from '../components/ui'
import Sheet from '../components/Sheet'
import Toast from '../components/Toast'
import BillCalendar from '../components/BillCalendar'
import { billCountdown } from '../lib/date'
import { listItem, spring } from '../lib/motion'
import type { Bill } from '../lib/types'

const fmt = (n: number) => '£' + n.toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

function BillRow({ bill, onDelete, onEdit }: { bill: Bill; onDelete: () => void; onEdit: () => void }) {
  const { days, label } = billCountdown(bill.dayOfMonth)
  const soon = days <= 3
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
        <div
          className={`tabular grid h-11 w-11 shrink-0 place-items-center rounded-[10px] text-callout font-semibold ${
            soon ? 'bg-danger/15 text-danger' : 'bg-fill text-label2'
          }`}
        >
          {bill.dayOfMonth}
        </div>
        <div className="min-w-0 flex-1">
          <div className="truncate text-body text-label">{bill.name}</div>
          <div className={`text-footnote ${soon ? 'text-danger' : 'text-label2'}`}>{label}</div>
        </div>
        <div className="tabular text-body font-medium text-label">{fmt(bill.amount)}</div>
        <button
          onClick={onEdit}
          onPointerDown={(e) => e.stopPropagation()}
          aria-label="Edit bill"
          className="shrink-0 p-1 text-label3 active:text-accent"
        >
          <Pencil size={15} />
        </button>
      </motion.div>
    </motion.div>
  )
}

export default function Money() {
  const { state, addBill, deleteBill, restoreBill, updateBill } = useLife()
  const [sheet, setSheet] = useState(false)
  const [name, setName] = useState('')
  const [amount, setAmount] = useState('')
  const [day, setDay] = useState('1')
  const [selectedDay, setSelectedDay] = useState<{ day: number; bills: Bill[] } | null>(null)

  // Edit state
  const [editBill, setEditBill] = useState<Bill | null>(null)
  const [editName, setEditName] = useState('')
  const [editAmount, setEditAmount] = useState('')
  const [editDay, setEditDay] = useState('1')

  // Undo state
  const [deletedBill, setDeletedBill] = useState<Bill | null>(null)
  const undoTimer = useRef<number | null>(null)

  const bills = [...state.bills].sort((a, b) => a.dayOfMonth - b.dayOfMonth)
  const monthlyTotal = bills.reduce((s, b) => s + b.amount, 0)
  const annualTotal = monthlyTotal * 12

  const submit = () => {
    const amt = parseFloat(amount)
    const d = parseInt(day, 10)
    if (!name.trim() || isNaN(amt) || isNaN(d)) return
    addBill(name, amt, Math.min(31, Math.max(1, d)))
    setName('')
    setAmount('')
    setDay('1')
    setSheet(false)
  }

  const openEdit = (bill: Bill) => {
    setEditBill(bill)
    setEditName(bill.name)
    setEditAmount(String(bill.amount))
    setEditDay(String(bill.dayOfMonth))
  }

  const submitEdit = () => {
    if (!editBill) return
    const amt = parseFloat(editAmount)
    const d = parseInt(editDay, 10)
    if (!editName.trim() || isNaN(amt) || isNaN(d)) return
    updateBill(editBill.id, { name: editName.trim(), amount: amt, dayOfMonth: Math.min(31, Math.max(1, d)) })
    setEditBill(null)
  }

  const handleDelete = (bill: Bill) => {
    deleteBill(bill.id)
    setDeletedBill(bill)
    if (undoTimer.current) clearTimeout(undoTimer.current)
    undoTimer.current = window.setTimeout(() => setDeletedBill(null), 4000)
  }

  const handleUndo = () => {
    if (deletedBill) restoreBill(deletedBill)
  }

  return (
    <div>
      <LargeTitleHeader
        title="Money"
        trailing={<IconButton icon={Plus} label="Add direct debit" accent onClick={() => setSheet(true)} />}
      />

      {/* Hero total */}
      <div className="mb-5 mt-2 overflow-hidden rounded-card bg-gradient-accent p-5 shadow-card">
        <div className="text-footnote font-medium text-white/80">Monthly direct debits</div>
        <div className="tabular mt-0.5 text-title1 text-white">{fmt(monthlyTotal)}</div>
        <div className="mt-1 text-footnote text-white/80">
          {bills.length} payment{bills.length === 1 ? '' : 's'} · {fmt(annualTotal)}/yr
        </div>
      </div>

      {bills.length > 0 && (
        <>
          <SectionLabel>Calendar</SectionLabel>
          <BillCalendar bills={bills} onSelectDay={(day, b) => setSelectedDay({ day, bills: b })} />
          <SectionLabel>All payments</SectionLabel>
        </>
      )}

      {bills.length === 0 ? (
        <EmptyState icon={Wallet} title="No direct debits yet" subtitle="Add what leaves your account each month so nothing surprises you." />
      ) : (
        <motion.div
          layout
          className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70"
        >
          <AnimatePresence initial={false}>
            {bills.map((b) => (
              <BillRow key={b.id} bill={b} onDelete={() => handleDelete(b)} onEdit={() => openEdit(b)} />
            ))}
          </AnimatePresence>
        </motion.div>
      )}

      <p className="mt-4 text-center text-caption text-label3">Tap to edit · Swipe left to delete</p>

      {/* Add sheet */}
      <Sheet open={sheet} onClose={() => setSheet(false)} title="New direct debit">
        <BillForm
          name={name} amount={amount} day={day}
          onName={setName} onAmount={setAmount} onDay={setDay}
          onSubmit={submit} submitLabel="Save"
          disabled={!name.trim() || !amount}
        />
      </Sheet>

      {/* Edit sheet */}
      <Sheet open={!!editBill} onClose={() => setEditBill(null)} title="Edit direct debit">
        <BillForm
          name={editName} amount={editAmount} day={editDay}
          onName={setEditName} onAmount={setEditAmount} onDay={setEditDay}
          onSubmit={submitEdit} submitLabel="Save changes"
          disabled={!editName.trim() || !editAmount}
        />
      </Sheet>

      {/* Day detail sheet */}
      <Sheet
        open={!!selectedDay}
        onClose={() => setSelectedDay(null)}
        title={selectedDay ? `Due on the ${ordinal(selectedDay.day)}` : undefined}
      >
        {selectedDay && (
          <div className="space-y-2">
            {selectedDay.bills.map((b) => (
              <div key={b.id} className="flex items-center justify-between rounded-card bg-surface px-4 py-3 shadow-card">
                <span className="text-body text-label">{b.name}</span>
                <span className="tabular text-body font-medium text-label">{fmt(b.amount)}</span>
              </div>
            ))}
            <div className="flex items-center justify-between px-4 pt-1 text-label2">
              <span className="text-subhead">Total this day</span>
              <span className="tabular text-subhead font-semibold">
                {fmt(selectedDay.bills.reduce((s, b) => s + b.amount, 0))}
              </span>
            </div>
          </div>
        )}
      </Sheet>

      <AnimatePresence>
        {deletedBill && (
          <Toast
            message={`"${deletedBill.name}" deleted`}
            onUndo={handleUndo}
            onDismiss={() => setDeletedBill(null)}
          />
        )}
      </AnimatePresence>
    </div>
  )
}

function BillForm({
  name, amount, day,
  onName, onAmount, onDay,
  onSubmit, submitLabel, disabled,
}: {
  name: string; amount: string; day: string
  onName: (v: string) => void; onAmount: (v: string) => void; onDay: (v: string) => void
  onSubmit: () => void; submitLabel: string; disabled: boolean
}) {
  return (
    <div className="space-y-3">
      <input
        autoFocus
        value={name}
        onChange={(e) => onName(e.target.value)}
        placeholder="Name (e.g. Netflix)"
        className="w-full rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
      />
      <div className="flex gap-3">
        <input
          value={amount}
          onChange={(e) => onAmount(e.target.value)}
          inputMode="decimal"
          placeholder="Amount £"
          className="w-1/2 rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
        />
        <input
          value={day}
          onChange={(e) => onDay(e.target.value)}
          inputMode="numeric"
          placeholder="Day of month"
          className="w-1/2 rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
        />
      </div>
      <motion.button
        whileTap={{ scale: 0.97 }}
        transition={spring}
        onClick={onSubmit}
        disabled={disabled}
        className="w-full rounded-card bg-gradient-accent py-3.5 text-headline text-white disabled:opacity-40"
      >
        {submitLabel}
      </motion.button>
    </div>
  )
}

function ordinal(n: number): string {
  const s = ['th', 'st', 'nd', 'rd']
  const v = n % 100
  return n + (s[(v - 20) % 10] || s[v] || s[0])
}
