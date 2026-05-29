/**
 * Thin wrapper around the Web Notifications API.
 *
 * Note for the iPhone build: notifications only work once "Life" is added to
 * the Home Screen (installed as a PWA) on iOS 16.4+. In a normal Safari tab
 * iOS will report "denied". On desktop browsers they work in the tab.
 */

export function notificationsSupported(): boolean {
  return typeof window !== 'undefined' && 'Notification' in window
}

export function notificationPermission(): NotificationPermission {
  if (!notificationsSupported()) return 'denied'
  return Notification.permission
}

export async function requestNotifications(): Promise<NotificationPermission> {
  if (!notificationsSupported()) return 'denied'
  try {
    return await Notification.requestPermission()
  } catch {
    return Notification.permission
  }
}

export function notify(title: string, body: string) {
  if (!notificationsSupported() || Notification.permission !== 'granted') return
  try {
    new Notification(title, { body, icon: '/icon-192.png', badge: '/icon-192.png' })
  } catch {
    /* Some browsers require notifications to come from the service worker; ignore. */
  }
}
