import Foundation
import UserNotifications

// MARK: - Notifications Manager

final class NotificationsManager {

    static let shared = NotificationsManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Water Reminder

    func scheduleWaterReminder(intervalMinutes: Int) {
        // Remove previous water reminders
        center.removePendingNotificationRequests(withIdentifiers: ["water_reminder"])
        center.removeDeliveredNotifications(withIdentifiers: ["water_reminder"])

        guard intervalMinutes > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to Hydrate 💧"
        content.body = "Don't forget to drink a glass of water!"
        content.sound = .default

        // Repeating trigger based on interval
        let triggerSeconds = TimeInterval(intervalMinutes * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerSeconds, repeats: true)

        let request = UNNotificationRequest(
            identifier: "water_reminder",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    // MARK: - Break Reminder

    func scheduleBreakReminder(intervalMinutes: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["break_reminder"])

        guard intervalMinutes > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Take a Break 🧘"
        content.body = "Time to step away from your screen for a moment."
        content.sound = .default

        let triggerSeconds = TimeInterval(intervalMinutes * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerSeconds, repeats: true)

        let request = UNNotificationRequest(
            identifier: "break_reminder",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    // MARK: - Rest Timer (one-shot)

    func scheduleRestTimerNotification(seconds: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["rest_timer"])

        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest Complete ✅"
        content.body = "Time for your next set!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(
            identifier: "rest_timer",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelRestTimer() {
        center.removePendingNotificationRequests(withIdentifiers: ["rest_timer"])
    }

    // MARK: - Cancel All

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
