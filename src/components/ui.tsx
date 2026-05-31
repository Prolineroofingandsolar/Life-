import { useEffect, useRef, useState } from 'react'
import type { ComponentType, ReactNode } from 'react'
import { motion } from 'framer-motion'
import type { LucideProps } from 'lucide-react'
import { spring, pressable } from '../lib/motion'

type Icon = ComponentType<LucideProps>

/* ----------------------------- Large title ----------------------------- */

export function LargeTitleHeader({
  title,
  trailing,
}: {
  title: string
  trailing?: ReactNode
}) {
  const sentinel = useRef<HTMLDivElement>(null)
  const [collapsed, setCollapsed] = useState(false)

  useEffect(() => {
    const el = sentinel.current
    if (!el) return
    const io = new IntersectionObserver(([e]) => setCollapsed(!e.isIntersecting), {
      rootMargin: '-52px 0px 0px 0px',
      threshold: 0,
    })
    io.observe(el)
    return () => io.disconnect()
  }, [])

  return (
    <>
      <div
        className={`material safe-top sticky top-0 z-20 -mx-4 px-4 ${
          collapsed ? 'border-b border-separator/60' : ''
        }`}
      >
        <div className="relative flex h-11 items-center justify-center">
          <motion.span
            className="text-headline"
            initial={false}
            animate={{ opacity: collapsed ? 1 : 0, y: collapsed ? 0 : 4 }}
            transition={spring}
          >
            {title}
          </motion.span>
          {trailing && <div className="absolute right-0">{trailing}</div>}
        </div>
      </div>
      <h1 className="mt-1 text-largetitle">{title}</h1>
      <div ref={sentinel} className="h-px w-full" />
    </>
  )
}

/* ------------------------------ Section label ------------------------------ */

export function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <div className="mb-2 ml-4 mt-5 flex items-center gap-2">
      <span
        className="h-1.5 w-1.5 shrink-0 rounded-full"
        style={{ background: 'rgb(var(--accent) / 0.55)' }}
      />
      <p className="text-footnote font-semibold uppercase tracking-wider text-label2">{children}</p>
    </div>
  )
}

/* ------------------------------- Cards ------------------------------- */

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={`rounded-card bg-surface shadow-card ${className}`}
      style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
    >
      {children}
    </div>
  )
}

export function GlassCard({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`glass rounded-xl2 ${className}`}>{children}</div>
}

export function PressableCard({
  children,
  className = '',
  onClick,
}: {
  children: ReactNode
  className?: string
  onClick?: () => void
}) {
  return (
    <motion.button
      {...pressable}
      onClick={onClick}
      className={`block w-full rounded-card bg-surface text-left shadow-card ${className}`}
      style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
    >
      {children}
    </motion.button>
  )
}

/* ----------------------------- List group ----------------------------- */

export function ListGroup({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={`overflow-hidden rounded-card bg-surface shadow-card ${className}`}
      style={{ border: '0.5px solid rgb(var(--separator) / 0.5)' }}
    >
      {children}
    </div>
  )
}

export function ListRow({
  icon: IconC,
  iconColor,
  title,
  subtitle,
  trailing,
  onClick,
}: {
  icon?: Icon
  iconColor?: string
  title: ReactNode
  subtitle?: ReactNode
  trailing?: ReactNode
  onClick?: () => void
}) {
  const inner = (
    <div className="relative flex min-h-[52px] items-center gap-3 px-4 py-2.5 before:absolute before:left-4 before:right-0 before:top-0 before:h-px before:bg-separator/60 before:content-[''] first:before:hidden">
      {IconC && (
        <span
          className="grid h-7 w-7 shrink-0 place-items-center rounded-[7px]"
          style={{ background: iconColor ?? 'rgb(var(--fill))' }}
        >
          <IconC size={17} className="text-white" strokeWidth={2.4} />
        </span>
      )}
      <div className="min-w-0 flex-1">
        <div className="truncate text-body text-label">{title}</div>
        {subtitle && <div className="truncate text-footnote text-label2">{subtitle}</div>}
      </div>
      {trailing && <div className="shrink-0 text-label2">{trailing}</div>}
    </div>
  )
  if (onClick) {
    return (
      <motion.button whileTap={{ backgroundColor: 'rgb(var(--fill))' }} onClick={onClick} className="block w-full text-left">
        {inner}
      </motion.button>
    )
  }
  return inner
}

