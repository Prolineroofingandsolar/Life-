import SwiftUI

// MARK: - Active Workout View

struct ActiveWorkoutView: View {

    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool

    let sessionId: String

    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var restSecondsRemaining: Int = 0
    @State private var restTotalSeconds: Int = 0
    @State private var restTimer: Timer? = nil
    @State private var showRestBanner = false
    @State private var showDiscardAlert = false
    @State private var showExercisePicker = false
    @State private var showSummary = false
    @State private var showPRBanner = false
    @State private var prBannerText = ""
    @State private var isEditingName = false
    @State private var sessionName: String = ""
    @State private var notesText: String = ""

    private var session: WorkoutSession? {
        appState.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = session {
                    workoutContent(session: session)
                } else {
                    // Session was discarded — dismiss
                    Color.clear.onAppear { isPresented = false }
                }
            }
        }
        .onAppear {
            sessionName = session?.name ?? "Workout"
            notesText = session?.notes ?? ""
            startElapsedTimer()
        }
        .onDisappear {
            stopTimers()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func workoutContent(session: WorkoutSession) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Rest timer banner
                if showRestBanner {
                    RestTimerBanner(
                        secondsRemaining: restSecondsRemaining,
                        totalSeconds: restTotalSeconds
                    ) {
                        stopRestTimer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showPRBanner {
                    PRBanner(text: prBannerText)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 16)
                }

                LazyVStack(spacing: 16) {
                    ForEach(session.exercises) { exercise in
                        ExerciseCard(
                            sessionId: sessionId,
                            sessionExercise: exercise,
                            onSetDone: { setId in
                                appState.toggleSetDone(sessionId: sessionId, exerciseId: exercise.id, setId: setId)
                                if appState.workoutSettings.restTimerEnabled {
                                    startRestTimer(seconds: appState.workoutSettings.defaultRestSeconds)
                                }
                                if let pr = appState.latestPR {
                                    prBannerText = "🏆 New PR — \(pr.exerciseName) \(pr.value)"
                                    appState.latestPR = nil
                                    withAnimation { showPRBanner = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        withAnimation { showPRBanner = false }
                                    }
                                }
                            }
                        )
                        .padding(.horizontal, 16)
                    }

                    Button {
                        showExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(Color(hex: "#30d158"))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                    }

                    // Session notes
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                        TextField("Add notes about this workout...", text: $notesText, axis: .vertical)
                            .font(.subheadline)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                            .lineLimit(3...6)
                            .onChange(of: notesText) { _, new in
                                appState.updateSessionNotes(sessionId: sessionId, notes: new)
                            }
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isEditingName {
                    TextField("Session name", text: $sessionName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit {
                            appState.renameSession(sessionId: sessionId, name: sessionName)
                            isEditingName = false
                        }
                } else {
                    Button {
                        isEditingName = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(elapsedSeconds.formattedDuration)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showDiscardAlert = true
                } label: {
                    Text("Discard")
                        .foregroundColor(.red)
                }

                Button {
                    stopTimers()
                    appState.finishSession(sessionId: sessionId)
                    showSummary = true
                } label: {
                    Text("Finish")
                        .bold()
                        .foregroundColor(Color(hex: "#30d158"))
                }
            }
        }
        .alert("Discard Workout?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                appState.discardSession(sessionId: sessionId)
                isPresented = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This workout will be permanently deleted.")
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet(sessionId: sessionId)
        }
        .fullScreenCover(isPresented: $showSummary) {
            WorkoutSummaryView(sessionId: sessionId) {
                showSummary = false
                isPresented = false
            }
        }
        .animation(.spring(response: 0.3), value: showRestBanner)
    }

    // MARK: - Timers

    private func startElapsedTimer() {
        if let start = session?.startedAt {
            elapsedSeconds = Int(Date().timeIntervalSince(start))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private func startRestTimer(seconds: Int) {
        stopRestTimer()
        restSecondsRemaining = seconds
        restTotalSeconds = seconds
        showRestBanner = true
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if restSecondsRemaining > 0 {
                restSecondsRemaining -= 1
            } else {
                stopRestTimer()
            }
        }
    }

    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        showRestBanner = false
        restSecondsRemaining = 0
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        stopRestTimer()
    }
}

// MARK: - Rest Timer Banner

private struct RestTimerBanner: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    let onSkip: () -> Void

    private var progress: Double {
        guard totalSeconds > 0 else { return 1 }
        return Double(secondsRemaining) / Double(totalSeconds)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.2), lineWidth: 3.5)
                    .frame(width: 42, height: 42)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text("\(secondsRemaining)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Rest")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(secondsRemaining.formattedDuration)
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.primary)
            }

            Spacer()

            Button("Skip", action: onSkip)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.orange.opacity(0.25)), alignment: .bottom)
    }
}

// MARK: - PR Banner

private struct PRBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .foregroundColor(.yellow)
                .font(.title3)
            Text(text)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#30d158").opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#30d158").opacity(0.4), lineWidth: 1))
        )
    }
}

// MARK: - Exercise Card

private struct ExerciseCard: View {
    @Environment(AppState.self) private var appState
    let sessionId: String
    let sessionExercise: SessionExercise
    let onSetDone: (String) -> Void

    private var exercise: Exercise? {
        appState.exercises.first { $0.id == sessionExercise.exerciseId }
    }

