import SwiftUI
import Charts

// MARK: - Sleep Tab

/// One stage of one night, flattened so Swift Charts can stack them.
private struct SleepStagePoint: Identifiable {
    let id: String
    let date: Date
    let stage: String
    let minutes: Int
}

struct HealthSleepTab: View {

    @Environment(AppState.self) private var appState
    @State private var range: HealthRange = .month

    private var settings: HealthSettings { appState.healthSettings }

    private var nights: [HealthDay] {
        let all = appState.healthHistory.filter { $0.sleepMin != nil }
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return all }
        let cutoffKey = cutoff.dayKey
        return all.filter { $0.dayKey >= cutoffKey }
    }

    private var averageMinutes: Int? {
        let values = nights.compactMap(\.sleepMin)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private var averageEfficiency: Double? {
        let values = nights.compactMap(\.sleepEfficiency)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The stacked bars, grouped into weeks or months on the longer ranges.
    ///
    /// Each grouped bar is the **average night** in that bucket, not the sum of
    /// its nights — a week's sleep added together would be a 50-hour bar next
    /// to 8-hour ones.
    private var chartStagePoints: [SleepStagePoint] {
        guard let bucket = range.bucket else { return stagePoints }
        let calendar = Calendar.current

        var totals: [String: (date: Date, stage: String, minutes: [Int])] = [:]
        for point in stagePoints {
            guard let start = calendar.dateInterval(of: bucket, for: point.date)?.start else { continue }
            let key = "\(start.timeIntervalSince1970)-\(point.stage)"
            var entry = totals[key] ?? (start, point.stage, [])
            entry.minutes.append(point.minutes)
            totals[key] = entry
        }

        return totals.values
            .map { entry in
                SleepStagePoint(
                    id: "\(entry.date.timeIntervalSince1970)-\(entry.stage)",
                    date: entry.date,
                    stage: entry.stage,
                    minutes: entry.minutes.reduce(0, +) / max(1, entry.minutes.count)
                )
            }
            .sorted { $0.date < $1.date }
    }

    private var stagePoints: [SleepStagePoint] {
        var out: [SleepStagePoint] = []
        for night in nights {
            guard let date = DayKey.date(from: night.dayKey) else { continue }
            let staged: [(String, Int?)] = [
                ("Deep", night.deepMin),
                ("REM", night.remMin),
                ("Light", night.lightMin),
                ("Awake", night.awakeMin)
            ]
            let hasBreakdown = staged.contains { $0.1 != nil }
            if hasBreakdown {
                for (name, minutes) in staged {
                    guard let minutes = minutes, minutes > 0 else { continue }
                    out.append(SleepStagePoint(id: "\(night.dayKey)-\(name)", date: date, stage: name, minutes: minutes))
                }
            } else if let total = night.sleepMin, total > 0 {
                // Trackers that report only a total still deserve a bar.
                out.append(SleepStagePoint(id: "\(night.dayKey)-asleep", date: date, stage: "Asleep", minutes: total))
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Above the empty check on purpose. It used to sit inside the
                // `else`, so picking a range with no data hid the control you
                // needed to pick a wider one — a dead end you could only escape
                // by leaving the screen.
                HealthRangePicker(range: $range)
                if nights.isEmpty {
                    HealthEmptyCard(
                        icon: "bed.double",
                        title: "No sleep data",
                        message: "Nothing recorded in the \(range.label). Try a wider range, or check your tracker is syncing."
                    )
                } else {
                    summaryCard
                    stageChartCard
                    splitCard
                    consistencyCard
                }
            }
            .padding(16)
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var summaryCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Averages · \(range.label)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let averageMinutes = averageMinutes {
                    Text(HealthInsights.formatDuration(averageMinutes))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }
                if let averageEfficiency = averageEfficiency {
                    InfoRow(label: "Efficiency", value: String(format: "%.0f%%", averageEfficiency * 100))
                }
                InfoRow(label: "Nights recorded", value: "\(nights.count)")
                InfoRow(label: "Goal", value: HealthInsights.formatDuration(settings.sleepGoalMinutes))
                streakRow
            }
        }
    }

    @ViewBuilder
    private var streakRow: some View {
        let streak = HealthInsights.sleepGoalStreak(appState.healthHistory, goalMinutes: settings.sleepGoalMinutes)
        if streak > 0 {
            InfoRow(label: "Current streak", value: "\(streak) night\(streak == 1 ? "" : "s")")
        }
    }

    private var stageChartTitle: String {
        guard let caption = range.bucketCaption else { return "Nightly breakdown" }
        return "Breakdown · " + caption
    }

    @ViewBuilder
    private var stageChartCard: some View {
        let points = chartStagePoints
        if !points.isEmpty {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stageChartTitle)
                        .font(.subheadline.weight(.semibold))
                    Chart(points) { point in
                        BarMark(
                            x: .value("Night", point.date, unit: range.bucket ?? .day),
                            y: .value("Minutes", point.minutes)
                        )
                        .foregroundStyle(by: .value("Stage", point.stage))
                    }
                    .chartForegroundStyleScale([
                        "Deep": Color.indigo,
                        "REM": Color.purple,
                        "Light": Color.blue.opacity(0.6),
                        "Awake": Color.orange.opacity(0.7),
                        "Asleep": Color.indigo.opacity(0.7)
                    ])
                    .frame(height: 190)
                }
            }
        }
    }

    @ViewBuilder
    private var splitCard: some View {
        if let split = HealthInsights.averageStageSplit(nights) {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Average stage split")
                        .font(.subheadline.weight(.semibold))
                    InfoRow(label: "Deep", value: String(format: "%.0f%%", split.deep * 100))
                    InfoRow(label: "REM", value: String(format: "%.0f%%", split.rem * 100))
                    InfoRow(label: "Light", value: String(format: "%.0f%%", split.light * 100))
                }
            }
        }
    }

    @ViewBuilder
    private var consistencyCard: some View {
        if let consistency = HealthInsights.sleepConsistency(appState.healthHistory) {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Consistency · last 14 nights")
                        .font(.subheadline.weight(.semibold))
                    InfoRow(label: "Bedtime varies by", value: "±\(Int(consistency.bedtimeSD.rounded())) min")
                    InfoRow(label: "Wake time varies by", value: "±\(Int(consistency.wakeSD.rounded())) min")
                    Text("Going to bed and waking at steadier times tends to help more than chasing extra hours.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Recovery Tab

struct HealthRecoveryTab: View {

    @Environment(AppState.self) private var appState
    @State private var metric: RecoveryMetric = .restingHr
    @State private var range: HealthRange = .month
    @State private var healthKit = HealthKitManager()

    /// Computed, not stored — see the note in `HealthView`.
    private var heartRate: HeartRateStore { HeartRateStore.shared }

    private var history: [HealthDay] { appState.healthHistory }

    /// Today's record, for the zone totals. Nil until the first sync of the day
    /// brings one back.
    private var today: HealthDay? { appState.healthDays[Date().dayKey] }

    private var points: [(date: Date, value: Double)] {
        let cutoffKey: String? = range.days.flatMap { days in
            Calendar.current.date(byAdding: .day, value: -days, to: Date())?.dayKey
        }
        return history.compactMap { day in
            if let cutoffKey = cutoffKey, day.dayKey < cutoffKey { return nil }
            guard let value = metric.value(from: day),
                  let date = DayKey.date(from: day.dayKey) else { return nil }
            return (date, value)
        }
    }

    private var trend: HealthInsights.Trend? {
        HealthInsights.trend(history, metric: { metric.value(from: $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HeartRateCurveCard(store: heartRate)
                HeartRateZonesCard(day: today)
                WorkoutsCard(store: heartRate)
                metricChips
                // Above the empty check: see the note in `HealthSleepTab`.
                HealthRangePicker(range: $range)
                if points.isEmpty {
                    HealthEmptyCard(
                        icon: metric.icon,
                        title: "No \(metric.rawValue) data",
                        message: "Nothing recorded in the \(range.label). Try a wider range — and note that not every tracker measures every metric."
                    )
                } else {
                    currentCard
                    chartCard
                    statsCard
                }
            }
            .padding(16)
        }
        // The Health tab owns the polling timer; this only covers the case of
        // landing here with nothing loaded yet.
        .task { await heartRate.refresh(healthKit: healthKit, appState: appState) }
    }

    // MARK: Cards

    @ViewBuilder
    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecoveryMetric.allCases) { m in
                    HealthChip(
                        title: m.rawValue,
                        colour: m.colour,
                        isSelected: m == metric
                    ) { metric = m }
                }
            }
        }
    }

    @ViewBuilder
    private var currentCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 6) {
                Label(metric.rawValue, systemImage: metric.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let latest = points.last {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(metric.format(latest.value))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(metric.unit)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                trendLine
            }
        }
    }

    @ViewBuilder
    private var trendLine: some View {
        if let trend = trend {
            let pct = abs(Int(trend.deltaPercent.rounded()))
            let above = trend.deltaPercent > 0
            let better = above == metric.higherIsBetter
            if trend.isMeaningful {
                Text("\(pct)% \(above ? "above" : "below") your 30-day average")
                    .font(.caption)
                    .foregroundColor(better ? .green : .orange)
            } else {
                Text("In line with your 30-day average")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            Text("Needs about two weeks of readings before comparing to a baseline")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Grouped into weeks or months on the longer ranges. Ninety daily marks
    /// across a phone screen is a smear rather than a trend.
    private var chartPoints: [(date: Date, value: Double)] {
        HealthInsights.grouped(points, by: range.bucket)
    }

    private var chartTitle: String {
        guard let caption = range.bucketCaption else { return "Trend · " + range.label }
        return "Trend · " + range.label + " · " + caption
    }

    @ViewBuilder
    private var chartCard: some View {
        let data = chartPoints
        if data.count > 1 {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(chartTitle)
                        .font(.subheadline.weight(.semibold))
                    Chart {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value(metric.rawValue, point.value)
                            )
                            .foregroundStyle(metric.colour)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value(metric.rawValue, point.value)
                            )
                            .foregroundStyle(metric.colour.opacity(0.12))
                            .interpolationMethod(.catmullRom)
                        }
                        baselineRule
                    }
                    .frame(height: 190)
                    .chartYScale(domain: .automatic(includesZero: metric.includesZero))
                }
            }
        }
    }

    /// Emits nothing when there's no baseline yet. Drawing an invisible rule at
    /// zero instead would drag the Y axis down to include it and flatten the
    /// line into a straight edge.
    @ChartContentBuilder
    private var baselineRule: some ChartContent {
        if let trend = trend {
            RuleMark(y: .value("Baseline", trend.baseline))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    @ViewBuilder
    private var statsCard: some View {
        let values = points.map(\.value)
        if !values.isEmpty {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Range · \(range.label)")
                        .font(.subheadline.weight(.semibold))
                    InfoRow(label: "Average", value: metric.format(values.reduce(0, +) / Double(values.count)))
                    InfoRow(label: "Lowest", value: metric.format(values.min() ?? 0))
                    InfoRow(label: "Highest", value: metric.format(values.max() ?? 0))
                    InfoRow(label: "Readings", value: "\(values.count)")
                }
            }
        }
    }
}

