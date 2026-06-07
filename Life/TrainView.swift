import SwiftUI
import Charts

// MARK: - TrainView

struct TrainView: View {

    @Environment(AppState.self) private var appState
    @State private var showActiveWorkout = false
    @State private var showExerciseLibrary = false
    @State private var showAddRoutine = false
    @State private var showBrowsePrograms = false
    @State private var showAchievements = false
    @State private var showPrograms = false
    @State private var pulseResume = false

    private var finishedSessions: [WorkoutSession] {
        appState.sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Weekly strip
                    WeeklyCalendarStrip()
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    // Muscle recovery
                    MuscleRecoverySection()

                    // Resume active workout
                    if let active = appState.activeSession {
                        ResumeCard(session: active, pulse: pulseResume) {
                            showActiveWorkout = true
                        }
                        .padding(.horizontal, 16)
                        .onAppear { pulseResume = true }
                    }

                    // Today's suggested
                    if let suggested = appState.todaysSuggestedRoutine() {
                        TodayRoutineCard(routine: suggested) {
                            appState.startSession(name: suggested.name, routineId: suggested.id)
                            showActiveWorkout = true
                        }
                        .padding(.horizontal, 16)
                    }

                    // Routines section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("MY ROUTINES")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 14) {
                                Button { showBrowsePrograms = true } label: {
                                    Image(systemName: "square.grid.2x2")
                                        .foregroundColor(Color(hex: "#30d158"))
                                }
                                Button { showPrograms = true } label: {
                                    Image(systemName: "calendar")
                                        .foregroundColor(Color(hex: "#30d158"))
                                }
                                Button { showAddRoutine = true } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(Color(hex: "#30d158"))
                                        .font(.system(size: 20))
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        // Quick Start
                        QuickStartCard {
                            appState.startSession(name: "Quick Workout")
                            showActiveWorkout = true
                        }
                        .padding(.horizontal, 16)

                        if appState.routines.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "dumbbell")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("No routines yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Button {
                                    showAddRoutine = true
                                } label: {
                                    Text("Create your first routine")
                                        .font(.subheadline.bold())
                                        .foregroundColor(Color(hex: "#30d158"))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        } else {
                            ForEach(appState.routines) { routine in
                                RoutineCard(routine: routine) {
                                    appState.startSession(name: routine.name, routineId: routine.id)
                                    showActiveWorkout = true
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // Weekly chart
                    if !appState.sessions.filter({ $0.finishedAt != nil }).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LAST 8 WEEKS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                            WeeklyConsistencyChart()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(14)
                                .padding(.horizontal, 16)
                        }
                    }

                    // History
                    if !finishedSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HISTORY")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)

                            ForEach(finishedSessions.prefix(10)) { session in
                                NavigationLink {
                                    SessionDetailView(session: session)
                                } label: {
                                    SessionHistoryCard(session: session)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showAchievements = true } label: {
                        Image(systemName: "trophy.fill").foregroundColor(.yellow)
                    }
                    Button { showExerciseLibrary = true } label: {
                        Image(systemName: "books.vertical")
                    }
                }
            }
            .fullScreenCover(isPresented: $showActiveWorkout) {
                if let session = appState.activeSession {
                    ActiveWorkoutView(isPresented: $showActiveWorkout, sessionId: session.id)
                }
            }
            .sheet(isPresented: $showExerciseLibrary) { ExerciseLibraryView() }
            .sheet(isPresented: $showAddRoutine) { AddRoutineSheet() }
            .sheet(isPresented: $showBrowsePrograms) { BrowseProgramsSheet() }
            .sheet(isPresented: $showAchievements) { AchievementsView() }
            .sheet(isPresented: $showPrograms) { ProgramsView() }
        }
    }
}

// MARK: - Resume Card

private struct ResumeCard: View {
    let session: WorkoutSession
    let pulse: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#30d158").opacity(pulse ? 0.25 : 0.12))
                        .frame(width: 44, height: 44)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                    Image(systemName: "play.fill")
                        .foregroundColor(Color(hex: "#30d158"))
                        .font(.system(size: 16))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Resume Workout")
                        .font(.headline)
                    Text(session.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color(hex: "#30d158"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(16)
            .background(Color(hex: "#30d158").opacity(0.1))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#30d158").opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Today Routine Card

private struct TodayRoutineCard: View {
    let routine: Routine
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Today's Workout", systemImage: "calendar.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(hex: "#30d158"))
                Text(routine.name)
                    .font(.headline)
                Text("\(routine.exercises.count) exercises")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onStart) {
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "#30d158"))
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}

// MARK: - Quick Start Card

private struct QuickStartCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#30d158"))
                Text("Quick Start")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: "#30d158").opacity(0.7))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Routine Card

