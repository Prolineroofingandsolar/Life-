import { motion } from 'framer-motion'
import type { ComponentType } from 'react'
import type { LucideProps } from 'lucide-react'
import { spring } from '../lib/motion'

export interface TabDef<T extends string> {
  id: T
  label: string
  icon: ComponentType<LucideProps>
}

export default function TabBar<T extends string>({
  tabs,
  active,
  onChange,
}: {
  tabs: TabDef<T>[]
  active: T
  onChange: (id: T) => void
}) {
  return (
    <nav className="material safe-bottom fixed inset-x-0 bottom-0 z-30 mx-auto max-w-app border-t border-separator/60">
      <div className="flex">
        {tabs.map((t) => {
          const on = t.id === active
          const Icon = t.icon
          return (
            <button
              key={t.id}
              onClick={() => onChange(t.id)}
              className="flex flex-1 flex-col items-center gap-0.5 pb-1.5 pt-2"
            >
              <motion.span
                animate={{ scale: on ? 1.06 : 1, y: on ? -1 : 0 }}
                transition={spring}
                className={on ? 'text-accent' : 'text-label3'}
              >
                <Icon size={25} strokeWidth={on ? 2.4 : 2} />
              </motion.span>
              <span className={`text-[10px] font-medium ${on ? 'text-accent' : 'text-label3'}`}>{t.label}</span>
            </button>
          )
        })}
      </div>
    </nav>
  )
}
