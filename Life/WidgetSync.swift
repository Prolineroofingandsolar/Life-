import Foundation
import WidgetKit

// MARK: - Widget Sync

/// Syncs today's undone tasks to the shared App Group so the widget can read them.
/// Uses the same JSON format as LifeTasksWidget expects: [{id, title, category, done, dueDate, priority}]

enum WidgetSync {

    private static let appGroup = "group.uk.co.prolineroofingandsolar.life"
    private static let defaultsKey = "life_widget_tasks"
    private static let fileName = "life_tasks.json"

    // MARK: - Widget Task Shape

    private struct WidgetTask: Codable {
        let id: String
        let title: String
        let category: String
        let done: Bool
        let dueDate: String?
        let priority: String
    }

    // MARK: - Sync

    static func sync(tasks: [AppTask]) {
        let widgetTasks = tasks.map { task in
            WidgetTask(
                id: task.id,
                title: task.title,
                category: task.category.rawValue,
                done: task.done,
                dueDate: task.dueDate?.rawValue,
                priority: task.priority.rawValue
            )
        }

        guard let data = try? JSONEncoder().encode(widgetTasks) else { return }
        let jsonString = String(data: data, encoding: .utf8)

        // Write to App Group UserDefaults
        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(jsonString, forKey: defaultsKey)
            defaults.synchronize()
        }

        // Write to shared file
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            let fileURL = containerURL.appendingPathComponent(fileName)
            try? data.write(to: fileURL, options: .atomic)
        }

        // Tell WidgetKit to refresh immediately
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Habit Shape

    struct WidgetHabit: Codable {
        let id: String
        let name: String
        let emoji: String
        let completedToday: Bool
    }

    private static let habitsDefaultsKey = "life_widget_habits"
    private static let habitsFileName = "life_habits.json"

    // MARK: - Sync Habits

    static func syncHabits(habits: [Habit], todayKey: String) {
        let widgetHabits = habits.filter { !$0.isArchived }.map { habit in
            let todayLog = habit.logs.first { $0.dayKey == todayKey }
            let completedToday: Bool
            if habit.kind == .break {
                completedToday = todayLog?.slipped != true
            } else {
                completedToday = todayLog.map { !$0.slipped && $0.count >= habit.targetCount } ?? false
            }
            return WidgetHabit(id: habit.id, name: habit.name, emoji: habit.emoji, completedToday: completedToday)
        }

        guard let data = try? JSONEncoder().encode(widgetHabits) else { return }
        let jsonString = String(data: data, encoding: .utf8)

        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(jsonString, forKey: habitsDefaultsKey)
            defaults.synchronize()
        }

        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            let fileURL = containerURL.appendingPathComponent(habitsFileName)
            try? data.write(to: fileURL, options: .atomic)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
