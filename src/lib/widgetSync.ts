import { registerPlugin } from '@capacitor/core'
import { Capacitor } from '@capacitor/core'

interface LifePluginInterface {
  syncTasks(options: { tasksJSON: string }): Promise<void>
}

const LifePlugin = registerPlugin<LifePluginInterface>('LifePlugin')

export interface WidgetTask {
  id: string
  title: string
  category: 'work' | 'gym' | 'personal'
  dueDate?: string
  done: boolean
}

export async function syncTasksToWidget(tasks: WidgetTask[]) {
  if (!Capacitor.isNativePlatform()) return
  try {
    const today = tasks.filter((t) => t.dueDate === 'today' && !t.done)
    await LifePlugin.syncTasks({ tasksJSON: JSON.stringify(today) })
  } catch {
    // plugin not available yet — silently ignore
  }
}
