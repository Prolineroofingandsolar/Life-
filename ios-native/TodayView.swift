import SwiftUI

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
        appState.tasks.filter { $0.dueDate == .today && !$0.done }
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

// MARK: - Care Section

private struct CareSection: View {

    @Environment(AppState.self) private var appState

    private var today: CareDay { appState.today }
    private var settings: CareSettings { appState.careSettings }

    private var timeSinceBreak: String? {
        guard let lastBreak = today.lastBreakAt else { return nil }
        let minutes = Int(Date().timeIntervalSince(lastBreak) / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h \(minutes % 60)m ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Care")
                .font(.headline)
                .padding(.horizontal, 20)

            // Water
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Water", systemImage: "drop.fill")
                        .foregroundColor(.blue)
                    Spacer()
                    Text("\(today.waterGlasses) / \(settings.waterGoal)")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                // Glass bubbles
                let glasses = settings.waterGoal
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(0..<glasses, id: \.self) { idx in
                        Image(systemName: idx < today.waterGlasses ? "drop.fill" : "drop")
                            .foregroundColor(idx < today.waterGlasses ? .blue : Color(.systemFill))
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        appState.addWater()
                    } label: {
                        Label("Add Glass", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    if today.waterGlasses > 0 {
                        Button {
                            appState.removeWater()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            // Meals & Break
            HStack(spacing: 12) {
                // Meals
                VStack(alignment: .leading, spacing: 8) {
                    Label("Meals", systemImage: "fork.knife")
                        .foregroundColor(.orange)
                        .font(.subheadline)

                    Text("\(today.meals.count) / \(settings.mealGoal)")
                        .font(.title2.bold())

                    Button {
                        appState.addMeal()
                    } label: {
                        Label("Log Meal", systemImage: "plus")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

                // Break
                VStack(alignment: .leading, spacing: 8) {
                    Label("Breaks", systemImage: "cup.and.saucer.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)

                    Text("\(today.breaksTaken) taken")
                        .font(.title2.bold())

                    if let lastBreak = timeSinceBreak {
                        Text(lastBreak)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        appState.markBreak()
                    } label: {
                        Label("Take Break", systemImage: "figure.walk")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
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

    private var todayLog: HabitLogEntry? {
        habit.logs.first { $0.dayKey == Date().dayKey }
    }

    private var isComplete: Bool {
        guard let log = todayLog else { return false }
        return log.count >= habit.targetCount && !log.slipped
    }

    var body: some View {
        Button {
            if habit.kind == .build {
                appState.incHabitToday(id: habit.id)
            } else {
                appState.slipHabitToday(id: habit.id)
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
                            Text("Maintained today")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if todayLog?.slipped == true {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}
