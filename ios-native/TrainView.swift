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

                // Quick start
                Section("Start Workout") {
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
                    }

                    Button {
                        showAddRoutine = true
                    } label: {
                        Label("New Routine", systemImage: "plus")
                            .foregroundColor(.secondary)
                    }
                }

                // History
                if !finishedSessions.isEmpty {
                    Section("History") {
                        ForEach(finishedSessions) { session in
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
                    ActiveWorkoutView(sessionId: session.id, isPresented: $showActiveWorkout)
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

    private var exerciseNames: String {
        routine.exercises.prefix(3)
            .compactMap { re in appState.exercises.first(where: { $0.id == re.exerciseId })?.name }
            .joined(separator: ", ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.headline)
                if !exerciseNames.isEmpty {
                    Text(exerciseNames + (routine.exercises.count > 3 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text("\(routine.exercises.count) exercises")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onStart) {
                Image(systemName: "play.fill")
                    .foregroundColor(Color(hex: "#30d158"))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
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

// MARK: - Session Detail View (read-only)

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    let session: WorkoutSession

    var body: some View {
        List {
            Section("Info") {
                if let finished = session.finishedAt {
                    LabeledContent("Date", value: finished.formatted(date: .long, time: .shortened))
                }
                LabeledContent("Duration", value: session.durationSeconds.formattedDurationShort)
                LabeledContent("Sets completed", value: "\(session.totalSets)")
            }

            ForEach(session.exercises) { ex in
                if let exercise = appState.exercises.first(where: { $0.id == ex.exerciseId }) {
                    Section(exercise.name) {
                        ForEach(ex.sets) { set in
                            HStack {
                                if set.isWarmup {
                                    Text("W")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                        .frame(width: 20)
                                } else {
                                    Text("\(ex.sets.firstIndex(where: { $0.id == set.id }).map { $0 + 1 } ?? 0)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                }

                                if exercise.kind == .cardio {
                                    Text("\(set.durationSec.formattedDuration)")
                                    if set.distanceKm > 0 {
                                        Text("· \(set.distanceKm.formatted1) km")
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("\(set.weight.formatted1) kg × \(set.reps)")
                                }

                                Spacer()

                                if set.done {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.large)
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

    private var groupedExercises: [(String, [Exercise])] {
        muscles.compactMap { muscle in
            let exercises = filtered.filter { $0.muscle == muscle }
            return exercises.isEmpty ? nil : (muscle, exercises)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedExercises, id: \.0) { muscle, exercises in
                    Section {
                        ForEach(exercises) { exercise in
                            HStack {
                                Circle()
                                    .fill(muscle.muscleColor)
                                    .frame(width: 8, height: 8)
                                Text(exercise.name)
                                Spacer()
                                Text(exercise.kind.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if exercise.isCustom {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundColor(.yellow)
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
                    Button {
                        showAddExercise = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
                    TextField("Name", text: $name)
                        .focused($isNameFocused)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        appState.addCustomExercise(name: name.trimmingCharacters(in: .whitespaces), muscle: muscle, kind: kind)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}

// MARK: - Add Routine Sheet

struct AddRoutineSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Routine name (e.g. Push A)", text: $name)
                        .focused($isNameFocused)
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
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        appState.addRoutine(name: name.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}
