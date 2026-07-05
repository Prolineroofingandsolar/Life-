import Foundation
import UserNotifications

// MARK: - Authorization Helper

extension UNUserNotificationCenter {
    /// Requests notification authorization on first use, then adds the
    /// request. Previously only the water-reminder toggle in Settings ever
    /// called `requestAuthorization`, so task and habit reminders scheduled
    /// elsewhere silently never surfaced for anyone who hadn't touched that
    /// toggle — the system never showed the permission prompt.
    func addRequestEnsuringAuthorization(_ request: UNNotificationRequest) {
        Task {
            let settings = await notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await requestAuthorization(options: [.alert, .sound, .badge])
            }
            try? await add(request)
        }
    }
}

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

    func cancelWaterReminder() {
        center.removePendingNotificationRequests(withIdentifiers: ["water_reminder"])
        center.removeDeliveredNotifications(withIdentifiers: ["water_reminder"])
    }

    func scheduleWaterReminder(intervalMinutes: Int) {
        cancelWaterReminder()

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

        center.addRequestEnsuringAuthorization(request)
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

        center.addRequestEnsuringAuthorization(request)
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
        center.addRequestEnsuringAuthorization(request)
    }

    func cancelRestTimer() {
        center.removePendingNotificationRequests(withIdentifiers: ["rest_timer"])
    }

    // MARK: - Task Reminder (one-shot)

    func scheduleTaskReminder(taskId: String, title: String, at date: Date) {
        let identifier = "task_reminder_\(taskId)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = title
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.addRequestEnsuringAuthorization(request)
    }

    func cancelTaskReminder(taskId: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["task_reminder_\(taskId)"])
    }

    // MARK: - Cancel All

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
