import SwiftUI

// MARK: - Habits View

struct HabitsView: View {

    @Environment(AppState.self) private var appState
    @State private var showAddHabit = false
    @State private var editHabit: Habit? = nil
    @State private var filter: HabitFilter = .today

    enum HabitFilter: String, CaseIterable {
        case today = "Today"
        case week  = "Week"
        case month = "Month"
    }

    private var activeHabits: [Habit] { appState.habits.filter { !$0.isArchived } }
    private var archivedHabits: [Habit] { appState.habits.filter { $0.isArchived } }

    private var completedToday: Int {
        activeHabits.filter { habit in
            guard let log = habit.logs.first(where: { $0.dayKey == Date().dayKey }) else { return false }
            return log.count >= habit.targetCount && !log.slipped
        }.count
    }
    private var totalToday: Int { activeHabits.count }
    private var todayProgress: Double {
        totalToday == 0 ? 0 : Double(completedToday) / Double(totalToday)
    }
    private var bestStreak: Int {
        activeHabits.map { appState.streakFor($0) }.max() ?? 0
    }
    private var weeklyRate: Double {
        guard !activeHabits.isEmpty else { return 0 }
        return activeHabits.map { appState.weeklyCompletionFor($0) }.reduce(0, +) / Double(activeHabits.count)
    }
    private var motivationalText: String {
        switch todayProgress {
        case 1.0:    return "All done! Amazing work 🎉"
        case 0.75...: return "Almost there, keep going!"
        case 0.5...:  return "Great momentum today"
        case 0.25...: return "Good start, keep it up"
        default:      return "Let's build momentum"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    statsRow
                    SupplementsSection()
                    filterPicker
                    habitsList
                    if !archivedHabits.isEmpty { archivedSection }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Habits")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddHabit = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppTheme.primary)
                    }
                }
            }
            .sheet(isPresented: $showAddHabit) { AddHabitSheet() }
            .sheet(item: $editHabit) { EditHabitSheet(habit: $0) }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(motivationalText)
                    .font(.title3.bold())
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: todayProgress)
                    .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: todayProgress)
                VStack(spacing: 0) {
                    Text("\(Int(todayProgress * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("done")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 64, height: 64)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            HabitStatCard(icon: "flame.fill",         iconColor: .orange,        value: "\(bestStreak)d",           label: "Best Streak")
            HabitStatCard(icon: "checkmark.circle.fill", iconColor: AppTheme.primary, value: "\(completedToday)/\(totalToday)", label: "Today")
            HabitStatCard(icon: "chart.bar.fill",      iconColor: .blue,          value: "\(Int(weeklyRate * 100))%", label: "This Week")
        }
    }

    // MARK: Filter

    private var filterPicker: some View {
        HStack(spacing: 0) {
            ForEach(HabitFilter.allCases, id: \.self) { f in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { filter = f }
                } label: {
                    Text(f.rawValue)
                        .font(.subheadline.weight(filter == f ? .semibold : .regular))
                        .foregroundColor(filter == f ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(filter == f ? Color(.secondarySystemGroupedBackground) : Color.clear)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.systemFill))
        .cornerRadius(13)
    }

    // MARK: List

    private var habitsList: some View {
        Group {
            if activeHabits.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No habits yet")
                        .font(.headline)
                    Text("Tap + to start tracking your first habit.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
            } else {
                VStack(spacing: 10) {
                    ForEach(activeHabits) { habit in
                        HabitCard(habit: habit, filter: filter, onEdit: { editHabit = habit })
                    }
                }
            }
        }
    }

    // MARK: Archived

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archived")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(archivedHabits) { habit in
                    HStack {
                        Text(habit.emoji)
                        Text(habit.name).font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button {
                            appState.toggleArchiveHabit(id: habit.id)
                        } label: {
                            Text("Restore").font(.caption.weight(.medium)).foregroundColor(AppTheme.primary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if habit.id != archivedHabits.last?.id { Divider().padding(.leading, 16) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }
}

// MARK: - Stat Card

struct HabitStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(iconColor)
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Habit Card

private struct HabitCard: View {
    @Environment(AppState.self) private var appState
    let habit: Habit
    let filter: HabitsView.HabitFilter
    let onEdit: () -> Void

    @State private var showUndo = false
    @State private var undoTask: Task<Void, Never>? = nil

    private var todayLog: HabitLogEntry? { habit.logs.first { $0.dayKey == Date().dayKey } }

    private var isComplete: Bool {
        guard let log = todayLog else { return false }
        return log.count >= habit.targetCount && !log.slipped
    }

    private var streak: Int { appState.streakFor(habit) }
    private var weeklyPct: Int { Int(appState.weeklyCompletionFor(habit) * 100) }
    private var progress: Double {
        guard habit.targetCount > 0 else { return 0 }
        return min(Double(todayLog?.count ?? 0) / Double(habit.targetCount), 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(habit.category.color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Text(habit.emoji).font(.system(size: 26))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(habit.name).font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        habitPill(habit.category.label, color: habit.category.color)
                        habitPill(habit.kind == .build ? "Build" : "Break",
                                  color: habit.kind == .build ? AppTheme.primary : .red)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if showUndo {
                        Button {
                            undoTask?.cancel()
                            showUndo = false
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
                    }

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
                        ZStack {
                            Circle()
                                .fill(isComplete ? AppTheme.primary : Color(.systemFill))
                                .frame(width: 36, height: 36)
                            if isComplete {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            } else if habit.kind == .break, todayLog?.slipped == true {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if habit.kind == .build && habit.targetCount > 1 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(.systemFill)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isComplete ? AppTheme.primary : habit.category.color)
                            .frame(width: geo.size.width * progress, height: 5)
                            .animation(.spring(response: 0.4), value: progress)
                    }
                }
                .frame(height: 5)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            HStack {
                Label("\(streak) day streak", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundColor(streak > 0 ? .orange : .secondary)
                Spacer()
                Text("\(weeklyPct)% this week")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, filter == .today ? 14 : 10)

            if filter == .week {
                WeekMiniGrid(habit: habit)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else if filter == .month {
                HabitHeatmapView(habit: habit)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button { appState.toggleArchiveHabit(id: habit.id) } label: { Label("Archive", systemImage: "archivebox") }
            Button(role: .destructive) { appState.deleteHabit(id: habit.id) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            if habit.kind == .build {
                Button { HapticManager.impact(.medium); appState.incHabitToday(id: habit.id) }
                    label: { Label("Log", systemImage: "plus") }
                    .tint(AppTheme.primary)
            } else {
                Button { HapticManager.impact(.medium); appState.slipHabitToday(id: habit.id) }
                    label: { Label("Slip", systemImage: "xmark") }
                    .tint(.red)
            }
        }
    }

    private func habitPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .cornerRadius(6)
    }
}

// MARK: - Week Mini Grid

private struct WeekMiniGrid: View {
    let habit: Habit

    private var days: [(label: String, key: String, intensity: Double)] {
        let cal = Calendar.current
        let today = Date()
        let dayLabels = ["S","M","T","W","T","F","S"]
        return (0..<7).reversed().map { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else {
                return ("", "", 0)
            }
            let key = date.dayKey
            let weekday = cal.component(.weekday, from: date) - 1
            let label = dayLabels[weekday]
            let log = habit.logs.first { $0.dayKey == key }
            let intensity: Double
            if let log {
                if log.slipped { intensity = -1 }
                else { intensity = min(Double(log.count) / Double(max(habit.targetCount, 1)), 1.0) }
            } else {
                intensity = 0
            }
            return (label, key, intensity)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(cellColor(day.intensity))
                        .frame(height: 28)
                    Text(day.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func cellColor(_ intensity: Double) -> Color {
        if intensity < 0 { return .red.opacity(0.6) }
        if intensity == 0 { return Color(.systemFill) }
        return AppTheme.primary.opacity(0.3 + intensity * 0.7)
    }
}

// MARK: - Heatmap (used by HabitDetailView)

struct HabitHeatmapView: View {
    let habit: Habit
    private let cols = 12
    private let rows = 7

    private var cells: [(date: Date, key: String)] {
        var result: [(Date, String)] = []
        let cal = Calendar.current
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let startOffset = (weekday - 1) + (cols - 1) * 7
        guard let startDate = cal.date(byAdding: .day, value: -startOffset, to: today.startOfDay) else { return result }
        for col in 0..<cols {
            for row in 0..<rows {
                if let date = cal.date(byAdding: .day, value: col * 7 + row, to: startDate) {
                    result.append((date, date.dayKey))
                }
            }
        }
        return result
    }

    private func intensity(for key: String) -> Double {
        guard let log = habit.logs.first(where: { $0.dayKey == key }) else { return 0 }
        if log.slipped { return -1 }
        return min(Double(log.count) / Double(max(habit.targetCount, 1)), 1.0)
    }

    private func cellColor(intensity: Double) -> Color {
        if intensity < 0 { return .red.opacity(0.7) }
        if intensity == 0 { return Color(.systemFill) }
        return AppTheme.primary.opacity(0.3 + intensity * 0.7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 12 weeks")
                .font(.caption).foregroundColor(.secondary)
                .padding(.horizontal, 16).padding(.top, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: cols), spacing: 3) {
                ForEach(cells, id: \.key) { cell in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(intensity: intensity(for: cell.key)))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }
}

// MARK: - Add Habit Sheet

struct AddHabitSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "⭐️"
    @State private var kind: HabitKind = .build
    @State private var category: HabitCategory = .health
    @State private var cadence: HabitCadence = .daily
    @State private var targetType: HabitTargetType = .yesNo
    @State private var targetCount = 1
    @State private var targetUnit = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    HStack {
                        TextField("Emoji", text: $emoji).frame(width: 50).multilineTextAlignment(.center)
                        Divider()
                        TextField("What do you want to track?", text: $name).focused($isNameFocused)
                    }
                }
                Section("Details") {
                    Picker("Type", selection: $kind) {
                        ForEach(HabitKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Category", selection: $category) {
                        ForEach(HabitCategory.allCases) { c in Text(c.emoji + " " + c.label).tag(c) }
                    }
                    Picker("Cadence", selection: $cadence) {
                        ForEach(HabitCadence.allCases) { Text($0.label).tag($0) }
                    }
                    if kind == .build {
                        Picker("Tracking", selection: $targetType) {
                            ForEach(HabitTargetType.allCases) { Text($0.label).tag($0) }
                        }
                        if targetType != .yesNo {
                            Stepper(
                                targetType == .timer ? "Target: \(targetCount) min" : "Target: \(targetCount)×",
                                value: $targetCount, in: 1...500
                            )
                            if targetType == .count {
                                HStack {
                                    Text("Unit")
                                    Spacer()
                                    TextField("e.g. glasses", text: $targetUnit)
                                        .multilineTextAlignment(.trailing).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let habit = Habit(
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "⭐️" : emoji,
                            category: category,
                            kind: kind,
                            cadence: cadence,
                            targetType: kind == .build ? targetType : .yesNo,
                            targetCount: targetCount,
                            targetUnit: targetUnit
                        )
                        appState.habits.append(habit)
                        appState.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}

// MARK: - Edit Habit Sheet

struct EditHabitSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let habit: Habit
    @State private var name: String
    @State private var emoji: String
    @State private var kind: HabitKind
    @State private var category: HabitCategory
    @State private var cadence: HabitCadence
    @State private var targetType: HabitTargetType
    @State private var targetCount: Int
    @State private var targetUnit: String

    init(habit: Habit) {
        self.habit = habit
        _name        = State(initialValue: habit.name)
        _emoji       = State(initialValue: habit.emoji)
        _kind        = State(initialValue: habit.kind)
        _category    = State(initialValue: habit.category)
        _cadence     = State(initialValue: habit.cadence)
        _targetType  = State(initialValue: habit.targetType)
        _targetCount = State(initialValue: habit.targetCount)
        _targetUnit  = State(initialValue: habit.targetUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    HStack {
                        TextField("Emoji", text: $emoji).frame(width: 50).multilineTextAlignment(.center)
                        Divider()
                        TextField("Name", text: $name)
                    }
                }
                Section("Details") {
                    Picker("Type", selection: $kind) {
                        ForEach(HabitKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Category", selection: $category) {
                        ForEach(HabitCategory.allCases) { c in Text(c.emoji + " " + c.label).tag(c) }
                    }
                    Picker("Cadence", selection: $cadence) {
                        ForEach(HabitCadence.allCases) { Text($0.label).tag($0) }
                    }
                    if kind == .build {
                        Picker("Tracking", selection: $targetType) {
                            ForEach(HabitTargetType.allCases) { Text($0.label).tag($0) }
                        }
                        if targetType != .yesNo {
                            Stepper(
                                targetType == .timer ? "Target: \(targetCount) min" : "Target: \(targetCount)×",
                                value: $targetCount, in: 1...500
                            )
                        }
                    }
                }
            }
            .navigationTitle("Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.updateHabit(id: habit.id, name: name.trimmingCharacters(in: .whitespaces),
                                             emoji: emoji.isEmpty ? "⭐️" : emoji,
                                             kind: kind, cadence: cadence, targetCount: targetCount)
                        if let idx = appState.habits.firstIndex(where: { $0.id == habit.id }) {
                            appState.habits[idx].category   = category
                            appState.habits[idx].targetType = targetType
                            appState.habits[idx].targetUnit = targetUnit
                            appState.save()
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supplements Section

private struct SupplementsSection: View {
    @Environment(AppState.self) private var appState
    @State private var showAdd = false

    private var activeSupplements: [Supplement] {
        appState.supplements.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Supplements")
                    .font(.headline)
                Spacer()
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primary)
                }
            }

            if activeSupplements.isEmpty {
                Button { showAdd = true } label: {
                    HStack {
                        Image(systemName: "pills")
                            .foregroundColor(.secondary)
                        Text("Add supplements, vitamins & more")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(activeSupplements) { supplement in
                    SupplementCard(supplement: supplement)
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddSupplementSheet() }
    }
}

private struct SupplementCard: View {
    @Environment(AppState.self) private var appState
    let supplement: Supplement

    @State private var showUndo = false
    @State private var undoTask: Task<Void, Never>? = nil

    private var taken: Int { appState.dosesToday(for: supplement) }
    private var total: Int { supplement.dosesPerDay }
    private var isDone: Bool { taken >= total }
    private var isDue: Bool { appState.isDueToday(supplement) }

    private var scheduleLabel: String {
        if supplement.scheduleDays.isEmpty { return "Every day" }
        let names = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        return supplement.scheduleDays.sorted().compactMap { ($0 >= 1 && $0 <= 7) ? names[$0-1] : nil }.joined(separator: " & ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? AppTheme.primary.opacity(0.15) : Color(.tertiarySystemFill))
                    .frame(width: 40, height: 40)
                Text(supplement.emoji)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(supplement.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isDue ? .primary : .secondary)
                Text(isDue ? "\(scheduleLabel) · \(supplement.doseUnit)" : "Not due today")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i < taken ? AppTheme.primary : Color(.tertiarySystemFill))
                        .frame(width: 8, height: 8)
                }
            }

            HStack(spacing: 8) {
                if showUndo {
                    Button {
                        undoTask?.cancel()
                        showUndo = false
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
                }

                Button {
                    guard isDue && !isDone else { return }
                    HapticManager.impact(.light)
                    appState.logDose(supplementId: supplement.id)
                    withAnimation { showUndo = true }
                    undoTask?.cancel()
                    undoTask = Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run { withAnimation { showUndo = false } }
                    }
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(isDone ? AppTheme.primary : (isDue ? .secondary : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!isDue || isDone)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .opacity(isDue ? 1 : 0.5)
        .contextMenu {
            Button(role: .destructive) {
                appState.deleteSupplement(id: supplement.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct AddSupplementSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "💊"
    @State private var dosesPerDay = 1
    @State private var doseUnit = "capsule"
    @State private var everyDay = true
    @State private var selectedDays: Set<Int> = []

    private let emojiOptions = ["💊","🧴","🫙","🧪","🍋","🫐","🥛","🌿","⚡️","🔥"]
    private let unitOptions = ["capsule","tablet","scoop","ml","drop","serving"]
    private let dayNames = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Creatine, Vitamin D", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(emojiOptions, id: \.self) { e in
                            Text(e)
                                .font(.system(size: 28))
                                .frame(width: 48, height: 48)
                                .background(emoji == e ? AppTheme.primary.opacity(0.15) : Color(.tertiarySystemFill))
                                .cornerRadius(10)
                                .onTapGesture { emoji = e }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section("Doses per day") {
                    Stepper("\(dosesPerDay) \(dosesPerDay == 1 ? doseUnit : doseUnit + "s")", value: $dosesPerDay, in: 1...6)
                    Picker("Unit", selection: $doseUnit) {
                        ForEach(unitOptions, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Schedule") {
                    Toggle("Every day", isOn: $everyDay)
                    if !everyDay {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                            ForEach(Array(dayNames.enumerated()), id: \.offset) { idx, day in
                                let dayNum = idx + 1
                                Text(String(day.prefix(1)))
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 36, height: 36)
                                    .background(selectedDays.contains(dayNum) ? AppTheme.primary : Color(.tertiarySystemFill))
                                    .foregroundColor(selectedDays.contains(dayNum) ? .white : .primary)
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        if selectedDays.contains(dayNum) { selectedDays.remove(dayNum) }
                                        else { selectedDays.insert(dayNum) }
                                    }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }
            }
            .navigationTitle("Add Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        var s = Supplement(name: name.trimmingCharacters(in: .whitespaces))
                        s.emoji = emoji
                        s.dosesPerDay = dosesPerDay
                        s.doseUnit = doseUnit
                        s.scheduleDays = everyDay ? [] : Array(selectedDays).sorted()
                        appState.addSupplement(s)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

