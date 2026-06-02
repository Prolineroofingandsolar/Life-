import SwiftUI

// MARK: - ProgramsView

struct ProgramsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddProgram = false
    @State private var editingProgram: WorkoutProgram? = nil

    var body: some View {
        NavigationStack {
            List {
                activeProgramCard
                programsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Programs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.impact(.medium)
                        showAddProgram = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddProgram) {
                AddProgramSheet()
            }
            .sheet(item: $editingProgram) { program in
                EditProgramSheet(program: program)
            }
        }
    }

    @ViewBuilder
    private var activeProgramCard: some View {
        Section {
            if let active = appState.activeProgram {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "#30d158"))
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Program")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#30d158"))
                        Text(active.name)
                            .font(.headline)
                    }
                    Spacer()
                    if let routine = appState.todaysSuggestedRoutine() {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Today")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(routine.name)
                                .font(.caption.bold())
                                .foregroundColor(Color(hex: "#30d158"))
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color(hex: "#30d158").opacity(0.1))
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "circle.dashed")
                        .foregroundColor(.secondary)
                        .font(.title2)
                    Text("No active program")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var programsSection: some View {
        if !appState.programs.isEmpty {
            Section("My Programs") {
                ForEach(appState.programs) { program in
                    ProgramRow(program: program) {
                        HapticManager.selection()
                        editingProgram = program
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if program.isActive {
                            Button {
                                HapticManager.impact()
                                appState.setActiveProgram(id: nil)
                            } label: {
                                Label("Deactivate", systemImage: "stop.circle")
                            }
                            .tint(.orange)
                        } else {
                            Button {
                                HapticManager.success()
                                appState.setActiveProgram(id: program.id)
                            } label: {
                                Label("Set Active", systemImage: "checkmark.circle")
                            }
                            .tint(Color(hex: "#30d158"))
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            appState.deleteProgram(id: program.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }

        Section {
            Button {
                HapticManager.impact(.medium)
                showAddProgram = true
            } label: {
                Label("New Program", systemImage: "plus")
                    .foregroundColor(Color(hex: "#30d158"))
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}

// MARK: - Program Row

private struct ProgramRow: View {
    let program: WorkoutProgram
    let onTap: () -> Void

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(program.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if program.isActive {
                        Text("Active")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: "#30d158").opacity(0.18))
                            .foregroundColor(Color(hex: "#30d158"))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color(.tertiaryLabel))
                }

                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { weekday in
                        let hasRoutine = program.days.first(where: { $0.weekday == weekday })?.routineId != nil
                        VStack(spacing: 3) {
                            Text(weekdays[weekday - 1])
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(hasRoutine ? Color(hex: "#30d158") : .secondary)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(hasRoutine ? Color(hex: "#30d158") : Color(.systemFill))
                                .frame(width: 28, height: 20)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Program Sheet

struct AddProgramSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var draftDays: [DraftProgramDay] = (1...7).map { DraftProgramDay(weekday: $0) }
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. 5-Day Split", text: $name)
                        .focused($isNameFocused)
                }

                Section("Weekly Schedule") {
                    ForEach($draftDays) { $day in
                        DayScheduleRow(day: $day, routines: appState.routines)
                    }
                }
            }
            .navigationTitle("New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let days = draftDays.compactMap { $0.toProgramDay() }
                        appState.addProgram(name: trimmed, days: days)
                        HapticManager.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}

// MARK: - Edit Program Sheet

struct EditProgramSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let program: WorkoutProgram
    @State private var name: String
    @State private var draftDays: [DraftProgramDay]

    init(program: WorkoutProgram) {
        self.program = program
        _name = State(initialValue: program.name)
        _draftDays = State(initialValue: (1...7).map { weekday in
            let existing = program.days.first(where: { $0.weekday == weekday })
            return DraftProgramDay(weekday: weekday, routineId: existing?.routineId)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Program name", text: $name)
                }

                Section("Weekly Schedule") {
                    ForEach($draftDays) { $day in
                        DayScheduleRow(day: $day, routines: appState.routines)
                    }
                }

                Section {
                    if program.isActive {
                        Button {
                            HapticManager.impact()
                            appState.setActiveProgram(id: nil)
                            dismiss()
                        } label: {
                            Label("Deactivate Program", systemImage: "stop.circle")
                                .foregroundColor(.orange)
                        }
                    } else {
                        Button {
                            HapticManager.success()
                            appState.setActiveProgram(id: program.id)
                            dismiss()
                        } label: {
                            Label("Set as Active", systemImage: "checkmark.circle")
                                .foregroundColor(Color(hex: "#30d158"))
                        }
                    }
                }
            }
            .navigationTitle("Edit Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let days = draftDays.compactMap { $0.toProgramDay() }
                        appState.updateProgram(id: program.id, name: trimmed, days: days)
                        HapticManager.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Day Schedule Row

private struct DayScheduleRow: View {
    @Binding var day: DraftProgramDay
    let routines: [Routine]

    private let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        HStack {
            Text(weekdayNames[day.weekday - 1])
                .font(.subheadline)
                .frame(width: 96, alignment: .leading)
            Spacer()
            Picker("", selection: $day.routineId) {
                Text("Rest").tag(Optional<String>.none)
                ForEach(routines) { routine in
                    Text(routine.name).tag(Optional(routine.id))
                }
            }
            .pickerStyle(.menu)
            .tint(day.routineId != nil ? Color(hex: "#30d158") : .secondary)
        }
    }
}

// MARK: - Draft Program Day

struct DraftProgramDay: Identifiable {
    let id = UUID()
    var weekday: Int
    var routineId: String? = nil

    func toProgramDay() -> ProgramDay? {
        guard routineId != nil else { return nil }
        return ProgramDay(id: UUID().uuidString, weekday: weekday, routineId: routineId)
    }
}
