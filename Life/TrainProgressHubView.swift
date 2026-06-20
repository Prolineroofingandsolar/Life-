import SwiftUI
import Charts

// MARK: - Progress Hub
// A polished, light-theme Progress screen with three segmented tabs:
// Activity, Progress, and Body. Wired to real AppState workout & body data.

private enum PColor {
    static let accent        = Color(hex: "#7C5CFC")
    static let bg            = Color(hex: "#F2F2F7")
    static let card          = Color.white
    static let textPrimary   = Color(hex: "#1C1C1E")
    static let textSecondary = Color(hex: "#8E8E93")
    static let green         = Color(hex: "#34C759")
    static let orange        = Color(hex: "#FF9500")
    static let blue          = Color(hex: "#5E9BF0")
}

struct TrainProgressHubView: View {

    enum HubTab: String, CaseIterable, Identifiable {
        case activity = "Activity"
        case progress = "Progress"
        case body = "Body"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: HubTab

    init(initialTab: HubTab = .activity) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 22) {
                    switch selectedTab {
                    case .activity: ActivityTab()
                    case .progress: ProgressTab()
                    case .body:     BodyTab()
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.top, 16)
            }
        }
        .background(PColor.bg.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Progress")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(PColor.textPrimary)
                    Text("Track your journey. Every rep counts.")
                        .font(.system(size: 14))
                        .foregroundColor(PColor.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(PColor.textSecondary.opacity(0.4))
                }
            }

            Picker("Section", selection: $selectedTab) {
                ForEach(HubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(PColor.bg)
    }
}

// MARK: - Shared Components

private struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PColor.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PColor.accent)
            }
        }
    }
}

private struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15)).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(PColor.textPrimary)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(PColor.textSecondary)
            }
        }
    }
}