    private var previousSets: [LoggedSet] {
        appState.previousSets(for: sessionExercise.exerciseId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                if let exercise = exercise {
                    Circle()
                        .fill(exercise.muscle.muscleColor)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.name)
                            .font(.headline)
                        Text("Target: \(sessionExercise.targetRepMin)–\(sessionExercise.targetRepMax) reps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(exercise.muscle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    appState.removeExerciseFromSession(sessionId: sessionId, exerciseId: sessionExercise.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Set header row
            if let ex = exercise, ex.kind != .cardio {
                HStack {
                    Text("Set").frame(width: 30, alignment: .leading)
                    Text("Prev").frame(width: 70, alignment: .center)
                    Text("Weight").frame(width: 104, alignment: .center)
                    Text("Reps").frame(width: 50, alignment: .center)
                    Text("✓").frame(width: 44, alignment: .center)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Sets
            ForEach(Array(sessionExercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    sessionId: sessionId,
                    exerciseId: sessionExercise.id,
                    set: set,
                    setNumber: index + 1,
                    exerciseKind: exercise?.kind ?? .weight,
                    prevSet: previousSets.indices.contains(index) ? previousSets[index] : previousSets.last
                ) {
                    onSetDone(set.id)
                }

                if set.id != sessionExercise.sets.last?.id {
                    Divider().padding(.leading, 16)
                }
            }

            Divider()

            // Add Set button
            Button {
                appState.addSet(sessionId: sessionId, exerciseId: sessionExercise.id)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "#30d158"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Set Row

private struct SetRow: View {
    @Environment(AppState.self) private var appState
    let sessionId: String
    let exerciseId: String
    let set: LoggedSet
    let setNumber: Int
    let exerciseKind: ExerciseKind
    let prevSet: LoggedSet?
    let onDone: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @FocusState private var weightFocused: Bool
    @FocusState private var repsFocused: Bool

    private func adjustWeight(_ delta: Double) {
        let current = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? set.weight
        let newWeight = max(0, current + delta)
        weightText = newWeight.formatted1
        appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, weight: newWeight)
    }

    private var prevLabel: String {
        guard let prev = prevSet, prev.weight > 0 || prev.reps > 0 else { return "—" }
        if prev.weight > 0 && prev.reps > 0 {
            return "\(prev.weight.formatted1)×\(prev.reps)"
        } else if prev.reps > 0 {
            return "\(prev.reps)r"
        }
        return "\(prev.weight.formatted1)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Set label
                Group {
                    if set.isWarmup {
                        Text("W")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    } else if set.isDropSet {
                        Text("D")
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                    } else if set.isFailure {
                        Text("F")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    } else {
                        Text("\(setNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 30, alignment: .leading)

                // Previous performance
                Text(prevLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .center)

                if exerciseKind == .cardio {
                    TextField("min", text: $weightText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 104)
                        .focused($weightFocused)
                        .onChange(of: weightText) { _, new in
                            if let val = Int(new) {
                                appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, durationSec: val * 60)
                            }
                        }
                } else {
                    HStack(spacing: 2) {
                        Button { adjustWeight(-2.5) } label: {
                            Text("−")
                                .font(.body.bold())
                                .frame(width: 26, height: 30)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        TextField("kg", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 48)
                            .focused($weightFocused)
                            .onChange(of: weightText) { _, new in
                                if let val = Double(new.replacingOccurrences(of: ",", with: ".")) {
                                    appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, weight: val)
                                }
                            }
                        Button { adjustWeight(2.5) } label: {
                            Text("+")
                                .font(.body.bold())
                                .frame(width: 26, height: 30)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 104)

                    TextField("reps", text: $repsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 50)
                        .focused($repsFocused)
                        .onChange(of: repsText) { _, new in
                            if let val = Int(new) {
                                appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, reps: val)
                            }
                        }
                }

                Button {
                    HapticManager.impact(set.done ? .light : .medium)
                    onDone()
                } label: {
                    Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(set.done ? Color(hex: "#30d158") : .secondary)
                        .font(.title3)
                        .scaleEffect(set.done ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: set.done)
                }
                .buttonStyle(.plain)
                .frame(width: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // RPE picker shown after marking done
            if set.done {
                RPEPicker(current: set.rpe) { rpe in
                    appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, rpe: rpe)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(set.done ? Color(hex: "#30d158").opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: set.done)
        .onAppear {
            weightText = set.weight == 0 ? "" : set.weight.formatted1
            repsText = set.reps == 0 ? "" : "\(set.reps)"
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                appState.removeSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, isWarmup: !set.isWarmup)
            } label: {
                Label(set.isWarmup ? "Working" : "Warmup", systemImage: "flame")
            }
            .tint(.orange)
            Button {
                appState.toggleSetFailure(sessionId: sessionId, exerciseId: exerciseId, setId: set.id)
            } label: {
                Label(set.isFailure ? "Clear" : "Failure", systemImage: "xmark.circle")
            }
            .tint(.red)
        }
    }
}

// MARK: - RPE Picker

private struct RPEPicker: View {
    let current: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("RPE")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(6...10, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text("\(value)")
                        .font(.caption.bold())
                        .frame(width: 28, height: 22)
                        .background(current == value ? Color(hex: "#30d158") : Color(.tertiarySystemFill))
                        .foregroundColor(current == value ? .white : .secondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            if current != nil {
                Button {
                    onSelect(0)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
    }
}

// MARK: - Exercise Picker Sheet

struct ExercisePickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
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
                                appState.addExerciseToSession(sessionId: sessionId, exerciseId: ex.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(ex.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(ex.kind.label)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText)
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
