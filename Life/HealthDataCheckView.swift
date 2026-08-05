import SwiftUI

// MARK: - Data check

/// Exactly what Life has stored, day by day.
///
/// This screen exists because "the numbers look wrong" has three completely
/// different causes that all look identical on a chart: the band hasn't synced
/// yet, a metric was refused during import, or it imported fine and was added
/// up wrong. Each needs an opposite fix, and without somewhere to look there
/// was no way to tell which — every report turned into a round of guessing.
///
/// Deliberately shows the *stored* values with no derivation, no averaging and
/// no gap-filling. A dash means nothing is stored for that day, which is a
/// different statement from a zero.
struct HealthDataCheckView: View {

    @Environment(AppState.self) private var appState

    private var settings: HealthSettings { appState.healthSettings }

    /// Newest first — the recent days are the ones being questioned.
    private var rows: [DataCheckRow] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = date.dayKey
            return DataCheckRow(
                dayKey: key,
                date: date,
                steps: appState.careDays[key]?.steps,
                health: appState.healthDays[key]
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                tableCard
                explainer
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Data check")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Status

    private var lastSynced: String {
        guard let date = settings.lastSyncedAt else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var weekStart: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = Calendar.current.firstWeekday - 1
        guard symbols.indices.contains(index) else { return "—" }
        return symbols[index]
    }

    @MainActor @ViewBuilder
    private var statusCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.subheadline.weight(.semibold))
                InfoRow(label: "Reading from", value: HealthSync.source(for: settings).detailedName)
                InfoRow(label: "Fitbit connected", value: GoogleHealthService.shared.isConnected ? "Yes" : "No")
                InfoRow(label: "Last sync", value: lastSynced)
                InfoRow(label: "Days stored", value: String(appState.healthDays.count))
                // The week boundary follows the phone's region setting, and a
                // Sunday-start region makes "this week" mean today alone on a
                // Sunday. Worth being able to see rather than deduce.
                InfoRow(label: "Week starts", value: weekStart)
                failures
            }
        }
    }

    @ViewBuilder
    private var failures: some View {
        if settings.lastSyncFailures.isEmpty {
            InfoRow(label: "Failed metrics", value: "None")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Failed metrics")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text(settings.lastSyncFailures.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Table

    @ViewBuilder
    private var tableCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 14 days")
                    .font(.subheadline.weight(.semibold))
                DataCheckHeaderRow()
                Divider()
                ForEach(rows) { row in
                    DataCheckDayRow(row: row)
                }
            }
        }
    }

    @ViewBuilder
    private var explainer: some View {
        Text("A dash means nothing is stored for that day — which is different from a recorded zero. Today is always partial: it only holds what your tracker had synced at the time above. Compare a completed day like yesterday against the Fitbit app; if that one matches and today doesn't, nothing is broken, the band simply hasn't sent today's yet.")
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Rows

private struct DataCheckRow: Identifiable {
    let dayKey: String
    let date: Date
    let steps: Int?
    let health: HealthDay?

    var id: String { dayKey }

    var day: String { date.formatted(.dateTime.weekday(.abbreviated).day()) }

    /// Stored values, formatted, with a dash for absent rather than zero.
    var stepsText: String {
        guard let steps, steps > 0 else { return "—" }
        return steps.formatted()
    }

    var sleepText: String {
        guard let minutes = health?.sleepMin else { return "—" }
        return HealthInsights.formatDuration(minutes)
    }

    var heartText: String {
        guard let hr = health?.restingHr else { return "—" }
        return String(Int(hr.rounded()))
    }

    var activeText: String {
        guard let minutes = health?.exerciseMinutes else { return "—" }
        return String(minutes)
    }
}

private struct DataCheckHeaderRow: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Day").frame(width: 62, alignment: .leading)
            Text("Steps").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Sleep").frame(maxWidth: .infinity, alignment: .trailing)
            Text("HR").frame(width: 34, alignment: .trailing)
            Text("Act").frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
    }
}

private struct DataCheckDayRow: View {

    let row: DataCheckRow

    var body: some View {
        HStack(spacing: 4) {
            Text(row.day)
                .frame(width: 62, alignment: .leading)
                .foregroundColor(.secondary)
            Text(row.stepsText).frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.sleepText).frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.heartText).frame(width: 34, alignment: .trailing)
            Text(row.activeText).frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 12, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
