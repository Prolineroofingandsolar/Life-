import SwiftUI
import Charts

// MARK: - Sleep Stage

/// The stage vocabulary, mapping the API's enum onto display names, colours and
/// the vertical order of the hypnogram (awake at the top, deep at the bottom —
/// the convention every sleep app uses).
enum SleepStageKind: String, CaseIterable {
    case awake = "AWAKE"
    case rem = "REM"
    case light = "LIGHT"
    case deep = "DEEP"
    /// Devices without stage tracking report one flat block.
    case asleep = "ASLEEP"

    /// Out-of-bed maps onto the awake lane. It has to map to *something* awake:
    /// falling through to `.asleep` would draw time spent up and about as sleep.
    init(apiValue: String) {
        switch apiValue.uppercased() {
        case "OUT_OF_BED", "RESTLESS": self = .awake
        default: self = SleepStageKind(rawValue: apiValue.uppercased()) ?? .asleep
        }
    }

    var label: String {
        switch self {
        case .awake:  return "Awake"
        case .rem:    return "REM"
        case .light:  return "Light"
        case .deep:   return "Deep"
        case .asleep: return "Asleep"
        }
    }

    var colour: Color {
        switch self {
        case .awake:  return .orange
        case .rem:    return .purple
        case .light:  return Color.blue.opacity(0.65)
        case .deep:   return .indigo
        case .asleep: return .indigo.opacity(0.7)
        }
    }

    /// Top-to-bottom order on the chart.
    static let laneOrder: [SleepStageKind] = [.awake, .rem, .light, .deep]

    /// Healthy adult reference range as a share of time asleep, where one
    /// exists. Percentages mean little without something to compare them to.
    var typicalRange: ClosedRange<Double>? {
        switch self {
        case .deep:  return 0.13...0.23
        case .rem:   return 0.20...0.25
        case .light: return 0.44...0.60
        default:     return nil
        }
    }
}

// MARK: - Sleep View

/// The full sleep screen: one night in detail, with trends underneath.
///
/// Every card is its own `struct` or `@ViewBuilder` property. `SettingsView` hit
/// *"unable to type-check this expression in reasonable time"* from far less
/// than this screen contains.
struct SleepView: View {

    @Environment(AppState.self) private var appState
    @State private var selectedKey: String? = nil

    private var settings: HealthSettings { appState.healthSettings }

    /// Nights with a recorded duration, most recent last.
    private var nights: [HealthDay] {
        appState.healthHistory.filter { $0.sleepMin != nil }
    }

    private var selected: HealthDay? {
        if let selectedKey, let match = nights.first(where: { $0.dayKey == selectedKey }) { return match }
        return nights.last
    }

