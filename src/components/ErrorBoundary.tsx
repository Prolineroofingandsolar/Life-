import { Component } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import { RefreshCw } from 'lucide-react'

interface State { error: Error | null }

/** Catches unhandled render errors and shows a recovery UI instead of a blank screen. */
export default class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[Life] Uncaught error:', error, info.componentStack)
  }

  render() {
    if (this.state.error) {
      return (
        <div
          className="flex min-h-screen flex-col items-center justify-center px-8 text-center"
          style={{ background: 'rgb(var(--bg-grouped))' }}
        >
          <div
            className="mb-5 grid h-16 w-16 place-items-center rounded-2xl text-label3"
            style={{
              background: 'linear-gradient(135deg, rgb(var(--fill)), rgb(var(--surface-2)))',
              border: '0.5px solid rgb(var(--separator) / 0.5)',
            }}
          >
            <RefreshCw size={28} strokeWidth={1.75} />
          </div>
          <h1 className="mb-2 text-headline text-label">Something went wrong</h1>
          <p className="mb-6 max-w-xs text-subhead text-label2">
            An unexpected error occurred. Your data is safe — tap below to try again.
          </p>
          <button
            onClick={() => this.setState({ error: null })}
            className="rounded-xl bg-accent px-8 py-3 text-headline text-white"
          >
            Try again
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
