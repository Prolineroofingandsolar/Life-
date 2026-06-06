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

    // MARK: - Habit Shape (matches SharedHabitStore.WidgetHabit exactly)

    private struct WidgetHabit: Codable {
        let id: String
        let name: String
        let emoji: String
        let category: String
        let kind: String
        let targetType: String
        let targetCount: Int
        let targetUnit: String
        let currentCount: Int
        let isCompleted: Bool
        let isSlipped: Bool
        let streak: Int
        let progress: Double
    }

    private static let habitsDefaultsKey = "life_widget_habits_v1"

    // MARK: - Sync Habits

    static func syncHabits(habits: [Habit], todayKey: String) {
        let widgetHabits: [WidgetHabit] = habits.filter { !$0.isArchived }.map { habit in
            let log = habit.logs.first { $0.dayKey == todayKey }
            let currentCount = log?.count ?? 0
            let isSlipped = log?.slipped ?? false
            let isCompleted = !isSlipped && currentCount >= habit.targetCount
            let progress = habit.targetCount > 0
                ? min(1.0, Double(currentCount) / Double(habit.targetCount))
                : 0.0
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
        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(data, forKey: habitsDefaultsKey)
            defaults.synchronize()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func streakFor(_ habit: Habit) -> Int {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        var count = 0
        var date = cal.startOfDay(for: Date())
        while true {
            let key = fmt.string(from: date)
            if let log = habit.logs.first(where: { $0.dayKey == key }),
               log.count >= habit.targetCount, !log.slipped {
                count += 1
                date = cal.date(byAdding: .day, value: -1, to: date) ?? date
            } else { break }
        }
        return count
    }
}
