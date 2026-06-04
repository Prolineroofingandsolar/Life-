import Foundation

// MARK: - Widget Habit Model

struct WidgetHabit: Codable, Identifiable {
    let id: String
    let name: String
    let emoji: String
    let category: String
    let kind: String          // "build" | "break"
    let targetType: String    // "yesNo" | "count" | "timer"
    let targetCount: Int
    let targetUnit: String
    let currentCount: Int
    let isCompleted: Bool
    let isSlipped: Bool
    let streak: Int
    let progress: Double      // 0.0 – 1.0
}

// MARK: - Shared Habit Store

enum SharedHabitStore {
    static let appGroup = "group.uk.co.prolineroofingandsolar.life"
    static let habitsKey = "life_widget_habits_v1"
    static let pendingKey = "life_pending_completions_v1"
    static let pendingDateKey = "life_pending_completions_date"

    // MARK: Write (called from main app AppState.save)

    static func write(_ habits: [WidgetHabit]) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        if let data = try? JSONEncoder().encode(habits) {
            defaults.set(data, forKey: habitsKey)
        }
    }

    static func read() -> [WidgetHabit] {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: habitsKey),
              let habits = try? JSONDecoder().decode([WidgetHabit].self, from: data) else { return [] }
        return habits
    }

    // MARK: Pending completions (written by widget Intent, read by main app)

    static func completeHabit(id: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let today = todayKey()
        // Reset list if it's from a different day
        if defaults.string(forKey: pendingDateKey) != today {
            defaults.set(today, forKey: pendingDateKey)
            defaults.set([String](), forKey: pendingKey)
        }
        var pending = (defaults.array(forKey: pendingKey) as? [String]) ?? []
        if !pending.contains(id) { pending.append(id) }
        defaults.set(pending, forKey: pendingKey)
        // Widget reload is triggered by the caller (CompleteHabitIntent or AppState.syncHabitsToWidget)
    }

    static func popPendingCompletions() -> [String] {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return [] }
        let today = todayKey()
        guard defaults.string(forKey: pendingDateKey) == today else { return [] }
        let pending = (defaults.array(forKey: pendingKey) as? [String]) ?? []
        defaults.set([String](), forKey: pendingKey)
        return pending
    }

    static func pendingIDs() -> Set<String> {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return [] }
        let today = todayKey()
        guard defaults.string(forKey: pendingDateKey) == today else { return [] }
        return Set((defaults.array(forKey: pendingKey) as? [String]) ?? [])
    }

    private static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
