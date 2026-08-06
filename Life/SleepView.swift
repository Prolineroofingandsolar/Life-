import SwiftUI

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
    private var calibration: SleepScoreCalibration.Model { appState.sleepCalibrationModel }

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
                        SleepHeadlineRow(day: night, history: nights)
                        SleepWarningsCard(day: night)
                        SleepScoreCard(night: night, history: nights, settings: settings, calibration: calibration)
                        SleepStagesCard(day: night, history: nights)
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
        guard let date = DayKey.date(from: day.dayKey) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private var dayNumber: String {
        guard let date = DayKey.date(from: day.dayKey) else { return "" }
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

    @State private var selected: SleepSegment?

    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let night, !night.segments.isEmpty {
                    SleepStageTimeline(
                        night: night,
                        lanes: laneKinds(night),
                        selected: $selected
                    )
                } else {
                    Text(unavailableMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // A block selected on Tuesday means nothing on Wednesday, and the card
        // keeps its identity when the night changes underneath it.
        .onChange(of: day.dayKey) { _, _ in selected = nil }
    }

    private func laneKinds(_ night: SleepNight) -> [SleepStageKind] {
        guard night.hasStages else { return [.asleep] }
        let used = Set(night.segments.map { SleepStageKind(apiValue: $0.stage) })
        return SleepStageKind.laneOrder.filter { used.contains($0) }
    }

    /// The night's headline, or the selected block's.
    ///
    /// One heading rather than a heading plus a read-out strip. Selecting a
    /// block replaces the total with what that block is, which keeps the
    /// answer where the eye already is and stops the card growing a row when
    /// you touch it.
    @ViewBuilder
    private var header: some View {
        if let selected {
            selectedHeader(selected)
        } else {
            nightHeader
        }
    }

    private func selectedHeader(_ segment: SleepSegment) -> some View {
        let kind = SleepStageKind(apiValue: segment.stage)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(kind.label)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(kind.colour)
                Button {
                    self.selected = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear selection")
                Spacer()
            }
            Text("\(segment.start.formatted(date: .omitted, time: .shortened)) – \(segment.end.formatted(date: .omitted, time: .shortened)) · \(HealthInsights.formatDuration(segment.minutes))")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var nightHeader: some View {
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

}

// MARK: - Stage timeline

/// The hypnogram, drawn as one labelled track per stage.
///
/// Replaces a `Chart` with four rows on a shared y-axis. That version was less
/// work but read worse: the stage names sat in a cramped axis gutter, every
/// stage carried the same weight, and there was no way to ask what a block
/// actually was.
///
/// Laid out by hand in a single coordinate space rather than as a stack of
/// independent rows, because the two things that make this chart legible both
/// need to cross row boundaries. The stalks joining consecutive blocks run from
/// one track's centre to the next, which is what turns four rows of disconnected
/// bars into one continuous night. The scrub line runs the full height, so a
/// moment reads as a moment rather than as a mark in one row.
private struct SleepStageTimeline: View {

    let night: SleepNight
    let lanes: [SleepStageKind]
    @Binding var selected: SleepSegment?

    /// Sorted once at construction. Every drawing pass walks this list several
    /// times over, and `segments` carries no ordering guarantee of its own.
    private let ordered: [SleepSegment]

    init(night: SleepNight, lanes: [SleepStageKind], selected: Binding<SleepSegment?>) {
        self.night = night
        self.lanes = lanes
        self._selected = selected
        self.ordered = night.segments.sorted { $0.start < $1.start }
    }

    /// Where the finger is, as a fraction of the night. Separate from
    /// `selected` because the line follows the touch while the block it
    /// resolves to stays put underneath it.
    @State private var scrubFraction: Double?

    // MARK: Geometry

    private let labelHeight: CGFloat = 18
    private let labelGap: CGFloat = 4
    private let trackHeight: CGFloat = 24
    private let rowGap: CGFloat = 14

    private var rowHeight: CGFloat { labelHeight + labelGap + trackHeight }

    private var chartHeight: CGFloat {
        CGFloat(lanes.count) * rowHeight + CGFloat(max(0, lanes.count - 1)) * rowGap
    }

    private func rowTop(_ index: Int) -> CGFloat {
        CGFloat(index) * (rowHeight + rowGap)
    }

    private func trackTop(_ index: Int) -> CGFloat {
        rowTop(index) + labelHeight + labelGap
    }

    private func trackCentre(_ index: Int) -> CGFloat {
        trackTop(index) + trackHeight / 2
    }

    private func laneIndex(of segment: SleepSegment) -> Int {
        let kind = SleepStageKind(apiValue: segment.stage)
        return lanes.firstIndex(of: kind) ?? 0
    }

    // MARK: Time

    private var windowStart: Date { night.start ?? Date() }
    private var windowEnd: Date { night.end ?? windowStart.addingTimeInterval(3600) }
    private var windowSeconds: Double { max(60, windowEnd.timeIntervalSince(windowStart)) }

    private func x(for time: Date, width: CGFloat) -> CGFloat {
        width * CGFloat(time.timeIntervalSince(windowStart) / windowSeconds)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    labelsAndTracks(width: width)
                    // Behind the blocks: a stalk is the join between two
                    // stages, not a thing in its own right.
                    stalks(width: width)
                    blocks(width: width)
                    scrubLine(width: width)
                }
                // Offsets don't contribute to layout, so without this the stack
                // sizes itself to one row and the gesture only responds near
                // the top of the chart.
                .frame(width: width, height: chartHeight, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(scrub(width: width))
            }
            .frame(height: chartHeight)

            axis
        }
    }

    // MARK: Tracks

    private func labelsAndTracks(width: CGFloat) -> some View {
        ForEach(lanes.indices, id: \.self) { index in
            let kind = lanes[index]
            let total = ordered
                .filter { SleepStageKind(apiValue: $0.stage) == kind }
                .reduce(0) { $0 + $1.minutes }

            Group {
                HStack(spacing: 4) {
                    Text(kind.label)
                        .font(.system(size: 14, weight: .semibold))
                    Text("• \(HealthInsights.formatDuration(total))")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(width: width, height: labelHeight, alignment: .leading)
                .offset(y: rowTop(index))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(kind.label), \(HealthInsights.formatDuration(total))")

                Capsule()
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: width, height: trackHeight)
                    .offset(y: trackTop(index))
            }
        }
    }

    // MARK: Stalks

    /// The thin vertical joins between one stage and the next.
    ///
    /// Tinted with the stage being entered and kept faint: they carry no
    /// information beyond "the night moved from here to there", and drawn at
    /// full strength they compete with the blocks, which do.
    private func stalks(width: CGFloat) -> some View {
        ForEach(Array(0..<max(0, ordered.count - 1)), id: \.self) { index in
            let from = ordered[index]
            let to = ordered[index + 1]
            let fromCentre = trackCentre(laneIndex(of: from))
            let toCentre = trackCentre(laneIndex(of: to))
            let position = x(for: to.start, width: width)

            Rectangle()
                .fill(SleepStageKind(apiValue: to.stage).colour.opacity(0.30))
                .frame(width: 2, height: abs(toCentre - fromCentre))
                .offset(x: min(max(position - 1, 0), max(width - 2, 0)),
                        y: min(fromCentre, toCentre))
        }
    }

    // MARK: Blocks

    private func blocks(width: CGFloat) -> some View {
        ForEach(ordered) { segment in
            let kind = SleepStageKind(apiValue: segment.stage)
            let length = Double(segment.minutes) * 60 / windowSeconds
            // A one-minute stage on an eight-hour night is a third of a point
            // wide. Floored so brief REM and deep blocks stay visible — they
            // are often the interesting part of the night, and a chart that
            // drops them is worse than one that slightly overstates them.
            let barWidth = max(3, width * CGFloat(length))
            let isSelected = selected?.id == segment.id

            Capsule()
                .fill(kind.colour)
                .frame(width: barWidth, height: trackHeight)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                        .frame(width: barWidth, height: trackHeight)
                )
                .offset(
                    x: min(x(for: segment.start, width: width), max(width - barWidth, 0)),
                    y: trackTop(laneIndex(of: segment))
                )
        }
    }

    // MARK: Scrub

    @ViewBuilder
    private func scrubLine(width: CGFloat) -> some View {
        if let selected, let scrubFraction {
            let position = min(max(CGFloat(scrubFraction) * width, 0), width)
            Rectangle()
                .fill(Color.primary)
                .frame(width: 1.5, height: chartHeight)
                .offset(x: position - 0.75)

            // The handle sits on the block being reported, so the line and the
            // heading above can't appear to describe different things.
            Circle()
                .fill(Color(.systemBackground))
                .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2))
                .frame(width: 12, height: 12)
                .offset(x: position - 6, y: trackCentre(laneIndex(of: selected)) - 6)
        }
    }

    /// One gesture for the whole chart.
    ///
    /// Per-block tap targets were the obvious approach and the wrong one: a
    /// two-minute block is under a point wide, which is untappable, and padding
    /// it to a usable size would overlap its neighbours. Scrubbing a shared time
    /// axis has neither problem — every horizontal position resolves to exactly
    /// one moment, and the stages are de-overlapped, so at most one block
    /// contains it.
    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                let fraction = min(max(Double(value.location.x / width), 0), 1)
                scrubFraction = fraction
                selected = segment(atFraction: fraction)
            }
    }

    private func segment(atFraction fraction: Double) -> SleepSegment? {
        let time = windowStart.addingTimeInterval(fraction * windowSeconds)
        return ordered.first { $0.start <= time && time < $0.end }
            // In a gap the source left, or past the final block: report the
            // nearest one rather than nothing, so dragging never blanks.
            ?? ordered.min {
                abs($0.start.timeIntervalSince(time)) < abs($1.start.timeIntervalSince(time))
            }
    }

    // MARK: Axis

    private var axis: some View {
        HStack(alignment: .top) {
            axisLabel(windowStart, caption: "Time you got to bed", alignment: .leading)
            Spacer(minLength: 4)
            axisLabel(
                windowStart.addingTimeInterval(windowSeconds / 2),
                caption: nil,
                alignment: .center
            )
            Spacer(minLength: 4)
            axisLabel(windowEnd, caption: "Time out of bed", alignment: .trailing)
        }
    }

    private func axisLabel(
        _ time: Date, caption: String?, alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(time.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Headline stats

private struct SleepHeadlineRow: View {
    let day: HealthDay
    let history: [HealthDay]

    /// "38m less than usual". Straight from measured data — no weighting, no
    /// formula, nothing to disagree with.
    private var durationComparison: String? {
        HealthInsights.comparison(
            day.sleepMin.map(Double.init),
            against: HealthInsights.recentAverage(history) { $0.sleepMin.map(Double.init) },
            formatter: { HealthInsights.formatDuration(Int($0.rounded())) },
            threshold: 15
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                SleepStat(title: "Asleep", value: day.sleepMin.map { HealthInsights.formatDuration($0) })
                SleepStat(title: "In bed", value: day.timeInBedMin.map { HealthInsights.formatDuration($0) })
                SleepStat(title: "Fell asleep", value: day.latencyMin.map { "\($0)m" })
                SleepStat(title: "Woke", value: day.awakenings.map { "\($0)×" })
            }
            if let durationComparison {
                Text(durationComparison)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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
    let calibration: SleepScoreCalibration.Model

    @Environment(AppState.self) private var appState
    @State private var showEntry = false

    private var existingComparison: SleepScoreComparison? { appState.sleepComparisons[night.dayKey] }

    private var breakdown: HealthInsights.SleepScoreBreakdown? {
        HealthInsights.sleepScoreBreakdown(
            for: night, history: history, settings: settings, calibration: calibration
        )
    }

    /// Why a night went unscored. Silence here reads as a bug; the measured
    /// figures above are unaffected and remain accurate.
    private var unscoreableReason: String {
        "Insufficient data was received for this night — without sleep stages there's nothing to score against. The measured figures above are unaffected and remain accurate."
    }

    private var measuredOn: String {
        guard let date = DayKey.date(from: night.dayKey) else { return night.dayKey }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        card
            .sheet(isPresented: $showEntry) {
                SleepScoreEntryView(day: night, estimate: breakdown?.estimate?.score)
            }
    }

    @ViewBuilder
    private var card: some View {
        HealthCard {
            if let breakdown = breakdown {
                scored(breakdown)
            } else {
                unscored
            }
        }
    }

    /// Kept small deliberately. `SettingsView` hit *"unable to type-check this
    /// expression in reasonable time"* from a single body with fewer moving
    /// parts than this card, so each section is its own builder.
    private func scored(_ breakdown: HealthInsights.SleepScoreBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(breakdown)
            rankLine
            // Components exist only for Life's own estimate. An official score
            // is shown exactly as the source gave it, with nothing added, so
            // there is no working to show.
            componentBars(breakdown.estimate)
            calibrationSection(breakdown)
            googleScoreButton
            provenanceLine(breakdown)
            disclaimer(breakdown)
        }
    }

    private func header(_ breakdown: HealthInsights.SleepScoreBreakdown) -> some View {
        // Pulled out of the interpolation so the type checker sees a plain
        // String rather than resolving it inside a view builder.
        let total = String(breakdown.total)
        return VStack(alignment: .leading, spacing: 6) {
            Text(breakdown.title)
                .font(.footnote.weight(.medium))
                .foregroundColor(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(total)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(breakdown.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(breakdown.tone.colour)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func componentBars(_ estimate: SleepScore.Result?) -> some View {
        if let estimate {
            SleepScoreBar(title: "Duration", earned: estimate.components.duration, colour: .indigo)
            SleepScoreBar(title: "Continuity", earned: estimate.components.continuity, colour: .teal)
            SleepScoreBar(title: "Restorative sleep", earned: estimate.components.stages, colour: .purple)
            SleepScoreBar(title: "Latency", earned: estimate.components.latency, colour: .blue)
            SleepScoreBar(title: "Consistency", earned: estimate.components.consistency, colour: AppTheme.primary)
            confidenceLine(estimate)
        }
    }

    private var unscored: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No estimated score for this night")
                .font(.subheadline.weight(.semibold))
            Text(unscoreableReason)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where this night ranks among recent ones. Derived purely from measured
    /// data, so it's the line to trust if it and the score ever disagree.
    @ViewBuilder
    private var rankLine: some View {
        if let text = rankText {
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var rankText: String? {
        guard let rank = HealthInsights.nightRank(for: night, in: history, settings: settings) else {
            return nil
        }
        return ordinal(rank.rank) + " best of your last " + String(rank.of) + " nights"
    }

    private func ordinal(_ value: Int) -> String {
        switch value {
        case 1: return "Best"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(value)th"
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

    /// Confidence is reported alongside the score and never alters it. A night
    /// with thin data does not get a higher number to compensate.
    @ViewBuilder
    private func confidenceLine(_ estimate: SleepScore.Result) -> some View {
        HStack(spacing: 6) {
            Text("Confidence: " + estimate.confidence.rawValue.capitalized)
                .font(.caption2)
                .foregroundColor(estimate.confidence == .high ? .secondary : .orange)
            if !estimate.missingFields.isEmpty {
                Text("· missing " + estimate.missingFields.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
    }

    /// The personal adjustment, shown only once calibration is actually being
    /// applied. Kept off the dashboard — this is detail-screen material.
    @ViewBuilder
    private func calibrationSection(_ breakdown: HealthInsights.SleepScoreBreakdown) -> some View {
        if let adjustment = breakdown.adjustment, adjustment.isPersonalised {
            VStack(alignment: .leading, spacing: 3) {
                Divider().padding(.vertical, 2)
                InfoRow(label: "Original estimate", value: String(adjustment.baseScore))
                InfoRow(label: "Personal adjustment", value: Self.signed(adjustment.correction))
                InfoRow(label: "Final estimate", value: String(adjustment.adjustedScore))
                Text(Self.personalisedNote(adjustment.stage.comparisonCount))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .font(.footnote)
        }
    }

    /// "+4" / "-6". Built outside the view builder so the ternary and the
    /// rounding aren't type-checked as part of a `Text` expression.
    private static func signed(_ value: Double) -> String {
        let whole = Int(value.rounded())
        return whole >= 0 ? "+" + String(whole) : String(whole)
    }

    private static func personalisedNote(_ count: Int) -> String {
        "Personalised using " + String(count) + " Google Health comparisons"
    }

    @ViewBuilder
    private var googleScoreButton: some View {
        Button {
            showEntry = true
        } label: {
            Label(
                existingComparison == nil ? "Add Google Health score" : "Edit Google Health score",
                systemImage: "plus.circle"
            )
            .font(.footnote)
        }
        .buttonStyle(.plain)
        .foregroundColor(AppTheme.primary)

        if let text = comparisonNote {
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comparisonNote: String? {
        guard let comparison = existingComparison else { return nil }
        let difference = comparison.baseScore - comparison.googleScore
        return "Google Health scored this night " + String(comparison.googleScore)
            + ". Difference: " + String(difference) + "."
    }

    @ViewBuilder
    private func disclaimer(_ breakdown: HealthInsights.SleepScoreBreakdown) -> some View {
        if breakdown.isEstimate {
            Text("This estimate uses sleep stages and available overnight health data imported from Google Health. It may differ from Google because Google uses additional Fitbit sensor data and a private scoring model.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SleepScoreBar: View {
    let title: String
    /// A 0–100 component score, not a share of the total.
    let earned: Double
    var outOf: Double = 100
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
    let history: [HealthDay]

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
                        SleepStageRow(kind: row.kind, minutes: row.minutes, totalAsleep: day.sleepMin ?? 0, history: history)
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
    var history: [HealthDay] = []

    private var share: Double? {
        guard totalAsleep > 0 else { return nil }
        return Double(minutes) / Double(totalAsleep)
    }

    /// This stage's usual share across recent nights.
    private var personalAverage: Double? {
        HealthInsights.recentAverage(history) { day in
            guard let asleep = day.sleepMin, asleep > 0 else { return nil }
            let stageMinutes: Int?
            switch kind {
            case .deep:  stageMinutes = day.deepMin
            case .rem:   stageMinutes = day.remMin
            case .light: stageMinutes = day.lightMin
            case .awake: stageMinutes = day.awakeMin
            default:     stageMinutes = nil
            }
            guard let stageMinutes else { return nil }
            return Double(stageMinutes) / Double(asleep)
        }
    }

    /// Your own recent average first — it's measured, and it's what actually
    /// tells you whether a night was unusual *for you*. The population range is
    /// the fallback until there's enough history to have a personal one.
    private var comparison: String? {
        if let share, let mine = personalAverage {
            let delta = (share - mine) * 100
            if abs(delta) < 2 { return "about your usual \(Int((mine * 100).rounded()))%" }
            return "\(delta > 0 ? "above" : "below") your usual \(Int((mine * 100).rounded()))%"
        }
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
                // Both HRV figures name their measurement window. An unqualified
                // "HRV" here against an unqualified "HRV" on the Health tab
                // showed two numbers a millisecond apart with no way to tell
                // that they measure different stretches of the same night.
                if let hrv = day.deepSleepHrvMs {
                    InfoRow(label: "HRV (deep sleep)", value: "\(Int(hrv)) ms")
                } else if let hrv = day.hrvMs {
                    InfoRow(label: "HRV (overnight average)", value: "\(Int(hrv)) ms")
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
