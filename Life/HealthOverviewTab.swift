import SwiftUI

// MARK: - Health Overview Tab

/// Everything Life stores about your health, on one screen, with each figure
/// labelled by where it actually came from.
///
/// This exists because "View all health data" used to open the Sleep tab. The
/// button promised a whole and delivered a part, and there was no screen the
/// promise could have been kept by — Sleep, Recovery and Activity each show one
/// domain in depth and nothing showed them together.
///
/// Every row states its provider. A weight typed in by hand, a resting heart
/// rate from a Fitbit and a body-fat percentage imported from Apple Health used
/// to look identical, so a figure that seemed wrong gave no clue as to which
/// device to go and check.
@MainActor
struct HealthOverviewTab: View {

    @Environment(AppState.self) private var appState

    private var history: [HealthDay] { appState.healthHistory }
    private var settings: HealthSettings { appState.healthSettings }

    /// The provider currently feeding the imported metrics.
    private var importProvider: HealthProvider? {
        HealthSync.source(for: settings).provider
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if history.isEmpty && appState.weightEntries.isEmpty {
                    HealthEmptyCard(
                        icon: "square.stack.3d.up",
                        title: "No health data yet",
                        message: "Connect a tracker or log something by hand, and every figure Life holds will be listed here with the source it came from."
                    )
                } else {
                    sleepCard
                    recoveryCard
                    activityCard
                    bodyCard
                    provenanceNote
                }
            }
            .padding(16)
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var sleepCard: some View {
        let night = appState.lastNightSleep
        OverviewSection(title: "Sleep", icon: "bed.double.fill", colour: .indigo) {
            OverviewRow(
                label: "Last night",
                value: night?.sleepMin.map { HealthInsights.formatDuration($0) },
                source: night.flatMap { sleepProvider(for: $0) })
            OverviewRow(
                label: "Time in bed",
                value: night?.timeInBedMin.map { HealthInsights.formatDuration($0) },
                source: night.flatMap { sleepProvider(for: $0) })
            OverviewRow(
                label: "Efficiency",
                value: night?.sleepEfficiency.map { String(format: "%.0f%%", $0 * 100) },
                source: .calculated)
        }
    }

    @ViewBuilder
    private var recoveryCard: some View {
        OverviewSection(title: "Recovery", icon: "heart.fill", colour: .pink) {
            OverviewRow(
                label: "Resting heart rate",
                value: latest { $0.restingHr }.map { "\(Int($0.rounded())) bpm" },
                source: importProvider)
            // Two different HRV numbers used to appear under one label on two
            // screens — an overnight mean of 109 ms here, a deep-sleep RMSSD of
            // 110 ms there — with nothing to say they measured different
            // windows. Both are shown, each named for what it is.
            OverviewRow(
                label: "HRV (overnight average)",
                value: latest { $0.hrvMs }.map { "\(Int($0.rounded())) ms" },
                source: importProvider)
            OverviewRow(
                label: "HRV (deep sleep)",
                value: latest { $0.deepSleepHrvMs }.map { "\(Int($0.rounded())) ms" },
                source: importProvider)
            OverviewRow(
                label: "Blood oxygen",
                value: latest { $0.spo2Pct }.map { String(format: "%.0f%%", $0) },
                source: importProvider)
            OverviewRow(
                label: "Breathing rate",
                value: latest { $0.respiratoryRate }.map { String(format: "%.1f /min", $0) },
                source: importProvider)
        }
    }

    @ViewBuilder
    private var activityCard: some View {
        let today = appState.careDays[appState.todayKey]
        OverviewSection(title: "Activity today", icon: "figure.walk", colour: AppTheme.primary) {
            OverviewRow(
                label: "Steps",
                value: today.flatMap { $0.steps > 0 ? $0.steps.formatted() : nil },
                source: importProvider)
            // Named "active calories" rather than "calories": this is the burn
            // above resting, not total daily expenditure. Total needs a basal
            // rate no connected source reports, so it isn't shown at all rather
            // than shown wrong.
            OverviewRow(
                label: "Active calories",
                value: latest { $0.activeEnergyKcal }.map { "\(Int($0.rounded())) kcal" },
                source: importProvider)
            OverviewRow(
                label: "Distance",
                value: latest { $0.distanceKm }.map { String(format: "%.2f km", $0) },
                source: importProvider)
            OverviewRow(
                label: "Active minutes",
                value: latest { $0.exerciseMinutes.map(Double.init) }.map { "\(Int($0)) min" },
                source: importProvider)
        }
    }

    @ViewBuilder
    private var bodyCard: some View {
        let weight = appState.weightEntries.max { $0.date < $1.date }
        let comp = appState.bodyCompEntries.max { $0.date < $1.date }
        OverviewSection(title: "Body", icon: "scalemass.fill", colour: .green) {
            OverviewRow(
                label: "Weight",
                value: weight.map { "\($0.valueKg.weightDisplay) kg" },
                source: weight.flatMap { HealthProvider(storageValue: $0.source) })
            OverviewRow(
                label: "Body fat",
                value: comp?.bodyFatPct.map { "\(($0 * 100).percentDisplay)%" },
                source: comp.flatMap { HealthProvider(storageValue: $0.source) })
            OverviewRow(
                label: "Lean mass",
                value: comp?.leanMassKg.map { "\($0.weightDisplay) kg" },
                source: comp.flatMap { HealthProvider(storageValue: $0.source) })
            OverviewRow(
                label: "BMI",
                value: comp?.bmi.map { $0.weightDisplay },
                source: comp.flatMap { HealthProvider(storageValue: $0.source) })
        }
    }

    @ViewBuilder
    private var provenanceNote: some View {
        Text("Each figure is labelled with the source it came from. A dash means nothing has been recorded — it is not a reading of zero.")
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: Helpers

    /// A night names its own recording device where the import supplied one,
    /// which can differ from the currently connected source when history was
    /// imported from a tracker since disconnected.
    private func sleepProvider(for day: HealthDay) -> HealthProvider? {
        HealthProvider(storageValue: day.sleepSourceDevice) ?? importProvider
    }

    private func latest(_ metric: (HealthDay) -> Double?) -> Double? {
        for day in history.reversed() {
            if let value = metric(day) { return value }
        }
        return nil
    }
}

// MARK: - Components

private struct OverviewSection<Content: View>: View {
    let title: String
    let icon: String
    let colour: Color
    @ViewBuilder var content: Content

    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colour)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                }
                content
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// One metric, its value, and the provider that supplied it.
private struct OverviewRow: View {
    let label: String
    let value: String?
    var source: HealthProvider?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value ?? "—")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(value == nil ? .secondary : .primary)
                if value != nil, let source {
                    Text(source.detailedName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        guard let value else { return "\(label), no data recorded" }
        guard let source else { return "\(label), \(value)" }
        return "\(label), \(value), from \(source.detailedName)"
    }
}
