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
    @State private var isReorderMode = false

    private var session: WorkoutSession? {
        appState.sessions.first { $0.id == sessionId }
    }

    // Groups exercises: supersets together, solo exercises alone
    private func exerciseGroups(session: WorkoutSession) -> [[SessionExercise]] {
        var groups: [[SessionExercise]] = []
        var seen = Set<String>()
        for ex in session.exercises {
            if seen.contains(ex.id) { continue }
            if let gid = ex.supersetGroupId {
                let group = session.exercises.filter { $0.supersetGroupId == gid }
                groups.append(group)
                group.forEach { seen.insert($0.id) }
            } else {
                groups.append([ex])
                seen.insert(ex.id)
            }
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = session {
                    workoutContent(session: session)
                } else {
                    Color.clear.onAppear { isPresented = false }
                }
            }
        }
        .onAppear {
            sessionName = session?.name ?? "Workout"
            notesText = session?.notes ?? ""
            startElapsedTimer()
            if #available(iOS 16.2, *), let session = session {
                let setsCompleted = session.exercises.flatMap { $0.sets }.filter { $0.done }.count
                WorkoutLiveActivityManager.shared.start(
                    workoutName: session.name,
                    startedAt: session.startedAt,
                    setsCompleted: setsCompleted
                )
            }
        }
        .onDisappear { stopTimers() }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func workoutContent(session: WorkoutSession) -> some View {
        Group {
            if isReorderMode {
                List {
                    ForEach(session.exercises, id: \.id) { ex in
                        let exercise = appState.exercises.first { $0.id == ex.exerciseId }
                        HStack(spacing: 12) {
                            Circle()
                                .fill(exercise?.muscle.muscleColor ?? Color.secondary)
                                .frame(width: 10, height: 10)
                            Text(exercise?.name ?? "Exercise")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { from, to in
                        appState.reorderExercises(sessionId: sessionId, from: from, to: to)
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if showPRBanner {
                            PRBanner(text: prBannerText)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        LazyVStack(spacing: 16) {
                            ForEach(exerciseGroups(session: session), id: \.first?.id) { group in
                                if group.count > 1 {
                                    SupersetCard(
                                        sessionId: sessionId,
                                        exercises: group,
                                        onSetDone: { handleSetDone($0) }
                                    )
                                    .padding(.horizontal, 16)
                                } else if let ex = group.first {
                                    ExerciseCard(
                                        sessionId: sessionId,
                                        sessionExercise: ex,
                                        onSetDone: { handleSetDone($0) },
                                        onPairSuperset: { pairWithNext(ex, in: session) }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }

                            Button {
                                showExercisePicker = true
                            } label: {
                                Label("Add Exercise", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(AppTheme.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal, 16)
                            }

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
                .overlay(alignment: .bottom) {
                    if showRestBanner {
                        RestTimerPill(secondsRemaining: restSecondsRemaining, totalSeconds: restTotalSeconds) {
                            stopRestTimer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // LEFT: minimise button
            ToolbarItem(placement: .navigationBarLeading) {
                Button { isPresented = false } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            // CENTER: session name + timer
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    if isEditingName {
                        TextField("Session name", text: $sessionName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                            .font(.headline)
                            .onSubmit {
                                appState.renameSession(sessionId: sessionId, name: sessionName)
                                isEditingName = false
                            }
                    } else {
                        Button { isEditingName = true } label: {
                            Text(session.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(elapsedSeconds.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            // RIGHT: reorder toggle + finish
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3)) { isReorderMode.toggle() }
                } label: {
                    Image(systemName: isReorderMode ? "checkmark" : "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isReorderMode ? AppTheme.primary : .secondary)
                }
                Menu {
                    Button(role: .destructive) { showDiscardAlert = true } label: {
                        Label("Discard Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
                Button {
                    stopTimers()
                    appState.finishSession(sessionId: sessionId)
                    showSummary = true
                } label: {
                    Text("Finish")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(AppTheme.primary)
                        .cornerRadius(8)
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
        .animation(.spring(response: 0.3), value: showPRBanner)
    }

    // MARK: - Superset pairing

    private func pairWithNext(_ ex: SessionExercise, in session: WorkoutSession) {
        guard let idx = session.exercises.firstIndex(where: { $0.id == ex.id }),
              idx + 1 < session.exercises.count else { return }
        let next = session.exercises[idx + 1]
        // If already in a superset, remove; otherwise create new group
        if ex.supersetGroupId != nil {
            appState.setSupersetGroup(sessionId: sessionId, exerciseIds: [ex.id, next.id], groupId: nil)
        } else {
            let gid = UUID().uuidString
            appState.setSupersetGroup(sessionId: sessionId, exerciseIds: [ex.id, next.id], groupId: gid)
        }
        HapticManager.impact(.medium)
    }

    // MARK: - Set done handler

    private var setsCompletedCount: Int {
        session?.exercises.reduce(0) { $0 + $1.sets.filter { $0.done }.count } ?? 0
    }

    private func handleSetDone(_ setId: String) {
        if appState.workoutSettings.restTimerEnabled {
            startRestTimer(seconds: appState.workoutSettings.defaultRestSeconds)
        } else if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.update(restEndsAt: nil, setsCompleted: setsCompletedCount)
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

    // MARK: - Timers

    private func startElapsedTimer() {
        if let start = session?.startedAt {
            elapsedSeconds = Int(Date().timeIntervalSince(start))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in elapsedSeconds += 1 }
    }

    private func startRestTimer(seconds: Int) {
        stopRestTimer()
        restSecondsRemaining = seconds
        restTotalSeconds = seconds
        showRestBanner = true
        NotificationsManager.shared.scheduleRestTimerNotification(seconds: seconds)
        if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.update(
                restEndsAt: Date().addingTimeInterval(TimeInterval(seconds)),
                setsCompleted: setsCompletedCount
            )
        }
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if restSecondsRemaining > 0 { restSecondsRemaining -= 1 } else { stopRestTimer() }
        }
    }

    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        showRestBanner = false
        restSecondsRemaining = 0
        NotificationsManager.shared.cancelRestTimer()
        if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.update(restEndsAt: nil, setsCompleted: setsCompletedCount)
        }
    }

    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        stopRestTimer()
    }
}

// MARK: - Superset Card

private struct SupersetCard: View {
    @Environment(AppState.self) private var appState
    let sessionId: String
    let exercises: [SessionExercise]
    let onSetDone: (String) -> Void

    private let supersetColors: [Color] = [Color(hex: "#5E9BF0"), Color(hex: "#FF6B6B"), Color(hex: "#F0A05E"), Color(hex: "#A05EF0")]

    var body: some View {
        VStack(spacing: 0) {
            // Superset header
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.bold())
                    .foregroundColor(Color(hex: "#5E9BF0"))
                Text("Superset")
                    .font(.caption.bold())
                    .foregroundColor(Color(hex: "#5E9BF0"))
                Spacer()
                Button {
                    appState.setSupersetGroup(sessionId: sessionId, exerciseIds: exercises.map(\.id), groupId: nil)
                    HapticManager.selection()
                } label: {
                    Text("Unlink")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: "#5E9BF0").opacity(0.08))

            ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                let label = ["A", "B", "C", "D"][min(idx, 3)]
                let color = supersetColors[min(idx, supersetColors.count - 1)]
                ExerciseCardContent(
                    sessionId: sessionId,
                    sessionExercise: ex,
                    supersetLabel: label,
                    accentColor: color,
                    onSetDone: { sid in
                        appState.toggleSetDone(sessionId: sessionId, exerciseId: ex.id, setId: sid)
                        onSetDone(sid)
                    }
                )
                if idx < exercises.count - 1 {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color(hex: "#5E9BF0").opacity(0.3))
                            .frame(width: 2, height: 20)
                            .padding(.leading, 20)
                        Text("then")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#5E9BF0").opacity(0.35), lineWidth: 1.5)
        )
    }
}

// MARK: - Exercise Card

private struct ExerciseCard: View {
    @Environment(AppState.self) private var appState
    let sessionId: String
    let sessionExercise: SessionExercise
    let onSetDone: (String) -> Void
    let onPairSuperset: () -> Void

    private var exercise: Exercise? {
        appState.exercises.first { $0.id == sessionExercise.exerciseId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ExerciseCardContent(
                sessionId: sessionId,
                sessionExercise: sessionExercise,
                supersetLabel: nil,
                accentColor: exercise?.muscle.muscleColor ?? AppTheme.primary,
                onSetDone: { sid in
                    appState.toggleSetDone(sessionId: sessionId, exerciseId: sessionExercise.id, setId: sid)
                    onSetDone(sid)
                },
                onPairSuperset: onPairSuperset
            )

            Divider()

            // Footer: Add Set
            Button {
                appState.addSet(sessionId: sessionId, exerciseId: sessionExercise.id)
                HapticManager.impact(.light)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}

// MARK: - Exercise Card Content (shared by solo + superset)

private struct ExerciseCardContent: View {
    @Environment(AppState.self) private var appState
    let sessionId: String
    let sessionExercise: SessionExercise
    let supersetLabel: String?
    let accentColor: Color
    let onSetDone: (String) -> Void
    var onPairSuperset: (() -> Void)? = nil

    @State private var showExerciseDetail = false

    private var exercise: Exercise? {
        appState.exercises.first { $0.id == sessionExercise.exerciseId }
    }

    private var previousSets: [LoggedSet] {
        appState.previousSets(for: sessionExercise.exerciseId)
    }

    private var overload: AppState.OverloadSuggestion {
        appState.progressiveOverloadSuggestion(
            for: sessionExercise.exerciseId,
            targetRepMax: sessionExercise.targetRepMax
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    if let label = supersetLabel {
                        Text(label)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(accentColor)
                            .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Button { showExerciseDetail = true } label: {
                            Text(exercise?.name ?? "Exercise")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 8) {
                            if let muscle = exercise?.muscle {
                                Text(muscle)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            if overload != .maintain {
                                HStack(spacing: 3) {
                                    Image(systemName: overload.icon).font(.caption2)
                                    Text(overload.label).font(.caption2.bold())
                                }
                                .foregroundColor(overload.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(overload.color.opacity(0.12))
                                .cornerRadius(6)
                            }
                        }
                    }
                    Spacer()
                    // Exercise actions menu
                    Menu {
                        Button { appState.addSet(sessionId: sessionId, exerciseId: sessionExercise.id) } label: {
                            Label("Add Set", systemImage: "plus")
                        }
                        Button {
                            let lastWorkingId = sessionExercise.sets.last(where: { !$0.isDropSet })?.id ?? sessionExercise.sets.last?.id ?? ""
                            appState.addDropSet(sessionId: sessionId, exerciseId: sessionExercise.id, afterSetId: lastWorkingId)
                            HapticManager.impact(.light)
                        } label: {
                            Label("Add Drop Set", systemImage: "arrow.down.circle")
                        }
                        Button { appState.addWarmupSets(sessionId: sessionId, exerciseId: sessionExercise.id) } label: {
                            Label("Add Warmup Sets", systemImage: "flame")
                        }
                        if let pair = onPairSuperset {
                            Button { pair() } label: {
                                Label("Superset with Next", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            appState.removeExerciseFromSession(sessionId: sessionId, exerciseId: sessionExercise.id)
                        } label: {
                            Label("Remove Exercise", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .sheet(isPresented: $showExerciseDetail) {
                if let ex = exercise { ExerciseDetailSheet(exerciseId: ex.id) }
            }

            Divider()

            // Sets — working and drop sets rendered together
            let sets = sessionExercise.sets
            ForEach(Array(workingSetIndices(sets).enumerated()), id: \.element) { labelIdx, workingIdx in
                let workingSet = sets[workingIdx]
                // Working set row
                SetRow(
                    sessionId: sessionId,
                    exerciseId: sessionExercise.id,
                    set: workingSet,
                    setLabel: setLabel(for: workingSet, number: labelIdx + 1),
                    labelColor: setLabelColor(for: workingSet),
                    exerciseKind: exercise?.kind ?? .weight,
                    prevSet: previousSets.indices.contains(labelIdx) ? previousSets[labelIdx] : previousSets.last,
                    isDropSet: false,
                    onDone: { onSetDone(workingSet.id) },
                    onAddDropSet: {
                        appState.addDropSet(sessionId: sessionId, exerciseId: sessionExercise.id, afterSetId: workingSet.id)
                        HapticManager.impact(.light)
                    }
                )

                // Drop sets immediately after this working set
                let drops = dropSetsAfter(index: workingIdx, in: sets)
                ForEach(Array(drops.enumerated()), id: \.element.id) { dropIdx, drop in
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.purple.opacity(0.4)).frame(width: 2)
                        }
                        .frame(width: 14)
                        .padding(.leading, 14)

                        SetRow(
                            sessionId: sessionId,
                            exerciseId: sessionExercise.id,
                            set: drop,
                            setLabel: "↓",
                            labelColor: .purple,
                            exerciseKind: exercise?.kind ?? .weight,
                            prevSet: nil,
                            isDropSet: true,
                            onDone: { onSetDone(drop.id) },
                            onAddDropSet: {
                                appState.addDropSet(sessionId: sessionId, exerciseId: sessionExercise.id, afterSetId: drop.id)
                                HapticManager.impact(.light)
                            }
                        )
                    }
                    .background(Color.purple.opacity(0.04))
                }

                if workingIdx < sets.lastIndex(where: { !$0.isDropSet }) ?? 0 {
                    Divider().padding(.leading, 14)
                }
            }

            // Add Set button inside superset card
            if supersetLabel != nil {
                Divider()
                Button {
                    appState.addSet(sessionId: sessionId, exerciseId: sessionExercise.id)
                    HapticManager.impact(.light)
                } label: {
                    Label("Add Set", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    // Returns indices of non-drop sets (working sets)
    private func workingSetIndices(_ sets: [LoggedSet]) -> [Int] {
        sets.indices.filter { !sets[$0].isDropSet }
    }

    // Returns drop sets immediately following the given index
    private func dropSetsAfter(index: Int, in sets: [LoggedSet]) -> [LoggedSet] {
        var result: [LoggedSet] = []
        var i = index + 1
        while i < sets.count && sets[i].isDropSet {
            result.append(sets[i])
            i += 1
        }
        return result
    }

    private func setLabel(for set: LoggedSet, number: Int) -> String {
        if set.isWarmup { return "W" }
        if set.isFailure { return "F" }
        return "\(number)"
    }

    private func setLabelColor(for set: LoggedSet) -> Color {
        if set.isWarmup { return .orange }
        if set.isFailure { return .red }
        return .secondary
    }
}

// MARK: - Set Row

private struct SetRow: View {
    @Environment(AppState.self) private var appState
    let sessionId: String
    let exerciseId: String
    let set: LoggedSet
    let setLabel: String
    let labelColor: Color
    let exerciseKind: ExerciseKind
    let prevSet: LoggedSet?
    let isDropSet: Bool
    let onDone: () -> Void
    let onAddDropSet: () -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @State private var showPlates: Bool = false
    @FocusState private var weightFocused: Bool
    @FocusState private var repsFocused: Bool

    private func adjustWeight(_ delta: Double) {
        let current = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? set.weight
        let newWeight = max(0, current + delta)
        weightText = newWeight.formatted1
        appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, weight: newWeight)
    }

    private var prevLabel: String? {
        guard let prev = prevSet, (prev.weight > 0 || prev.reps > 0) else { return nil }
        if prev.weight > 0 && prev.reps > 0 { return "\(prev.weight.formatted1) × \(prev.reps)" }
        if prev.reps > 0 { return "\(prev.reps) reps" }
        return "\(prev.weight.formatted1) kg"
    }

    private var parsedWeight: Double {
        Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Set label (44pt wide)
                Text(setLabel)
                    .font(setLabel.first?.isNumber == true ? .body.bold() : .callout.bold())
                    .foregroundColor(labelColor)
                    .frame(width: 44, alignment: .center)
                    .padding(.leading, isDropSet ? 0 : 4)

                if exerciseKind == .cardio {
                    // Cardio: duration field
                    TextField("min", text: $weightText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .focused($weightFocused)
                        .onChange(of: weightText) { _, new in
                            if let val = Int(new) {
                                appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, durationSec: val * 60)
                            }
                        }
                } else {
                    // Weight: − field +
                    HStack(spacing: 4) {
                        Button { adjustWeight(-2.5) } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 44, height: 44)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 2) {
                            TextField("0", text: $weightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .frame(width: 68)
                                .focused($weightFocused)
                                .onChange(of: weightText) { _, new in
                                    if let val = Double(new.replacingOccurrences(of: ",", with: ".")) {
                                        appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, weight: val)
                                    }
                                }
                                .onChange(of: weightFocused) { _, focused in
                                    if !focused { showPlates = false }
                                    else if parsedWeight > 20 { showPlates = true }
                                }
                            Text("kg")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                        .frame(width: 68)

                        Button { adjustWeight(2.5) } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 44, height: 44)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }

                    // × separator
                    Text("×")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    // Reps field
                    VStack(spacing: 2) {
                        TextField("0", text: $repsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .frame(width: 52)
                            .focused($repsFocused)
                            .onChange(of: repsText) { _, new in
                                if let val = Int(new) {
                                    appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, reps: val)
                                }
                            }
                        Text("reps").font(.caption2).foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                // Done button — large
                Button {
                    HapticManager.impact(set.done ? .light : .medium)
                    onDone()
                } label: {
                    ZStack {
                        Circle()
                            .fill(set.done ? AppTheme.primary : Color(.tertiarySystemFill))
                            .frame(width: 44, height: 44)
                        Image(systemName: set.done ? "checkmark" : "")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(set.done ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: set.done)
                }
                .buttonStyle(.plain)
                .frame(width: 52)

                // Trash — always visible, subtle
                Button {
                    HapticManager.impact(.light)
                    appState.removeSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 28, height: 44)
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 8)
            .background(set.done ? AppTheme.primary.opacity(0.08) : Color.clear)
            .animation(.easeInOut(duration: 0.2), value: set.done)
            .contextMenu {
                if !set.isDropSet {
                    Button {
                        appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, isWarmup: !set.isWarmup)
                    } label: {
                        Label(set.isWarmup ? "Mark as Working Set" : "Mark as Warmup", systemImage: "flame")
                    }
                    Button {
                        appState.toggleSetFailure(sessionId: sessionId, exerciseId: exerciseId, setId: set.id)
                    } label: {
                        Label(set.isFailure ? "Clear Failure" : "Mark as Failure", systemImage: "xmark.circle")
                    }
                    Button { onAddDropSet() } label: {
                        Label("Add Drop Set", systemImage: "arrow.down.circle")
                    }
                }
                Button(role: .destructive) {
                    appState.removeSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id)
                } label: { Label("Delete Set", systemImage: "trash") }
            }

            // Previous session row (only if data exists)
            if let prev = prevLabel, !isDropSet {
                HStack {
                    Spacer().frame(width: 44)
                    Text("prev: \(prev)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }

            // Plate calculator (shown when weight field focused and weight > 20kg)
            if showPlates && parsedWeight > 20 && exerciseKind != .cardio && !isDropSet {
                PlateBreakdownView(totalKg: parsedWeight)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // RPE after done
            if set.done {
                RPEPicker(current: set.rpe) { rpe in
                    appState.updateSet(sessionId: sessionId, exerciseId: exerciseId, setId: set.id, rpe: rpe)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            weightText = set.weight == 0 ? "" : set.weight.formatted1
            repsText = set.reps == 0 ? "" : "\(set.reps)"
        }
    }
}

// MARK: - Plate Breakdown View

private struct PlateBreakdownView: View {
    let totalKg: Double
    var barbellKg: Double = 20

    private struct PlateLoad: Identifiable {
        let id = UUID()
        let kg: Double
        let count: Int
        var color: Color {
            switch kg {
            case 25: return Color(hex: "#FF3B30")
            case 20: return Color(hex: "#007AFF")
            case 15: return Color(hex: "#FFD60A")
            case 10: return AppTheme.primary
            case 5:  return Color(hex: "#F2F2F7").opacity(0.9)
            case 2.5: return Color(hex: "#636366")
            default: return Color(hex: "#8E8E93")
            }
        }
        var textColor: Color { kg == 5 ? .black : .white }
    }

    private var plates: [PlateLoad] {
        let available = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]
        var remaining = max(0, (totalKg - barbellKg)) / 2
        var result: [PlateLoad] = []
        for plate in available {
            let count = Int(remaining / plate)
            if count > 0 {
                result.append(PlateLoad(kg: plate, count: count))
                remaining -= Double(count) * plate
                remaining = round(remaining * 100) / 100
            }
        }
        return result
    }

    var body: some View {
        if !plates.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Each side of \(Int(barbellKg))kg bar:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(plates) { plate in
                            HStack(spacing: 3) {
                                ForEach(0..<plate.count, id: \.self) { _ in
                                    Text(plate.kg == plate.kg.rounded() ? "\(Int(plate.kg))" : "\(plate.kg)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(plate.textColor)
                                        .frame(width: 32, height: 32)
                                        .background(plate.color)
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemFill))
            .cornerRadius(10)
            .animation(.spring(response: 0.3), value: plates.count)
        }
    }
}

// MARK: - Rest Timer Pill

private struct RestTimerPill: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    let onSkip: () -> Void

    private var progress: Double {
        guard totalSeconds > 0 else { return 1 }
        return Double(secondsRemaining) / Double(totalSeconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.25), lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text("\(secondsRemaining)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            Text(secondsRemaining.formattedDuration)
                .font(.headline.monospacedDigit())
                .foregroundColor(.primary)
            Spacer()
            Button("Skip", action: onSkip)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

// MARK: - PR Banner

private struct PRBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill").foregroundColor(.yellow).font(.title3)
            Text(text).font(.subheadline.bold()).foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.primary.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.primary.opacity(0.4), lineWidth: 1))
        )
    }
}

// MARK: - RPE Picker

private struct RPEPicker: View {
    let current: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("RPE").font(.caption2).foregroundColor(.secondary)
            ForEach(6...10, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text("\(value)")
                        .font(.caption.bold())
                        .frame(width: 28, height: 22)
                        .background(current == value ? AppTheme.primary : Color(.tertiarySystemFill))
                        .foregroundColor(current == value ? .white : .secondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            if current != nil {
                Button { onSelect(0) } label: {
                    Image(systemName: "xmark").font(.caption2).foregroundColor(.secondary)
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
    @State private var equipmentFilter: ExerciseEquipment? = nil
    @State private var showCreateExercise = false

    private var muscles: [String] {
        Array(Set(appState.exercises.map(\.muscle))).sorted()
    }

    private var filtered: [Exercise] {
        appState.exercises.filter { ex in
            let matchesSearch = searchText.isEmpty ||
                ex.name.localizedCaseInsensitiveContains(searchText) ||
                ex.muscle.localizedCaseInsensitiveContains(searchText)
            let matchesEquipment = equipmentFilter == nil || ex.equipment == equipmentFilter
            return matchesSearch && matchesEquipment
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
            VStack(spacing: 0) {
                EquipmentFilterChips(selected: $equipmentFilter)
                List {
                    ForEach(grouped, id: \.0) { muscle, exs in
                        Section(muscle) {
                            ForEach(exs) { ex in
                                Button {
                                    appState.addExerciseToSession(sessionId: sessionId, exerciseId: ex.id)
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
            .searchable(text: $searchText)
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreateExercise = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateExercise) {
                AddExerciseSheet()
            }
        }
    }
}

// MARK: - Equipment Filter Chips (shared)

struct EquipmentFilterChips: View {
    @Binding var selected: ExerciseEquipment?

    private let options: [ExerciseEquipment?] = [nil] + ExerciseEquipment.allCases.map { Optional($0) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { idx in
                    let option = options[idx]
                    let label = option?.label ?? "All"
                    let isSelected = selected == option
                    Button {
                        selected = option
                        HapticManager.selection()
                    } label: {
                        Text(label)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isSelected ? AppTheme.primary : Color(.secondarySystemGroupedBackground))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }
}
