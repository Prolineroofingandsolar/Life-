import SwiftUI
import Charts

// MARK: - Task Stats View

struct TaskStatsView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var completedToday: Int {
        let key = Date().dayKey
        return appState.tasks.filter {
            $0.done && $0.completedAt.map { Calendar.current.startOfDay(for: $0).dayKey == key } == true
        }.count
    }

    private var completedThisWeek: Int {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return appState.tasks.filter {
            $0.done && ($0.completedAt ?? .distantPast) >= weekAgo
        }.count
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        var streak = 0
        var date = cal.startOfDay(for: Date())
        while true {
            let key = date.dayKey
            let hasCompletion = appState.tasks.contains {
                $0.done && ($0.completedAt.map { cal.startOfDay(for: $0).dayKey == key } == true)
            }
            if hasCompletion {
                streak += 1
                date = cal.date(byAdding: .day, value: -1, to: date) ?? date
            } else {
                break
            }
        }
        return streak
    }

    private struct DayBar: Identifiable {
        let id = UUID()
        let label: String
        let date: Date
        let count: Int
    }

    private var last7Days: [DayBar] {
        let cal = Calendar.current
        return (0..<7).reversed().compactMap { i -> DayBar? in
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { return nil }
            let key = cal.startOfDay(for: date).dayKey
            let count = appState.tasks.filter {
                $0.done && ($0.completedAt.map { cal.startOfDay(for: $0).dayKey == key } == true)
            }.count
            return DayBar(label: date.formatted(.dateTime.weekday(.abbreviated)), date: date, count: count)
        }
    }

    private struct ListStat {
        let list: TaskList
        let done: Int
        let total: Int
        var pct: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }

    private var listStats: [ListStat] {
        appState.taskLists.compactMap { list in
            let listTasks = appState.tasks.filter { $0.listId == list.id }
            guard !listTasks.isEmpty else { return nil }
            return ListStat(list: list, done: listTasks.filter(\.done).count, total: listTasks.count)
        }
        .sorted { $0.pct > $1.pct }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCards
                    chartCard
                    if !listStats.isEmpty {
                        listBreakdownCard
                    }
                    Spacer(minLength: 24)
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Task Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(value: "\(completedToday)", label: "Done Today", icon: "checkmark.circle.fill", color: AppTheme.primary)
            StatCard(value: "\(completedThisWeek)", label: "This Week", icon: "calendar.badge.checkmark", color: .blue)
            StatCard(value: "\(currentStreak)", label: "Day Streak", icon: "flame.fill", color: .orange)
            StatCard(value: "\(appState.tasks.filter { !$0.done }.count)", label: "Remaining", icon: "circle", color: .secondary)
        }
        .padding(.horizontal, 16)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)
                .padding(.horizontal, 20)

            Chart(last7Days) { bar in
                BarMark(x: .value("Day", bar.label), y: .value("Count", bar.count))
                    .foregroundStyle(AppTheme.primary)
                    .cornerRadius(4)
            }
            .frame(height: 140)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    private var listBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By List")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            VStack(spacing: 12) {
                ForEach(listStats, id: \.list.id) { stat in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(stat.list.emoji + " " + stat.list.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(stat.done)/\(stat.total)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.tertiarySystemFill))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(stat.list.color)
                                    .frame(width: geo.size.width * stat.pct, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
        .padding(.horizontal, 16)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
        .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
    }
}
