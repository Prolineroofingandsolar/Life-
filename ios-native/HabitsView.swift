import SwiftUI

// MARK: - HabitsView

struct HabitsView: View {

    @Environment(AppState.self) private var appState
    @State private var showAddHabit = false
    @State private var selectedHabit: Habit? = nil
    @State private var editHabit: Habit? = nil

    private var activeHabits: [Habit] {
        appState.habits.filter { !$0.isArchived }
    }

    private var archivedHabits: [Habit] {
        appState.habits.filter { $0.isArchived }
    }

    var body: some View {
        NavigationStack {
            List {
                if activeHabits.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No habits yet")
                                .font(.headline)
                            Text("Tap + to start tracking a habit.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Active Habits") {
                        ForEach(activeHabits) { habit in
                            HabitRow(habit: habit, onTap: {
                                withAnimation { selectedHabit = (selectedHabit?.id == habit.id) ? nil : habit }
                            })
                            .contextMenu {
                                Button {
                                    editHabit = habit
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    appState.toggleArchiveHabit(id: habit.id)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                Button(role: .destructive) {
                                    appState.deleteHabit(id: habit.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            if selectedHabit?.id == habit.id {
                                HabitHeatmapView(habit: habit)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                            }
                        }
                    }
                }

                if !archivedHabits.isEmpty {
                    Section("Archived") {
                        ForEach(archivedHabits) { habit in
                            HStack {
                                Text(habit.emoji)
                                Text(habit.name)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button {
                                    appState.toggleArchiveHabit(id: habit.id)
                                } label: {
                                    Text("Unarchive")
                                        .font(.caption)
                                        .foregroundColor(Color(hex: "#30d158"))
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Habits")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddHabit) {
                AddHabitSheet()
            }
            .sheet(item: $editHabit) { habit in
                EditHabitSheet(habit: habit)
            }
        }
    }
}

// MARK: - Habit Row

private struct HabitRow: View {
    @Environment(AppState.self) private var appState
    let habit: Habit
    let onTap: () -> Void

    private var todayLog: HabitLogEntry? {
        habit.logs.first { $0.dayKey == Date().dayKey }
    }

    private var isComplete: Bool {
        guard let log = todayLog else { return false }
        return !log.slipped && log.count >= habit.targetCount
    }

    private var streak: Int {
        var count = 0
        let cal = Calendar.current
        var date = Date()
        while true {
            let key = date.dayKey
            if let log = habit.logs.first(where: { $0.dayKey == key }), log.count >= habit.targetCount && !log.slipped {
                count += 1
                date = cal.date(byAdding: .day, value: -1, to: date) ?? date
            } else {
                break
            }
        }
        return count
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(habit.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    if habit.kind == .build {
                        // Progress bar
                        let progress = min(Double(todayLog?.count ?? 0) / Double(max(habit.targetCount, 1)), 1.0)
                        HStack(spacing: 6) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.systemFill))
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isComplete ? Color(hex: "#30d158") : .orange)
                                        .frame(width: geo.size.width * progress, height: 6)
                                }
                            }
                            .frame(height: 6)

                            Text("\(todayLog?.count ?? 0)/\(habit.targetCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Break habit status
                        if let log = todayLog, log.slipped {
                            Text("Slipped")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Maintained")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "#30d158"))
                    } else if habit.kind == .break, todayLog?.slipped == true {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }

                    if streak > 1 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                            Text("\(streak)")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if habit.kind == .build {
                Button {
                    appState.incHabitToday(id: habit.id)
                } label: {
                    Label("Log", systemImage: "plus")
                }
                .tint(Color(hex: "#30d158"))
            } else {
                Button {
                    appState.slipHabitToday(id: habit.id)
                } label: {
                    Label("Slip", systemImage: "xmark")
                }
                .tint(.red)
            }
        }
    }
}

// MARK: - Heatmap View

struct HabitHeatmapView: View {
    let habit: Habit

    private let weeks = 12
    private let cols = 12
    private let rows = 7

    private var cells: [(date: Date, key: String)] {
        var result: [(Date, String)] = []
        let cal = Calendar.current
        // Align to Sunday of the current week going back 'cols' weeks
        let today = Date()
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let startOffset = (weekday - 1) + (cols - 1) * 7
        guard let startDate = cal.date(byAdding: .day, value: -startOffset, to: today.startOfDay) else {
            return result
        }
        for col in 0..<cols {
            for row in 0..<rows {
                let offset = col * 7 + row
                if let date = cal.date(byAdding: .day, value: offset, to: startDate) {
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
        return Color(hex: "#30d158").opacity(0.3 + intensity * 0.7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last \(weeks) weeks")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Grid
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: cols),
                spacing: 3
            ) {
                ForEach(cells, id: \.key) { cell in
                    let v = intensity(for: cell.key)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(intensity: v))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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
    @State private var cadence: HabitCadence = .daily
    @State private var targetCount = 1
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    HStack {
                        TextField("Emoji", text: $emoji)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                        Divider()
                        TextField("What habit do you want to track?", text: $name)
                            .focused($isNameFocused)
                    }
                }

                Section("Details") {
                    Picker("Type", selection: $kind) {
                        ForEach(HabitKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Cadence", selection: $cadence) {
                        ForEach(HabitCadence.allCases) { Text($0.label).tag($0) }
                    }

                    if kind == .build {
                        Stepper("Target: \(targetCount)×", value: $targetCount, in: 1...100)
                    }
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        appState.addHabit(
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "⭐️" : emoji,
                            kind: kind,
                            cadence: cadence,
                            targetCount: targetCount
                        )
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
    @State private var cadence: HabitCadence
    @State private var targetCount: Int

    init(habit: Habit) {
        self.habit = habit
        _name = State(initialValue: habit.name)
        _emoji = State(initialValue: habit.emoji)
        _kind = State(initialValue: habit.kind)
        _cadence = State(initialValue: habit.cadence)
        _targetCount = State(initialValue: habit.targetCount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    HStack {
                        TextField("Emoji", text: $emoji)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                        Divider()
                        TextField("Name", text: $name)
                    }
                }
                Section("Details") {
                    Picker("Type", selection: $kind) {
                        ForEach(HabitKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Cadence", selection: $cadence) {
                        ForEach(HabitCadence.allCases) { Text($0.label).tag($0) }
                    }
                    if kind == .build {
                        Stepper("Target: \(targetCount)×", value: $targetCount, in: 1...100)
                    }
                }
            }
            .navigationTitle("Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.updateHabit(
                            id: habit.id,
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "⭐️" : emoji,
                            kind: kind,
                            cadence: cadence,
                            targetCount: targetCount
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}
