import SwiftUI
import HealthKit

struct TodayView: View {

    @Environment(AppState.self) private var appState
    @State private var showSettings = false
    @State private var showActiveWorkout = false
    @State private var presentedWorkoutId: String?
    @State private var dayToken = UUID()

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
                VStack(spacing: 20) {
                    DaySummaryCard(
                        tasksLeft: todayTasks.count,
                        habitsDone: habitsDoneCount,
                        habitsTotal: todayHabits.count,
                        workedOut: workedOutToday
                    )
                    CareSection()
                    TodayWorkoutCard(plan: todaysPlan) {
                        if appState.activeSession == nil {
                            if let plan = todaysPlan {
                                appState.startSession(name: plan.routineName, routineId: plan.routineId)
                            } else {
                                appState.startSession(name: "Quick Workout")
                            }
                        }
                        showActiveWorkout = true
                    }
                    if !todaySupplements.isEmpty {
                        TodaySupplementsSection(supplements: todaySupplements)
                    }
                    TodayTasksSection(tasks: todayTasks)
                    TodayHabitsSection(habits: todayHabits)
                }
                .padding(.vertical, 8)
                .id(dayToken)
            }
            .background(Color(.systemGroupedBackground))
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                dayToken = UUID()
            }
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
            .onChange(of: showActiveWorkout) { _, shown in
                if shown { presentedWorkoutId = appState.activeSession?.id }
            }
            .sheet(isPresented: $showActiveWorkout) {
                if let id = presentedWorkoutId {
                    ActiveWorkoutView(isPresented: $showActiveWorkout, sessionId: id)
                }
            }
        }
    }
}

// MARK: - Day Summary Card

private struct DaySummaryCard: View {
    let tasksLeft: Int
    let habitsDone: Int
    let habitsTotal: Int
    let workedOut: Bool

    var body: some View {
        HStack(spacing: 0) {
            summaryItem(
                icon: "checkmark.circle.fill",
                color: tasksLeft == 0 ? .green : AppTheme.primary,
                value: tasksLeft == 0 ? "Clear" : "\(tasksLeft)",
                label: tasksLeft == 1 ? "task left" : "tasks left"
            )
            Divider().frame(height: 34)
            summaryItem(
                icon: "chart.bar.fill",
                color: .blue,
                value: "\(habitsDone)/\(habitsTotal)",
                label: "habits"
            )
            Divider().frame(height: 34)
            summaryItem(
                icon: "flame.fill",
                color: workedOut ? .orange : Color(.tertiaryLabel),
                value: workedOut ? "Done" : "Rest",
                label: "workout"
            )
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    private func summaryItem(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Today Workout Card

private struct TodayWorkoutCard: View {
    @Environment(AppState.self) private var appState
    let plan: PlannedSession?
    let onStart: () -> Void

    private var isActive: Bool { appState.activeSession != nil }

    var body: some View {
        Button {
            HapticManager.impact(.medium)
            onStart()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill((isActive ? Color.orange : AppTheme.primary).opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: isActive ? "figure.run" : "dumbbell.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(isActive ? .orange : AppTheme.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isActive ? "Workout in progress" : (plan != nil ? "Today's Plan" : "Start a workout"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(isActive ? (appState.activeSession?.name ?? "Resume") : (plan?.routineName ?? "Quick session — log as you go"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(isActive ? "Resume" : "Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background {
                        if isActive { Color.orange } else { AppTheme.brandGradient }
                    }
                    .clipShape(Capsule())
            }
            .padding(16)
            .background(AppTheme.cardBg)
            .cornerRadius(AppTheme.cardRadius)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, 16)
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
    @State private var showMealSheet = false

    private var today: CareDay { appState.today }
    private var settings: CareSettings { appState.careSettings }

    @State private var hkManager = HealthKitManager()

    private var workedOutToday: Bool {
        let key = Date().dayKey
        return appState.completedWorkouts.contains { $0.startedAt.dayKey == key }
    }

    private var rings: [ActivityRingsView.Ring] {
        [
            .init(color: .blue,   progress: settings.waterGoal > 0 ? Double(today.waterGlasses) / Double(settings.waterGoal) : 0),
            .init(color: .orange, progress: settings.mealGoal > 0  ? Double(today.meals.count)  / Double(settings.mealGoal)  : 0),
            .init(color: AppTheme.primary,  progress: settings.stepGoal > 0  ? Double(today.steps)        / Double(settings.stepGoal)  : 0),
        ]
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 12) {
            // Rings card
            HStack {
                Spacer()
                ActivityRingsView(rings: rings, size: 150)
                    .padding(.vertical, 22)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(AppTheme.cardBg)
            .cornerRadius(AppTheme.cardRadius)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

            // Stat boxes
            LazyVGrid(columns: columns, spacing: 12) {
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
                    done: today.meals.count >= settings.mealGoal
                ) { showMealSheet = true }

                TodayStatBox(
                    icon: "figure.walk", iconColor: AppTheme.primary,
                    value: today.steps.formatted(), label: "Steps · \(settings.stepGoal.formatted()) goal",
                    done: today.steps >= settings.stepGoal
                )

                TodayStatBox(
                    icon: "flame.fill", iconColor: workedOutToday ? .orange : .secondary,
                    value: workedOutToday ? "Done" : "Rest", label: "Workout",
                    done: workedOutToday
                )
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showMealSheet) {
            MealLogSheet { name in
                appState.addMeal(name: name)
            }
        }
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

// MARK: - Today Stat Box

private struct TodayStatBox: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    var done: Bool = false
    var action: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button {
                HapticManager.impact(done ? .light : .medium)
                action()
            } label: { content }
            .buttonStyle(PressableButtonStyle())
            .simultaneousGesture(
                secondaryAction.map { secondary in
                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                        HapticManager.impact(.rigid)
                        secondary()
                    }
                }
            )
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15)).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundColor(iconColor)
                } else if action != nil {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 30, height: 30)
                        .background(iconColor.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: done)
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

// MARK: - Today Empty Card

private struct TodayEmptyCard: View {
    let icon: String
    let iconColor: Color
    let message: String

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundColor(iconColor)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            Spacer()
        }
        .background(AppTheme.cardBg)
        .cornerRadius(12)
        .padding(.horizontal, 16)
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
                TodayEmptyCard(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    message: "All done for today!"
                )
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

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Toggle (independent of navigation)
            Button {
                HapticManager.impact(.light)
                appState.toggleTask(id: task.id)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.done ? .green : task.category.color)
                    .font(.title3)
            }
            .buttonStyle(.plain)

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
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .strikethrough(task.done)
                            .foregroundColor(task.done ? .secondary : .primary)

                        HStack(spacing: 6) {
                            Text(task.category.emoji + " " + task.category.label)
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
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                TodayEmptyCard(
                    icon: "repeat.circle.fill",
                    iconColor: Color(.tertiaryLabel),
                    message: "No habits yet.\nAdd some in the Habits tab."
                )
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

    private var streak: Int { appState.streakFor(habit) }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                HabitDetailView(habitId: habit.id)
            } label: {
                HStack(spacing: 12) {
                    Text(habit.emoji)
                        .font(.title2)

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
                            }
                        }

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
                }
            }
            .buttonStyle(.plain)

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
