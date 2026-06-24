import SwiftUI
import HealthKit

struct TodayView: View {

    @Environment(AppState.self) private var appState
    @State private var showSettings = false

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
        return appState.tasks.filter { task in
            guard !task.done, let resolved = task.resolvedDate else { return false }
            return Calendar.current.startOfDay(for: resolved) == todayStart
        }
    }

    private var todayHabits: [Habit] {
        appState.habits.filter { !$0.isArchived }
    }

    private var todaySupplements: [Supplement] {
        appState.supplements.filter { appState.isDueToday($0) }
    }

    private var workedOutToday: Bool {
        let key = Date().dayKey
        return appState.sessions.contains { $0.finishedAt != nil && $0.startedAt.dayKey == key }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CareSection()
                    if workedOutToday {
                        WorkedOutBanner()
                    }
                    if !todaySupplements.isEmpty {
                        TodaySupplementsSection(supplements: todaySupplements)
                    }
                    TodayTasksSection(tasks: todayTasks)
                    TodayHabitsSection(habits: todayHabits)
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

// MARK: - Activity Rings

private struct ActivityRingsView: View {
    struct Ring {
        let color: Color
        let progress: Double  // 0…1
    }
    let rings: [Ring]
    var size: CGFloat = 130

    var body: some View {
        ZStack {
            ForEach(rings.indices, id: \.self) { i in
                let strokeWidth = size * 0.092
                let gap = strokeWidth * 0.55
                let radius = (size / 2) - strokeWidth / 2 - CGFloat(i) * (strokeWidth + gap)
                let pct = max(0, min(1, rings[i].progress))

                Circle()
                    .stroke(rings[i].color.opacity(0.14), lineWidth: strokeWidth)
                    .frame(width: radius * 2, height: radius * 2)

                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(rings[i].color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.9), value: pct)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Care Section

private struct CareSection: View {

    @Environment(AppState.self) private var appState
    @State private var stepSyncTask: Task<Void, Never>? = nil

    private var today: CareDay { appState.today }
    private var settings: CareSettings { appState.careSettings }

    private let hkManager = HealthKitManager()

    private var rings: [ActivityRingsView.Ring] {
        [
            .init(color: .blue,   progress: settings.waterGoal > 0 ? Double(today.waterGlasses) / Double(settings.waterGoal) : 0),
            .init(color: .orange, progress: settings.mealGoal > 0  ? Double(today.meals.count)  / Double(settings.mealGoal)  : 0),
            .init(color: .green,  progress: settings.stepGoal > 0  ? Double(today.steps)        / Double(settings.stepGoal)  : 0),
        ]
    }

    var body: some View {
        HStack(spacing: 16) {
            ActivityRingsView(rings: rings, size: 130)
                .padding(.leading, 4)

            VStack(spacing: 16) {
                CareRow(
                    systemImage: "drop.fill",
                    color: .blue,
                    label: "Hydrate",
                    count: "\(today.waterGlasses)/\(settings.waterGoal)",
                    done: today.waterGlasses >= settings.waterGoal
                ) {
                    appState.addWater()
                }

                CareRow(
                    systemImage: "fork.knife",
                    color: .orange,
                    label: "Nourish",
                    count: "\(today.meals.count)/\(settings.mealGoal)",
                    done: today.meals.count >= settings.mealGoal
                ) {
                    appState.addMeal()
                }

                CareRow(
                    systemImage: "figure.walk",
                    color: .green,
                    label: "Move",
                    count: "\(today.steps.formatted())/\(settings.stepGoal.formatted())",
                    done: today.steps >= settings.stepGoal,
                    buttonDisabled: true
                ) {
                    // Steps come from HealthKit — no manual increment
                }
            }
            .padding(.trailing, 4)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .task {
            await syncStepsFromHealth()
        }
        .onAppear {
            stepSyncTask?.cancel()
            stepSyncTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                    if !Task.isCancelled { await syncStepsFromHealth() }
                }
            }
        }
        .onDisappear { stepSyncTask?.cancel() }
    }

    private func syncStepsFromHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        _ = await hkManager.requestPermissions()
        let steps = await hkManager.fetchStepsForToday()
        appState.syncSteps(steps)
    }
}

private struct CareRow: View {
    let systemImage: String
    let color: Color
    let label: String
    let count: String
    let done: Bool
    var buttonDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                Text(count)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                HapticManager.impact(done ? .light : .medium)
                action()
            } label: {
                Image(systemName: done ? "checkmark" : (buttonDisabled ? "arrow.clockwise" : "plus"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(done ? color : color.opacity(buttonDisabled ? 0.4 : 0.85))
                    .clipShape(Circle())
                    .shadow(color: color.opacity(done ? 0.5 : 0.3), radius: done ? 6 : 4, x: 0, y: 2)
                    .scaleEffect(done ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: done)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(buttonDisabled && !done)
        }
    }
}

// MARK: - Worked Out Banner

private struct WorkedOutBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout complete!")
                    .font(.subheadline.weight(.semibold))
                Text("Great work today.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

// MARK: - Today Supplements Section

private struct TodaySupplementsSection: View {
    @Environment(AppState.self) private var appState
    let supplements: [Supplement]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Supplements")
                .font(.headline)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(supplements) { supplement in
                    TodaySupplementRow(supplement: supplement)
                    if supplement.id != supplements.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }
}

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
                        .frame(width: 36, height: 36)
                        .background(done ? Color.purple : Color.purple.opacity(0.85))
                        .clipShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(done)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Today Tasks Section

private struct TodayTasksSection: View {

    @Environment(AppState.self) private var appState
    let tasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's Tasks")
                    .font(.headline)
                Spacer()
                if !tasks.isEmpty {
                    Text("\(tasks.count) remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)

            if tasks.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("All done for today!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    Spacer()
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        TodayTaskRow(task: task)
                        if task.id != tasks.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct TodayTaskRow: View {
    @Environment(AppState.self) private var appState
    let task: AppTask

    var body: some View {
        Button {
            HapticManager.impact(.light)
            appState.toggleTask(id: task.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.done ? .green : task.category.color)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .strikethrough(task.done)
                        .foregroundColor(task.done ? .secondary : .primary)

                    Text(task.category.emoji + " " + task.category.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today Habits Section

private struct TodayHabitsSection: View {
    @Environment(AppState.self) private var appState
    let habits: [Habit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Habits")
                .font(.headline)
                .padding(.horizontal, 20)

            if habits.isEmpty {
                Text("No habits yet. Add some in the Habits tab.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(habits) { habit in
                        TodayHabitRow(habit: habit)
                        if habit.id != habits.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
        }
    }
}

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

    var body: some View {
        HStack(spacing: 12) {
            Text(habit.emoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .foregroundColor(.primary)
                    .font(.subheadline)

                if habit.kind == .build {
                    Text("\(todayLog?.count ?? 0) / \(habit.targetCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    if todayLog?.slipped == true {
                        Text("Slipped today")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if todayLog != nil {
                        Text("Maintained today")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Clean so far")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

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
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if todayLog?.slipped == true {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