// MARK: - Activity Tab

struct HealthActivityTab: View {

    @Environment(AppState.self) private var appState
    @State private var metric: ActivityMetric = .steps
    @State private var range: HealthRange = .month

    private var settings: HealthSettings { appState.healthSettings }
    private var history: [ActivityDay] { appState.activityHistory }

    private var points: [(date: Date, value: Double)] {
        let cutoffKey: String? = range.days.flatMap { days in
            Calendar.current.date(byAdding: .day, value: -days, to: Date())?.dayKey
        }
        return history.compactMap { day in
            if let cutoffKey = cutoffKey, day.dayKey < cutoffKey { return nil }
            guard let value = metric.value(from: day), let date = day.date else { return nil }
            return (date, value)
        }
    }

    /// Follows the range picker. This was pinned at eight weeks of the whole
    /// history regardless of the selection, so the weekly chart never moved
    /// when you changed range — it looked broken because it was.
    private var weeks: [HealthInsights.WeekTotal] {
        HealthInsights.weeklyTotals(history, metric: metric, weeks: range.weeksToShow)
    }

    /// Grouped on the longer ranges — see `HealthRecoveryTab.chartPoints`.
    private var chartPoints: [(date: Date, value: Double)] {
        HealthInsights.grouped(points, by: range.bucket)
    }

