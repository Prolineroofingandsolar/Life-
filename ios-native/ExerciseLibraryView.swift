import SwiftUI

// MARK: - Exercise Library View

struct ExerciseLibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedMuscle: String? = nil
    @State private var showFilterSheet = false
    @State private var showAddExercise = false
    @State private var selectedExercise: Exercise? = nil

    // Filter state
    @State private var filterEquipment: Set<ExerciseEquipment> = []
    @State private var filterDifficulty: Int? = nil
    @State private var filterFavoritesOnly = false

    private let muscleOrder = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Legs", "Core", "Cardio", "Other"]

    private var availableMuscles: [String] {
        muscleOrder.filter { m in appState.exercises.contains { $0.muscle == m } }
    }

    private var activeFilterCount: Int {
        (filterEquipment.isEmpty ? 0 : 1) + (filterDifficulty == nil ? 0 : 1) + (filterFavoritesOnly ? 1 : 0)
    }

    private var popularExercises: [Exercise] {
        var counts: [String: Int] = [:]
        for session in appState.sessions where session.finishedAt != nil {
            for ex in session.exercises {
                counts[ex.exerciseId, default: 0] += ex.sets.filter(\.done).count
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { entry in appState.exercises.first { $0.id == entry.key } }
    }

    private var filteredExercises: [Exercise] {
        var list = appState.exercises
        if let m = selectedMuscle { list = list.filter { $0.muscle == m } }
        if !searchText.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.muscle.localizedCaseInsensitiveContains(searchText)
            }
        }
        if !filterEquipment.isEmpty { list = list.filter { filterEquipment.contains($0.equipment) } }
        if let diff = filterDifficulty { list = list.filter { $0.difficulty == diff } }
        if filterFavoritesOnly { list = list.filter(\.isFavorite) }
        return list.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Search + filter row
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search exercises…", text: $searchText)
                                .autocorrectionDisabled()
                        }
                        .padding(10)
                        .background(Color(.secondarySystemFill))
                        .cornerRadius(10)

                        Button {
                            showFilterSheet = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                                    .padding(10)
                                    .background(Color(.secondarySystemFill))
                                    .cornerRadius(10)
                                if activeFilterCount > 0 {
                                    Circle()
                                        .fill(Color(hex: "#30d158"))
                                        .frame(width: 16, height: 16)
                                        .overlay(Text("\(activeFilterCount)").font(.system(size: 10, weight: .bold)).foregroundColor(.black))
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                    // Muscle chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            MuscleChip(label: "All", isSelected: selectedMuscle == nil, recovery: nil) {
                                withAnimation(.spring(response: 0.3)) { selectedMuscle = nil }
                            }
                            ForEach(availableMuscles, id: \.self) { muscle in
                                let recovery = appState.recoveryStatus(muscle: muscle)
                                MuscleChip(label: muscle, isSelected: selectedMuscle == muscle, recovery: recovery) {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedMuscle = selectedMuscle == muscle ? nil : muscle
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 16)

                    // Popular section (only when unfiltered, unsearched)
                    if searchText.isEmpty && selectedMuscle == nil && activeFilterCount == 0 && !popularExercises.isEmpty {
                        LibrarySectionHeader(title: "Popular")
                        ForEach(popularExercises) { ex in
                            ExerciseCard(exercise: ex) { selectedExercise = ex }
                        }
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }

                    // Main list
                    let title = selectedMuscle ?? (searchText.isEmpty ? "All Exercises" : "Results")
                    LibrarySectionHeader(title: title, count: filteredExercises.count)
                    if filteredExercises.isEmpty {
                        ContentUnavailableView("No Exercises Found", systemImage: "dumbbell",
                            description: Text("Try changing your filters or search term."))
                            .padding(.top, 40)
                    } else {
                        ForEach(filteredExercises) { ex in
                            ExerciseCard(exercise: ex) { selectedExercise = ex }
                        }
                    }

                    Color.clear.frame(height: 20)
                }
            }
            .background(Color(.systemGroupedBackground))
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
            .sheet(isPresented: $showFilterSheet) {
                LibraryFilterSheet(
                    selectedEquipment: $filterEquipment,
                    selectedDifficulty: $filterDifficulty,
                    favoritesOnly: $filterFavoritesOnly
                )
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseSheet()
            }
            .sheet(item: $selectedExercise) { ex in
                ExerciseDetailSheet(exerciseId: ex.id)
            }
        }
    }
}

