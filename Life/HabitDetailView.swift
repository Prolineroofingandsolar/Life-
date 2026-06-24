import SwiftUI

// MARK: - Habit Detail View

struct HabitDetailView: View {
    @Environment(AppState.self) private var appState
    let habitId: String

    @State private var showEdit = false
    @State private var timerRunning = false
    @State private var elapsed = 0
    @State private var showCompletion = false

    @State private var clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var habit: Habit? { appState.habits.first { $0.id == habitId } }

    private var todayLog: HabitLogEntry? { habit?.logs.first { $0.dayKey == Date().dayKey } }

    private var isCompleted: Bool {
        guard let h = habit else { return false }
        if h.kind == .break { return todayLog?.slipped != true }
        guard let log = todayLog else { return false }
        return log.count >= h.targetCount && !log.slipped
    }

    private var progress: Double {
        guard let h = habit else { return 0 }
        let count = Double(todayLog?.count ?? 0)
        return min(count / Double(max(h.targetCount, 1)), 1.0)
    }

    var body: some View {
        Group {
            if let habit = habit {
                ScrollView {
                    VStack(spacing: 20) {
                        headerCard(habit)
                        statsRow(habit)
                        checkinCard(habit)
                        heatmapCard(habit)
                        if !habit.notes.isEmpty { notesCard(habit) }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(habit.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") { showEdit = true }
                    }
                }
                .sheet(isPresented: $showEdit) {
                    if let h = appState.habits.first(where: { $0.id == habitId }) {
                        EditHabitSheet(habit: h)
                    }
                }
                .onReceive(clockTimer) { _ in
                    if timerRunning { elapsed += 1 }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 48)).foregroundColor(.secondary)
                    Text("Habit Not Found").font(.headline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Header Card

    private func headerCard(_ habit: Habit) -> some View {
        VStack(spacing: 14) {
            Text(habit.emoji)
                .font(.system(size: 56))
                .frame(width: 96, height: 96)
                .background(habit.category.color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 24))

            Text(habit.name)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                habitBadge(habit.category.label, color: habit.category.color)
                habitBadge(habit.kind == .build ? "Build" : "Break",
                           color: habit.kind == .build ? AppTheme.primary : .red)
                habitBadge(habit.cadence.label, color: .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
    }

    private func habitBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    // MARK: - Stats Row

    private func statsRow(_ habit: Habit) -> some View {
        let streak   = appState.streakFor(habit)
        let best     = appState.bestStreakFor(habit)
        let weekly   = appState.weeklyCompletionFor(habit)
        let total    = appState.totalCompletionsFor(habit)

        return HStack(spacing: 10) {
            DetailStatCard(value: "\(streak)",         label: "Current\nStreak", icon: "flame.fill",          color: .orange)
            DetailStatCard(value: "\(best)",           label: "Best\nStreak",    icon: "trophy.fill",         color: Color(hex: "#FFD700"))
            DetailStatCard(value: "\(Int(weekly*100))%", label: "This\nWeek",   icon: "chart.bar.fill",       color: Color(hex: "#5E9BF0"))
            DetailStatCard(value: "\(total)",          label: "Total\nDone",     icon: "checkmark.seal.fill", color: AppTheme.primary)
        }
    }

    // MARK: - Check-in Card

    private func checkinCard(_ habit: Habit) -> some View {
        VStack(spacing: 18) {
            HStack {
                Text("Today's Check-in")
                    .font(.headline)
                Spacer()
                if todayLog != nil {
                    Button("Undo") {
                        appState.undoHabitCompletion(id: habitId)
                        timerRunning = false
                        elapsed = 0
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                }
            }

            if habit.kind == .break {
                breakCheckin(habit)
            } else if habit.targetType == .count {
                countCheckin(habit)
            } else if habit.targetType == .timer {
                timerCheckin(habit)
            } else {
                yesNoCheckin(habit)
            }
        }
        .padding(20)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
    }

    // YES/NO
    private func yesNoCheckin(_ habit: Habit) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { showCompletion = true }
            HapticManager.success()
            appState.toggleHabitToday(id: habitId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCompletion = false }
        } label: {
            ZStack {
                Circle()
                    .fill(isCompleted ? AppTheme.primary : Color(.systemFill))
                    .frame(width: 88, height: 88)
                Image(systemName: isCompleted ? "checkmark" : "circle")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(isCompleted ? .white : .secondary)
            }
            .scaleEffect(showCompletion ? 1.25 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // BREAK
    private func breakCheckin(_ habit: Habit) -> some View {
        HStack(spacing: 16) {
            Button {
                HapticManager.success()
                appState.undoHabitCompletion(id: habitId)
            } label: {
                Label("Maintained", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .background(isCompleted ? AppTheme.primary : Color.gray.opacity(0.3))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.impact(.heavy)
                appState.slipHabitToday(id: habitId)
            } label: {
                Label("Slipped", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .background(todayLog?.slipped == true ? Color.red : Color.gray.opacity(0.3))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // COUNT
    private func countCheckin(_ habit: Habit) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 28) {
                Button {
                    HapticManager.impact(.light)
                    let current = todayLog?.count ?? 0
                    appState.setHabitCount(id: habitId, count: current - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(Color(.systemFill))
                }
                .buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text("\(todayLog?.count ?? 0)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("/ \(habit.targetCount) \(habit.targetUnit)")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .animation(.spring(response: 0.3), value: todayLog?.count)

                Button {
                    HapticManager.impact(.light)
                    appState.incHabitToday(id: habitId)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AppTheme.primary)
                }
                .buttonStyle(.plain)
            }

            ProgressView(value: progress)
                .tint(AppTheme.primary)
                .animation(.spring(response: 0.4), value: progress)
        }
    }

    // TIMER
    private func timerCheckin(_ habit: Habit) -> some View {
        let targetSecs = habit.targetCount * 60
        return VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 10)
                    .frame(width: 148, height: 148)
                Circle()
                    .trim(from: 0, to: min(Double(elapsed) / Double(max(targetSecs, 1)), 1.0))
                    .stroke(AppTheme.primary,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 148, height: 148)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: elapsed)
                VStack(spacing: 3) {
                    Text(elapsed.formattedDuration)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                    Text("/ \(habit.targetCount) min")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            HStack(spacing: 20) {
                Button {
                    elapsed = 0; timerRunning = false
                    HapticManager.impact(.medium)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 48, height: 48)
                        .background(Color(.systemFill))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    timerRunning.toggle()
                    HapticManager.impact(.medium)
                } label: {
                    Image(systemName: timerRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(timerRunning ? Color.orange : AppTheme.primary)
                        .clipShape(Circle())
                        .shadow(color: (timerRunning ? Color.orange : AppTheme.primary).opacity(0.4), radius: 8)
                }
                .buttonStyle(.plain)

                if elapsed >= targetSecs {
                    Button {
                        appState.completeHabitTimer(id: habitId, seconds: elapsed)
                        timerRunning = false
                        HapticManager.success()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }
            }
        }
    }

    // MARK: - Heatmap Card

    private func heatmapCard(_ habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.headline)
            HabitHeatmapView(habit: habit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
    }

    // MARK: - Notes Card

    private func notesCard(_ habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(.headline)
            Text(habit.notes)
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
    }
}

// MARK: - Detail Stat Card

struct DetailStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.subheadline).foregroundColor(color)
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
    }
}
