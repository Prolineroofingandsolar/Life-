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

    /// The widget only has bespoke color/emoji for these three default list
    /// ids (see LifeTasksWidget's `categoryColor`/`categoryEmoji`); a custom
    /// user-created list falls back to its own name so it's still
    /// recognizable instead of silently showing as "personal".
    private static let widgetKnownListIds: Set<String> = ["work", "gym", "personal"]

    static func sync(tasks: [AppTask], taskLists: [TaskList]) {
        let listsById = Dictionary(uniqueKeysWithValues: taskLists.map { ($0.id, $0) })
        let widgetTasks = tasks.map { task -> WidgetTask in
            let list = listsById[task.listId]
            let category = list.map { widgetKnownListIds.contains($0.id) ? $0.id : $0.name } ?? "personal"
            return WidgetTask(
                id: task.id,
                title: task.title,
                category: category,
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

    // MARK: - Coach Tip
    // Field names MUST match the widget's decoder
    // (LifeTasksWidget/SharedCoachTip.swift) or the widget silently shows its
    // placeholder instead.

    /// What the coach said, and who said it.
    ///
    /// `origin` is not decoration. The whole point of `CoachProvenance` is that
    /// a rule-written line is never shown under a label implying a model wrote
    /// it — and a widget is the one surface where that mistake would be hardest
    /// to notice, because there is no card, no explanation sheet and no Retry
    /// button next to it. So the origin travels with the words.
    ///
    /// Deliberately carries no health figures. A widget sits on a lock screen
    /// in full view of anyone holding the phone; "Your HRV is down 18%" is not
    /// something to put there, and the headline the coach writes is general
    /// enough not to be.
    struct WidgetCoachTip: Codable {
        let headline: String
        let summary: String
        /// "gemini" | "onDevice" | "offlineFallback" | "usageLimited".
        let origin: String
        let generatedAt: Date
    }

    private static let coachTipDefaultsKey = "life_widget_coach_tip"
    private static let coachTipFileName = "life_coach_tip.json"

    /// Writes the current tip, or clears it when there isn't one.
    ///
    /// Clearing matters: a stale tip left behind after the user switches AI off
    /// would keep a Gemini label on their lock screen for a feature they turned
    /// off, which is exactly the sort of thing provenance exists to prevent.
    static func syncCoachTip(_ tip: WidgetCoachTip?) {
        let defaults = UserDefaults(suiteName: appGroup)
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        )
        let fileURL = containerURL?.appendingPathComponent(coachTipFileName)

        guard let tip else {
            defaults?.removeObject(forKey: coachTipDefaultsKey)
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tip) else { return }

        defaults?.set(data, forKey: coachTipDefaultsKey)
        if let fileURL { try? data.write(to: fileURL, options: .atomic) }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