// MARK: - Library Section Header

private struct LibrarySectionHeader: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            if let count = count {
                Text("(\(count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Muscle Chip

private struct MuscleChip: View {
    let label: String
    let isSelected: Bool
    let recovery: AppState.RecoveryStatus?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let r = recovery, !isSelected {
                    Circle()
                        .fill(r.color)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? Color(hex: "#30d158") : Color(.secondarySystemFill))
            .foregroundColor(isSelected ? .black : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Exercise Card

private struct ExerciseCard: View {
    @Environment(AppState.self) private var appState
    let exercise: Exercise
    let onTap: () -> Void

    private var pr: AppState.PRResult { appState.computePRs(for: exercise.id) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Equipment icon thumb
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(width: 56, height: 56)
                    Image(systemName: exercise.equipment.icon)
                        .font(.system(size: 22))
                        .foregroundColor(exercise.muscle.muscleColor)
                    // PR badge
                    if pr.bestWeight > 0 {
                        VStack {
                            Spacer()
                            HStack {
                                Text("\(Int(pr.bestWeight))kg")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "#30d158"))
                                    .cornerRadius(4)
                                Spacer()
                            }
                        }
                        .frame(width: 56, height: 56)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(exercise.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if exercise.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }

                    Text(exercise.muscle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(exercise.muscle.muscleColor)

                    HStack(spacing: 6) {
                        Text(exercise.movementType.label)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        HStack(spacing: 3) {
                            ForEach(1...3, id: \.self) { level in
                                Circle()
                                    .fill(level <= exercise.difficulty ? exercise.muscle.muscleColor : Color(.systemFill))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                }

                Spacer()

                // Body diagram + chevron
                VStack(spacing: 4) {
                    BodyDiagramView(muscle: exercise.muscle, size: 28)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Library Filter Sheet

private struct LibraryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEquipment: Set<ExerciseEquipment>
    @Binding var selectedDifficulty: Int?
    @Binding var favoritesOnly: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Equipment") {
                    ForEach(ExerciseEquipment.allCases) { eq in
                        Toggle(isOn: Binding(
                            get: { selectedEquipment.contains(eq) },
                            set: { on in
                                if on { selectedEquipment.insert(eq) }
                                else { selectedEquipment.remove(eq) }
                            }
                        )) {
                            Label(eq.label, systemImage: eq.icon)
                        }
                    }
                }

                Section("Difficulty") {
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        Text("Any").tag(Optional<Int>.none)
                        Text("Beginner").tag(Optional<Int>.some(1))
                        Text("Intermediate").tag(Optional<Int>.some(2))
                        Text("Advanced").tag(Optional<Int>.some(3))
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Toggle("Favourites Only", isOn: $favoritesOnly)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        selectedEquipment = []
                        selectedDifficulty = nil
                        favoritesOnly = false
                    }
                    .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { dismiss() }
                        .foregroundColor(Color(hex: "#30d158"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscle = "Chest"
    @State private var kind: ExerciseKind = .weight
    @State private var equipment: ExerciseEquipment = .barbell
    @State private var movementType: MovementType = .compound
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
                    Picker("Equipment", selection: $equipment) {
                        ForEach(ExerciseEquipment.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Movement", selection: $movementType) {
                        ForEach(MovementType.allCases) { Text($0.label).tag($0) }
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
                        appState.addCustomExercise(name: n, muscle: muscle, kind: kind,
                                                   equipment: equipment, movementType: movementType)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }
}
