import WidgetKit
import SwiftUI

// Paste this file into: ios/App/LifeTasksWidget/LifeTasksWidget.swift

// MARK: - Data model

struct WidgetTask: Codable, Identifiable {
    let id: String
    let title: String
    let category: String
    let done: Bool
    let dueDate: String?
}

struct AppState: Codable {
    let tasks: [WidgetTask]
}

// MARK: - Timeline provider

struct Provider: TimelineProvider {
    let appGroup = "group.uk.co.prolineroofingandsolar.life"

    func tasks() -> [WidgetTask] {
        // First try App Group UserDefaults (set by LifePlugin)
        if let defaults = UserDefaults(suiteName: appGroup),
           let json = defaults.string(forKey: "life_widget_tasks"),
           let data = json.data(using: .utf8),
           let tasks = try? JSONDecoder().decode([WidgetTask].self, from: data) {
            return tasks.filter { !$0.done && $0.dueDate == "today" }
        }

        // Fallback: read from shared app container localStorage file
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            let fileURL = containerURL.appendingPathComponent("life_tasks.json")
            if let data = try? Data(contentsOf: fileURL),
               let tasks = try? JSONDecoder().decode([WidgetTask].self, from: data) {
                return tasks.filter { !$0.done && $0.dueDate == "today" }
            }
        }

        return []
    }

    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), tasks: [
            WidgetTask(id: "1", title: "Reply to the email", category: "work", done: false, dueDate: "today"),
            WidgetTask(id: "2", title: "Push session — legs", category: "gym", done: false, dueDate: "today"),
            WidgetTask(id: "3", title: "Refill water bottle", category: "personal", done: false, dueDate: "today"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        let t = tasks()
        let entry = TaskEntry(date: Date(), tasks: t.isEmpty ? placeholder(in: context).tasks : t)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = TaskEntry(date: Date(), tasks: tasks())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
}

// MARK: - Colours

extension String {
    var categoryColor: Color {
        switch self {
        case "work":     return Color(red: 0.37, green: 0.36, blue: 0.90)
        case "gym":      return Color(red: 0.19, green: 0.82, blue: 0.35)
        case "personal": return Color(red: 1.00, green: 0.62, blue: 0.04)
        default:         return .secondary
        }
    }

    var categoryEmoji: String {
        switch self {
        case "work":     return "💼"
        case "gym":      return "🏋️"
        case "personal": return "🌱"
        default:         return "•"
        }
    }
}

// MARK: - Views

struct TaskRow: View {
    let task: WidgetTask

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .strokeBorder(task.category.categoryColor, lineWidth: 1.5)
                .frame(width: 14, height: 14)
                .padding(.top, 2)
            Text(task.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer()
        }
    }
}

struct SmallWidgetView: View {
    let tasks: [WidgetTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            if tasks.isEmpty {
                Spacer()
                Text("All done! 🎉")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ForEach(tasks.prefix(3)) { task in
                    TaskRow(task: task)
                }
                if tasks.count > 3 {
                    Text("+\(tasks.count - 3) more")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

struct MediumWidgetView: View {
    let tasks: [WidgetTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's Tasks")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(tasks.count) remaining")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            if tasks.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("All done! 🎉")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(tasks.prefix(4)) { task in
                    TaskRow(task: task)
                        .padding(.vertical, 3)
                    if task.id != tasks.prefix(4).last?.id {
                        Divider().opacity(0.4)
                    }
                }
                if tasks.count > 4 {
                    Text("+\(tasks.count - 4) more")
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

struct LargeWidgetView: View {
    let tasks: [WidgetTask]

    var grouped: [(String, [WidgetTask])] {
        let categories = ["work", "gym", "personal"]
        return categories.compactMap { cat in
            let items = tasks.filter { $0.category == cat }
            guard !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's Tasks")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(tasks.count) remaining")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 10)

            if tasks.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("🎉")
                            .font(.system(size: 32))
                        Text("All done for today!")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(grouped, id: \.0) { category, items in
                    HStack(spacing: 5) {
                        Text(category.categoryEmoji)
                            .font(.system(size: 11))
                        Text(category.categoryEmoji == "•" ? category : category.capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(category.categoryColor)
                    }
                    .padding(.bottom, 4)

                    ForEach(items.prefix(4)) { task in
                        TaskRow(task: task)
                            .padding(.bottom, 3)
                    }
                    if items.count > 4 {
                        Text("+\(items.count - 4) more")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 3)
                    }
                    Divider().padding(.vertical, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

// MARK: - Widget entry view

struct LifeTasksWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(tasks: entry.tasks)
        case .systemMedium:
            MediumWidgetView(tasks: entry.tasks)
        case .systemLarge:
            LargeWidgetView(tasks: entry.tasks)
        default:
            MediumWidgetView(tasks: entry.tasks)
        }
    }
}

// MARK: - Widget definition

struct LifeTasksWidget: Widget {
    let kind: String = "LifeTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            LifeTasksWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Life Tasks")
        .description("See today's tasks at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