private struct RoutineCard: View {
    @Environment(AppState.self) private var appState
    let routine: Routine
    let onStart: () -> Void

    @State private var expanded = false
    @State private var showEdit = false

    private var muscleGroups: [String] {
        Array(Set(routine.exercises.compactMap { re in
            appState.exercises.first(where: { $0.id == re.exerciseId })?.muscle
        })).sorted()
    }

    private var totalSets: Int {
        routine.exercises.reduce(0) { $0 + $1.defaultSets }
    }

    private var estimatedMinutes: Int {
        max(10, totalSets * 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 14) {
                // Muscle colour stack
                VStack(spacing: -4) {
                    ForEach(muscleGroups.prefix(3), id: \.self) { muscle in
                        Circle()
                            .fill(muscle.muscleColor)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                    }
                    if muscleGroups.count > 3 {
                        Text("+\(muscleGroups.count - 3)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    // Muscle tags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(muscleGroups, id: \.self) { muscle in
                                Text(muscle)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(muscle.muscleColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(muscle.muscleColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .frame(height: 22)

                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell").font(.caption2)
                        Text("\(routine.exercises.count) ex")
                        Text("·")
                        Image(systemName: "square.stack").font(.caption2)
                        Text("\(totalSets) sets")
                        Text("·")
                        Image(systemName: "clock").font(.caption2)
                        Text("~\(estimatedMinutes)m")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    HapticManager.impact(.medium)
                    onStart()
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color(hex: "#30d158"))
                        .clipShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35)) { expanded.toggle() }
                HapticManager.selection()
            }

            // Expanded exercise list
            if expanded {
                Divider().padding(.horizontal, 14)
                VStack(spacing: 0) {
                    ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { idx, re in
                        if let ex = appState.exercises.first(where: { $0.id == re.exerciseId }) {
                            HStack(spacing: 10) {
                                Circle().fill(ex.muscle.muscleColor).frame(width: 7, height: 7)
                                Text(ex.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(re.defaultSets)×\(re.defaultReps)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                if re.defaultWeight > 0 {
                                    Text("\(re.defaultWeight.formatted1)kg")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            if idx < routine.exercises.count - 1 {
                                Divider().padding(.leading, 30)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .contextMenu {
            Button { showEdit = true } label: {
                Label("Edit Routine", systemImage: "pencil")
            }
            Button(role: .destructive) {
                appState.deleteRoutine(id: routine.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEdit) {
            EditRoutineSheet(routine: routine)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                appState.deleteRoutine(id: routine.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Session History Card

private struct SessionHistoryCard: View {
    @Environment(AppState.self) private var appState
    let session: WorkoutSession

    private var muscles: [String] {
        Array(Set(session.exercises.compactMap { se in
            appState.exercises.first(where: { $0.id == se.exerciseId })?.muscle
        })).sorted()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: -4) {
                ForEach(muscles.prefix(3), id: \.self) { m in
                    Circle()
                        .fill(m.muscleColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                HStack(spacing: 10) {
                    if let finished = session.finishedAt {
                        Label(finished.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    Label(session.durationSeconds.formattedDurationShort, systemImage: "clock")
                    Label("\(session.exercises.count) ex", systemImage: "dumbbell")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if session.totalVolumeKg > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(session.totalVolumeKg))")
                        .font(.subheadline.bold().monospacedDigit())
                    Text("kg vol")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}

// MARK: - Add Routine Sheet

struct AddRoutineSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var exercises: [DraftRoutineExercise] = []
    @State private var showExercisePicker = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Push A, Leg Day", text: $name)
                        .focused($isNameFocused)
                }
                Section {
                    ForEach($exercises) { $ex in
                        DraftExerciseRow(draft: $ex, allExercises: appState.exercises)
                    }
                    .onDelete { offsets in exercises.remove(atOffsets: offsets) }
                    .onMove { from, to in exercises.move(fromOffsets: from, toOffset: to) }

                    Button {
                        showExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .foregroundColor(Color(hex: "#30d158"))
                    }
                } header: {
                    Text("Exercises")
                }
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let routineExercises = exercises.map { d in
                            RoutineExercise(exerciseId: d.exerciseId, defaultSets: d.sets,
                                           defaultReps: d.reps, defaultWeight: d.weight)
                        }
                        appState.addRoutine(name: trimmed, exercises: routineExercises)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
            }
            .onAppear { isNameFocused = true }
            .sheet(isPresented: $showExercisePicker) {
                ExerciseSelectSheet { exerciseId in
                    if !exercises.contains(where: { $0.exerciseId == exerciseId }) {
                        exercises.append(DraftRoutineExercise(exerciseId: exerciseId))
                    }
                }
            }
        }
    }
}

// MARK: - Edit Routine Sheet

struct EditRoutineSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let routine: Routine
    @State private var name: String
    @State private var exercises: [DraftRoutineExercise]
    @State private var showExercisePicker = false

    init(routine: Routine) {
        self.routine = routine
        _name = State(initialValue: routine.name)
        _exercises = State(initialValue: routine.exercises.map { re in
            DraftRoutineExercise(exerciseId: re.exerciseId, sets: re.defaultSets,
                                 reps: re.defaultReps, weight: re.defaultWeight)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Routine name", text: $name)
                }
                Section {
                    ForEach($exercises) { $ex in
                        DraftExerciseRow(draft: $ex, allExercises: appState.exercises)
                    }
                    .onDelete { offsets in exercises.remove(atOffsets: offsets) }
                    .onMove { from, to in exercises.move(fromOffsets: from, toOffset: to) }

                    Button {
                        showExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .foregroundColor(Color(hex: "#30d158"))
                    }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        EditButton().font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let routineExercises = exercises.map { d in
                            RoutineExercise(exerciseId: d.exerciseId, defaultSets: d.sets,
                                           defaultReps: d.reps, defaultWeight: d.weight)
                        }
                        appState.updateRoutine(id: routine.id, name: trimmed, exercises: routineExercises)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExerciseSelectSheet { exerciseId in
                    if !exercises.contains(where: { $0.exerciseId == exerciseId }) {
                        exercises.append(DraftRoutineExercise(exerciseId: exerciseId))
                    }
                }
            }
        }
    }
}

// MARK: - Draft Routine Exercise helpers

struct DraftRoutineExercise: Identifiable {
    let id = UUID()
    var exerciseId: String
    var sets: Int = 3
    var reps: Int = 10
    var weight: Double = 0
}

private struct DraftExerciseRow: View {
    @Binding var draft: DraftRoutineExercise
    let allExercises: [Exercise]

    private var exercise: Exercise? { allExercises.first { $0.id == draft.exerciseId } }

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var setsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let ex = exercise {
                    Circle().fill(ex.muscle.muscleColor).frame(width: 8, height: 8)
                    Text(ex.name).font(.subheadline.bold())
                } else {
                    Text("Unknown exercise").font(.subheadline).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    TextField("3", text: $setsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: setsText) { _, v in if let n = Int(v) { draft.sets = max(1, n) } }
                    Text("sets").font(.caption2).foregroundColor(.secondary)
                }
                VStack(spacing: 2) {
                    TextField("10", text: $repsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: repsText) { _, v in if let n = Int(v) { draft.reps = max(1, n) } }
                    Text("reps").font(.caption2).foregroundColor(.secondary)
                }
                if exercise?.kind == .weight {
                    VStack(spacing: 2) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: weightText) { _, v in if let n = Double(v) { draft.weight = n } }
                        Text("kg").font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            setsText = "\(draft.sets)"
            repsText = "\(draft.reps)"
            weightText = draft.weight == 0 ? "" : draft.weight.formatted1
        }
    }
}

// MARK: - Exercise Select Sheet

struct ExerciseSelectSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedMuscle: String? = nil

    private let muscleOrder = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Legs", "Core", "Other"]

    private var availableMuscles: [String] {
        muscleOrder.filter { m in appState.exercises.contains { $0.muscle == m } }
    }

    private var filtered: [Exercise] {
        appState.exercises.filter { ex in
            let matchesMuscle = selectedMuscle == nil || ex.muscle == selectedMuscle
            let matchesSearch = searchText.isEmpty ||
                ex.name.localizedCaseInsensitiveContains(searchText) ||
                ex.muscle.localizedCaseInsensitiveContains(searchText)
            return matchesMuscle && matchesSearch
        }
        .sorted { $0.name < $1.name }
    }

    private var grouped: [(String, [Exercise])] {
        if selectedMuscle != nil {
            return [(selectedMuscle!, filtered)]
        }
        return availableMuscles.compactMap { muscle in
            let exs = filtered.filter { $0.muscle == muscle }
            return exs.isEmpty ? nil : (muscle, exs)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Muscle filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChipSmall(label: "All", isSelected: selectedMuscle == nil) {
                            selectedMuscle = nil
                        }
                        ForEach(availableMuscles, id: \.self) { muscle in
                            FilterChipSmall(label: muscle, isSelected: selectedMuscle == muscle, color: muscle.muscleColor) {
                                selectedMuscle = selectedMuscle == muscle ? nil : muscle
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))

                List {
                    ForEach(grouped, id: \.0) { muscle, exs in
                        Section(muscle) {
                            ForEach(exs) { ex in
                                Button {
                                    onSelect(ex.id)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Circle().fill(muscle.muscleColor).frame(width: 8, height: 8)
                                        Text(ex.name).foregroundColor(.primary)
                                        Spacer()
                                        Text(ex.equipment.label).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Filter Chip Small

private struct FilterChipSmall: View {
    let label: String
    let isSelected: Bool
    var color: Color = Color(hex: "#30d158")
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                .foregroundColor(isSelected ? color : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    let session: WorkoutSession

    var body: some View {
        List {
            SessionSummarySection(session: session)
            ForEach(session.exercises) { ex in
                SessionExerciseSection(ex: ex)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct SessionSummarySection: View {
    let session: WorkoutSession
    var body: some View {
        Section {
            InfoRow(label: "Date", value: session.finishedAt.map { $0.formatted(date: .long, time: .shortened) } ?? "In progress")
            InfoRow(label: "Duration", value: session.durationSeconds.formattedDurationShort)
            InfoRow(label: "Sets completed", value: "\(session.totalSets)")
            InfoRow(label: "Volume", value: session.totalVolumeKg > 0 ? "\(Int(session.totalVolumeKg)) kg" : "—")
        } header: { Text("Summary") }
    }
}

private struct SessionExerciseSection: View {
    @Environment(AppState.self) private var appState
    let ex: SessionExercise
    var body: some View {
        if let exercise = appState.exercises.first(where: { $0.id == ex.exerciseId }) {
            Section {
                ForEach(Array(ex.sets.enumerated()), id: \.element.id) { idx, set in
                    SessionSetRow(set: set, index: idx, kind: exercise.kind)
                }
            } header: {
                HStack {
                    Circle().fill(exercise.muscle.muscleColor).frame(width: 8, height: 8)
                    Text(exercise.name)
                }
            }
        }
    }
}

private struct SessionSetRow: View {
    let set: LoggedSet
    let index: Int
    let kind: ExerciseKind
    var body: some View {
        HStack {
            Group {
                if set.isWarmup { Text("W").font(.caption.bold()).foregroundColor(.orange) }
                else if set.isDropSet { Text("↓").font(.caption.bold()).foregroundColor(.purple) }
                else { Text("\(index + 1)").font(.caption).foregroundColor(.secondary) }
            }
            .frame(width: 20)
            if kind == .cardio {
                Text(set.durationSec > 0 ? "\(set.durationSec / 60):\(String(format: "%02d", set.durationSec % 60))" : "—")
                if set.distanceKm > 0 { Text("· \(set.distanceKm.formatted1) km").foregroundColor(.secondary) }
            } else {
                Text(set.weight > 0 ? "\(set.weight.formatted1) kg" : "BW")
                Text("×")
                Text(set.reps > 0 ? "\(set.reps)" : "—")
            }
            Spacer()
            if set.done { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption) }
        }
        .font(.subheadline)
    }
}

// MARK: - Weekly Calendar Strip

private struct WeeklyCalendarStrip: View {
    @Environment(AppState.self) private var appState

    private var weekDays: [(date: Date, label: String, dayNum: String)] {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let shortDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            return (date: date, label: shortDays[offset], dayNum: "\(cal.component(.day, from: date))")
        }
    }

    private var sessionDays: Set<Date> {
        let cal = Calendar.current
        return Set(appState.sessionsThisWeek().keys.map { cal.startOfDay(for: $0) })
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.dayNum) { entry in
                let isToday = Calendar.current.isDateInToday(entry.date)
                let hasSession = sessionDays.contains(Calendar.current.startOfDay(for: entry.date))
                VStack(spacing: 6) {
                    Text(entry.label).font(.caption2).foregroundColor(.secondary)
                    ZStack {
                        Circle()
                            .fill(hasSession ? Color(hex: "#30d158") : Color(.systemFill))
                            .frame(width: 32, height: 32)
                        if isToday && !hasSession {
                            Circle().stroke(Color(hex: "#30d158"), lineWidth: 2).frame(width: 32, height: 32)
                        }
                        Text(entry.dayNum)
                            .font(.caption.bold())
                            .foregroundColor(hasSession ? .white : (isToday ? Color(hex: "#30d158") : .primary))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}

// MARK: - Muscle Recovery Section

private struct MuscleRecoverySection: View {
    @Environment(AppState.self) private var appState

    private var muscles: [String] {
        Array(Set(appState.exercises.filter { $0.kind != .cardio }.map(\.muscle))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MUSCLE RECOVERY")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(muscles, id: \.self) { muscle in
                        let status = appState.recoveryStatus(muscle: muscle)
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(status.color.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Circle()
                                    .stroke(status.color, lineWidth: 2)
                                    .frame(width: 48, height: 48)
                                Text(String(muscle.prefix(2)))
                                    .font(.caption2.bold())
                                    .foregroundColor(status.color)
                            }
                            Text(muscle)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 56)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            HStack(spacing: 14) {
                ForEach([AppState.RecoveryStatus.fatigued, .recovering, .recovered, .fresh], id: \.label) { s in
                    HStack(spacing: 4) {
                        Circle().fill(s.color).frame(width: 7, height: 7)
                        Text(s.label).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Weekly Consistency Chart

private struct WeeklyConsistencyChart: View {
    @Environment(AppState.self) private var appState

    private var data: [(weekLabel: String, count: Int)] { appState.weeklyWorkoutCounts(weeks: 8) }

    var body: some View {
        Chart {
            ForEach(data.indices, id: \.self) { i in
                BarMark(
                    x: .value("Week", data[i].weekLabel),
                    y: .value("Sessions", data[i].count)
                )
                .foregroundStyle(Color(hex: "#30d158").gradient)
                .cornerRadius(4)
            }
        }
        .frame(height: 110)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let s = value.as(String.self) {
                        Text(s.components(separatedBy: " ").last ?? s).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .stride(by: 1)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)").font(.caption2) }
                }
            }
        }
    }
}

// MARK: - Browse Programs Sheet

struct BrowseProgramsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmProgram: WorkoutSeed.WorkoutProgram? = nil

    private let programs = WorkoutSeed.programTemplates

    var body: some View {
        NavigationStack {
            List(programs) { program in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: program.icon)
                                .font(.title2)
                                .foregroundColor(Color(hex: "#30d158"))
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(program.name).font(.headline)
                                Text(program.description)
                                    .font(.caption).foregroundColor(.secondary).lineLimit(2)
                            }
                        }
                        HStack(spacing: 12) {
                            Label("\(program.daysPerWeek)×/week", systemImage: "calendar")
                            Label(program.difficulty, systemImage: "chart.bar")
                            Label("\(program.routines.count) routines", systemImage: "list.bullet")
                        }
                        .font(.caption2).foregroundColor(.secondary)

                        Button {
                            confirmProgram = program
                        } label: {
                            Text("Add Program")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color(hex: "#30d158"))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Browse Programs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .alert("Add Program?", isPresented: Binding(
                get: { confirmProgram != nil },
                set: { if !$0 { confirmProgram = nil } }
            )) {
                Button("Add Routines") {
                    if let prog = confirmProgram {
                        for routine in prog.routines {
                            appState.addRoutine(name: routine.name, exercises: routine.exercises)
                        }
                        HapticManager.success()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { confirmProgram = nil }
            } message: {
                if let prog = confirmProgram {
                    Text("Add \(prog.routines.count) routines from \"\(prog.name)\" to your routines list?")
                }
            }
        }
    }
}
