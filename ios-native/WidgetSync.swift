import Foundation
import WidgetKit

// MARK: - Widget Sync

/// Syncs today's tasks and habits to the shared App Group so widgets can read them.

enum WidgetSync {

    private static let appGroup = "group.uk.co.prolineroofingandsolar.life"
    private static let tasksKey = "life_widget_tasks"
    private static let habitsKey = "life_widget_habits"
    private static let tasksFile = "life_tasks.json"
    private static let habitsFile = "life_habits.json"

    // MARK: - Widget Shapes

    private struct WidgetTask: Codable {
        let id: String
        let title: String
        let category: String
        let done: Bool
        let dueDate: String?
        let priority: String
    }

    private struct WidgetHabit: Codable {
        let id: String
        let name: String
        let emoji: String
        let done: Bool
        let count: Int
        let targetCount: Int
        let kind: String
    }

    // MARK: - Sync

    static func sync(tasks: [AppTask], habits: [Habit]) {
        syncTasks(tasks)
        syncHabits(habits)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func syncTasks(_ tasks: [AppTask]) {
        let widgetTasks = tasks.map { task in
            WidgetTask(
                id: task.id,
                title: task.title,
                category: task.category.rawValue,
                done: task.done,
                dueDate: task.dueDate.rawValue,
                priority: task.priority.rawValue
            )
        }
        write(widgetTasks, defaultsKey: tasksKey, fileName: tasksFile)
    }

    private static func syncHabits(_ habits: [Habit]) {
        let today = Date().dayKey
        let widgetHabits = habits
            .filter { !$0.isArchived && $0.cadence == .daily }
            .map { habit in
                let count = habit.logs.first { $0.dayKey == today }?.count ?? 0
                return WidgetHabit(
                    id: habit.id,
                    name: habit.name,
                    emoji: habit.emoji,
                    done: count >= habit.targetCount,
                    count: count,
                    targetCount: habit.targetCount,
                    kind: habit.kind.rawValue
                )
            }
        write(widgetHabits, defaultsKey: habitsKey, fileName: habitsFile)
    }

    private static func write<T: Encodable>(_ value: T, defaultsKey: String, fileName: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let jsonString = String(data: data, encoding: .utf8)

        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(jsonString, forKey: defaultsKey)
            defaults.synchronize()
        }

        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            try? data.write(to: containerURL.appendingPathComponent(fileName), options: .atomic)
        }
    }
}
