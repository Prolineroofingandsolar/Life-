import SwiftUI

// MARK: - Filter

enum HabitFilter: String, CaseIterable {
    case today = "Today"
    case week  = "Week"
    case month = "Month"
}

// MARK: - HabitsView

struct HabitsView: View {
    @Environment(AppState.self) private var appState
    @State private var filter: HabitFilter = .today
    @State private var showAddHabit = false
    @State private var showAnalytics = false
    @State private var editingHabit: Habit? = nil
    @State private var showUndoFor: String? = nil
    @State private var noteHabitId: String? = nil
    @State private var noteText = ""

    private var activeHabits: [Habit] { appState.habits.filter { !$0.isArchived } }
    private var archivedHabits: [Habit] { appState.habits.filter { $0.isArchived } }

    private var filteredHabits: [Habit] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date()) // 1=Sun…7=Sat
        let mondayBased = weekday == 1 ? 7 : weekday - 1   // 1=Mon…7=Sun
        switch filter {
        case .today:
            return activeHabits.filter { h in
                switch h.cadence {
                case .daily: return true
                case .weekly, .timesPerWeek: return true
                case .specificWeekdays: return h.weekdays.contains(mondayBased)
                case .timesPerMonth: return true
                }
            }
        case .week:
            return activeHabits.filter { h in
                h.cadence == .daily || h.cadence == .weekly || h.cadence == .timesPerWeek || h.cadence == .specificWeekdays
            }
        case .month:
            return activeHabits
        }
    }

    private var motivationMessage: String {
        let done = activeHabits.filter { isCompletedToday($0) }.count
        let total = activeHabits.count
        if total == 0 { return "Add your first habit" }
        if done == total { return "Perfect day! 🎉" }
        if done == 0 { return "Let's build momentum" }
        if Double(done) / Double(total) >= 0.75 { return "Almost there! 🔥" }
        if done >= 3 { return "Great progress! 💪" }
        return "Keep going!"
    }

    private var completionToday: Double {
        guard !activeHabits.isEmpty else { return 0 }
        return Double(activeHabits.filter { isCompletedToday($0) }.count) / Double(activeHabits.count)
    }

    private var weeklyPct: Double {
        guard !activeHabits.isEmpty else { return 0 }
        let cal = Calendar.current
        var done = 0.0
        for i in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let key = d.dayKey
            for h in activeHabits where isCompleted(h, for: key) { done += 1 }
        }
        return done / Double(activeHabits.count * 7)
    }

    private var topStreak: Int { activeHabits.map { appState.streakFor($0) }.max() ?? 0 }

    private func isCompletedToday(_ h: Habit) -> Bool { isCompleted(h, for: Date().dayKey) }

    private func isCompleted(_ h: Habit, for key: String) -> Bool {
        guard let log = h.logs.first(where: { $0.dayKey == key }) else { return false }
        return h.kind == .break ? !log.slipped : log.count >= h.targetCount && !log.slipped
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        dashboardHeader
                        filterPicker
                        habitsList
                        if !archivedHabits.isEmpty { archivedSection }
                        Color.clear.frame(height: 100)
                    }
                }
                .background(Color(.systemGroupedBackground))

                // FAB
                Button { showAddHabit = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(AppTheme.primary)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.primary.opacity(0.4), radius: 10, x: 0, y: 4)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Habits")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAnalytics = true } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                }
            }
            .sheet(isPresented: $showAddHabit) { AddHabitView() }
            .sheet(item: $editingHabit) { h in EditHabitView(habit: h) }
            .navigationDestination(isPresented: $showAnalytics) { HabitAnalyticsView() }
            .sheet(item: Binding(
                get: { noteHabitId.map { HabitNoteContext(id: $0) } },
                set: { noteHabitId = $0?.id }
            )) { ctx in
                HabitQuickNoteSheet(habitId: ctx.id, note: $noteText) {
                    if !noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                        appState.addNoteToTodayLog(id: ctx.id, note: noteText)
                    }
                    noteHabitId = nil
                    noteText = ""
                }
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
            }
            .overlay(alignment: .bottom) {
                if let undoId = showUndoFor {
                    undoToast(id: undoId)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 90)
                }
            }
            .animation(.spring(response: 0.3), value: showUndoFor)
            .onAppear { appState.applyPendingWidgetCompletions() }
        }
    }

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(motivationMessage)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 12)
                // Completion ring
                ZStack {
                    Circle()
                        .stroke(Color(.systemFill), lineWidth: 7)
                        .frame(width: 68, height: 68)
                    Circle()
                        .trim(from: 0, to: completionToday)
                        .stroke(AppTheme.primary,
                                style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: completionToday)
                    VStack(spacing: 1) {
                        Text("\(Int(completionToday * 100))%")
                            .font(.system(size: 15, weight: .bold))
                        Text("done")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                DashStatPill(icon: "flame.fill",
                             value: "\(topStreak)d",
                             label: "Best Streak",
                             color: .orange)
                DashStatPill(icon: "checkmark.circle.fill",
                             value: "\(activeHabits.filter { isCompletedToday($0) }.count)/\(activeHabits.count)",
                             label: "Today",
                             color: AppTheme.primary)
                DashStatPill(icon: "chart.bar.fill",
                             value: "\(Int(weeklyPct * 100))%",
                             label: "This Week",
                             color: Color(hex: "#5E9BF0"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [AppTheme.primary.opacity(0.12), Color(.systemGroupedBackground)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Filter Picker

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(HabitFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Habits List

    @ViewBuilder
    private var habitsList: some View {
        if activeHabits.isEmpty {
            emptyState
        } else if filteredHabits.isEmpty {
            VStack(spacing: 8) {
                Text("No habits for this period")
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding(.top, 32)
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredHabits) { habit in
                    NavigationLink(destination: HabitDetailView(habitId: habit.id)) {
                        HabitCardView(habit: habit, onComplete: { id in
                            showUndoFor = id
                            noteHabitId = id
                            noteText = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                if showUndoFor == id { showUndoFor = nil }
                            }
                        })
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            HapticManager.success()
                            appState.toggleHabitToday(id: habit.id)
                        } label: {
                            Label("Done", systemImage: "checkmark.circle.fill")
                        }
                        .tint(AppTheme.primary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            appState.deleteHabit(id: habit.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            appState.toggleArchiveHabit(id: habit.id)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)
                        Button {
                            editingHabit = habit
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button { editingHabit = habit } label: { Label("Edit", systemImage: "pencil") }
                        Button { appState.toggleArchiveHabit(id: habit.id) } label: { Label("Archive", systemImage: "archivebox") }
                        Button(role: .destructive) { appState.deleteHabit(id: habit.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.primary.opacity(0.7))
                .padding(.top, 48)
            VStack(spacing: 8) {
                Text("No habits yet")
                    .font(.title2.bold())
                Text("Start building the life you want, one habit at a time.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button { showAddHabit = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add First Habit").fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(AppTheme.primary)
                .clipShape(Capsule())
            }
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Archived Section

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archived")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ForEach(archivedHabits) { habit in
                HStack(spacing: 12) {
                    Text(habit.emoji).font(.title3)
                    Text(habit.name).font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Button { appState.toggleArchiveHabit(id: habit.id) } label: {
                        Text("Restore")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppTheme.primary)
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Undo Toast

    private func undoToast(id: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.primary)
            Text("Habit completed")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Undo") {
                appState.undoHabitCompletion(id: id)
                showUndoFor = nil
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppTheme.primary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 10)
        .padding(.horizontal, 16)
    }
}

// MARK: - Dash Stat Pill

private struct DashStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption.weight(.semibold)).foregroundColor(color)
                Text(value).font(.subheadline.bold())
            }
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Habit Card View

struct HabitCardView: View {
    @Environment(AppState.self) private var appState
    let habit: Habit
    var onComplete: ((String) -> Void)? = nil
    @State private var completing = false

    private var todayLog: HabitLogEntry? { habit.logs.first { $0.dayKey == Date().dayKey } }

    private var isCompleted: Bool {
        guard let log = todayLog else { return false }
        return habit.kind == .break ? !log.slipped : log.count >= habit.targetCount && !log.slipped
    }

    private var progress: Double {
        let count = Double(todayLog?.count ?? 0)
        return min(count / Double(max(habit.targetCount, 1)), 1.0)
    }

    private var streak: Int { appState.streakFor(habit) }
    private var weeklyPct: Double { appState.weeklyCompletionFor(habit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row
            HStack(spacing: 12) {
                Text(habit.emoji)
                    .font(.system(size: 28))
                    .frame(width: 52, height: 52)
                    .background(habit.category.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        badgeView(habit.category.label, color: habit.category.color)
                        badgeView(habit.kind == .build ? "Build" : "Break",
                                  color: habit.kind == .build ? AppTheme.primary : .red)
                    }
                }
                Spacer()
                completionButton
            }

            // Progress bar for count habits
            if habit.kind == .build && habit.targetType == .count && habit.targetCount > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.systemFill)).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isCompleted ? AppTheme.primary : AppTheme.primary.opacity(0.6))
                                .frame(width: geo.size.width * progress, height: 6)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: progress)
                        }
                    }
                    .frame(height: 6)
                    Text("\(todayLog?.count ?? 0)/\(habit.targetCount) \(habit.targetUnit.isEmpty ? "" : habit.targetUnit)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            // Bottom stats
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.caption.weight(.medium)).foregroundColor(.orange)
                    Text("\(streak) day streak")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(Int(weeklyPct * 100))% this week")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
    }

    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var completionButton: some View {
        if habit.kind == .break {
            // Break habits: show status indicator, tap to confirm slip
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { completing = true }
                HapticManager.impact(.heavy)
                appState.slipHabitToday(id: habit.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completing = false }
            } label: {
                ZStack {
                    Circle()
                        .fill(todayLog?.slipped == true ? Color.red : AppTheme.primary)
                        .frame(width: 38, height: 38)
                    Image(systemName: todayLog?.slipped == true ? "xmark" : "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .scaleEffect(completing ? 1.3 : 1.0)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Mark as slipped today?", isPresented: .constant(false)) {}
        } else {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { completing = true }
                HapticManager.success()
                if habit.targetType == .count && habit.targetCount > 1 {
                    appState.incHabitToday(id: habit.id)
                } else {
                    appState.toggleHabitToday(id: habit.id)
                    if !isCompleted { onComplete?(habit.id) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completing = false }
            } label: {
                ZStack {
                    Circle()
                        .fill(isCompleted ? AppTheme.primary : Color(.systemFill))
                        .frame(width: 38, height: 38)
                    Image(systemName: isCompleted ? "checkmark" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isCompleted ? .white : .secondary)
                }
                .scaleEffect(completing ? 1.3 : 1.0)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Add Habit View

struct AddHabitView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "⭐️"
    @State private var category: HabitCategory = .health
    @State private var kind: HabitKind = .build
    @State private var cadence: HabitCadence = .daily
    @State private var targetType: HabitTargetType = .yesNo
    @State private var targetCount = 1
    @State private var targetUnit = ""
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var notes = ""
    @State private var showEmojiPicker = false
    @FocusState private var nameFocused: Bool

    private let emojiGrid = [
        "⭐️","💧","📚","🏃","🧘","💪","🥗","😴","🧠","⚡️",
        "🎯","✅","🔥","💊","🚶","🏋️","📝","🍎","☕","🎵",
        "🌞","🌿","🦷","🧴","💰","🎨","🤸","🧹","🐕","📵"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Emoji + Name
                Section {
                    HStack(spacing: 12) {
                        Button { withAnimation { showEmojiPicker.toggle() } } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(width: 52, height: 52)
                                .background(category.color.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        TextField("Habit name", text: $name)
                            .font(.headline)
                            .focused($nameFocused)
                    }
                    if showEmojiPicker {
                        LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 40)), count: 6), spacing: 8) {
                            ForEach(emojiGrid, id: \.self) { e in
                                Button { emoji = e; showEmojiPicker = false } label: {
                                    Text(e).font(.system(size: 24))
                                        .frame(width: 40, height: 40)
                                        .background(emoji == e ? category.color.opacity(0.2) : Color(.systemFill))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Category
                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(HabitCategory.allCases) { cat in
                                Button { category = cat } label: {
                                    HStack(spacing: 4) {
                                        Text(cat.emoji)
                                        Text(cat.label).font(.caption.weight(.medium))
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(category == cat ? cat.color : Color(.systemFill))
                                    .foregroundColor(category == cat ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Type
                Section("Habit Type") {
                    Picker("Type", selection: $kind) {
                        Text("📈 Build").tag(HabitKind.build)
                        Text("📉 Break").tag(HabitKind.break)
                    }
                    .pickerStyle(.segmented)
                }

                // Cadence
                Section("Frequency") {
                    Picker("Cadence", selection: $cadence) {
                        ForEach(HabitCadence.allCases) { Text($0.label).tag($0) }
                    }
                }

                // Target (build habits only)
                if kind == .build {
                    Section("Target") {
                        Picker("Target Type", selection: $targetType) {
                            ForEach(HabitTargetType.allCases) { t in
                                Label(t.label, systemImage: t.icon).tag(t)
                            }
                        }
                        if targetType == .count {
                            Stepper("Count: \(targetCount)", value: $targetCount, in: 1...500)
                            TextField("Unit (e.g. glasses, pages)", text: $targetUnit)
                        }
                        if targetType == .timer {
                            Stepper("Duration: \(targetCount) min", value: $targetCount, in: 1...240)
                        }
                    }
                }

                // Reminder
                Section("Reminder") {
                    Toggle("Daily Reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                }

                // Notes
                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 72)
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        appState.addHabit(
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji,
                            category: category,
                            kind: kind,
                            cadence: cadence,
                            targetType: targetType,
                            targetCount: targetCount,
                            targetUnit: targetUnit,
                            reminderEnabled: reminderEnabled,
                            reminderTime: reminderEnabled ? reminderTime : nil,
                            notes: notes
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
    }
}

// MARK: - Edit Habit View

struct EditHabitView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let habit: Habit

    @State private var name: String
    @State private var emoji: String
    @State private var category: HabitCategory
    @State private var kind: HabitKind
    @State private var cadence: HabitCadence
    @State private var targetType: HabitTargetType
    @State private var targetCount: Int
    @State private var targetUnit: String
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var notes: String

    init(habit: Habit) {
        self.habit = habit
        _name           = State(initialValue: habit.name)
        _emoji          = State(initialValue: habit.emoji)
        _category       = State(initialValue: habit.category)
        _kind           = State(initialValue: habit.kind)
        _cadence        = State(initialValue: habit.cadence)
        _targetType     = State(initialValue: habit.targetType)
        _targetCount    = State(initialValue: habit.targetCount)
        _targetUnit     = State(initialValue: habit.targetUnit)
        _reminderEnabled = State(initialValue: habit.reminderEnabled)
        _reminderTime   = State(initialValue: habit.reminderTime ?? Calendar.current.date(from: DateComponents(hour: 9)) ?? Date())
        _notes          = State(initialValue: habit.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("Emoji", text: $emoji)
                            .font(.system(size: 28))
                            .frame(width: 52)
                            .multilineTextAlignment(.center)
                        Divider()
                        TextField("Habit name", text: $name).font(.headline)
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(HabitCategory.allCases) { c in Text(c.emoji + " " + c.label).tag(c) }
                    }
                }
                Section("Details") {
                    Picker("Type", selection: $kind) {
                        Text("📈 Build").tag(HabitKind.build)
                        Text("📉 Break").tag(HabitKind.break)
                    }
                    .pickerStyle(.segmented)
                    Picker("Cadence", selection: $cadence) {
                        ForEach(HabitCadence.allCases) { Text($0.label).tag($0) }
                    }
                    if kind == .build {
                        Picker("Target Type", selection: $targetType) {
                            ForEach(HabitTargetType.allCases) { t in Label(t.label, systemImage: t.icon).tag(t) }
                        }
                        if targetType != .yesNo {
                            Stepper("Target: \(targetCount)\(targetType == .timer ? " min" : "×")", value: $targetCount, in: 1...500)
                        }
                        if targetType == .count {
                            TextField("Unit (optional)", text: $targetUnit)
                        }
                    }
                }
                Section("Reminder") {
                    Toggle("Daily Reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 72)
                }
            }
            .navigationTitle("Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.updateHabit(
                            id: habit.id,
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "⭐️" : emoji,
                            category: category, kind: kind, cadence: cadence,
                            targetType: targetType, targetCount: targetCount, targetUnit: targetUnit,
                            reminderEnabled: reminderEnabled,
                            reminderTime: reminderEnabled ? reminderTime : nil,
                            notes: notes
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Heatmap View (keep for use in HabitDetailView)

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
                if let d = cal.date(byAdding: .day, value: col * 7 + row, to: startDate) {
                    result.append((d, d.dayKey))
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

    private func cellColor(_ v: Double) -> Color {
        if v < 0 { return .red.opacity(0.6) }
        if v == 0 { return Color(.systemFill) }
        return AppTheme.primary.opacity(0.25 + v * 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 12 weeks")
                .font(.caption).foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: cols), spacing: 3) {
                ForEach(cells, id: \.key) { cell in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(intensity(for: cell.key)))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            // Legend
            HStack(spacing: 10) {
                Spacer()
                legendItem(color: Color(.systemFill), label: "None")
                legendItem(color: AppTheme.primary.opacity(0.7), label: "Done")
                legendItem(color: .red.opacity(0.6), label: "Slipped")
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Habit Note Helper

private struct HabitNoteContext: Identifiable {
    let id: String
}

struct HabitQuickNoteSheet: View {
    let habitId: String
    @Binding var note: String
    let onDone: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Add a note for today")
                .font(.headline)
                .padding(.top, 20)

            TextField("How did it go? (optional)", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(AppTheme.chipRadius)
                .focused($focused)
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button("Skip") { onDone() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemFill))
                    .cornerRadius(AppTheme.buttonRadius)
                    .foregroundColor(.primary)

                Button("Save") { onDone() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary)
                    .cornerRadius(AppTheme.buttonRadius)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .buttonStyle(.plain)
        }
        .onAppear { focused = true }
    }
}
