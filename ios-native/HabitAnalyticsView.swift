import SwiftUI
import Charts

// MARK: - Habit Analytics View

struct HabitAnalyticsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let habit: Habit

    private var streak: Int        { appState.streakFor(habit) }
    private var bestStreak: Int    { appState.bestStreakFor(habit) }
    private var totalDone: Int     { appState.totalCompletionsFor(habit) }
    private var weeklyRate: Double { appState.weeklyCompletionFor(habit) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statsRow
                    weeklyChart
                    heatmap
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(habit.emoji)  \(habit.name)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(title: "Streak", value: "\(streak)", unit: "days",
                     icon: "flame.fill", color: Color(hex: "#30d158"))
            StatCard(title: "Best", value: "\(bestStreak)", unit: "days",
                     icon: "trophy.fill", color: .orange)
            StatCard(title: "Total", value: "\(totalDone)", unit: "times",
                     icon: "checkmark.seal.fill", color: .blue)
        }
    }

    // MARK: - Weekly Completion Rate Bar

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 7 Days")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            let days = last7Days
            if #available(iOS 16, *) {
                Chart {
                    ForEach(days, id: \.key) { day in
                        BarMark(
                            x: .value("Day", day.label),
                            y: .value("Done", day.done ? 1 : 0)
                        )
                        .foregroundStyle(day.done ? Color(hex: "#30d158") : Color(.systemFill))
                        .cornerRadius(4)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 80)
            } else {
                HStack(spacing: 6) {
                    ForEach(days, id: \.key) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(day.done ? Color(hex: "#30d158") : Color(.systemFill))
                                .frame(height: day.done ? 48 : 16)
                            Text(day.label)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 60)
            }

            HStack {
                Text("This week")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(weeklyRate * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(weeklyRate >= 0.7 ? Color(hex: "#30d158") : .secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - All-Time Heatmap

    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Time")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            let keys = Set(habit.logs.map(\.dayKey))
            let weeks = last16Weeks

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(weeks, id: \.self) { week in
                        VStack(spacing: 3) {
                            ForEach(week, id: \.self) { dayKey in
                                let done = keys.contains(dayKey)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(done ? Color(hex: "#30d158") : Color(.systemFill))
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                }
                .padding(4)
            }

            HStack {
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: 8, height: 8)
                Text("Missed")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(Color(hex: "#30d158"))
                    .frame(width: 8, height: 8)
                Text("Completed")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Helpers

    private struct DayResult {
        let key: String
        let label: String
        let done: Bool
    }

    private var last7Days: [DayResult] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let keys = Set(habit.logs.filter { !$0.slipped && $0.count >= habit.targetCount }.map(\.dayKey))
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return (0..<7).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let key = date.dayKey
            return DayResult(key: key, label: fmt.string(from: date), done: keys.contains(key))
        }
    }

    private var last16Weeks: [[String]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var weeks: [[String]] = []
        for weekOffset in (0..<16).reversed() {
            var week: [String] = []
            for dayOffset in 0..<7 {
                let daysBack = weekOffset * 7 + (6 - dayOffset)
                if let date = cal.date(byAdding: .day, value: -daysBack, to: today) {
                    week.append(date.dayKey)
                }
            }
            weeks.append(week)
        }
        return weeks
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}
