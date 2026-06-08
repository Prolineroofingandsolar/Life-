import SwiftUI
import Charts

// MARK: - ExerciseDetailSheet

struct ExerciseDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let exerciseId: String
    @State private var showAddToRoutine = false

    private var exercise: Exercise? {
        appState.exercises.first { $0.id == exerciseId }
    }

    private var prs: AppState.PRResult {
        appState.computePRs(for: exerciseId)
    }

    private var recentSessions: [(date: Date, bestSet: LoggedSet)] {
        appState.sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .prefix(10)
            .compactMap { session -> (date: Date, bestSet: LoggedSet)? in
                guard let fin = session.finishedAt,
                      let ex = session.exercises.first(where: { $0.exerciseId == exerciseId }) else { return nil }
                let done = ex.sets.filter { $0.done && !$0.isWarmup }
                guard !done.isEmpty else { return nil }
                let best = done.max { a, b in
                    let a1RM = a.weight * (1 + Double(a.reps) / 30.0)
                    let b1RM = b.weight * (1 + Double(b.reps) / 30.0)
                    return a1RM < b1RM
                }
                guard let bestSet = best else { return nil }
                return (date: fin, bestSet: bestSet)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let ex = exercise {
                        HeaderCard(exercise: ex, onFavorite: {
                            HapticManager.selection()
                            if let idx = appState.exercises.firstIndex(where: { $0.id == exerciseId }) {
                                appState.exercises[idx].isFavorite.toggle()
                                appState.save()
                            }
                        })

                        if !ex.instructions.isEmpty {
                            InstructionsCard(instructions: ex.instructions)
                        }
                    }

                    PRCard(prs: prs, kind: exercise?.kind ?? .weight)

                    if !recentSessions.isEmpty {
                        SessionHistoryCard(sessions: recentSessions, kind: exercise?.kind ?? .weight)
                        StrengthChartCard(sessions: recentSessions)
                    }

                    Button { showAddToRoutine = true } label: {
                        Label("Add to Routine", systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "#30d158").opacity(0.15))
                            .foregroundColor(Color(hex: "#30d158"))
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showAddToRoutine) {
                AddExerciseToRoutineSheet(exerciseId: exerciseId)
            }
            .navigationTitle(exercise?.name ?? "Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if let ex = exercise {
                        Button {
                            HapticManager.selection()
                            if let idx = appState.exercises.firstIndex(where: { $0.id == exerciseId }) {
                                appState.exercises[idx].isFavorite.toggle()
                                appState.save()
                            }
                        } label: {
                            Image(systemName: ex.isFavorite ? "heart.fill" : "heart")
                                .foregroundColor(ex.isFavorite ? .red : .secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Header Card

private struct HeaderCard: View {
    let exercise: Exercise
    let onFavorite: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(exercise.muscle.muscleColor.opacity(0.2))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: exercise.equipment.icon)
                        .font(.title)
                        .foregroundColor(exercise.muscle.muscleColor)
                }

            VStack(spacing: 6) {
                Text(exercise.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(exercise.muscle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    KindBadge(label: exercise.kind.label)
                    Text(exercise.equipment.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(6)
                }

                DifficultyDots(difficulty: exercise.difficulty)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

private struct KindBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.caption.bold())
            .foregroundColor(Color(hex: "#30d158"))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: "#30d158").opacity(0.15))
            .cornerRadius(6)
    }
}

private struct DifficultyDots: View {
    let difficulty: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { level in
                Circle()
                    .fill(level <= difficulty ? Color(hex: "#30d158") : Color(.systemFill))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Instructions Card

private struct InstructionsCard: View {
    let instructions: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Instructions", systemImage: "text.alignleft")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            Text(instructions)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - PR Card

private struct PRCard: View {
    let prs: AppState.PRResult
    let kind: ExerciseKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All-Time PRs")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal)

            HStack(spacing: 8) {
                PRStatCell(label: "Best Weight", value: prs.bestWeight > 0 ? "\(prs.bestWeight.formatted1) kg" : "—")
                PRStatCell(label: "Best Reps", value: prs.bestReps > 0 ? "\(prs.bestReps)" : "—")
                PRStatCell(label: "Est. 1RM", value: prs.best1RM > 0 ? "\(prs.best1RM.formatted1) kg" : "—")
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

private struct PRStatCell: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.bold())
                .foregroundColor(Color(hex: "#30d158"))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill))
        .cornerRadius(10)
    }
}

// MARK: - Session History Card

private struct SessionHistoryCard: View {
    let sessions: [(date: Date, bestSet: LoggedSet)]
    let kind: ExerciseKind

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 5 Sessions")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.offset) { idx, entry in
                    HStack {
                        Text(dateFormatter.string(from: entry.date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Spacer()
                        if kind == .cardio {
                            Text(entry.bestSet.durationSec > 0 ? "\(entry.bestSet.durationSec / 60):\(String(format: "%02d", entry.bestSet.durationSec % 60))" : "—")
                                .font(.subheadline.bold())
                        } else {
                            Text(entry.bestSet.weight > 0 ? "\(entry.bestSet.weight.formatted1) kg" : "BW")
                                .font(.subheadline.bold())
                            Text("×")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("\(entry.bestSet.reps)")
                                .font(.subheadline.bold())
                        }
                    }
                    .padding(.vertical, 8)
                    if idx < sessions.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Strength Chart Card

private struct StrengthChartCard: View {
    let sessions: [(date: Date, bestSet: LoggedSet)]
    @State private var show1RM = false

    // sessions arrive newest-first; chart needs oldest-first
    private var chartData: [(date: Date, value: Double)] {
        sessions.reversed().map { entry in
            let v: Double = show1RM
                ? entry.bestSet.weight * (1 + Double(entry.bestSet.reps) / 30.0)
                : entry.bestSet.weight
            return (date: entry.date, value: v)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Strength Progress")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $show1RM) {
                    Text("Weight").tag(false)
                    Text("Est. 1RM").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if chartData.count < 2 {
                Text("Log more sessions to see progress")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                Chart {
                    ForEach(chartData.indices, id: \.self) { i in
                        let pt = chartData[i]
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value(show1RM ? "1RM" : "Weight", pt.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color(hex: "#30d158").gradient)

                        PointMark(
                            x: .value("Date", pt.date),
                            y: .value(show1RM ? "1RM" : "Weight", pt.value)
                        )
                        .foregroundStyle(Color(hex: "#30d158"))
                        .symbolSize(40)
                    }
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text(d, format: .dateTime.day().month(.abbreviated))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))").font(.caption2)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Add Exercise to Routine Sheet

private struct AddExerciseToRoutineSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let exerciseId: String

    var body: some View {
        NavigationStack {
            List {
                if appState.routines.isEmpty {
                    ContentUnavailableView("No Routines", systemImage: "list.bullet.rectangle",
                        description: Text("Create a routine in the Train tab first."))
                } else {
                    ForEach(appState.routines) { routine in
                        Button {
                            let alreadyIn = routine.exercises.contains { $0.exerciseId == exerciseId }
                            guard !alreadyIn else { dismiss(); return }
                            let re = RoutineExercise(exerciseId: exerciseId)
                            appState.updateRoutine(
                                id: routine.id,
                                exercises: routine.exercises + [re]
                            )
                            HapticManager.success()
                            dismiss()
                        } label: {
                            HStack {
                                Text(routine.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if routine.exercises.contains(where: { $0.exerciseId == exerciseId }) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color(hex: "#30d158"))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