    private var selectedNight: SleepNight? {
        selected.flatMap { appState.sleepNights[$0.dayKey] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if nights.isEmpty {
                    HealthEmptyCard(
                        icon: "bed.double",
                        title: "No sleep recorded",
                        message: "Once your tracker syncs a night, it'll appear here with the full stage breakdown."
                    )
                } else {
                    nightPicker
                    if let night = selected {
                        SleepHypnogramCard(night: selectedNight, day: night)
                        SleepHeadlineRow(day: night)
                        SleepWarningsCard(day: night)
                        SleepScoreCard(night: night, history: nights, settings: settings)
                        SleepStagesCard(day: night)
                        SleepVitalsCard(day: night, history: nights)
                    }
                    trendsLink
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Night picker

    /// Horizontally scrolling strip of recent nights. Cheaper to build and
    /// quicker to use than a date picker, and it doubles as a week-at-a-glance.
    @ViewBuilder
    private var nightPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(nights.suffix(30).reversed(), id: \.dayKey) { night in
                    SleepNightChip(
                        day: night,
                        settings: settings,
                        history: nights,
                        isSelected: night.dayKey == (selected?.dayKey ?? "")
                    ) { selectedKey = night.dayKey }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var trendsLink: some View {
        NavigationLink { HealthSleepTab().navigationTitle("Sleep Trends") } label: {
            HealthCard {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Trends & averages")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Night chip

private struct SleepNightChip: View {
    let day: HealthDay
    let settings: HealthSettings
    let history: [HealthDay]
    let isSelected: Bool
    let action: () -> Void

    private var weekday: String {
        guard let date = _dayKeyFormatter.date(from: day.dayKey) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private var dayNumber: String {
        guard let date = _dayKeyFormatter.date(from: day.dayKey) else { return "" }
        return date.formatted(.dateTime.day())
    }

    private var score: Int? {
        HealthInsights.sleepScoreBreakdown(for: day, history: history, settings: settings)?.total
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(weekday)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text(dayNumber)
                    .font(.system(size: 15, weight: .semibold))
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .indigo)
                    .frame(width: 26, height: 18)
                    .background(
                        Capsule().fill(isSelected ? Color.indigo : Color.indigo.opacity(0.15))
                    )
            }
            .frame(width: 52)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.indigo.opacity(0.12) : AppTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.indigo.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hypnogram

/// The banded stage chart — the thing people actually come to a sleep screen to
/// look at.
private struct SleepHypnogramCard: View {
    let night: SleepNight?
    let day: HealthDay

    private var lanes: [String] {
        guard let night, night.hasStages else { return [SleepStageKind.asleep.label] }
        // Only show lanes the night actually used, so a chart isn't padded with
        // empty rows.
        let used = Set(night.segments.map { SleepStageKind(apiValue: $0.stage) })
        return SleepStageKind.laneOrder.filter { used.contains($0) }.map(\.label)
    }

    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let night, !night.segments.isEmpty {
                    chart(night)
                    legend(night)
                } else {
                    Text(unavailableMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.sleepMin.map { HealthInsights.formatDuration($0) } ?? "—")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Spacer()
            if let bedtime = day.bedtime, let wake = day.wakeTime {
                Text("\(bedtime.formatted(date: .omitted, time: .shortened)) – \(wake.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Segments beyond the 30-night retention window are pruned, so an older
    /// night keeps its totals but loses its shape. Say so rather than showing an
    /// empty chart.
    private var unavailableMessage: String {
        day.sleepType == "CLASSIC"
            ? "This night was tracked without sleep stages, so there's no breakdown to chart."
            : "Stage detail isn't kept for older nights — only the last 30 are stored in full."
    }

    private func chart(_ night: SleepNight) -> some View {
        Chart(night.segments) { segment in
            RectangleMark(
                xStart: .value("Start", segment.start),
                xEnd: .value("End", segment.end),
                y: .value("Stage", SleepStageKind(apiValue: segment.stage).label)
            )
            .foregroundStyle(SleepStageKind(apiValue: segment.stage).colour)
            .cornerRadius(3)
        }
        .chartYScale(domain: lanes)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                AxisGridLine()
            }
        }
        .frame(height: 34 * CGFloat(max(lanes.count, 1)) + 20)
    }

    @ViewBuilder
    private func legend(_ night: SleepNight) -> some View {
        let used = SleepStageKind.laneOrder.filter { kind in
            night.segments.contains { SleepStageKind(apiValue: $0.stage) == kind }
        }
        HStack(spacing: 12) {
            ForEach(used, id: \.self) { kind in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(kind.colour)
                        .frame(width: 10, height: 10)
                    Text(kind.label)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Headline stats

private struct SleepHeadlineRow: View {
    let day: HealthDay

    var body: some View {
        HStack(spacing: 0) {
            SleepStat(title: "Asleep", value: day.sleepMin.map { HealthInsights.formatDuration($0) })
            SleepStat(title: "In bed", value: day.timeInBedMin.map { HealthInsights.formatDuration($0) })
            SleepStat(title: "Fell asleep", value: day.latencyMin.map { "\($0)m" })
            SleepStat(title: "Woke", value: day.awakenings.map { "\($0)×" })
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}

private struct SleepStat: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(value ?? "—")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Warnings

/// Surfaces gaps in the night's data rather than letting the figures imply a
/// completeness they don't have.
private struct SleepWarningsCard: View {
    let day: HealthDay

    private var warnings: [SleepAnalysis.Warning] {
        SleepAnalysis.warnings(for: day)
    }

    var body: some View {
        if !warnings.isEmpty {
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text(warning.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Score

/// Shows the total *and* its three components. A score you can't interrogate is
/// just a number to disagree with — and this one is deliberately modelled on
/// Fitbit's without being able to match it exactly, so the working matters.
private struct SleepScoreCard: View {
    let night: HealthDay
    let history: [HealthDay]
    let settings: HealthSettings

    private var breakdown: HealthInsights.SleepScoreBreakdown? {
        HealthInsights.sleepScoreBreakdown(for: night, history: history, settings: settings)
    }

    private var measuredOn: String {
        guard let date = _dayKeyFormatter.date(from: night.dayKey) else { return night.dayKey }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HealthCard {
            if let breakdown = breakdown {
                VStack(alignment: .leading, spacing: 12) {
                    Text(breakdown.title)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(breakdown.total)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(breakdown.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(breakdown.tone.colour)
                        Spacer()
                    }
                    // Components only exist for Life's own estimate. An official
                    // score is shown exactly as the source gave it, with nothing
                    // added, so there's no working to show.
                    if breakdown.isEstimate {
                        SleepScoreBar(title: "Duration", earned: breakdown.duration, outOf: 50, colour: .indigo)
                        SleepScoreBar(title: "Quality", earned: breakdown.quality, outOf: 25, colour: .purple)
                        SleepScoreBar(title: "Restoration", earned: breakdown.restoration, outOf: 25, colour: AppTheme.primary)
                    }
                    provenanceLine(breakdown)
                    disclaimer(breakdown)
                }
            } else {
                Text("This night doesn't carry enough stage detail to estimate a score. The measured figures above are still accurate.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func provenanceLine(_ breakdown: HealthInsights.SleepScoreBreakdown) -> some View {
        HStack(spacing: 4) {
            Text(measuredOn)
            if let device = breakdown.device {
                Text("·")
                Text(device)
            }
        }
        .font(.caption2)
        .foregroundColor(Color(.tertiaryLabel))
    }

    @ViewBuilder
    private func disclaimer(_ breakdown: HealthInsights.SleepScoreBreakdown) -> some View {
        if breakdown.isEstimate {
            Text("Life's own estimate, not Google's or Fitbit's sleep score — neither is published through the API. Calculated from your measured duration, deep and REM sleep, and how settled your heart rate and HRV were against your own baseline.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SleepScoreBar: View {
    let title: String
    let earned: Double
    let outOf: Double
    let colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text("\(Int(earned.rounded()))/\(Int(outOf))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(colour.opacity(0.15))
                    Capsule()
                        .fill(colour)
                        .frame(width: geometry.size.width * min(1, earned / outOf))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Stages

/// A stage and its minutes. A named type rather than a tuple because Swift key
/// paths can't address tuple elements, so `ForEach(_:id:)` needs this.
private struct StageTotal: Identifiable {
    let kind: SleepStageKind
    let minutes: Int
    var id: String { kind.rawValue }
}

private struct SleepStagesCard: View {
    let day: HealthDay

    private var rows: [StageTotal] {
        var out: [StageTotal] = []
        if let minutes = day.deepMin, minutes > 0 { out.append(StageTotal(kind: .deep, minutes: minutes)) }
        if let minutes = day.remMin, minutes > 0 { out.append(StageTotal(kind: .rem, minutes: minutes)) }
        if let minutes = day.lightMin, minutes > 0 { out.append(StageTotal(kind: .light, minutes: minutes)) }
        if let minutes = day.awakeMin, minutes > 0 { out.append(StageTotal(kind: .awake, minutes: minutes)) }
        return out
    }

    var body: some View {
        if !rows.isEmpty {
            HealthCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stages")
                        .font(.subheadline.weight(.semibold))
                    ForEach(rows) { row in
                        SleepStageRow(kind: row.kind, minutes: row.minutes, totalAsleep: day.sleepMin ?? 0)
                    }
                }
            }
        }
    }
}

private struct SleepStageRow: View {
    let kind: SleepStageKind
    let minutes: Int
    let totalAsleep: Int

    private var share: Double? {
        guard totalAsleep > 0 else { return nil }
        return Double(minutes) / Double(totalAsleep)
    }

    /// "typical 13–23%" — the figures mean nothing without it.
    private var comparison: String? {
        guard let share, let range = kind.typicalRange else { return nil }
        let typical = "typical \(Int(range.lowerBound * 100))–\(Int(range.upperBound * 100))%"
        if share < range.lowerBound { return "below \(typical)" }
        if share > range.upperBound { return "above \(typical)" }
        return typical
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(kind.colour)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.label)
                    .font(.system(size: 14, weight: .medium))
                if let comparison = comparison {
                    Text(comparison)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(HealthInsights.formatDuration(minutes))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if let share = share {
                    Text("\(Int((share * 100).rounded()))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Overnight vitals

private struct SleepVitalsCard: View {
    let day: HealthDay
    let history: [HealthDay]

    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("While you slept")
                    .font(.subheadline.weight(.semibold))
                if let hr = day.restingHr {
                    InfoRow(label: "Resting heart rate", value: "\(Int(hr)) bpm")
                }
                if let hrv = day.deepSleepHrvMs ?? day.hrvMs {
                    InfoRow(label: day.deepSleepHrvMs != nil ? "HRV (deep sleep)" : "HRV", value: "\(Int(hrv)) ms")
                }
                if let spo2 = day.spo2Pct {
                    InfoRow(label: "Blood oxygen", value: String(format: "%.1f%%", spo2))
                }
                breathingRows
                if let deviation = day.tempDeviationC {
                    InfoRow(
                        label: "Skin temperature",
                        value: String(format: "%+.1f°C vs your baseline", deviation)
                    )
                } else if let temp = day.wristTempC {
                    InfoRow(label: "Skin temperature", value: String(format: "%.1f°C", temp))
                }
            }
        }
    }

    @ViewBuilder
    private var breathingRows: some View {
        if let breathing = day.respiratoryRate {
            InfoRow(label: "Breathing rate", value: String(format: "%.1f /min", breathing))
        }
        if let rem = day.breathingRem, let deep = day.breathingDeep {
            InfoRow(
                label: "  REM / deep",
                value: String(format: "%.1f / %.1f", rem, deep)
            )
        }
    }
}
