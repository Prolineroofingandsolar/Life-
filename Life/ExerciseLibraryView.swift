import SwiftUI

// MARK: - Exercise Library View

struct ExerciseLibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var expandedMuscles: Set<String> = []
    @State private var showFilterSheet = false
    @State private var showAddExercise = false
    @State private var selectedExercise: Exercise? = nil

    // Filter state
    @State private var filterEquipment: Set<ExerciseEquipment> = []
    @State private var filterDifficulty: Int? = nil
    @State private var filterFavoritesOnly = false

    private let muscleOrder = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Legs", "Core", "Cardio", "Other"]

    private var activeFilterCount: Int {
        (filterEquipment.isEmpty ? 0 : 1) + (filterDifficulty == nil ? 0 : 1) + (filterFavoritesOnly ? 1 : 0)
    }

    private var filteredExercises: [Exercise] {
        var list = appState.exercises
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

    private var groupedExercises: [(muscle: String, exercises: [Exercise])] {
        muscleOrder.compactMap { muscle in
            let exs = filteredExercises.filter { $0.muscle == muscle }
            return exs.isEmpty ? nil : (muscle: muscle, exercises: exs)
        }
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
                                        .fill(AppTheme.primary)
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

                    // Equipment filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            EquipmentChip(label: "All", isSelected: filterEquipment.isEmpty) {
                                filterEquipment = []
                            }
                            ForEach(ExerciseEquipment.allCases) { eq in
                                EquipmentChip(label: eq.label, isSelected: filterEquipment.contains(eq)) {
                                    if filterEquipment.contains(eq) { filterEquipment.remove(eq) }
                                    else { filterEquipment.insert(eq) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 12)

                    // Accordion groups
                    if groupedExercises.isEmpty {
                        ContentUnavailableView("No Exercises Found", systemImage: "dumbbell",
                            description: Text("Try changing your filters or search term."))
                            .padding(.top, 40)
                    } else {
                        ForEach(groupedExercises, id: \.muscle) { group in
                            AccordionSection(
                                muscle: group.muscle,
                                exercises: group.exercises,
                                isExpanded: expandedMuscles.contains(group.muscle),
                                recovery: appState.recoveryStatus(muscle: group.muscle)
                            ) {
                                withAnimation(.spring(response: 0.35)) {
                                    if expandedMuscles.contains(group.muscle) {
                                        expandedMuscles.remove(group.muscle)
                                    } else {
                                        expandedMuscles.insert(group.muscle)
                                    }
                                }
                            } onSelect: { ex in
                                selectedExercise = ex
                            }
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
            .onChange(of: searchText) { _, new in
                if !new.isEmpty {
                    let matchingMuscles = Set(filteredExercises.map(\.muscle))
                    expandedMuscles = matchingMuscles
                }
            }
        }
    }
}

// MARK: - Accordion Section

private struct AccordionSection: View {
    let muscle: String
    let exercises: [Exercise]
    let isExpanded: Bool
    let recovery: AppState.RecoveryStatus
    let onToggle: () -> Void
    let onSelect: (Exercise) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(muscle.muscleColor)
                        .frame(width: 10, height: 10)
                    Text(muscle.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    Text("(\(exercises.count))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    // Recovery dot
                    Circle()
                        .fill(recovery.color)
                        .frame(width: 8, height: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(Color(.secondarySystemGroupedBackground))

            if isExpanded {
                Divider().padding(.horizontal, 16)
                ForEach(exercises) { ex in
                    ExerciseRow(exercise: ex) { onSelect(ex) }
                    if ex.id != exercises.last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Exercise Row

private struct ExerciseRow: View {
    @Environment(AppState.self) private var appState
    let exercise: Exercise
    let onTap: () -> Void

    private var pr: AppState.PRResult { appState.computePRs(for: exercise.id) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(exercise.muscle.muscleColor)
                    .frame(width: 8, height: 8)
                    .padding(.leading, 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(exercise.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if exercise.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(exercise.movementType.label)
                        Text("·")
                        Text(exercise.equipment.label)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if pr.bestWeight > 0 {
                    Text("\(Int(pr.bestWeight))kg")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.trailing, 8)
            }
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Equipment Chip

private struct EquipmentChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.primary.opacity(0.15) : Color(.secondarySystemFill))
                .foregroundColor(isSelected ? AppTheme.primary : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? AppTheme.primary.opacity(0.4) : Color.clear, lineWidth: 1))
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
                        .foregroundColor(AppTheme.primary)
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
