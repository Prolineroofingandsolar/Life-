import SwiftUI

// MARK: - Mid-Workout Coach

/// Five questions, mid-session, answered in a sentence.
///
/// **Deliberately not a chat.** No transcript, no open-ended box, no history —
/// someone between sets has a phone in one hand and about fifteen seconds. Five
/// fixed questions cover almost everything anyone asks at that moment, and four
/// of the five are answered by engines that need no network at all: the
/// progression rules, the adjuster, the substitution engine, and the resolver's
/// own notes.
///
/// There is no model call here at all, and that is the design rather than a
/// limitation: everything asked between sets is answerable from the sets
/// themselves. Nothing changes the session without the confirm button that
/// appears under the answer.
struct MidWorkoutCoachSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let sessionId: String
    /// The exercise currently in front of them, when there is one.
    var focusedExerciseId: String?

    @State private var answer: Answer?

    private var session: WorkoutSession? { appState.sessions.first { $0.id == sessionId } }

    /// What came back. Every case carries its own confirm action or none at all.
    enum Answer: Equatable {
        case text(String)
        case progression(ProgressionEngine.Proposal)
        case adjustment(WorkoutAdjuster.Adjustment)
        case substitutes([SubstitutionEngine.Candidate], replacing: Exercise)
        case unavailable(String)
    }

    enum Question: String, CaseIterable, Identifiable {
        case heavier
        case shorten
        case replace
        case fifteenLeft
        case why

        var id: String { rawValue }

        var label: String {
            switch self {
            case .heavier:     return "Should I go heavier?"
            case .shorten:     return "Shorten the rest of this"
            case .replace:     return "Replace this exercise"
            case .fifteenLeft: return "I've only got 15 minutes left"
            case .why:         return "Why is this exercise here?"
            }
        }

        var icon: String {
            switch self {
            case .heavier:     return "arrow.up"
            case .shorten:     return "timer"
            case .replace:     return "arrow.left.arrow.right"
            case .fifteenLeft: return "hourglass"
            case .why:         return "questionmark"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Question.allCases) { question in
                        questionButton(question)
                    }

                    if let answer { answerCard(answer) }

                    footnote
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Quick question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func questionButton(_ question: Question) -> some View {
        Button {
            HapticManager.selection()
            ask(question)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: question.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.trainAccent)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(question.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        Text("Answered from your own sets and your own library. Nothing here changes the session unless you tap to apply it.")
            .font(.caption)
            .foregroundColor(Color(.tertiaryLabel))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Answers

    @ViewBuilder
    private func answerCard(_ answer: Answer) -> some View {
        switch answer {
        case .text(let text), .unavailable(let text):
            card { Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true) }

        case .progression(let proposal):
            card {
                VStack(alignment: .leading, spacing: 6) {
                    Text(proposal.action.headline)
                        .font(.subheadline.weight(.semibold))
                    Text("\(proposal.currentWeight.formatted1)kg × \(proposal.currentReps) → \(proposal.proposedWeight.formatted1)kg × \(proposal.proposedReps)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                    ForEach(proposal.evidence, id: \.self) { line in
                        Text(line).font(.caption).foregroundColor(.secondary)
                    }
                    // Read-only mid-session on purpose. Changing next session's
                    // numbers belongs in the review afterwards, not between two
                    // sets when the session isn't finished.
                    Text("Saved for the review at the end.")
                        .font(.caption2)
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }

        case .adjustment(let adjustment):
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(adjustment.originalMinutes)m → \(adjustment.adjustedMinutes)m")
                        .font(.subheadline.weight(.semibold))
                    ForEach(adjustment.changes) { change in
                        Text(change.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Apply to this session") { apply(adjustment) }
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 4)
                }
            }

        case .substitutes(let candidates, let replacing):
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instead of \(replacing.name)")
                        .font(.subheadline.weight(.semibold))
                    ForEach(candidates.prefix(3)) { candidate in
                        Button {
                            replaceExercise(replacing, for: candidate.exercise)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.exercise.name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    if let reason = candidate.reasons.first {
                                        Text(reason)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundColor(Color(.tertiaryLabel))
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Asking

    private func ask(_ question: Question) {
        switch question {
        case .heavier:      answer = heavierAnswer()
        case .shorten:      answer = shortenAnswer(byMinutes: 10)
        case .fifteenLeft:  answer = fitInAnswer(minutes: 15)
        case .replace:      answer = replaceAnswer()
        case .why:          answer = whyAnswer()
        }
    }

    /// The progression rules, applied to the sets already logged today.
    private func heavierAnswer() -> Answer {
        guard let session,
              let exerciseId = focusedExerciseId ?? session.exercises.last?.exerciseId,
              let performed = session.exercises.first(where: { $0.exerciseId == exerciseId }),
              let exercise = appState.exercises.first(where: { $0.id == exerciseId })
        else {
            return .unavailable("Log a set first and I'll have something to go on.")
        }

        let working = performed.sets.filter { $0.done && !$0.isWarmup }
        guard !working.isEmpty else {
            return .unavailable("Nothing logged for \(exercise.name) yet.")
        }

        let comparable = appState.completedWorkouts
            .filter { $0.exercises.contains { $0.exerciseId == exerciseId } }
            .count

        let proposal = ProgressionEngine.propose(
            ProgressionEngine.Input(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                repRangeMin: performed.targetRepMin,
                repRangeMax: performed.targetRepMax,
                lastSession: working.map {
                    ProgressionEngine.SetResult(
                        weight: $0.weight,
                        reps: $0.reps,
                        completed: $0.done,
                        rpe: $0.rpe,
                        toFailure: $0.isFailure
                    )
                },
                comparableSessions: comparable + 1,
                // The equipment's own smallest step. "Add 2.5kg" on a rack that
                // jumps in 2s is advice nobody can follow.
                loadIncrement: ProgressionEngine.increment(for: exercise)
            )
        )
        return .progression(proposal)
    }

    private func shortenAnswer(byMinutes minutes: Int) -> Answer {
        guard let remaining = remainingExercises(), !remaining.isEmpty else {
            return .unavailable("Nothing left to trim — you're at the end of it.")
        }
        return .adjustment(
            WorkoutAdjuster.adjust(
                exercises: remaining, library: appState.exercises, request: .shorten(byMinutes: minutes)
            )
        )
    }

    /// "I've got fifteen minutes" is a target, not a reduction — so the
    /// reduction is computed from where the session actually stands.
    private func fitInAnswer(minutes: Int) -> Answer {
        guard let remaining = remainingExercises(), !remaining.isEmpty else {
            return .unavailable("You're already done.")
        }
        // Their own pace, where the app has learned it — the standard estimate
        // is three seconds a rep for everybody, and "I've got fifteen minutes"
        // deserves an answer computed from how long their sessions actually
        // take.
        let pace = TrainingMemory.pace(appState: appState)
        let current = Int(Double(WorkoutAdjuster.estimatedMinutes(remaining)) * pace.factor)
        guard current > minutes else {
            return .text("What's left is about \(current) minutes. You'll make it.")
        }
        return .adjustment(
            WorkoutAdjuster.adjust(
                exercises: remaining,
                library: appState.exercises,
                request: .shorten(byMinutes: current - minutes)
            )
        )
    }

    private func replaceAnswer() -> Answer {
        guard let session,
              let exerciseId = focusedExerciseId ?? session.exercises.last?.exerciseId,
              let exercise = appState.exercises.first(where: { $0.id == exerciseId })
        else {
            return .unavailable("Pick an exercise first.")
        }

        let candidates = SubstitutionEngine.candidates(
            for: SubstitutionEngine.Request(
                replacing: exercise,
                library: appState.exercises,
                idsInWorkout: Set(session.exercises.map(\.exerciseId)),
                trainedIds: Set(appState.completedWorkouts.flatMap { $0.exercises.map(\.exerciseId) }),
                favouriteIds: Set(appState.exercises.filter(\.isFavorite).map(\.id))
            )
        )
        guard !candidates.isEmpty else {
            return .unavailable("Nothing in your library stands in for that one.")
        }
        return .substitutes(candidates, replacing: exercise)
    }

    /// Answered from the routine, not from a model.
    ///
    /// "Because it trains chest and it's in your Push routine" is the true
    /// answer, and it costs nothing. A generated paragraph here would be paying
    /// for prose about a fact the app already holds.
    private func whyAnswer() -> Answer {
        guard let session,
              let exerciseId = focusedExerciseId ?? session.exercises.last?.exerciseId,
              let exercise = appState.exercises.first(where: { $0.id == exerciseId })
        else {
            return .unavailable("Pick an exercise and I'll tell you.")
        }

        var parts = ["\(exercise.name) trains \(exercise.muscle.lowercased())"]
        if let routineId = session.routineId,
           let routine = appState.routines.first(where: { $0.id == routineId }) {
            parts.append("and it's part of \(routine.name)")
        }
        parts.append("using \(exercise.equipment.label.lowercased())")

        let done = appState.completedWorkouts
            .filter { $0.exercises.contains { $0.exerciseId == exerciseId } }
            .count
        var text = parts.joined(separator: ", ") + "."
        if done > 0 {
            text += " You've done it \(done) time\(done == 1 ? "" : "s") before."
        }
        return .text(text)
    }

    // MARK: Applying

    private func remainingExercises() -> [RoutineExercise]? {
        guard let session else { return nil }
        return session.exercises
            .filter { performed in
                // Anything with an unfinished set still to do.
                performed.sets.contains { !$0.done }
            }
            .map { performed in
                var item = RoutineExercise(exerciseId: performed.exerciseId)
                item.defaultSets = performed.sets.filter { !$0.done }.count
                item.repRangeMin = performed.targetRepMin
                item.repRangeMax = performed.targetRepMax
                item.restSeconds = 90
                return item
            }
    }

    /// Removes the sets the adjustment dropped. The only write in this file, and
    /// it happens on a button under a visible diff.
    private func apply(_ adjustment: WorkoutAdjuster.Adjustment) {
        guard let session,
              let index = appState.sessions.firstIndex(where: { $0.id == session.id }) else { return }

        let keep = Dictionary(
            adjustment.exercises.map { ($0.exerciseId, $0.defaultSets) },
            uniquingKeysWith: { first, _ in first }
        )

        for (exerciseIndex, performed) in appState.sessions[index].exercises.enumerated() {
            let allowed = keep[performed.exerciseId] ?? 0
            var sets = performed.sets
            var undone = sets.enumerated().filter { !$0.element.done }.map(\.offset)

            // Completed sets are history and are never removed — only the ones
            // still to do can be trimmed.
            while undone.count > allowed, let last = undone.popLast() {
                sets.remove(at: last)
            }
            appState.sessions[index].exercises[exerciseIndex].sets = sets
        }

        appState.save()
        HapticManager.success()
        dismiss()
    }

    private func replaceExercise(_ from: Exercise, for to: Exercise) {
        guard let session,
              let index = appState.sessions.firstIndex(where: { $0.id == session.id }),
              let exerciseIndex = appState.sessions[index].exercises
                .firstIndex(where: { $0.exerciseId == from.id }) else { return }

        appState.sessions[index].exercises[exerciseIndex].exerciseId = to.id

        // Swapping mid-session is the clearest preference signal the app ever
        // gets: one exercise refused with another in front of you, and one
        // chosen over five alternatives.
        appState.recordFeedback(.dismissed, source: .substitution, exerciseId: from.id)
        appState.recordFeedback(.accepted, source: .substitution, exerciseId: to.id)
        // The load was for the old movement. Carrying it over would put one
        // exercise's numbers on another's bar.
        for setIndex in appState.sessions[index].exercises[exerciseIndex].sets.indices
        where !appState.sessions[index].exercises[exerciseIndex].sets[setIndex].done {
            appState.sessions[index].exercises[exerciseIndex].sets[setIndex].weight = 0
        }

        appState.save()
        HapticManager.success()
        dismiss()
    }
}
