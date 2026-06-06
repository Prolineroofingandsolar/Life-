import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct HabitsProvider: TimelineProvider {

    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: Date(), habits: [
            WidgetHabit(id: "1", name: "Morning run",   emoji: "🏃", category: "fitness",
                        kind: "build", targetType: "yesNo", targetCount: 1, targetUnit: "",
                        currentCount: 1, isCompleted: true,  isSlipped: false, streak: 5, progress: 1.0),
            WidgetHabit(id: "2", name: "Read 20 mins",  emoji: "📚", category: "mindset",
                        kind: "build", targetType: "yesNo", targetCount: 1, targetUnit: "",
                        currentCount: 0, isCompleted: false, isSlipped: false, streak: 2, progress: 0.0),
            WidgetHabit(id: "3", name: "No sugar",      emoji: "🚫", category: "nutrition",
                        kind: "break", targetType: "yesNo", targetCount: 1, targetUnit: "",
                        currentCount: 1, isCompleted: true,  isSlipped: false, streak: 3, progress: 1.0),
            WidgetHabit(id: "4", name: "Meditate",      emoji: "🧘", category: "mindset",
                        kind: "build", targetType: "yesNo", targetCount: 1, targetUnit: "",
                        currentCount: 0, isCompleted: false, isSlipped: false, streak: 0, progress: 0.0),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        let h = SharedHabitStore.read()
        completion(HabitsEntry(date: Date(), habits: h.isEmpty ? placeholder(in: context).habits : h))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let entry = HabitsEntry(date: Date(), habits: SharedHabitStore.read())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct HabitsEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabit]
    var completed: Int { habits.filter(\.isCompleted).count }
    var total: Int { habits.count }
}

// MARK: - Small Widget

private struct SmallHabitsView: View {
    let entry: HabitsEntry
    private var progress: Double {
        entry.total == 0 ? 0 : Double(entry.completed) / Double(entry.total)
    }
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(red: 0.19, green: 0.82, blue: 0.35),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(entry.completed)")
                        .font(.system(size: 22, weight: .bold))
                    Text("/\(entry.total)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            Text("Habits")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(14)
    }
}

// MARK: - Medium Widget

private struct MediumHabitsView: View {
    let entry: HabitsEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's Habits")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(entry.completed)/\(entry.total)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            if entry.habits.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No habits tracked yet")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(entry.habits.prefix(4)), id: \.id) { habit in
                    HStack(spacing: 8) {
                        Text(habit.emoji).font(.system(size: 14))
                        Text(habit.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(habit.isCompleted
                                ? Color(red: 0.19, green: 0.82, blue: 0.35)
                                : Color.secondary.opacity(0.4))
                            .font(.system(size: 16))
                    }
                    .padding(.vertical, 4)
                    if habit.id != entry.habits.prefix(4).last?.id {
                        Divider().opacity(0.3)
                    }
                }
                if entry.habits.count > 4 {
                    Text("+\(entry.habits.count - 4) more")
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
    var entry: HabitsProvider.Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallHabitsView(entry: entry)
            default:           MediumHabitsView(entry: entry)
            }
        }
        .widgetURL(URL(string: "life://habits")!)
    }
}

// MARK: - Widget Definition

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
