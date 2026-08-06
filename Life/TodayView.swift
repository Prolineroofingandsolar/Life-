import SwiftUI

/// The Today screen.
///
/// The old order was summary → briefing → AI action → care dashboard → workout →
/// tasks → habits: seven full-width cards, each with 16 points of padding and 20
/// points of gap, all styled as though equally important. The consequence was
/// that nothing was. The single most useful thing on the page — the next action
/// — sat third, below a briefing that repeated the navigation title's "Good
/// morning", and the tasks anyone actually opened the app for were four screens
/// down.
///
/// The order now follows what a person opens this screen to find out:
///
/// 1. **Greeting and freshness.** One compact row. Who you are, and whether the
///    numbers below are current — because every figure on this page is only as
///    trustworthy as the last sync.
/// 2. **Do this next.** One recommendation, one primary button, visually
///    unmistakable.
/// 3. **Today.** Tasks, habits and the planned workout in one section rather
///    than three competing cards.
/// 4. **Health.** Collapsed to a summary row, expandable. It is reference
///    material, and the Health tab exists for the full version.
/// 5. **Daily insight.** The briefing, as an entry rather than a second essay.
///
/// Spacing follows the same logic: tight *within* a section, generous *between*
/// them, so the grouping is visible without every card needing a shadow.
struct TodayView: View {

    @Environment(AppState.self) private var appState
    @State private var showSettings = false
    @State private var presentedWorkout: PresentedWorkout?
    @State private var showQuickStartPicker = false
    @State private var dayToken = UUID()

    /// Gaps between conceptual sections. Everything inside a section is tighter
    /// than this; nothing else is looser.
    private static let sectionSpacing: CGFloat = 22
    private static let itemSpacing: CGFloat = 10

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        if hour < 12 { timeGreeting = "Good morning" }
        else if hour < 17 { timeGreeting = "Good afternoon" }
        else { timeGreeting = "Good evening" }