private struct EmptyHint: View {
    let text: String
    var body: some View {
        CardContainer {
            HStack {
                Spacer()
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(PColor.textSecondary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Activity Tab

private struct ActivityTab: View {
    @Environment(AppState.self) private var appState

    private var trainingTime: String {
        let s = appState.trainingSecondsThisWeek
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)] }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                SectionHeader(title: "This Week")
                LazyVGrid(columns: columns, spacing: 12) {
                    StatCard(icon: "dumbbell.fill", iconColor: PColor.accent,
                             value: "\(appState.workoutsThisWeekCount)", label: "Workouts")
                    StatCard(icon: "flame.fill", iconColor: PColor.orange,
                             value: "\(appState.workoutStreak)", label: "Day Streak")
                    StatCard(icon: "clock.fill", iconColor: PColor.green,
                             value: trainingTime, label: "Training Time")
                    StatCard(icon: "chart.line.uptrend.xyaxis", iconColor: PColor.blue,
                             value: "\(Int(appState.volumeThisWeekKg).formatted()) kg", label: "Volume Lifted")
                }
            }

            VStack(spacing: 12) {
                SectionHeader(title: "Calendar")
                WorkoutCalendarCard(onPlanDate: { _ in }, onTapSession: { _ in })
            }

            VStack(spacing: 12) {
                SectionHeader(title: "Muscle Recovery")
                MuscleRecoverySection()
            }

            if !appState.sessions.filter({ $0.finishedAt != nil }).isEmpty {
                VStack(spacing: 12) {
                    SectionHeader(title: "Last 8 Weeks")
                    CardContainer {
                        WeeklyConsistencyChart()
                    }
                }
            }

            VStack(spacing: 12) {
                SectionHeader(title: "Recent Workouts")
                let recent = appState.recentFinishedSessions(limit: 5)
                if recent.isEmpty {
                    EmptyHint(text: "No workouts logged yet")
                } else {
                    CardContainer {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { idx, session in
                                RecentWorkoutRow(session: session)
                                if idx < recent.count - 1 { Divider().opacity(0.4) }
                            }
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                SectionHeader(title: "Muscle Groups", trailing: "This Week")
                let muscles = appState.muscleCountsThisWeek()
                if muscles.isEmpty {
                    EmptyHint(text: "Train this week to see muscle activity")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(muscles.prefix(8)) { item in
                                MuscleChip(muscle: item.muscle, count: item.count)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct RecentWorkoutRow: View {
    let session: WorkoutSession
    private var subtitle: String {
        let s = session.durationSeconds
        let h = s / 3600, m = (s % 3600) / 60
        let dur = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "\(session.finishedAt?.formatted(date: .abbreviated, time: .omitted) ?? "") · \(dur)"
    }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(PColor.accent.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(PColor.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PColor.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(PColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PColor.textSecondary.opacity(0.5))
        }
        .padding(.vertical, 8)
    }
}

private struct MuscleChip: View {
    let muscle: String
    let count: Int
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(PColor.accent.opacity(0.12)).frame(width: 56, height: 56)
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 24))
                    .foregroundColor(PColor.accent)
            }
            Text(muscle.capitalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PColor.textPrimary)
            Text("\(count)x")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(PColor.accent)
        }
        .frame(width: 76)
    }
}

// MARK: - Progress Tab

private struct ProgressTab: View {
    @Environment(AppState.self) private var appState
    @State private var selectedExerciseId: String? = nil

    private var topLifts: [Exercise] { appState.topExercises(limit: 6) }
    private var currentExercise: Exercise? {
        if let id = selectedExerciseId { return topLifts.first { $0.id == id } }
        return topLifts.first
    }

    var body: some View {
        VStack(spacing: 22) {
            if topLifts.isEmpty {
                EmptyHint(text: "Log workouts to see your lift progress")
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 12) {
                    SectionHeader(title: "Top Lifts")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(topLifts) { ex in
                                LiftIcon(name: ex.name,
                                         selected: ex.id == (currentExercise?.id))
                                    .onTapGesture { selectedExerciseId = ex.id }
                            }
                        }
                    }
                    if let ex = currentExercise {
                        LiftChartCard(exercise: ex)
                    }
                }
                .padding(.horizontal, 20)
            }

            VStack(spacing: 12) {
                SectionHeader(title: "Personal Records")
                if topLifts.isEmpty {
                    EmptyHint(text: "No personal records yet")
                } else {
                    CardContainer {
                        VStack(spacing: 0) {
                            ForEach(Array(topLifts.prefix(5).enumerated()), id: \.element.id) { idx, ex in
                                PRRow(exercise: ex)
                                if idx < min(topLifts.count, 5) - 1 { Divider().opacity(0.4) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 12) {
                SectionHeader(title: "Achievements")
                AchievementsStrip()
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct LiftIcon: View {
    let name: String
    let selected: Bool
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(selected ? PColor.accent.opacity(0.18) : Color(hex: "#EFEFF4"))
                    .frame(width: 56, height: 56)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 22))
                    .foregroundColor(selected ? PColor.accent : PColor.textSecondary)
            }
            Text(name)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? PColor.accent : PColor.textSecondary)
                .lineLimit(1)
                .frame(width: 64)
        }
    }
}

private struct LiftChartCard: View {
    @Environment(AppState.self) private var appState
    let exercise: Exercise

    private var history: [AppState.DatedValue] { appState.oneRMHistory(for: exercise.id) }
    private var best1RM: Double { history.map(\.value).max() ?? 0 }
    private var delta: Double { appState.prDelta(for: exercise.id) }
    private var unit: String { appState.workoutSettings.weightUnit.label }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(PColor.textPrimary)
                        Text("1RM Estimate")
                            .font(.system(size: 12))
                            .foregroundColor(PColor.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(best1RM)) \(unit)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(PColor.textPrimary)
                        if delta > 0 {
                            Text("+\(Int(delta)) \(unit)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(PColor.green)
                        }
                    }
                }

                if history.count >= 2 {
                    Chart(history) { point in
                        LineMark(x: .value("Date", point.date), y: .value("1RM", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(PColor.accent)
                        AreaMark(x: .value("Date", point.date), y: .value("1RM", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(
                                colors: [PColor.accent.opacity(0.25), PColor.accent.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom))
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 180)
                } else {
                    Text("Need more sessions to chart progress")
                        .font(.system(size: 13))
                        .foregroundColor(PColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
    }
}

private struct PRRow: View {
    @Environment(AppState.self) private var appState
    let exercise: Exercise
    private var pr: AppState.PRResult { appState.computePRs(for: exercise.id) }
    private var delta: Double { appState.prDelta(for: exercise.id) }
    private var unit: String { appState.workoutSettings.weightUnit.label }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(PColor.accent.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: "trophy.fill").foregroundColor(PColor.accent)
            }
            Text(exercise.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PColor.textPrimary)
            Spacer()
            Text("\(Int(pr.bestWeight)) \(unit)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(PColor.textPrimary)
            if delta > 0 {
                Text("+\(Int(delta))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PColor.green)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct AchievementsStrip: View {
    @Environment(AppState.self) private var appState
    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }
    private var unlocked: Set<AchievementKind> { Set(appState.achievements.map(\.kind)) }
    private var display: [AchievementKind] {
        let unlockedKinds = appState.achievements.map(\.kind)
        let rest = AchievementKind.allCases.filter { !unlockedKinds.contains($0) }
        return Array((unlockedKinds + rest).prefix(8))
    }
    var body: some View {
        CardContainer {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(display, id: \.self) { kind in
                    let on = unlocked.contains(kind)
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(on ? Color(hex: kind.color).opacity(0.18) : Color(hex: "#EFEFF4"))
                                .frame(width: 52, height: 52)
                            Image(systemName: kind.icon)
                                .font(.system(size: 22))
                                .foregroundColor(on ? Color(hex: kind.color) : PColor.textSecondary.opacity(0.5))
                        }
                        Text(kind.title)
                            .font(.system(size: 10, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundColor(on ? PColor.textPrimary : PColor.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

// MARK: - Body Tab

private struct BodyTab: View {
    @Environment(AppState.self) private var appState
    @State private var showPhotos = false
    private let hk = HealthKitManager()

    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)] }
    private var unit: String { appState.workoutSettings.weightUnit.label }

    private func fmt(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "—" }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                SectionHeader(title: "Body Overview")
                LazyVGrid(columns: columns, spacing: 12) {
                    StatCard(icon: "scalemass.fill", iconColor: PColor.accent,
                             value: appState.latestWeightKg != nil ? "\(fmt(appState.latestWeightKg)) \(unit)" : "—",
                             label: weightSub)
                    StatCard(icon: "percent", iconColor: PColor.orange,
                             value: appState.latestBodyFatPct != nil ? "\(fmt(appState.latestBodyFatPct))%" : "—",
                             label: "Body Fat")
                    StatCard(icon: "figure.arms.open", iconColor: PColor.green,
                             value: appState.latestLeanMassKg != nil ? "\(fmt(appState.latestLeanMassKg)) \(unit)" : "—",
                             label: "Lean Mass")
                    StatCard(icon: "target", iconColor: PColor.blue,
                             value: appState.workoutSettings.goalWeightKg != nil ? "\(fmt(appState.workoutSettings.goalWeightKg)) \(unit)" : "—",
                             label: goalSub)
                }
            }

            VStack(spacing: 12) {
                SectionHeader(title: "Weight Trend", trailing: "3 Months")
                let trend = appState.weightTrend(days: 90)
                if trend.count >= 2 {
                    CardContainer {
                        Chart(trend) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(PColor.accent)
                            AreaMark(x: .value("Date", point.date), y: .value("Weight", point.value))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(LinearGradient(
                                    colors: [PColor.accent.opacity(0.25), PColor.accent.opacity(0.0)],
                                    startPoint: .top, endPoint: .bottom))
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 180)
                    }
                } else {
                    EmptyHint(text: "Log your weight to see the trend")
                }
            }

            VStack(spacing: 12) {
                SectionHeader(title: "Progress Photos", trailing: "View all")
                ProgressPhotosPreview { showPhotos = true }
            }

            VStack(spacing: 12) {
                SectionHeader(title: "Measurements")
                MeasurementsCard()
            }
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showPhotos) { ProgressPhotosView() }
        .task { await syncHealthKit() }
    }

    private func syncHealthKit() async {
        let granted = await hk.requestPermissions()
        guard granted else { return }
        let data = await hk.importBodyData(daysBack: 365)
        for (date, kg) in data.weight {
            await MainActor.run { appState.logBodyWeight(valueKg: kg, date: date) }
        }
        var entryMap: [String: BodyCompEntry] = [:]
        for (date, pct) in data.bodyFat {
            let key = date.dayKey
            var e = entryMap[key] ?? BodyCompEntry(date: date)
            e.bodyFatPct = pct; entryMap[key] = e
        }
        for (date, kg) in data.leanMass {
            let key = date.dayKey
            var e = entryMap[key] ?? BodyCompEntry(date: date)
            e.leanMassKg = kg; entryMap[key] = e
        }
        for (date, val) in data.bmi {
            let key = date.dayKey
            var e = entryMap[key] ?? BodyCompEntry(date: date)
            e.bmi = val; entryMap[key] = e
        }
        let newEntries = entryMap.values.filter { $0.bodyFatPct != nil || $0.leanMassKg != nil || $0.bmi != nil }
        await MainActor.run { appState.mergeBodyCompEntries(Array(newEntries)) }
    }

    private var weightSub: String {
        guard let c = appState.weightChangeKg else { return "Weight" }
        let arrow = c <= 0 ? "↓" : "↑"
        return "\(arrow) \(String(format: "%.1f", abs(c))) \(unit)"
    }
    private var goalSub: String {
        guard let goal = appState.workoutSettings.goalWeightKg, let cur = appState.latestWeightKg else { return "Goal Weight" }
        let togo = abs(goal - cur)
        return "\(String(format: "%.1f", togo)) \(unit) to go"
    }
}

private struct ProgressPhotosPreview: View {
    @Environment(AppState.self) private var appState
    let onTap: () -> Void
    private var photos: [ProgressPhoto] { appState.progressPhotos.sorted { $0.date < $1.date } }
    var body: some View {
        if let first = photos.first, let last = photos.last, photos.count >= 2 {
            CardContainer {
                HStack(spacing: 10) {
                    photoView(first, caption: first.date.formatted(date: .abbreviated, time: .omitted))
                    photoView(last, caption: last.date.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .onTapGesture(perform: onTap)
        } else {
            Button(action: onTap) {
                EmptyHint(text: "Add progress photos to compare over time")
            }
            .buttonStyle(.plain)
        }
    }
    private func photoView(_ photo: ProgressPhoto, caption: String) -> some View {
        VStack(spacing: 6) {
            if let img = UIImage(data: photo.imageData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text(caption)
                .font(.system(size: 12))
                .foregroundColor(PColor.textSecondary)
        }
    }
}

private struct MeasurementsCard: View {
    @Environment(AppState.self) private var appState

    private var latest: BodyMeasurement? { appState.bodyMeasurements.sorted { $0.date > $1.date }.first }

    private struct Row: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let value: Double
    }

    private var rows: [Row] {
        guard let m = latest else { return [] }
        var out: [Row] = []
        if let v = m.chestCm     { out.append(Row(name: "Chest", icon: "figure.arms.open", value: v)) }
        if let v = m.waistCm     { out.append(Row(name: "Waist", icon: "circle.dashed", value: v)) }
        if let v = m.leftArmCm ?? m.rightArmCm { out.append(Row(name: "Arms", icon: "dumbbell.fill", value: v)) }
        if let v = m.shouldersCm { out.append(Row(name: "Shoulders", icon: "figure.stand", value: v)) }
        if let v = m.leftThighCm ?? m.rightThighCm { out.append(Row(name: "Thighs", icon: "figure.walk", value: v)) }
        return out
    }

    var body: some View {
        if rows.isEmpty {
            EmptyHint(text: "Add measurements to track changes")
        } else {
            CardContainer {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(PColor.accent.opacity(0.15)).frame(width: 36, height: 36)
                                Image(systemName: row.icon).font(.system(size: 15)).foregroundColor(PColor.accent)
                            }
                            Text(row.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(PColor.textPrimary)
                            Spacer()
                            Text("\(Int(row.value)) cm")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(PColor.textPrimary)
                        }
                        .padding(.vertical, 9)
                        if idx < rows.count - 1 { Divider().opacity(0.4) }
                    }
                }
            }
        }
    }
}
