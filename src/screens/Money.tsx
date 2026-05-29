import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Plus, Trash2, Wallet } from 'lucide-react'
import { useLife } from '../lib/store'
import { LargeTitleHeader, IconButton, EmptyState } from '../components/ui'
import Sheet from '../components/Sheet'
import { billCountdown } from '../lib/date'
import { listItem, spring } from '../lib/motion'
import type { Bill } from '../lib/types'

const fmt = (n: number) => '£' + n.toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

function BillRow({ bill, onDelete }: { bill: Bill; onDelete: () => void }) {
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
        onDragEnd={(_, info) => info.offset.x < -72 && onDelete()}
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
      </motion.div>
    </motion.div>
  )
}

export default function Money() {
  const { state, addBill, deleteBill } = useLife()
  const [sheet, setSheet] = useState(false)
  const [name, setName] = useState('')
  const [amount, setAmount] = useState('')
  const [day, setDay] = useState('1')

  const bills = [...state.bills].sort((a, b) => a.dayOfMonth - b.dayOfMonth)
  const monthlyTotal = bills.reduce((s, b) => s + b.amount, 0)

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

  return (
    <div>
      <LargeTitleHeader
        title="Money"
        trailing={<IconButton icon={Plus} label="Add direct debit" accent onClick={() => setSheet(true)} />}
      />

      {/* Hero total */}
      <div className="mb-5 mt-2 overflow-hidden rounded-card bg-gradient-to-br from-accent to-[#9d7cff] p-5 shadow-card">
        <div className="text-footnote font-medium text-white/80">Monthly direct debits</div>
        <div className="tabular mt-0.5 text-title1 text-white">{fmt(monthlyTotal)}</div>
        <div className="mt-1 text-footnote text-white/80">
          {bills.length} regular payment{bills.length === 1 ? '' : 's'}
        </div>
      </div>

      {bills.length === 0 ? (
        <EmptyState icon={Wallet} title="No direct debits yet" subtitle="Add what leaves your account each month so nothing surprises you." />
      ) : (
        <motion.div
          layout
          className="overflow-hidden rounded-card bg-surface shadow-card [&>*+*]:border-t [&>*+*]:border-separator/70"
        >
          <AnimatePresence initial={false}>
            {bills.map((b) => (
              <BillRow key={b.id} bill={b} onDelete={() => deleteBill(b.id)} />
            ))}
          </AnimatePresence>
        </motion.div>
      )}

      <p className="mt-4 text-center text-caption text-label3">Swipe a payment left to delete</p>

      <Sheet open={sheet} onClose={() => setSheet(false)} title="New direct debit">
        <div className="space-y-3">
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Name (e.g. Netflix)"
            className="w-full rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
          />
          <div className="flex gap-3">
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              inputMode="decimal"
              placeholder="Amount £"
              className="w-1/2 rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
            />
            <input
              value={day}
              onChange={(e) => setDay(e.target.value)}
              inputMode="numeric"
              placeholder="Day of month"
              className="w-1/2 rounded-card bg-surface px-4 py-3.5 text-body text-label shadow-card placeholder:text-label3 focus:outline-none"
            />
          </div>
          <motion.button
            whileTap={{ scale: 0.97 }}
            transition={spring}
            onClick={submit}
            disabled={!name.trim() || !amount}
            className="w-full rounded-card bg-accent py-3.5 text-headline text-white disabled:opacity-40"
          >
            Save
          </motion.button>
        </div>
      </Sheet>
    </div>
  )
}