        if appState.userName.isEmpty {
            return timeGreeting
        }
        return "\(timeGreeting), \(appState.userName)"
    }

    private var todayTasks: [AppTask] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return appState.tasks
            .filter { task in
                guard !task.done, let resolved = task.resolvedDate else { return false }
                return Calendar.current.startOfDay(for: resolved) == todayStart
            }
            .sorted { a, b in
                // Timed tasks first (chronological), then untimed.
                switch (a.scheduledTime, b.scheduledTime) {
                case let (ta?, tb?): return ta < tb
                case (_?, nil):      return true
                case (nil, _?):      return false
                case (nil, nil):     return false
                }
            }
    }

    /// Whether anything is due today at all, as opposed to nothing being due.
    ///
    /// "All done" and "nothing was ever scheduled" are different days and
    /// deserve different words; a single "All done for today!" told someone with
    /// an empty list that they had achieved something.
    private var hasAnyTaskToday: Bool {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return appState.tasks.contains { task in
            guard let resolved = task.resolvedDate else { return false }
            return Calendar.current.startOfDay(for: resolved) == todayStart
        }
    }

    private var todayHabits: [Habit] {
        appState.habits.filter { !$0.isArchived }
    }

    private var todaySupplements: [Supplement] {
        appState.supplements.filter { appState.isDueToday($0) }
    }

    /// Today's planned (uncompleted) workout, if one is scheduled.
    private var todaysPlan: PlannedSession? {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return appState.plannedSessions.first {
            !$0.completed && Calendar.current.startOfDay(for: $0.date) == todayStart
        }
    }

    private func habitComplete(_ habit: Habit) -> Bool {
        let log = habit.logs.first { $0.dayKey == Date().dayKey }
        if habit.kind == .break { return log?.slipped != true }
        guard let log else { return false }
        return log.count >= habit.targetCount && !log.slipped
    }

    private var habitsDoneCount: Int {
        todayHabits.filter { habitComplete($0) }.count
    }

    private var workedOutToday: Bool {
        let key = Date().dayKey
        return appState.completedWorkouts.contains { $0.startedAt.dayKey == key }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Self.sectionSpacing) {
                    GreetingHeader(greeting: greeting)

                    // The one thing on the page meant to be acted on, directly
                    // under the greeting rather than third behind two cards of
                    // prose.
                    CoachCard()

                    todaySection

                    HealthSummarySection()

                    // Reference, not an equal-weight card. The morning briefing
                    // used to sit above the recommendation and open with "Good
                    // morning", duplicating the navigation title two rows above
                    // it.
                    CoachBriefingView(kind: .morning)
                    CoachBriefingView(kind: .evening)
                }
                .padding(.top, 4)
                .padding(.bottom, 28)
                .id(dayToken)
            }
            .background(Color(.systemGroupedBackground))
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                // The day rolled over while the app was open. Everything on this
                // page is keyed to "today", so it all has to be rebuilt — and
                // the memoised health snapshot has to go with it, or the new day
                // renders against yesterday's figures.
                appState.invalidateHealthSnapshot()
                dayToken = UUID()
            }
            // "Today", not the greeting. The greeting lives in the content row
            // below, once, where it can carry the sync status beside it.
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showQuickStartPicker) {
                ExercisePickerSheet(title: "Choose an Exercise") { exerciseId in
                    appState.startSession(name: "Quick Workout")
                    guard let session = appState.activeSession else { return }
                    appState.addExerciseToSession(sessionId: session.id, exerciseId: exerciseId)
                    presentedWorkout = PresentedWorkout(id: session.id)
                }
            }
            .sheet(item: $presentedWorkout) { workout in
                ActiveWorkoutView(
                    isPresented: Binding(
                        get: { presentedWorkout != nil },
                        set: { if !$0 { presentedWorkout = nil } }
                    ),
                    sessionId: workout.id
                )
            }
        }
    }

    // MARK: Today section

    /// Tasks, habits and the workout under one heading.
    ///
    /// Previously three separate sections with three headings and three cards'
    /// worth of chrome, which is what pushed habits below the fold on every
    /// device. They answer one question — what is there to do today — so they
    /// share one heading and one container.
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: Self.itemSpacing) {
            SectionHeading(
                title: "Today",
                trailing: todayTasks.isEmpty ? nil : "\(todayTasks.count) to do"
            )

            VStack(spacing: 0) {
                TodayWorkoutRow(plan: todaysPlan, workedOutToday: workedOutToday) {
                    if let active = appState.activeSession {
                        presentedWorkout = PresentedWorkout(id: active.id)
                    } else if let plan = todaysPlan, !plan.isRestDay {
                        appState.startSession(name: plan.routineName, routineId: plan.routineId)
                        presentedWorkout = appState.activeSession.map { PresentedWorkout(id: $0.id) }
                    } else {
                        // No routine to start from, so there's nothing to put in
                        // the workout yet. Same rule as Train's Quick Start: pick
                        // the exercise first, and only then does a workout — and
                        // its running timer — come into existence.
                        showQuickStartPicker = true
                    }
                }

                if todayTasks.isEmpty {
                    Divider().padding(.leading, 16)
                    TodayEmptyRow(
                        icon: hasAnyTaskToday ? "checkmark.circle.fill" : "tray",
                        iconColor: hasAnyTaskToday ? .green : Color(.tertiaryLabel),
                        title: hasAnyTaskToday ? "All tasks done" : "No tasks due today",
                        subtitle: hasAnyTaskToday
                            ? "Everything scheduled for today is complete."
                            : "Nothing is scheduled. Add something in Tasks if you want it here."
                    )
                } else {
                    ForEach(todayTasks) { task in
                        Divider().padding(.leading, 48)
                        TodayTaskRow(task: task)
                    }
                }

                if todayHabits.isEmpty {
                    Divider().padding(.leading, 16)
                    TodayEmptyRow(
                        icon: "repeat.circle",
                        iconColor: Color(.tertiaryLabel),
                        title: "No habits yet",
                        subtitle: "Add some in More ▸ Habits and they'll appear here."
                    )
                } else {
                    Divider().padding(.leading, 16)
                    HabitsSubheading(done: habitsDoneCount, total: todayHabits.count)
                    ForEach(todayHabits) { habit in
                        Divider().padding(.leading, 48)
                        TodayHabitRow(habit: habit)
                    }
                }

                if !todaySupplements.isEmpty {
                    Divider().padding(.leading, 16)
                    SupplementsSubheading()
                    ForEach(todaySupplements) { supplement in
                        Divider().padding(.leading, 48)
                        TodaySupplementRow(supplement: supplement)
                    }
                }
            }
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Greeting header

/// The greeting and the one fact that qualifies everything under it: whether
/// the health figures on this page are current.
///
/// Compact on purpose. A large-title greeting plus a briefing that also opened
/// with "Good morning" spent the top third of the screen saying hello twice.
private struct GreetingHeader: View {

    @Environment(AppState.self) private var appState
    let greeting: String

    private var snapshot: HealthSnapshot { appState.healthSnapshot }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                statusRow
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(greeting). \(statusText)")
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
            if appState.isSyncingHealth {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: statusIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusColour)
                    .accessibilityHidden(true)
            }
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    /// Says which of the four situations this is, because they need different
    /// responses: connect a tracker, wait, open the tracker's app, or nothing.
    private var statusText: String {
        if appState.isSyncingHealth { return "Updating health data…" }
        return snapshot.freshnessStatement
    }

    private var statusIcon: String {
        if !snapshot.hasConnectedSource { return "exclamationmark.circle" }
        if snapshot.lastSyncedAt == nil { return "clock" }
        return snapshot.isFresh ? "checkmark.circle.fill" : "clock.badge.exclamationmark"
    }

    private var statusColour: Color {
        if !snapshot.hasConnectedSource { return .orange }
        return snapshot.isFresh ? .green : .orange
    }
}

