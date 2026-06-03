import SwiftUI
import Charts

// MARK: - Habit Analytics View

struct HabitAnalyticsView: View {
    @Environment(AppState.self) private var appState

    private var active: [Habit] { appState.habits.filter { !$0.isArchived } }

    // MARK: Data helpers

    private struct DayPoint: Identifiable {
        let id = UUID()
        let label: String
        let date: Date
        let pct: Double
    }

    private func dayPoints(range: Int) -> [DayPoint] {
        let cal = Calendar.current
        return (0..<range).reversed().compactMap { i -> DayPoint? in
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { return nil }
            let key = date.dayKey
            let done = Double(active.filter { h in
                guard let log = h.logs.first(where: { $0.dayKey == key }) else { return false }
                return h.kind == .break ? !log.slipped : log.count >= h.targetCount && !log.slipped
            }.count)
            let label = i % (range > 14 ? 7 : 1) == 0
                ? date.formatted(.dateTime.weekday(.abbreviated))
                : ""
            return DayPoint(label: label, date: date, pct: active.isEmpty ? 0 : done / Double(active.count))
        }
    }

    private var totalCompletions: Int {
        active.reduce(0) { $0 + appState.totalCompletionsFor($1) }
    }
    private var longestStreak: Int {
        active.map { appState.bestStreakFor($0) }.max() ?? 0
    }
    private var avgWeekly: Double {
        guard !active.isEmpty else { return 0 }
        return active.reduce(0.0) { $0 + appState.weeklyCompletionFor($1) } / Double(active.count)
    }

    private var byStreak: [Habit] { active.sorted { appState.streakFor($0) > appState.streakFor($1) } }
    private var byWeekly: [Habit] { active.sorted { appState.weeklyCompletionFor($0) > appState.weeklyCompletionFor($1) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCards
                weeklyBarChart
                monthlyLineChart
                topHabitsCard
                categoryBreakdown
                Spacer(minLength: 40)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            AnalyticsStatCard(title: "Total Completions", value: "\(totalCompletions)",
                              icon: "checkmark.seal.fill", color: Color(hex: "#30d158"))
            AnalyticsStatCard(title: "Longest Streak", value: "\(longestStreak) days",
                              icon: "flame.fill", color: .orange)
            AnalyticsStatCard(title: "Active Habits", value: "\(active.count)",
                              icon: "list.bullet", color: Color(hex: "#5E9BF0"))
            AnalyticsStatCard(title: "Weekly Avg", value: "\(Int(avgWeekly * 100))%",
                              icon: "chart.bar.fill", color: Color(hex: "#BF5AF2"))
        }
    }

    // MARK: - Weekly Bar Chart

    private var weeklyBarChart: some View {
        let data = dayPoints(range: 7)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days").font(.headline)
            if active.isEmpty {
                emptyChartPlaceholder(height: 160)
            } else {
                Chart(data) { p in
                    BarMark(x: .value("Day", p.label), y: .value("Completion", p.pct))
                        .foregroundStyle(Color(hex: "#30d158").gradient)
                        .cornerRadius(6)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1.0]) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text("\(Int(d * 100))%").font(.caption2) }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
    }

    // MARK: - Monthly Line Chart

    private var monthlyLineChart: some View {
        let data = dayPoints(range: 30)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 30 Days").font(.headline)
            if active.isEmpty {
                emptyChartPlaceholder(height: 140)
            } else {
                Chart(data) { p in
                    LineMark(x: .value("Day", p.date), y: .value("Completion", p.pct))
                        .foregroundStyle(Color(hex: "#5E9BF0"))
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Day", p.date), y: .value("Completion", p.pct))
                        .foregroundStyle(Color(hex: "#5E9BF0").opacity(0.12).gradient)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1.0]) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text("\(Int(d * 100))%").font(.caption2) }
                        }
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
    }

    // MARK: - Top Habits

    private var topHabitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Habits by Streak").font(.headline)

            if active.isEmpty {
                Text("No active habits").font(.subheadline).foregroundColor(.secondary)
            } else {
                ForEach(byStreak.prefix(5)) { habit in
                    HStack(spacing: 12) {
                        Text(habit.emoji)
                            .font(.title3)
                            .frame(width: 38, height: 38)
                            .background(habit.category.color.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(Int(appState.weeklyCompletionFor(habit) * 100))% this week")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill").font(.caption).foregroundColor(.orange)
                            Text("\(appState.streakFor(habit))").font(.subheadline.bold())
                        }
                    }
                    if habit.id != byStreak.prefix(5).last?.id { Divider().opacity(0.4) }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
    }

    // MARK: - Category Breakdown

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By Category").font(.headline)
            ForEach(HabitCategory.allCases) { cat in
                let catHabits = active.filter { $0.category == cat }
                if !catHabits.isEmpty {
                    let pct = catHabits.reduce(0.0) { $0 + appState.weeklyCompletionFor($1) } / Double(catHabits.count)
                    VStack(spacing: 6) {
                        HStack {
                            HStack(spacing: 6) {
                                Text(cat.emoji)
                                Text(cat.label).font(.subheadline)
                            }
                            Spacer()
                            Text("\(catHabits.count) habit\(catHabits.count == 1 ? "" : "s")")
                                .font(.caption).foregroundColor(.secondary)
                            Text("\(Int(pct * 100))%")
                                .font(.subheadline.bold()).foregroundColor(cat.color)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color(.systemFill)).frame(height: 5)
                                RoundedRectangle(cornerRadius: 3).fill(cat.color)
                                    .frame(width: geo.size.width * pct, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
    }

    private func emptyChartPlaceholder(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(.systemFill))
            Text("No data yet — start completing habits!")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(height: height)
    }
}

// MARK: - Analytics Stat Card

private struct AnalyticsStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.subheadline).foregroundColor(color)
                Spacer()
            }
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}
