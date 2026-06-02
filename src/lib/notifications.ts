/**
 * Thin wrapper around the Web Notifications API.
 *
 * In the Capacitor (native iOS) build, Web Notifications work for in-app
 * nudges because WKWebView supports Notification.requestPermission() and
 * new Notification() on iOS 16.4+. Notifications delivered while the app is
 * in the background still require @capacitor/local-notifications — the nudges
 * in this app are intentionally in-app only (water, meals, breaks).
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
    // Some environments require notifications from a service worker; ignore silently.
  }
}