/* ------------------------------- Switch ------------------------------- */

export function Switch({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`relative h-[31px] w-[51px] rounded-full transition-colors ${checked ? 'bg-move' : 'bg-fill'}`}
    >
      <motion.span
        initial={false}
        animate={{ left: checked ? 22 : 2 }}
        transition={spring}
        className="absolute top-[2px] h-[27px] w-[27px] rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.25)]"
      />
    </button>
  )
}

/* ------------------------------ Stepper ------------------------------ */

export function Stepper({
  value,
  onChange,
  step = 1,
  min = 1,
  max = 999,
}: {
  value: number
  onChange: (v: number) => void
  step?: number
  min?: number
  max?: number
}) {
  return (
    <div className="flex items-center overflow-hidden rounded-[8px] bg-fill">
      <motion.button
        whileTap={{ scale: 0.9 }}
        onClick={() => onChange(Math.max(min, value - step))}
        className="grid h-8 w-11 place-items-center text-title3 text-label active:bg-separator/40"
        aria-label="decrease"
      >
        −
      </motion.button>
      <span className="h-5 w-px bg-separator/70" />
      <motion.button
        whileTap={{ scale: 0.9 }}
        onClick={() => onChange(Math.min(max, value + step))}
        className="grid h-8 w-11 place-items-center text-title3 text-label active:bg-separator/40"
        aria-label="increase"
      >
        +
      </motion.button>
    </div>
  )
}

/* -------------------------- Segmented control -------------------------- */

export function SegmentedControl<T extends string>({
  value,
  onChange,
  options,
  layoutId,
}: {
  value: T
  onChange: (v: T) => void
  options: { value: T; label: string }[]
  layoutId: string
}) {
  return (
    <div className="flex rounded-[9px] bg-fill p-[2px]">
      {options.map((o) => {
        const active = o.value === value
        return (
          <button
            key={o.value}
            onClick={() => onChange(o.value)}
            className="relative flex-1 rounded-[7px] px-3 py-1.5 text-subhead font-medium"
          >
            {active && (
              <motion.span
                layoutId={layoutId}
                transition={spring}
                className="absolute inset-0 rounded-[7px] bg-surface shadow-[0_1px_3px_rgba(0,0,0,0.12)]"
              />
            )}
            <span className={`relative z-10 ${active ? 'text-label' : 'text-label2'}`}>{o.label}</span>
          </button>
        )
      })}
    </div>
  )
}

/* ----------------------------- Icon button ----------------------------- */

export function IconButton({
  icon: IconC,
  onClick,
  label,
  accent,
}: {
  icon: Icon
  onClick?: () => void
  label: string
  accent?: boolean
}) {
  return (
    <motion.button
      {...pressable}
      onClick={onClick}
      aria-label={label}
      className={`grid h-9 w-9 place-items-center rounded-full ${
        accent ? 'bg-accent/10 text-accent' : 'text-label2'
      }`}
    >
      <IconC size={22} strokeWidth={2} />
    </motion.button>
  )
}

/* ----------------------------- Empty state ----------------------------- */

export function EmptyState({ icon: IconC, title, subtitle }: { icon: Icon; title: string; subtitle?: string }) {
  return (
    <div className="flex flex-col items-center justify-center px-8 py-16 text-center">
      <span
        className="mb-4 grid h-16 w-16 place-items-center rounded-2xl text-label3"
        style={{
          background: 'linear-gradient(135deg, rgb(var(--fill)), rgb(var(--surface-2)))',
          border: '0.5px solid rgb(var(--separator) / 0.5)',
        }}
      >
        <IconC size={30} strokeWidth={1.75} />
      </span>
      <p className="text-headline text-label">{title}</p>
      {subtitle && <p className="mt-1 max-w-xs text-subhead text-label2">{subtitle}</p>}
    </div>
  )
}
