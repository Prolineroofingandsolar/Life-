import SwiftUI
import Charts

// MARK: - Today's curve

/// The day's heart rate as a curve, one line per source.
///
/// Two lines rather than one merged series on purpose: the band records all
/// day while heart-rate-capable AirPods only record during a workout, and
/// flattening them into a single line would imply a continuous reading that
/// doesn't exist. Nothing here is summed, so two sources can't inflate a total
/// the way they can with steps.
struct HeartRateCurveCard: View {

    let store: HeartRateStore

    private var sources: [HeartRateSource] { store.presentSources }

    private var summary: String? {
        guard let figures = store.dailyAggregates else { return nil }
        return "Low " + String(Int(figures.min.rounded()))
            + " · Average " + String(Int(figures.average.rounded()))
            + " · High " + String(Int(figures.max.rounded()))
    }

    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                if sources.isEmpty {
                    emptyMessage
                } else {
                    chart
                    if sources.count > 1 { legend }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Heart rate today")
                .font(.subheadline.weight(.semibold))
            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var emptyMessage: some View {
        Text(store.message ?? "No heart-rate readings have come through for today yet.")
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // Deliberately no shaded zone bands behind the line. The band boundaries
    // are personal — they depend on your maximum heart rate — and Life isn't
    // told what yours are, so drawing them would mean inventing them from a
    // rule of thumb and presenting the guess as data.
    private var chart: some View {
        Chart {
            ForEach(sources) { source in
                ForEach(store.series(for: source)) { sample in
                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("bpm", sample.bpm),
                        series: .value("Source", source.label)
                    )
                    .foregroundStyle(Self.colour(for: source))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .frame(height: 180)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                AxisGridLine()
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(sources) { source in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.colour(for: source))
                        .frame(width: 10, height: 10)
                    Text(source.label)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    static func colour(for source: HeartRateSource) -> Color {
        switch source {
        case .fitbit:      return .pink
        case .appleHealth: return .purple
        }
    }
}

// MARK: - Zones

private struct ZoneRow: Identifiable {
    let zone: HeartRateZone
    let minutes: Int
    var id: String { zone.rawValue }
}

/// Minutes spent in each heart-rate zone, straight from the source's own
/// `timeInHeartRateZone` totals — not derived from the curve, so these match
/// what the Fitbit app reports.
struct HeartRateZonesCard: View {

    let day: HealthDay?

    private var rows: [ZoneRow] {
        guard let day else { return [] }
        var out: [ZoneRow] = []
        if let minutes = day.hrZoneLightMin, minutes > 0 {
            out.append(ZoneRow(zone: .light, minutes: minutes))
        }
        if let minutes = day.hrZoneModerateMin, minutes > 0 {
            out.append(ZoneRow(zone: .moderate, minutes: minutes))
        }
        if let minutes = day.hrZoneVigorousMin, minutes > 0 {
            out.append(ZoneRow(zone: .vigorous, minutes: minutes))
        }
        if let minutes = day.hrZonePeakMin, minutes > 0 {
            out.append(ZoneRow(zone: .peak, minutes: minutes))
        }
        return out
    }

    private var longest: Int {
        max(1, rows.map(\.minutes).max() ?? 1)
    }

    var body: some View {
        if !rows.isEmpty {
            HealthCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Time in zones")
                        .font(.subheadline.weight(.semibold))
                    ForEach(rows) { row in
                        HeartRateZoneBar(zone: row.zone, minutes: row.minutes, longest: longest)
                    }
                }
            }
        }
    }
}

private struct HeartRateZoneBar: View {

    let zone: HeartRateZone
    let minutes: Int
    let longest: Int

    private var share: Double {
        longest > 0 ? min(1, Double(minutes) / Double(longest)) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(zone.label)
                    .font(.system(size: 13))
                Spacer()
                Text(HealthInsights.formatDuration(minutes))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(zone.colour.opacity(0.15))
                    Capsule()
                        .fill(zone.colour)
                        .frame(width: geometry.size.width * share)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Workouts

/// The day's exercise sessions with their heart-rate figures.
struct WorkoutsCard: View {

    let store: HeartRateStore

    var body: some View {
        if !store.sessions.isEmpty {
            HealthCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Workouts")
                        .font(.subheadline.weight(.semibold))
                    ForEach(store.sessions) { session in
                        WorkoutRow(session: session, store: store)
                    }
                }
            }
        }
    }
}

private struct WorkoutRow: View {

    let session: ExerciseSession
    let store: HeartRateStore

    /// The source's own figures where it supplied them, otherwise derived from
    /// the sample curve clipped to this session. Which one it is doesn't change
    /// the meaning, so it isn't labelled — but a derived figure is only as
    /// complete as the readings that synced.
    private var beats: (average: Double, maximum: Double)? {
        if let average = session.averageBpm, let maximum = session.maximumBpm {
            return (average, maximum)
        }
        return store.heartRate(during: session)
    }

    private var detail: String {
        var parts = [HealthInsights.formatDuration(session.minutes)]
        if let beats {
            parts.append("avg " + String(Int(beats.average.rounded())))
            parts.append("max " + String(Int(beats.maximum.rounded())))
        }
        if let kcal = session.kcal {
            parts.append(String(Int(kcal.rounded())) + " kcal")
        }
        return parts.joined(separator: " · ")
    }

    private var startTime: String {
        session.start.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.pink)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.name)
                    .font(.system(size: 14, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(startTime)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
