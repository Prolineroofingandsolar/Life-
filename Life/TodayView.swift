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
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return appState.tasks.filter { task in
            guard !task.done else { return false }
            guard let resolved = task.resolvedDate else { return false }
            return cal.startOfDay(for: resolved) == today
        }
    }

    private var todayHabits: [Habit] {
        appState.habits.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CareSection()
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
                    actionIcon: "arrow.clockwise"
                ) {
                    Task { await syncStepsFromHealth() }
                }
            }
            .padding(.trailing, 4)
        }
        .padding(16)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
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
    var actionIcon: String = "plus"
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
                Image(systemName: done && actionIcon == "plus" ? "checkmark" : actionIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(done ? color : color.opacity(0.85))
                    .clipShape(Circle())
                    .shadow(color: color.opacity(done ? 0.5 : 0.3), radius: done ? 6 : 4, x: 0, y: 2)
                    .scaleEffect(done ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: done)
            }
            .buttonStyle(PressableButtonStyle())
        }
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
                .background(AppTheme.cardBg)
                .cornerRadius(AppTheme.chipRadius)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
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
                .background(AppTheme.cardBg)
                .cornerRadius(AppTheme.chipRadius)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct TodayTaskRow: View {
    @Environment(AppState.self) private var appState
    let task: AppTask

    private var list: TaskList? { appState.taskList(for: task) }

    var body: some View {
        NavigationLink(destination: TaskDetailView(taskId: task.id)) {
            HStack(spacing: 12) {
                Button {
                    HapticManager.impact(.light)
                    appState.toggleTask(id: task.id)
                } label: {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.done ? .green : (list?.color ?? AppTheme.primary))
                        .font(.title3)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .strikethrough(task.done)
                        .foregroundColor(task.done ? .secondary : .primary)
                        .font(.subheadline)

                    if let list = list {
                        Text(list.emoji + " " + list.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                .background(AppTheme.cardBg)
                .cornerRadius(AppTheme.chipRadius)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct TodayHabitRow: View {
    @Environment(AppState.self) private var appState
    let habit: Habit
    @State private var showSlipConfirm = false

    private var todayLog: HabitLogEntry? {
        habit.logs.first { $0.dayKey == Date().dayKey }
    }

    private var isComplete: Bool {
        guard let log = todayLog else { return false }
        if habit.kind == .break { return !log.slipped }
        return log.count >= habit.targetCount && !log.slipped
    }

    var body: some View {
        Button {
            HapticManager.impact(.medium)
            if habit.kind == .build {
                appState.incHabitToday(id: habit.id)
            } else {
                // Break habits: confirm before marking slipped
                showSlipConfirm = true
            }
        } label: {
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
                        } else {
                            Text("Maintained ✓")
                                .font(.caption)
                                .foregroundColor(AppTheme.primary)
                        }
                    }
                }

                Spacer()

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.primary)
                } else if todayLog?.slipped == true {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Mark \"\(habit.name)\" as slipped today?", isPresented: $showSlipConfirm, titleVisibility: .visible) {
            Button("Mark as Slipped", role: .destructive) {
                HapticManager.impact(.heavy)
                appState.slipHabitToday(id: habit.id)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
