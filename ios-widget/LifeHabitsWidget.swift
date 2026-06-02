import WidgetKit
import SwiftUI

// Paste this file into your widget extension target alongside LifeTasksWidget.swift

// MARK: - Model

struct WidgetHabit: Codable, Identifiable {
    let id: String
    let name: String
    let emoji: String
    let done: Bool
    let count: Int
    let targetCount: Int
    let kind: String
}

// MARK: - Provider

struct HabitsProvider: TimelineProvider {
    let appGroup = "group.uk.co.prolineroofingandsolar.life"

    func habits() -> [WidgetHabit] {
        if let defaults = UserDefaults(suiteName: appGroup),
           let json = defaults.string(forKey: "life_widget_habits"),
           let data = json.data(using: .utf8),
           let habits = try? JSONDecoder().decode([WidgetHabit].self, from: data) {
            return habits
        }
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ),
           let data = try? Data(contentsOf: containerURL.appendingPathComponent("life_habits.json")),
           let habits = try? JSONDecoder().decode([WidgetHabit].self, from: data) {
            return habits
        }
        return []
    }

    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: Date(), habits: [
            WidgetHabit(id: "1", name: "Drink water", emoji: "💧", done: true,  count: 8, targetCount: 8, kind: "build"),
            WidgetHabit(id: "2", name: "Morning walk", emoji: "🚶", done: false, count: 0, targetCount: 1, kind: "build"),
            WidgetHabit(id: "3", name: "Read",         emoji: "📖", done: false, count: 0, targetCount: 1, kind: "build"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        let h = habits()
        completion(HabitsEntry(date: Date(), habits: h.isEmpty ? placeholder(in: context).habits : h))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let entry = HabitsEntry(date: Date(), habits: habits())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct HabitsEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabit]
}

// MARK: - Views

struct HabitRow: View {
    let habit: WidgetHabit

    var body: some View {
        HStack(spacing: 8) {
            Text(habit.emoji)
                .font(.system(size: 16))
            Text(habit.name)
                .font(.system(size: 13))
                .foregroundColor(habit.done ? .secondary : .primary)
                .strikethrough(habit.done)
                .lineLimit(1)
            Spacer()
            if habit.targetCount > 1 {
                Text("\(habit.count)/\(habit.targetCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Image(systemName: habit.done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(habit.done ? Color(red: 0.19, green: 0.82, blue: 0.35) : .secondary)
                .font(.system(size: 14))
        }
    }
}

struct HabitsSmallView: View {
    let habits: [WidgetHabit]

    var doneCount: Int { habits.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Habits")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(doneCount)/\(habits.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            if habits.isEmpty {
                Spacer()
                Text("No habits yet")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(habits.prefix(3)) { habit in
                    HabitRow(habit: habit)
                }
                if habits.count > 3 {
                    Text("+\(habits.count - 3) more")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

struct HabitsMediumView: View {
    let habits: [WidgetHabit]

    var doneCount: Int { habits.filter(\.done).count }
    var progress: Double { habits.isEmpty ? 0 : Double(doneCount) / Double(habits.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's Habits")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(doneCount) of \(habits.count) done")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 6)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.19, green: 0.82, blue: 0.35))
                        .frame(width: geo.size.width * progress, height: 5)
                }
            }
            .frame(height: 5)
            .padding(.bottom, 10)

            if habits.isEmpty {
                Spacer()
                Text("No habits yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(habits.prefix(4)) { habit in
                    HabitRow(habit: habit)
                        .padding(.vertical, 3)
                    if habit.id != habits.prefix(4).last?.id {
                        Divider().opacity(0.4)
                    }
                }
                if habits.count > 4 {
                    Text("+\(habits.count - 4) more")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Entry View

struct LifeHabitsWidgetEntryView: View {
    var entry: HabitsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            HabitsSmallView(habits: entry.habits)
        default:
            HabitsMediumView(habits: entry.habits)
        }
    }
}

// MARK: - Widget

struct LifeHabitsWidget: Widget {
    let kind: String = "LifeHabitsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitsProvider()) { entry in
            LifeHabitsWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Life Habits")
        .description("Track today's habits at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
