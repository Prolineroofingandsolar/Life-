import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import type { ReactNode } from 'react'

export type ThemeMode = 'auto' | 'light' | 'dark'

const KEY = 'life.theme'

interface ThemeCtx {
  mode: ThemeMode
  /** The actually-applied theme after resolving 'auto'. */
  resolved: 'light' | 'dark'
  setMode: (m: ThemeMode) => void
}

const Ctx = createContext<ThemeCtx | null>(null)

function systemPrefersDark() {
  return typeof matchMedia !== 'undefined' && matchMedia('(prefers-color-scheme: dark)').matches
}

function apply(resolved: 'light' | 'dark') {
  document.documentElement.classList.toggle('dark', resolved === 'dark')
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta) meta.setAttribute('content', resolved === 'dark' ? '#000000' : '#f2f2f7')
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [mode, setModeState] = useState<ThemeMode>(() => (localStorage.getItem(KEY) as ThemeMode) || 'auto')
  const [systemDark, setSystemDark] = useState(systemPrefersDark)

  // Track the OS setting so 'auto' stays live.
  useEffect(() => {
    const mq = matchMedia('(prefers-color-scheme: dark)')
    const onChange = (e: MediaQueryListEvent) => setSystemDark(e.matches)
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])

  const resolved: 'light' | 'dark' = mode === 'auto' ? (systemDark ? 'dark' : 'light') : mode

  useEffect(() => {
    apply(resolved)
  }, [resolved])

  const setMode = useCallback((m: ThemeMode) => {
    setModeState(m)
    localStorage.setItem(KEY, m)
  }, [])

  return <Ctx.Provider value={{ mode, resolved, setMode }}>{children}</Ctx.Provider>
}

export function useTheme() {
  const c = useContext(Ctx)
  if (!c) throw new Error('useTheme must be used within ThemeProvider')
  return c
}