    private var dailyChartTitle: String {
        guard let caption = range.bucketCaption else { return "Daily · " + range.label }
        return range.label.prefix(1).uppercased() + range.label.dropFirst() + " · " + caption
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                metricChips
                // Above the empty check: see the note in `HealthSleepTab`.
                HealthRangePicker(range: $range)
                if points.isEmpty {
                    HealthEmptyCard(
                        icon: metric.icon,
                        title: "No \(metric.rawValue.lowercased()) data",
                        message: "Nothing recorded in the \(range.label). Try a wider range."
                    )
                } else {
                    weekComparisonCard
                    dailyChartCard
                    weeklyChartCard
                    goalCard
                }
            }
            .padding(16)
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityMetric.allCases) { m in
                    HealthChip(
                        title: m.rawValue,
                        colour: m.colour,
                        isSelected: m == metric
                    ) { metric = m }
                }
            }
        }
    }

    private var week: HealthInsights.WeekToDate? {
        HealthInsights.weekToDate(history, metric: metric)
    }

    @ViewBuilder
    private var weekComparisonCard: some View {
        if let week {
            HealthCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.periodCaption(week))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(metric.format(week.thisWeek))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(metric.unit)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    weekDelta(week)
                }
            }
        }
    }

    /// "This week so far · Mon 27 Jul – Sun 2 Aug · day 3 of 7".
    ///
    /// Naming the period is the point. A week that's one day old showing a
    /// single day's steps under a bare "This week" is indistinguishable from a
    /// broken total — and on a phone set to a Sunday-start region, that's
    /// exactly what Sunday looks like.
    ///
    /// The range is built from the calendar's own week boundaries rather than
    /// "start plus six days", so the last day named is the one the region
    /// actually ends its week on, and a week containing a clock change doesn't
    /// print a day either side of the truth.
    private static func periodCaption(_ week: HealthInsights.WeekToDate) -> String {
        "This week so far · " + Self.rangeText(from: week.start, until: week.end)
            + " · day " + String(week.daysElapsed) + " of " + String(week.daysInWeek)
    }

    /// A half-open range rendered as inclusive days: `until` is the first
    /// instant of the following week, so the day named is the one before it.
    private static func rangeText(from start: Date, until end: Date) -> String {
        let calendar = Calendar.current
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        return start.formatted(style) + " – " + lastDay.formatted(style)
    }

    /// Compared against the same number of days last week, never against a
    /// complete week — otherwise every Monday reads as a collapse — and only
    /// when both stretches actually hold data for those days.
    @ViewBuilder
    private func weekDelta(_ week: HealthInsights.WeekToDate) -> some View {
        if week.isComparable, let previous = week.lastWeekToDate, previous > 0 {
            let change = (week.thisWeek - previous) / previous * 100
            let up = change >= 0
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.deltaText(percent: change, up: up, days: week.daysElapsed))
                    .font(.caption)
                    .foregroundColor(up ? .green : .secondary)
                Text("vs " + Self.rangeText(from: week.lastStart, until: week.lastEnd))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(week.insufficientDataReason)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func deltaText(percent: Double, up: Bool, days: Int) -> String {
        let magnitude = abs(Int(percent.rounded()))
        let span = days == 1 ? "same day" : "same \(days) days"
        return String(magnitude) + "% " + (up ? "up" : "down") + " on the " + span + " last week"
    }

    @ViewBuilder
    private var dailyChartCard: some View {
        let data = chartPoints
        if data.count > 1 {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(dailyChartTitle)
                        .font(.subheadline.weight(.semibold))
                    Chart {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                            BarMark(
                                x: .value("Date", point.date, unit: range.bucket ?? .day),
                                y: .value(metric.rawValue, point.value)
                            )
                            .foregroundStyle(metric.colour)
                        }
                    }
                    .frame(height: 170)
                }
            }
        }
    }

    @ViewBuilder
    private var weeklyChartCard: some View {
        let data = weeks
        if data.count > 1 {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly totals")
                        .font(.subheadline.weight(.semibold))
                    Chart(data) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value(metric.rawValue, week.total)
                        )
                        .foregroundStyle(metric.colour.opacity(0.8))
                    }
                    .frame(height: 150)
                }
            }
        }
    }

    @ViewBuilder
    private var goalCard: some View {
        if metric == .exercise {
            let days = HealthInsights.exerciseGoalDays(history, goalMinutes: settings.exerciseGoalMinutes)
            HealthCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal")
                        .font(.subheadline.weight(.semibold))
                    InfoRow(label: "Target", value: "\(settings.exerciseGoalMinutes) min/day")
                    InfoRow(label: "Met in last 7 days", value: "\(days) day\(days == 1 ? "" : "s")")
                }
            }
        }
    }
}

// MARK: - Chip

struct HealthChip: View {
    let title: String
    let colour: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius)
                        .fill(isSelected ? colour.opacity(0.18) : Color(.tertiarySystemFill))
                )
                .foregroundColor(isSelected ? colour : .secondary)
        }
        .buttonStyle(.plain)
    }
}
