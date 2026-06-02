import SwiftUI

// MARK: - TrainView

struct TrainView: View {

    @Environment(AppState.self) private var appState
    @State private var showActiveWorkout = false
    @State private var showExerciseLibrary = false
    @State private var showAddRoutine = false

    private var finishedSessions: [WorkoutSession] {
        appState.sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Active session banner
                if let active = appState.activeSession {
                    Section {
                        Button {
                            showActiveWorkout = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Resume Workout")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(active.name)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(Color(hex: "#30d158"))
                            }
                        }
                        .listRowBackground(Color(hex: "#30d158").opacity(0.12))
                    }
                }

                // Routines
                Section {
                    Button {
                        appState.startSession(name: "Quick Workout")
                        showActiveWorkout = true
                    } label: {
                        Label("Quick Start", systemImage: "bolt.fill")
                            .font(.headline)
                            .foregroundColor(Color(hex: "#30d158"))
                    }

                    ForEach(appState.routines) { routine in
                        RoutineRow(routine: routine) {
                            appState.startSession(name: routine.name, routineId: routine.id)
                            showActiveWorkout = true
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                appState.deleteRoutine(id: routine.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showAddRoutine = true
                    } label: {
                        Label("New Routine", systemImage: "plus")
                            .foregroundColor(Color(hex: "#30d158"))
                    }
                } header: {
                    Text("Routines")
                }

                // History
                if !finishedSessions.isEmpty {
                    Section("History") {
                        ForEach(finishedSessions.prefix(20)) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionHistoryRow(session: session)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showExerciseLibrary = true
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                }
            }
            .fullScreenCover(isPresented: $showActiveWorkout) {
                if let session = appState.activeSession {
                    ActiveWorkoutView(isPresented: $showActiveWorkout, sessionId: session.id)
                }
            }
            .sheet(isPresented: $showExerciseLibrary) {
                ExerciseLibraryView()
            }
            .sheet(isPresented: $showAddRoutine) {
                AddRoutineSheet()
            }
        }
    }
}

// MARK: - Routine Row

private struct RoutineRow: View {
    @Environment(AppState.self) private var appState
    let routine: Routine
    let onStart: () -> Void

    @State private var showEdit = false

    private var exerciseNames: String {
        routine.exercises.prefix(3)
            .compactMap { re in appState.exercises.first(where: { $0.id == re.exerciseId })?.name }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.headline)
                if !routine.exercises.isEmpty {
                    Text(exerciseNames + (routine.exercises.count > 3 ? " +\(routine.exercises.count - 3)" : ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text("\(routine.exercises.count) exercise\(routine.exercises.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            Spacer()
            Button {
                showEdit = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button(action: onStart) {
                Image(systemName: "play.fill")
                    .foregroundColor(Color(hex: "#30d158"))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showEdit) {
            EditRoutineSheet(routine: routine)
        }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let routineExercises = exercises.map { d in
                            RoutineExercise(
                                exerciseId: d.exerciseId,
                                defaultSets: d.sets,
                                defaultReps: d.reps,
                                defaultWeight: d.weight
                            )
                        }
                        appState.addRoutine(name: trimmed, exercises: routineExercises)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
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
            DraftRoutineExercise(
                exerciseId: re.exerciseId,
                sets: re.defaultSets,
                reps: re.defaultReps,
                weight: re.defaultWeight
            )
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
                        EditButton()
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let routineExercises = exercises.map { d in
                            RoutineExercise(
                                exerciseId: d.exerciseId,
                                defaultSets: d.sets,
                                defaultReps: d.reps,
                                defaultWeight: d.weight
                            )
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

    private var exercise: Exercise? {
        allExercises.first { $0.id == draft.exerciseId }
    }

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

// MARK: - Exercise Select Sheet (for picking an exercise to add to a routine)

struct ExerciseSelectSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    @State private var searchText = ""

    private var muscles: [String] {
        Array(Set(appState.exercises.map(\.muscle))).sorted()
    }

    private var filtered: [Exercise] {
        if searchText.isEmpty { return appState.exercises }
        return appState.exercises.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.muscle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var grouped: [(String, [Exercise])] {
        muscles.compactMap { muscle in
            let exs = filtered.filter { $0.muscle == muscle }
            return exs.isEmpty ? nil : (muscle, exs)
        }
    }

    var body: some View {
        NavigationStack {
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
                                    Text(ex.kind.label).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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

// MARK: - Session History Row

private struct SessionHistoryRow: View {
    @Environment(AppState.self) private var appState
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.name)
                .font(.headline)
            HStack(spacing: 12) {
                if let finished = session.finishedAt {
                    Label(finished.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                Label(session.durationSeconds.formattedDurationShort, systemImage: "clock")
                Label("\(session.exercises.count) exercises", systemImage: "dumbbell")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
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
        } header: {
            Text("Summary")
        }
    }
}

private struct SessionExerciseSection: View {
    @Environment(AppState.self) private var appState
    let ex: SessionExercise
    var body: some View {
        Group {
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
}

private struct SessionSetRow: View {
    let set: LoggedSet
    let index: Int
    let kind: ExerciseKind
    var body: some View {
        HStack {
            Group {
                if set.isWarmup {
                    Text("W").font(.caption.bold()).foregroundColor(.orange)
                } else {
                    Text("\(index + 1)").font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(width: 20)
            if kind == .cardio {
                Text(set.durationSec > 0 ? "\(set.durationSec / 60):\(String(format: "%02d", set.durationSec % 60))" : "—")
                if set.distanceKm > 0 {
                    Text("· \(set.distanceKm.formatted1) km").foregroundColor(.secondary)
                }
            } else {
                Text(set.weight > 0 ? "\(set.weight.formatted1) kg" : "BW")
                Text("×")
                Text(set.reps > 0 ? "\(set.reps)" : "—")
            }
            Spacer()
            if set.done {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Exercise Library View

struct ExerciseLibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddExercise = false
    @State private var searchText = ""

    private var muscles: [String] {
        Array(Set(appState.exercises.map(\.muscle))).sorted()
    }

    private var filtered: [Exercise] {
        if searchText.isEmpty { return appState.exercises }
        return appState.exercises.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.muscle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var grouped: [(String, [Exercise])] {
        muscles.compactMap { muscle in
            let exs = filtered.filter { $0.muscle == muscle }
            return exs.isEmpty ? nil : (muscle, exs)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.0) { muscle, exs in
                    Section {
                        ForEach(exs) { ex in
                            HStack {
                                Circle().fill(muscle.muscleColor).frame(width: 8, height: 8)
                                Text(ex.name)
                                Spacer()
                                Text(ex.kind.label).font(.caption).foregroundColor(.secondary)
                                if ex.isCustom {
                                    Image(systemName: "star.fill").font(.caption2).foregroundColor(.yellow)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Circle().fill(muscle.muscleColor).frame(width: 10, height: 10)
                            Text(muscle)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText)
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddExercise = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseSheet()
            }
        }
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscle = "Chest"
    @State private var kind: ExerciseKind = .weight
    @FocusState private var isNameFocused: Bool

    private let muscles = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Legs", "Core", "Cardio", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name).focused($isNameFocused)
                }
                Section("Details") {
                    Picker("Muscle Group", selection: $muscle) {
                        ForEach(muscles, id: \.self) { Text($0) }
                    }
                    Picker("Type", selection: $kind) {
                        ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        appState.addCustomExercise(name: n, muscle: muscle, kind: kind)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}
