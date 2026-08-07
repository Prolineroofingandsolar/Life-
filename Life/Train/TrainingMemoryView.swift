import SwiftUI

// MARK: - Training Memory View

/// What the app has learned about you, and how to make it forget.
///
/// Personalisation that can't be inspected is just an app behaving oddly. Every
/// figure here is traceable to specific taps and specific sessions, and the
/// button at the bottom deletes all of it — because something that changes what
/// you're prescribed should be something you can see and switch off.
struct TrainingMemoryView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showForgetConfirmation = false

    private var preferences: [String: Int] { TrainingMemory.preferences(appState: appState) }
    private var refused: Set<String> { TrainingMemory.refused(appState: appState) }
    private var pace: TrainingMemory.Pace { TrainingMemory.pace(appState: appState) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    preferenceSection
                    paceSection
                    incrementSection
                    forgetButton
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("What Life has learned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                "Forget everything?",
                isPresented: $showForgetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Forget it all", role: .destructive) {
                    appState.coachFeedback = []
                    appState.save()
                }
            } message: {
                Text("Suggestions go back to the defaults. Your workouts, routines and history are untouched.")
            }
        }
    }

    private var intro: some View {
        Text("Life adjusts what it suggests based on what you accept and turn down. Nothing here is a model's opinion — it's a count of your own taps.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    // MARK: Preferences

    @ViewBuilder
    private var preferenceSection: some View {
        let liked = preferences.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(5)
        let disliked = preferences.filter { $0.value < 0 }
            .sorted { $0.value < $1.value }
            .prefix(5)

        VStack(alignment: .leading, spacing: 10) {
            Text("EXERCISES")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            if liked.isEmpty && disliked.isEmpty {
                emptyRow("Nothing yet. Accept or dismiss a few suggestions and this fills in.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(liked), id: \.key) { id, score in
                        row(id, detail: "Suggested more often", score: score)
                    }
                    ForEach(Array(disliked), id: \.key) { id, score in
                        row(
                            id,
                            detail: refused.contains(id)
                                ? "No longer suggested — you've turned it down three times"
                                : "Suggested less often",
                            score: score
                        )
                    }
                }
                .background(AppTheme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func row(_ exerciseId: String, detail: String, score: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.exercises.first { $0.id == exerciseId }?.name ?? "An exercise")
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(score > 0 ? "+\(score)" : "\(score)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(score > 0 ? AppTheme.trainAccent : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Pace

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR PACE")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            if pace.isLearned {
                infoRow(
                    title: pace.factor > 1.05
                        ? "You take about \(Int((pace.factor - 1) * 100))% longer than the estimate"
                        : (pace.factor < 0.95
                            ? "You finish about \(Int((1 - pace.factor) * 100))% quicker than the estimate"
                            : "Your sessions run about as long as estimated"),
                    detail: "From \(pace.samples) sessions. Duration estimates and 'make this shorter' use this."
                )
            } else {
                // The distinction the whole app is built on: not learned yet is
                // not the same as no difference.
                emptyRow("Not enough finished sessions yet — using the standard estimate of three seconds a rep.")
            }
        }
    }

    // MARK: Increments

    @ViewBuilder
    private var incrementSection: some View {
        let learned = learnedIncrements()

        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR JUMPS")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            if learned.isEmpty {
                emptyRow("Once you've added weight to a lift a few times, Life uses your own step size instead of the default.")
            } else {
                VStack(spacing: 0) {
                    ForEach(learned, id: \.name) { item in
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Text("\(item.increment.formatted1)kg")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundColor(AppTheme.trainAccent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
                .background(AppTheme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    /// Only where the learned figure differs from the shipped default —
    /// listing "2.5kg, same as everyone" for twenty exercises would say nothing.
    private func learnedIncrements() -> [(name: String, increment: Double)] {
        var out: [(name: String, increment: Double)] = []
        for exercise in appState.exercises {
            let learned = TrainingMemory.increment(for: exercise, appState: appState)
            guard learned != ProgressionEngine.increment(for: exercise) else { continue }
            out.append((name: exercise.name, increment: learned))
        }
        return Array(out.sorted { $0.name < $1.name }.prefix(6))
    }

    // MARK: Shared

    private func infoRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var forgetButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Forget what you've learned") { showForgetConfirmation = true }
                .font(.subheadline)
                .foregroundColor(.red)
            Text("Feedback older than four months stops counting on its own, so this is rarely needed.")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
