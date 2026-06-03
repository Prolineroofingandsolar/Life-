import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct HabitEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabit]
    let pendingIDs: Set<String>
}

// MARK: - Timeline Provider

struct HabitProvider: AppIntentTimelineProvider {
    typealias Entry = HabitEntry
    typealias Intent = HabitWidgetConfigIntent

    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: Date(), habits: [
            WidgetHabit(id: "1", name: "Morning Run", emoji: "🏃", category: "fitness",
                        kind: "build", targetType: "yesNo", targetCount: 1, targetUnit: "",
                        currentCount: 0, isCompleted: false, isSlipped: false, streak: 5, progress: 0),
            WidgetHabit(id: "2", name: "Drink Water", emoji: "💧", category: "nutrition",
                        kind: "build", targetType: "count", targetCount: 8, targetUnit: "glasses",
                        currentCount: 5, isCompleted: false, isSlipped: false, streak: 3, progress: 0.625),
            WidgetHabit(id: "3", name: "Meditate", emoji: "🧘", category: "mindset",
                        kind: "build", targetType: "yesNo", targetCount: 1, targetUnit: "",
                        currentCount: 1, isCompleted: true, isSlipped: false, streak: 12, progress: 1),
        ], pendingIDs: [])
    }

    func snapshot(for config: HabitWidgetConfigIntent, in context: Context) async -> HabitEntry {
        let habits = SharedHabitStore.read()
        let pending = SharedHabitStore.pendingIDs()
        return HabitEntry(date: Date(), habits: habits.isEmpty ? placeholder(in: context).habits : habits, pendingIDs: pending)
    }

    func timeline(for config: HabitWidgetConfigIntent, in context: Context) async -> Timeline<HabitEntry> {
        let habits = SharedHabitStore.read()
        let pending = SharedHabitStore.pendingIDs()
        let entry = HabitEntry(date: Date(), habits: habits, pendingIDs: pending)
        let nextMidnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        return Timeline(entries: [entry], policy: .after(nextMidnight))
    }
}

// MARK: - Config Intent (required for AppIntentTimelineProvider)

struct HabitWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Habit Widget"
    static var description = IntentDescription("Shows your habits for today.")
}

// MARK: - Colours

private extension String {
    var habitCategoryColor: Color {
        switch self {
        case "health":       return Color(red: 1.0, green: 0.22, blue: 0.37)
        case "fitness":      return Color(red: 0.19, green: 0.82, blue: 0.35)
        case "mindset":      return Color(red: 0.75, green: 0.35, blue: 0.95)
        case "productivity": return Color(red: 1.0, green: 0.62, blue: 0.04)
        case "sleep":        return Color(red: 0.37, green: 0.60, blue: 0.95)
        case "nutrition":    return Color(red: 0.20, green: 0.67, blue: 0.90)
        default:             return Color(red: 0.39, green: 0.82, blue: 1.0)
        }
    }
}

// MARK: - Habit Row for Widget

private struct HabitWidgetRow: View {
    let habit: WidgetHabit
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Interactive checkbox
            Button(intent: CompleteHabitIntent(habitId: habit.id)) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color(red: 0.19, green: 0.82, blue: 0.35) : Color.secondary.opacity(0.2))
                        .frame(width: 26, height: 26)
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isCompleted)

            // Habit name — opens app when tapped
            Link(destination: URL(string: "life://habits/\(habit.id)")!) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(habit.emoji)
                            .font(.system(size: 14))
                        Text(habit.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    if habit.targetType == "count" && habit.targetCount > 1 {
                        Text("\(habit.currentCount)/\(habit.targetCount) \(habit.targetUnit)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Streak
            if habit.streak > 1 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("\(habit.streak)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Small Widget (progress ring + stats)

private struct SmallHabitWidgetView: View {
    let entry: HabitEntry

    private var completedCount: Int {
        entry.habits.filter { h in
            entry.pendingIDs.contains(h.id) || h.isCompleted
        }.count
    }
    private var total: Int { entry.habits.count }
    private var pct: Double { total == 0 ? 0 : Double(completedCount) / Double(total) }
    private var topStreak: Int { entry.habits.map(\.streak).max() ?? 0 }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(Color(red: 0.19, green: 0.82, blue: 0.35),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(completedCount)/\(total)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("done")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("\(topStreak)d streak")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(14)
    }
}

// MARK: - Medium Widget (habit list with interactive checkboxes)

private struct MediumHabitWidgetView: View {
    let entry: HabitEntry

    private var displayHabits: [WidgetHabit] { Array(entry.habits.prefix(4)) }
    private var completedCount: Int {
        entry.habits.filter { h in entry.pendingIDs.contains(h.id) || h.isCompleted }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's Habits")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(completedCount)/\(entry.habits.count)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            if entry.habits.isEmpty {
                Spacer()
                Text("No habits for today")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(displayHabits) { habit in
                    let isCompleted = entry.pendingIDs.contains(habit.id) || habit.isCompleted
                    HabitWidgetRow(habit: habit, isCompleted: isCompleted)
                        .padding(.vertical, 4)
                    if habit.id != displayHabits.last?.id {
                        Divider().opacity(0.4)
                    }
                }
                if entry.habits.count > 4 {
                    Text("+\(entry.habits.count - 4) more")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }
}

// MARK: - Lock Screen Widget (.accessoryRectangular)

private struct LockScreenHabitView: View {
    let entry: HabitEntry

    private var completedCount: Int {
        entry.habits.filter { h in entry.pendingIDs.contains(h.id) || h.isCompleted }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Habits")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("\(completedCount)/\(entry.habits.count) done")
                    .font(.system(size: 14, weight: .bold))
            }
            Spacer()
            if let first = entry.habits.first(where: { !(entry.pendingIDs.contains($0.id) || $0.isCompleted) }) {
                HStack(spacing: 4) {
                    Text(first.emoji)
                    Text(first.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Entry View

struct HabitWidgetEntryView: View {
    var entry: HabitEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallHabitWidgetView(entry: entry)
        case .systemMedium:
            MediumHabitWidgetView(entry: entry)
        case .accessoryRectangular:
            LockScreenHabitView(entry: entry)
        default:
            MediumHabitWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Definition

struct LifeHabitsWidget: Widget {
    let kind: String = "LifeHabitsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: HabitWidgetConfigIntent.self, provider: HabitProvider()) { entry in
            HabitWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Life Habits")
        .description("See and complete today's habits at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
