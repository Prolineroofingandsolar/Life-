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
    <nav
      className="shrink-0 border-t border-separator/40"
      style={{
        background: 'rgb(var(--bg))',
        paddingBottom: 'max(env(safe-area-inset-bottom), 8px)',
        position: 'relative',
        zIndex: 10,
      }}
    >
      <div className="flex">
        {tabs.map((t) => {
          const on = t.id === active
          const Icon = t.icon
          return (
            <button
              key={t.id}
              onClick={() => onChange(t.id)}
              aria-current={on ? 'page' : undefined}
              aria-label={t.label}
              className="flex flex-1 flex-col items-center gap-0.5 pb-1 pt-3"
            >
              <span className={on ? 'text-accent' : 'text-label3'}>
                <Icon size={24} strokeWidth={on ? 2.3 : 1.8} />
              </span>
              <span className={`text-[10px] font-medium leading-none ${on ? 'text-accent' : 'text-label3'}`}>
                {t.label}
              </span>
            </button>
          )
        })}
      </div>
    </nav>
  )
}
