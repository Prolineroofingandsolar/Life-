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
    // Field names MUST match the widget's `WidgetHabit` decoder
    // (LifeTasksWidget/SharedHabitStore.swift) or decoding fails and the widget
    // falls back to placeholder data.

    struct WidgetHabit: Codable {
        let id: String
        let name: String
        let emoji: String
        let category: String
        let kind: String          // "build" | "break"
        let targetType: String
        let targetCount: Int
        let targetUnit: String
        let currentCount: Int
        let isCompleted: Bool
        let isSlipped: Bool
        let streak: Int
        let progress: Double
    }

    private static let habitsDefaultsKey = "life_widget_habits"
    private static let habitsFileName = "life_habits.json"

    // MARK: - Sync Habits

    static func syncHabits(habits: [Habit], todayKey: String, streakFor: (Habit) -> Int) {
        let widgetHabits = habits.filter { !$0.isArchived }.map { habit -> WidgetHabit in
            let todayLog = habit.logs.first { $0.dayKey == todayKey }
            let currentCount = todayLog?.count ?? 0
            let isSlipped = todayLog?.slipped == true
            let isCompleted: Bool
            if habit.kind == .break {
                isCompleted = !isSlipped
            } else {
                isCompleted = !isSlipped && currentCount >= habit.targetCount
            }
            let progress: Double = habit.targetCount > 0
                ? min(1.0, Double(currentCount) / Double(habit.targetCount))
                : (isCompleted ? 1.0 : 0.0)
            return WidgetHabit(
                id: habit.id,
                name: habit.name,
                emoji: habit.emoji,
                category: habit.category.rawValue,
                kind: habit.kind.rawValue,
                targetType: habit.targetType.rawValue,
                targetCount: habit.targetCount,
                targetUnit: habit.targetUnit,
                currentCount: currentCount,
                isCompleted: isCompleted,
                isSlipped: isSlipped,
                streak: streakFor(habit),
                progress: progress
            )
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
