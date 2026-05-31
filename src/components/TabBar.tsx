import type { ComponentType } from 'react'
import type { LucideProps } from 'lucide-react'

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
    <nav className="material safe-bottom shrink-0 border-t border-separator/40">
      <div className="flex">
        {tabs.map((t) => {
          const on = t.id === active
          const Icon = t.icon
          return (
            <button
              key={t.id}
              onClick={() => onChange(t.id)}
              className="relative flex flex-1 flex-col items-center gap-0.5 pb-2 pt-2"
            >
              {/* Static pill indicator */}
              {on && (
                <span className="absolute top-1 h-8 w-12 rounded-[10px] bg-accent/10" />
              )}
              <span className={`relative z-10 ${on ? 'text-accent' : 'text-label3'}`}>
                <Icon size={24} strokeWidth={on ? 2.3 : 1.8} />
              </span>
              <span
                className={`relative z-10 text-[10px] font-medium leading-none ${on ? 'text-accent' : 'text-label3'}`}
              >
                {t.label}
              </span>
            </button>
          )
        })}
      </div>
    </nav>
  )
}
