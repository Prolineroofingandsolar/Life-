import AppIntents
import WidgetKit

// MARK: - Complete Habit Intent (iOS 17+ interactive widget)

struct CompleteHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Habit"
    static var description = IntentDescription("Mark a habit as complete for today.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Habit ID")
    var habitId: String

    init() { self.habitId = "" }
    init(habitId: String) { self.habitId = habitId }

    func perform() async throws -> some IntentResult {
        SharedHabitStore.completeHabit(id: habitId)
        WidgetCenter.shared.reloadTimelines(ofKind: "LifeHabitsWidget")
        return .result()
    }
}