// MARK: - Section chrome

/// One heading style for the whole page, so a section is recognisable as a
/// section without each one inventing its own type scale.
private struct SectionHeading: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct HabitsSubheading: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack {
            Text("Habits")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text("\(done) of \(total) done")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Habits, \(done) of \(total) done")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SupplementsSubheading: View {
    var body: some View {
        HStack {
            Text("Supplements")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// An empty state that says which kind of empty it is.
private struct TodayEmptyRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Workout row

/// Today's training, as one row rather than a card.
///
/// The three states are kept apart deliberately. "Rest" used to be shown
/// whenever no workout had been *completed*, so a Tuesday with a hard session
/// still ahead of it read as a rest day right up until it was done. A rest day
/// is something you planned; an empty day is something you haven't.
private struct TodayWorkoutRow: View {
    @Environment(AppState.self) private var appState
    let plan: PlannedSession?
    let workedOutToday: Bool
    let onStart: () -> Void

    private var isActive: Bool { appState.activeSession != nil }
    private var isRestDay: Bool { plan?.isRestDay == true }

    private var title: String {
        if isActive { return "Workout in progress" }
        if workedOutToday { return "Workout done" }
        if isRestDay { return "Rest day" }
        if let plan { return plan.routineName }
        return "No workout planned"
    }

    private var subtitle: String {
        if isActive { return appState.activeSession?.name ?? "Resume" }
        if workedOutToday { return "Logged today" }
        if isRestDay { return "Scheduled rest — nothing to do" }
        if plan != nil { return "Planned for today" }
        return "Start one whenever you like"
    }

    private var actionTitle: String? {
        if isActive { return "Resume" }
        if workedOutToday || isRestDay { return nil }
        return plan != nil ? "Start" : "Quick start"
    }

    private var icon: String {
        if isActive { return "figure.run" }
        if workedOutToday { return "checkmark.circle.fill" }
        if isRestDay { return "moon.zzz.fill" }
        return "dumbbell.fill"
    }

    private var tint: Color {
        if isActive { return .orange }
        if workedOutToday { return .green }
        if isRestDay { return .indigo }
        return AppTheme.primary
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let actionTitle {
                Button {
                    HapticManager.impact(.medium)
                    onStart()
                } label: {
                    Text(actionTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background { isActive ? AnyView(Color.orange) : AnyView(AppTheme.brandGradient) }
                        .clipShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("\(actionTitle) \(title)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Health summary

/// Health, collapsed.
///
/// The care dashboard was a rings card plus a six-tile grid — the single
/// tallest thing on Today, above tasks, repeating what the Health tab shows in
/// full. Here it is one summary row that expands, and the figures it shows come
/// from the canonical snapshot rather than being read out of the store again.
/// That is what stops Today reporting "no HRV" while Health, one tab across,
/// shows 79 ms.
private struct HealthSummarySection: View {

    @Environment(AppState.self) private var appState
    @AppStorage("today_health_expanded_v1") private var isExpanded = false
    @State private var healthSyncTask: Task<Void, Never>? = nil
    @State private var showMealSheet = false
    @State private var hkManager = HealthKitManager()

    private var snapshot: HealthSnapshot { appState.healthSnapshot }
    private var today: CareDay { appState.today }
    private var settings: CareSettings { appState.careSettings }
    private var healthSettings: HealthSettings { appState.healthSettings }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: TodayLayout.itemSpacing) {
            SectionHeading(title: "Health")

            VStack(spacing: 0) {
                disclosureRow

                if isExpanded {
                    Divider().padding(.leading, 16)
                    detail
                        .padding(16)
                        .transition(.opacity)
                }
            }
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .padding(.horizontal, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .sheet(isPresented: $showMealSheet) {
            MealLogSheet { name in appState.addMeal(name: name) }
        }
        .task { await syncHealth() }
        .onAppear {
            healthSyncTask?.cancel()
            healthSyncTask = Task {
                while !Task.isCancelled {
                    // Two minutes rather than five. The sync is incremental —
                    // each metric asks only for what it hasn't already got — so
                    // a poll that finds nothing new costs a handful of requests
                    // instead of a re-download, which is what made five minutes
                    // the safe number before.
                    try? await Task.sleep(nanoseconds: 2 * 60 * 1_000_000_000)
                    if !Task.isCancelled { await syncHealth() }
                }
            }
        }
        .onDisappear { healthSyncTask?.cancel() }
    }

    // MARK: Collapsed row

    private var disclosureRow: some View {
        Button {
            isExpanded.toggle()
            HapticManager.selection()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summaryLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Text(snapshot.freshnessStatement)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health summary. \(summaryLine). \(snapshot.freshnessStatement)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    /// The one line worth reading when the section is closed.
    ///
    /// Built from the snapshot's states rather than from raw optionals, so a
    /// tracker that hasn't synced, a night that wasn't recorded and a night
    /// recorded but not yet comparable each produce a different sentence.
    private var summaryLine: String {
        if !snapshot.hasConnectedSource {
            return "No tracker connected"
        }
        var parts: [String] = []
        if let minutes = snapshot.sleepMinutes.value {
            let text = HealthInsights.formatDuration(minutes)
            parts.append(snapshot.sleepMinutes.state == .stale ? "Sleep \(text) (not last night)" : "Slept \(text)")
        }
        if let steps = snapshot.steps.value {
            parts.append("\(steps.formatted()) steps")
        }
        if let readiness = snapshot.readiness.value {
            parts.append("Readiness \(readiness)")
        } else if snapshot.readiness.state == .insufficientHistory {
            parts.append("Recovery: not enough history yet")
        }
        return parts.isEmpty ? "Nothing recorded yet today" : parts.joined(separator: " · ")
    }

    // MARK: Expanded detail

    private var detail: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            TodayStatBox(
                icon: "drop.fill", iconColor: .blue,
                value: "\(today.waterGlasses)/\(settings.waterGoal)", label: "Water",
                done: today.waterGlasses >= settings.waterGoal,
                action: { appState.addWater() },
                secondaryAction: { appState.removeWater() }
            )

            TodayStatBox(
                icon: "fork.knife", iconColor: .orange,
                value: "\(today.meals.count)/\(settings.mealGoal)", label: "Meals",
                done: today.meals.count >= settings.mealGoal,
                action: { showMealSheet = true }
            )

            stepsBox
            sleepBox
            if healthSettings.showRecoveryTile { recoveryBox }
        }
    }

    /// Steps, or a statement of why there aren't any.
    ///
    /// A dash rather than a zero. "0 steps" and "your tracker hasn't synced"
    /// look identical as a number and need opposite responses, and the whole
    /// point of the snapshot's `missing` state is that the app knows which.
    @ViewBuilder
    private var stepsBox: some View {
        let source = HealthSync.source(for: healthSettings)
        let goalLabel = "\(settings.stepGoal.formatted()) goal"
        let sourceLabel = source == .none ? goalLabel : source.displayName + " · " + goalLabel

        if let steps = snapshot.steps.value {
            TodayStatBox(
                icon: "figure.walk", iconColor: AppTheme.primary,
                value: steps.formatted(), label: "Steps · " + sourceLabel,
                done: steps >= settings.stepGoal
            )
        } else {
            TodayStatBox(
                icon: "figure.walk", iconColor: Color(.tertiaryLabel),
                value: "—",
                label: source == .none ? "Steps · no tracker" : "Steps · not synced yet"
            )
        }
    }

    /// Last night's sleep against the goal, or the reason there isn't one.
    @ViewBuilder
    private var sleepBox: some View {
        let goal = healthSettings.sleepGoalMinutes
        let goalLabel = goal % 60 == 0 ? "\(goal / 60)h" : "\(goal / 60)h\(goal % 60)m"

        if let minutes = snapshot.sleepMinutes.value {
            TodayStatBox(
                icon: "bed.double.fill", iconColor: .indigo,
                value: HealthInsights.formatDuration(minutes),
                label: snapshot.sleepMinutes.state == .stale
                    ? "Sleep · not last night"
                    : "Sleep · \(goalLabel) goal",
                done: minutes >= goal
            )
        } else {
            TodayStatBox(
                icon: "bed.double.fill", iconColor: Color(.tertiaryLabel),
                value: "—", label: "Sleep · not recorded"
            )
        }
    }

    /// Recovery, including the case that used to be reported as nothing at all.
    ///
    /// A resting heart rate of 59 with only four nights behind it is a real
    /// measurement without an interpretation. It gets shown, with "not enough
    /// history yet" underneath — not withheld, and never described as absent.
    @ViewBuilder
    private var recoveryBox: some View {
        if let hr = snapshot.restingHeartRate.value {
            TodayStatBox(
                icon: "heart.fill", iconColor: .pink,
                value: "\(Int(hr))",
                label: recoveryLabel
            )
        } else if let hrv = snapshot.hrvMs.value {
            TodayStatBox(
                icon: "waveform.path.ecg", iconColor: AppTheme.primary,
                value: "\(Int(hrv))",
                label: snapshot.hrvMs.state == .insufficientHistory
                    ? "HRV ms · no baseline yet"
                    : "HRV ms"
            )
        } else {
            TodayStatBox(
                icon: "heart", iconColor: Color(.tertiaryLabel),
                value: "—",
                label: snapshot.hasConnectedSource ? "Recovery · not recorded" : "Recovery · no tracker"
            )
        }
    }

    private var recoveryLabel: String {
        if let comparison = snapshot.restingHeartRateBaseline, comparison.isMeaningful {
            return comparison.direction == .below
                ? "Resting HR · below usual"
                : "Resting HR · above usual"
        }
        if snapshot.restingHeartRate.state == .insufficientHistory {
            let recorded = snapshot.restingHeartRate.sampleCount
            let required = snapshot.restingHeartRate.requiredSamples
            return "Resting HR · \(recorded)/\(required) nights"
        }
        if let hrv = snapshot.hrvMs.value {
            return "Resting HR · HRV \(Int(hrv))ms"
        }
        return "Resting HR"
    }

    // MARK: Syncing

    @MainActor
    private func syncHealth() async {
        // Routed through HealthSync so this agrees with the Health tab about
        // which source is authoritative — Fitbit when connected, Apple Health
        // otherwise. Syncing HealthKit here regardless would let an iPhone-only
        // step count overwrite the wrist tracker's.
        let window = appState.healthSettings.hasBackfilled ? 7 : 365
        await HealthSync.run(appState: appState, healthKit: hkManager, daysBack: window)

        // Today's step count comes straight from HealthKit on the Apple Health
        // path so the Move ring stays live between the coarser daily merges.
        if HealthSync.source(for: appState.healthSettings) == .appleHealth {
            appState.syncSteps(await hkManager.fetchStepsForToday())
            appState.invalidateHealthSnapshot()
        }
    }
}

/// Shared spacing, so the health section and the Today section agree without
/// either one owning the other's constant.
private enum TodayLayout {
    static let itemSpacing: CGFloat = 10
}

// MARK: - Meal Log Sheet

private struct MealLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String) -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    private let quickPicks = ["Breakfast", "Lunch", "Dinner", "Snack"]

    var body: some View {
        NavigationStack {
            Form {
                Section("What did you eat?") {
                    TextField("Optional — e.g. Chicken & rice", text: $name)
                        .focused($focused)
                }
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(quickPicks, id: \.self) { pick in
                            Button {
                                onAdd(pick)
                                HapticManager.impact(.medium)
                                dismiss()
                            } label: {
                                Text(pick)
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundColor(.orange)
                                    .cornerRadius(AppTheme.chipRadius)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Log a Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name.trimmingCharacters(in: .whitespaces))
                        HapticManager.impact(.medium)
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}

private struct LongPressActionModifier: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    HapticManager.impact(.rigid)
                    action()
                }
            )
        } else {
            content
        }
    }
}

// MARK: - Today Stat Box

private struct TodayStatBox: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    var done: Bool = false
    var action: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil

    /// One spoken string for the whole tile.
    ///
    /// VoiceOver used to read the glyph, the number and the label as three
    /// elements — "drop fill, 3 slash 8, Water" — which is three swipes to learn
    /// one fact. The symbol is hidden and the rest is combined, so it reads
    /// "Water, 3 of 8" and the tile's own state comes through as a value rather
    /// than a fourth element.
    private var spokenLabel: String {
        let core = "\(label), \(value.replacingOccurrences(of: "/", with: " of "))"
        return done ? "\(core), complete" : core
    }

    var body: some View {
        if let action {
            Button {
                HapticManager.impact(done ? .light : .medium)
                action()
            } label: { content.contentShape(Rectangle()) }
            .buttonStyle(PressableButtonStyle())
            .modifier(LongPressActionModifier(action: secondaryAction))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15)).frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                .accessibilityHidden(true)
                Spacer()
                if action != nil {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconColor.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(alignment: .topTrailing) {
                            if done {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                    .background(Circle().fill(Color(.systemBackground)))
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .accessibilityHidden(true)
                } else if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(iconColor)
                        .accessibilityHidden(true)
                }
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // Tertiary, not secondary. These tiles sit *inside* a card already
        // painted `AppTheme.cardBg` (secondary), so the same fill would make
        // them invisible — one flat rectangle with numbers floating on it.
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(12)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: done)
    }
}

// MARK: - Supplement row

private struct TodaySupplementRow: View {
    @Environment(AppState.self) private var appState
    let supplement: Supplement

    @State private var showUndo = false
    @State private var undoTask: Task<Void, Never>? = nil

    private var taken: Int { appState.dosesToday(for: supplement) }
    private var done: Bool { taken >= supplement.dosesPerDay }

    var body: some View {
        HStack(spacing: 12) {
            Text(supplement.emoji)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(supplement.name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    ForEach(0..<supplement.dosesPerDay, id: \.self) { i in
                        Image(systemName: i < taken ? "circle.fill" : "circle")
                            .font(.system(size: 8))
                            .foregroundColor(i < taken ? AppTheme.primary : .secondary)
                    }
                }
                .accessibilityHidden(true)
            }

            Spacer()

            if showUndo {
                Button {
                    undoTask?.cancel()
                    withAnimation { showUndo = false }
                    HapticManager.impact(.light)
                    appState.undoDose(supplementId: supplement.id)
                } label: {
                    Text("Undo")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo last dose of \(supplement.name)")
                .transition(.opacity.combined(with: .scale))
            } else {
                Button {
                    guard !done else { return }
                    HapticManager.impact(.medium)
                    appState.logDose(supplementId: supplement.id)
                    withAnimation { showUndo = true }
                    undoTask?.cancel()
                    undoTask = Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run { withAnimation { showUndo = false } }
                    }
                } label: {
                    Image(systemName: done ? "checkmark" : "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(done ? Color.purple : Color.purple.opacity(0.85))
                        .clipShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(done)
                // The control and what it acts on, as one announcement. A bare
                // "plus, button" gives VoiceOver no way to tell which of five
                // supplement rows it is sitting on.
                .accessibilityLabel(
                    done
                        ? "\(supplement.name), all \(supplement.dosesPerDay) doses taken"
                        : "Take a dose of \(supplement.name), \(taken) of \(supplement.dosesPerDay) taken"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Task row

private struct TodayTaskRow: View {
    @Environment(AppState.self) private var appState
    let task: AppTask

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    private var list: TaskList? { appState.taskList(for: task) }

    /// "Refill water bottle, incomplete" — the toggle and the thing it toggles,
    /// spoken together.
    ///
    /// Separately they are a circle with no name and a title with no state,
    /// which is two elements to convey one fact and neither of them sufficient.
    private var toggleLabel: String {
        var parts = [task.title, task.done ? "complete" : "incomplete"]
        if task.priority != .none { parts.append("\(task.priority.label) priority") }
        if let time = task.scheduledTime { parts.append("at \(Self.timeFmt.string(from: time))") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Toggle (independent of navigation)
            Button {
                HapticManager.impact(.light)
                appState.toggleTask(id: task.id)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.done ? .green : (list?.color ?? .secondary))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toggleLabel)
            .accessibilityHint(task.done ? "Marks as not done" : "Marks as done")

            // Tap row body → detail
            NavigationLink {
                TaskDetailView(taskId: task.id)
            } label: {
                HStack(spacing: 8) {
                    // Priority indicator
                    if task.priority != .none {
                        Circle()
                            .fill(task.priority.color)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .strikethrough(task.done)
                            .foregroundColor(task.done ? .secondary : .primary)

                        HStack(spacing: 6) {
                            if let list { Text(list.emoji + " " + list.name) }
                            if let time = task.scheduledTime {
                                Text("·")
                                Label(Self.timeFmt.string(from: time), systemImage: "clock")
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(task.title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Habit row

private struct TodayHabitRow: View {
    @Environment(AppState.self) private var appState
    let habit: Habit

    @State private var showUndo = false
    @State private var undoTask: Task<Void, Never>? = nil

    private var todayLog: HabitLogEntry? {
        habit.logs.first { $0.dayKey == Date().dayKey }
    }

    private var isComplete: Bool {
        if habit.kind == .break { return todayLog?.slipped != true }
        guard let log = todayLog else { return false }
        return log.count >= habit.targetCount && !log.slipped
    }

    private var streak: Int { appState.streakFor(habit) }

    private var progressText: String {
        if habit.kind == .build { return "\(todayLog?.count ?? 0) of \(habit.targetCount)" }
        if todayLog?.slipped == true { return "Slipped today" }
        if todayLog != nil { return "Maintained today" }
        return "Clean so far"
    }

    /// The control and its subject in one announcement.
    private var toggleLabel: String {
        var parts = [habit.name, progressText]
        if streak > 0 { parts.append("\(streak) day streak") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                HabitDetailView(habitId: habit.id)
            } label: {
                HStack(spacing: 12) {
                    Text(habit.emoji)
                        .font(.title2)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(habit.name)
                                .foregroundColor(.primary)
                                .font(.subheadline)
                            if streak > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 10))
                                    Text("\(streak)")
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                                .accessibilityHidden(true)
                            }
                        }

                        Text(progressText)
                            .font(.caption)
                            .foregroundColor(
                                todayLog?.slipped == true
                                    ? .red
                                    : (habit.kind == .break && todayLog != nil ? .green : .secondary)
                            )
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(habit.name), \(progressText)\(streak > 0 ? ", \(streak) day streak" : "")")

            if showUndo {
                Button {
                    undoTask?.cancel()
                    withAnimation { showUndo = false }
                    HapticManager.impact(.light)
                    if habit.kind == .build {
                        appState.decHabitToday(id: habit.id)
                    } else {
                        appState.unslipHabitToday(id: habit.id)
                    }
                } label: {
                    Text("Undo")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo \(habit.name)")
                .transition(.opacity.combined(with: .scale))
            } else {
                Button {
                    HapticManager.impact(.medium)
                    if habit.kind == .build {
                        appState.incHabitToday(id: habit.id)
                    } else {
                        appState.slipHabitToday(id: habit.id)
                    }
                    withAnimation { showUndo = true }
                    undoTask?.cancel()
                    undoTask = Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run { withAnimation { showUndo = false } }
                    }
                } label: {
                    Group {
                        if isComplete {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        } else if todayLog?.slipped == true {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        } else {
                            Image(systemName: "circle").foregroundColor(.secondary)
                        }
                    }
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(toggleLabel)
                .accessibilityHint(habit.kind == .build ? "Logs one" : "Records a slip")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
