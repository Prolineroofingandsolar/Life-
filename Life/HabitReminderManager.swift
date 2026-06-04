import Foundation
import UserNotifications

// MARK: - Habit Reminder Manager

final class HabitReminderManager {

    static let shared = HabitReminderManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Per-Habit Daily Reminder

    func scheduleReminder(for habit: Habit, at time: Date) {
        cancelReminder(habitId: habit.id)

        let content = UNMutableNotificationContent()
        content.title = "Time to \(habit.kind == .break ? "avoid" : "complete") your habit 💪"
        content.body = habit.name
        content.sound = .default
        content.categoryIdentifier = "HABIT_REMINDER"

        var comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: "habit_\(habit.id)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelReminder(habitId: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["habit_\(habitId)"])
        center.removeDeliveredNotifications(withIdentifiers: ["habit_\(habitId)"])
    }

    // MARK: - Batch Update (call when app launches or settings change)

    func syncReminders(for habits: [Habit]) {
        for habit in habits {
            if habit.isArchived || !habit.reminderEnabled {
                cancelReminder(habitId: habit.id)
            } else if let time = habit.reminderTime {
                scheduleReminder(for: habit, at: time)
            }
        }
    }

    // MARK: - Morning Summary (8 am)

    func scheduleMorningSummary(activeCount: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["habit_morning_summary"])
        guard activeCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Good morning! 🌅"
        content.body = "You have \(activeCount) habit\(activeCount == 1 ? "" : "s") to complete today."
        content.sound = .default

        var comps = DateComponents()
        comps.hour = 8
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "habit_morning_summary", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Evening Nudge (9 pm)

    func scheduleEveningNudge(unfinishedNames: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ["habit_evening_nudge"])
        guard !unfinishedNames.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Almost a perfect day! 🌙"
        let preview = unfinishedNames.prefix(2).joined(separator: ", ")
        let extra = unfinishedNames.count > 2 ? " and \(unfinishedNames.count - 2) more" : ""
        content.body = "Still to do: \(preview)\(extra)"
        content.sound = .default

        var comps = DateComponents()
        comps.hour = 21
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "habit_evening_nudge", content: content, trigger: trigger)
        center.add(request)
    }

    func cancelAll() {
        center.getPendingNotificationRequests { requests in
            let habitIds = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("habit_") }
            self.center.removePendingNotificationRequests(withIdentifiers: habitIds)
        }
    }
}
