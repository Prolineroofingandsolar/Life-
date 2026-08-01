import SwiftUI

// MARK: - Health View

/// The Health tab: one scrolling overview, with the detail screens hanging off
/// it behind chevrons.
///
/// Everything here is derived from what Apple Health hands over — there's no
/// stored state of its own beyond `HealthDay`. Scores are Life's own composites
/// (see `HealthInsights`), and each one refuses to render rather than inventing
/// a number from too little history.
struct HealthView: View {

    @Environment(AppState.self) private var appState
    @State private var isSyncing = false
    @State private var syncMessage: String? = nil
    @State private var sources: [String] = []
    @State private var healthKit = HealthKitManager()

    private var health: [HealthDay] { appState.healthHistory }
    private var activity: [ActivityDay] { appState.activityHistory }
    private var settings: HealthSettings { appState.healthSettings }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if health.isEmpty {
                        emptyState
                    } else {
                        guidanceLine
                        scoreCard
                        guidanceCard
                        calloutsSection
                        exertionRow
                        bodyCard
                        vitalsCard
                    }
                    sourcesCard
                    allDataLink
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { syncPill }
            }
            .task { await loadSources() }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var syncPill: some View {
        Button {
            sync()
        } label: {
            HStack(spacing: 6) {
                if isSyncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle()
                        .fill(settings.hasBackfilled ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                }
                Text(isSyncing ? "Syncing" : "Sync")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.primary)
            }
        }
        .disabled(isSyncing)
    }

    @ViewBuilder
    private var guidanceLine: some View {
        let guidance = HealthInsights.guidance(readiness: readiness, health: health, settings: settings)
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(guidance.tone.colour.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(guidance.tone.colour)
            }
            Text(guidance.headline)
                .font(.system(size: 16, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Scores

    private var readiness: HealthInsights.Score? {
        HealthInsights.readinessScore(health, settings: settings)
    }

    private var sleep: HealthInsights.Score? {
        HealthInsights.sleepScore(health, settings: settings)
    }

    private var activityScore: HealthInsights.Score? {
        HealthInsights.activityScore(activity, settings: settings, stepGoal: appState.careSettings.stepGoal)
    }

    /// Each dial is its own drill-down — tapping Sleep is the main way into the
    /// sleep screen, so it has to be tappable rather than decorative.
    @ViewBuilder
    private var scoreCard: some View {
        HealthCard {
            HStack(alignment: .top, spacing: 4) {
                NavigationLink { HealthDetailView(initialTab: .recovery) } label: {
                    HealthGauge(score: readiness, title: "Readiness", icon: "figure.stand", colour: AppTheme.primary)
                }
                .buttonStyle(.plain)

                NavigationLink { SleepView() } label: {
                    HealthGauge(score: sleep, title: "Sleep", icon: "moon.stars.fill", colour: .blue)
                }
                .buttonStyle(.plain)

                NavigationLink { HealthDetailView(initialTab: .activity) } label: {
                    HealthGauge(score: activityScore, title: "Activity", icon: "flame.fill", colour: .orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var guidanceCard: some View {
        let guidance = HealthInsights.guidance(readiness: readiness, health: health, settings: settings)
        NavigationLink {
            HealthDetailView(initialTab: .recovery)
        } label: {
            HealthCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(guidance.tone.colour.opacity(0.15)).frame(width: 40, height: 40)
                        Image(systemName: "target")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(guidance.tone.colour)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Today's guidance")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(guidance.tone.colour)
                        Text(guidance.headline)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(guidance.detail)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Callouts

    /// Only rendered when there's something worth saying — an empty list means
    /// the data doesn't support any observation yet, and padding that with
    /// filler would be worse than silence.
    @ViewBuilder
    private var calloutsSection: some View {
        let items = HealthInsights.callouts(health: health, activity: activity, settings: settings)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("What stands out")
                    .font(.system(size: 17, weight: .semibold))
                ForEach(items) { callout in
                    HealthCalloutRow(callout: callout)
                }
            }
        }
    }

    // MARK: Exertion + recovery pair

    @ViewBuilder
    private var exertionRow: some View {
        HStack(spacing: 12) {
            exertionCard
            recoveryTrendCard
        }
    }

    @ViewBuilder
    private var exertionCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Exertion")
                    .font(.subheadline.weight(.semibold))
                if let value = HealthInsights.exertion(activity) {
                    let described = HealthInsights.exertionLabel(value)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", value))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        HealthPill(text: described.0, tone: described.1)
                    }
                    Text("Today, out of 10")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Needs a few days of activity")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var recoveryTrendCard: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("HRV")
                    .font(.subheadline.weight(.semibold))
                if let latest = latestHealth({ $0.hrvMs }) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(Int(latest))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("ms")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    hrvTrendCaption
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Not recorded")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var hrvTrendCaption: some View {
        if let trend = HealthInsights.trend(health, metric: { $0.hrvMs }) {
            let pct = Int(trend.deltaPercent.rounded())
            Text(pct >= 0 ? "+\(pct)% vs 30-day" : "\(pct)% vs 30-day")
                .font(.caption2)
                .foregroundColor(pct >= 0 ? .green : .orange)
        } else {
            Text("Building baseline")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: Body

    @ViewBuilder
    private var bodyCard: some View {
        NavigationLink { BodyView() } label: {
            HealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    HealthCardHeader(title: "Body")
                    HStack(alignment: .top, spacing: 0) {
                        HealthMiniMetric(
                            icon: "scalemass.fill", colour: .green, title: "Weight",
                            value: weightValue, unit: "kg", delta: weightDelta, unitForDelta: "kg")
                        HealthMiniMetric(
                            icon: "percent", colour: .orange, title: "Body fat",
                            value: bodyFatValue, unit: "%", delta: bodyFatDelta, unitForDelta: "%")
                        HealthMiniMetric(
                            icon: "figure.arms.open", colour: .purple, title: "Lean mass",
                            value: leanValue, unit: "kg", delta: leanDelta, unitForDelta: "kg")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Vitals

    @ViewBuilder
    private var vitalsCard: some View {
        NavigationLink { HealthDetailView(initialTab: .recovery) } label: {
            HealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    HealthCardHeader(title: "Vitals")
                    HStack(alignment: .top, spacing: 0) {
                        vitalMetric(.restingHr, title: "Resting HR", icon: "heart.fill", colour: .pink)
                        vitalMetric(.hrv, title: "HRV", icon: "waveform.path.ecg", colour: .purple)
                        vitalMetric(.spo2, title: "SpO₂", icon: "drop.fill", colour: .blue)
                        vitalMetric(.wristTemp, title: "Temp", icon: "thermometer.medium", colour: .orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func vitalMetric(
        _ metric: RecoveryMetric, title: String, icon: String, colour: Color
    ) -> some View {
        let latest = latestHealth { metric.value(from: $0) }
        let change = HealthInsights.changeFromPrevious(health) { metric.value(from: $0) }
        return HealthMiniMetric(
            icon: icon, colour: colour, title: title,
            value: latest.map { metric.format($0) },
            unit: metric.unit,
            delta: change,
            unitForDelta: metric.unit,
            deltaCaption: "vs previous"
        )
    }

    // MARK: Sources

    @ViewBuilder
    private var sourcesCard: some View {
        if !sources.isEmpty {
            HealthCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sources")
                        .font(.subheadline.weight(.semibold))
                    ForEach(sources, id: \.self) { source in
                        HStack(spacing: 10) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text(source)
                                .font(.footnote)
                            Spacer()
                        }
                    }
                    Text("Apps and devices writing into Apple Health that Life can read.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var allDataLink: some View {
        NavigationLink { HealthDetailView(initialTab: .sleep) } label: {
            HealthCard {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("View all health data")
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

    @ViewBuilder
    private var emptyState: some View {
        HealthEmptyCard(
            icon: "heart.text.square",
            title: "No health data yet",
            message: "Tap Sync to pull your sleep, heart rate and activity from Apple Health. Anything your watch, ring or tracker writes there will show up here."
        )
        if let syncMessage = syncMessage {
            Text(syncMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Body values

    private var weightValue: String? {
        appState.weightEntries.sorted { $0.date < $1.date }.last.map { $0.valueKg.formatted1 }
    }

    private var weightDelta: Double? {
        deltaOverWeek(appState.weightEntries.sorted { $0.date < $1.date }.map { ($0.date, $0.valueKg) })
    }

    private var bodyFatValue: String? {
        latestComp { $0.bodyFatPct }.map { String(format: "%.1f", $0 * 100) }
    }

    private var bodyFatDelta: Double? {
        deltaOverWeek(compSeries { $0.bodyFatPct }).map { $0 * 100 }
    }

    private var leanValue: String? {
        latestComp { $0.leanMassKg }.map { $0.formatted1 }
    }

    private var leanDelta: Double? {
        deltaOverWeek(compSeries { $0.leanMassKg })
    }

    private func compSeries(_ metric: (BodyCompEntry) -> Double?) -> [(Date, Double)] {
        appState.bodyCompEntries
            .sorted { $0.date < $1.date }
            .compactMap { entry in metric(entry).map { (entry.date, $0) } }
    }

    private func latestComp(_ metric: (BodyCompEntry) -> Double?) -> Double? {
        compSeries(metric).last?.1
    }

    /// Change between the latest reading and the closest one at least 7 days
    /// older. Nil when there's nothing that far back to compare against.
    private func deltaOverWeek(_ series: [(Date, Double)]) -> Double? {
        guard let latest = series.last else { return nil }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: latest.0) else { return nil }
        guard let earlier = series.last(where: { $0.0 <= cutoff }) else { return nil }
        return latest.1 - earlier.1
    }

    private func latestHealth(_ metric: (HealthDay) -> Double?) -> Double? {
        for day in health.reversed() {
            if let value = metric(day) { return value }
        }
        return nil
    }

    // MARK: Actions

    @MainActor
    private func loadSources() async {
        guard sources.isEmpty else { return }
        switch HealthSync.activeSource {
        case .fitbit:      sources = ["Fitbit"]
        case .appleHealth: sources = await healthKit.fetchDataSources()
        case .none:        sources = []
        }
    }

    private func sync() {
        isSyncing = true
        syncMessage = nil
        Task {
            // A manual sync reaches further back than the background one — this
            // is the button people press when a chart looks short. Fitbit's
            // 150-requests-per-hour budget is why it's a year here and a week
            // on the automatic path, not a year everywhere.
            let outcome = await HealthSync.run(appState: appState, healthKit: healthKit, daysBack: 365)
            if HealthSync.activeSource == .appleHealth {
                sources = await healthKit.fetchDataSources()
            }
            isSyncing = false
            syncMessage = outcome.message
        }
    }
}

// MARK: - Detail Hub

/// The drill-down behind the overview's chevrons — the full charts for sleep,
/// recovery and activity.
struct HealthDetailView: View {

    let initialTab: DetailTab
    @State private var selectedTab: DetailTab

    init(initialTab: DetailTab = .sleep) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    enum DetailTab: String, CaseIterable, Identifiable {
        case sleep = "Sleep"
        case recovery = "Recovery"
        case activity = "Activity"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                ForEach(DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            content
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Health Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .sleep:    SleepView()
        case .recovery: HealthRecoveryTab()
        case .activity: HealthActivityTab()
        }
    }
}

// MARK: - Components

/// Health's own card chrome. Train's `CardContainer`/`StatCard` are private to
/// `TrainProgressHubView.swift`, and `StatCard` is separately defined in
/// `WorkoutSummaryView` and `TaskStatsView` too — promoting one would shadow the
/// others, so Health carries its own.
struct HealthCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

struct HealthCardHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
    }
}

/// A 270° score dial. Shows a dash rather than a ring when the score is nil, so
/// "not enough data" never reads as a bad score.
struct HealthGauge: View {
    let score: HealthInsights.Score?
    let title: String
    let icon: String
    let colour: Color

    private var progress: Double {
        Double(score?.value ?? 0) / 100
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundColor(.secondary)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(colour.opacity(0.15), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * progress)
                    .stroke(colour, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(135))
                VStack(spacing: 0) {
                    Text(score.map { "\($0.value)" } ?? "—")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(score?.label ?? "No data")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(score.map { $0.tone.colour } ?? .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 92, height: 92)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colour)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One figure in a multi-metric row, with its change since a reference point.
struct HealthMiniMetric: View {
    let icon: String
    let colour: Color
    let title: String
    let value: String?
    let unit: String
    var delta: Double? = nil
    var unitForDelta: String = ""
    var deltaCaption: String = "vs last 7 days"

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(colour.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colour)
            }
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if value != nil {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            deltaLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var deltaLine: some View {
        if let delta = delta, abs(delta) >= 0.05 {
            let up = delta > 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text("\(abs(delta).formatted1)\(unitForDelta)")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)
            Text(deltaCaption)
                .font(.system(size: 9))
                .foregroundColor(Color(.tertiaryLabel))
                .lineLimit(1)
        } else {
            Text("—")
                .font(.system(size: 10))
                .foregroundColor(Color(.tertiaryLabel))
        }
    }
}

struct HealthPill: View {
    let text: String
    let tone: HealthInsights.Tone
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tone.colour.opacity(0.16)))
            .foregroundColor(tone.colour)
    }
}

struct HealthCalloutRow: View {
    let callout: HealthInsights.Callout

    var body: some View {
        HealthCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: callout.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(callout.tone.colour)
                    .frame(width: 22)
                Text(callout.text)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}

struct HealthEmptyCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Range picker shared by the detail tabs.
struct HealthRangePicker: View {
    @Binding var range: HealthRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(HealthRange.allCases) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }
}
