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
                dueDate: task.dueDate.rawValue,
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
}
