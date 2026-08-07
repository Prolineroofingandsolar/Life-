import SwiftUI

// MARK: - Progression Review

/// Before and after, with the evidence, and three ways out.
///
/// Accept applies the proposal to the routine's stored prescription. Edit lets
/// the number be changed first. Dismiss leaves everything as it was. Nothing
/// here happens on appearance — the same rule as every other AI-adjacent surface
/// in this app, except that here the decision underneath came from rules rather
/// than a model, and the sheet says so.
struct ProgressionReviewSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let proposals: [ProgressionEngine.Proposal]

    /// Per-exercise overrides, so Edit changes one row without re-deciding the
    /// others.
    @State private var editedWeights: [String: Double] = [:]
    @State private var editedReps: [String: Int] = [:]
    @State private var accepted: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let review { summaryCard(review) }
                    explanation

                    ForEach(proposals) { proposal in
                        ProposalRow(
                            proposal: proposal,
                            weight: binding(for: proposal, keyPath: \.proposedWeight),
                            reps: repsBinding(for: proposal),
                            isAccepted: accepted.contains(proposal.exerciseId),
                            onAccept: { accept(proposal) }
                        )
                    }

                    Text("Accepting updates the sets and reps saved on the routine. Your finished workout isn't changed.")
                        .font(.caption)
                        .foregroundColor(Color(.tertiaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Next time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") { dismissAll() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept all") { acceptAll() }
                        .disabled(accepted.count == proposals.count)
                }
            }
        }
    }

    /// How the session went, in three lines at most.
    ///
    /// Computed from the session itself — no model call. This runs after every
    /// workout, and paying for one to rephrase four numbers the app already
    /// knows would be a standing cost for nothing.
    private var review: PostWorkoutReview.Review? {
        let finished = appState.completedWorkouts
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        guard let session = finished.first else { return nil }
        return PostWorkoutReview.review(
            PostWorkoutReview.input(for: session, appState: appState)
        )
    }

    private func summaryCard(_ review: PostWorkoutReview.Review) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            line("checkmark.circle.fill", AppTheme.trainAccent, review.success)
            if let attention = review.attention {
                line("exclamationmark.circle", .orange, attention)
            }
            if let next = review.nextAction {
                line("arrow.turn.down.right", .secondary, next)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func line(_ icon: String, _ colour: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(colour)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "function")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("Worked out from your last session's sets and reps — not from a model.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemFill).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Bindings

    private func binding(
        for proposal: ProgressionEngine.Proposal,
        keyPath: KeyPath<ProgressionEngine.Proposal, Double>
    ) -> Binding<Double> {
        Binding(
            get: { editedWeights[proposal.exerciseId] ?? proposal[keyPath: keyPath] },
            set: { editedWeights[proposal.exerciseId] = $0 }
        )
    }

    private func repsBinding(for proposal: ProgressionEngine.Proposal) -> Binding<Int> {
        Binding(
            get: { editedReps[proposal.exerciseId] ?? proposal.proposedReps },
            set: { editedReps[proposal.exerciseId] = $0 }
        )
    }

    // MARK: Applying

    private func accept(_ proposal: ProgressionEngine.Proposal) {
        let weight = editedWeights[proposal.exerciseId] ?? proposal.proposedWeight
        let reps = editedReps[proposal.exerciseId] ?? proposal.proposedReps

        appState.applyProgression(
            exerciseId: proposal.exerciseId,
            weight: weight,
            reps: reps
        )
        accepted.insert(proposal.exerciseId)

        // Recorded so the app learns from it. An accepted-as-proposed number is
        // an endorsement; an edited one says the proposal was in the right
        // direction and the wrong size, and `TrainingMemory` weighs the two
        // differently.
        let wasEdited = weight != proposal.proposedWeight || reps != proposal.proposedReps
        appState.recordFeedback(
            wasEdited ? .edited : .accepted,
            source: .progression,
            exerciseId: proposal.exerciseId
        )

        HapticManager.success()
    }

    /// Dismissing is an answer too, and the app should hear it.
    private func dismissAll() {
        for proposal in proposals where !accepted.contains(proposal.exerciseId) {
            appState.recordFeedback(
                .dismissed, source: .progression, exerciseId: proposal.exerciseId
            )
        }
        dismiss()
    }

    private func acceptAll() {
        for proposal in proposals where !accepted.contains(proposal.exerciseId) {
            accept(proposal)
        }
        dismiss()
    }
}

// MARK: - Row

private struct ProposalRow: View {

    let proposal: ProgressionEngine.Proposal
    @Binding var weight: Double
    @Binding var reps: Int
    let isAccepted: Bool
    let onAccept: () -> Void

    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.exerciseName)
                        .font(.subheadline.weight(.semibold))
                    Text(proposal.action.headline)
                        .font(.caption)
                        .foregroundColor(AppTheme.primary)
                }
                Spacer()
                if isAccepted {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                        .labelStyle(.titleAndIcon)
                }
            }

            // Before → after, always both sides, whatever the outcome.
            HStack(spacing: 12) {
                valueBlock(
                    title: "Last time",
                    weight: proposal.currentWeight,
                    reps: proposal.currentReps,
                    muted: true
                )
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
                valueBlock(title: "Next time", weight: weight, reps: reps, muted: false)
            }

            ForEach(proposal.evidence, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(Color(.tertiaryLabel))
                        .frame(width: 3, height: 3)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isEditing {
                VStack(spacing: 6) {
                    if proposal.currentWeight > 0 {
                        Stepper("Weight: \(weight.weightDisplay) kg", value: $weight, in: 0...500, step: 1.25)
                            .font(.caption)
                    }
                    Stepper("Reps: \(reps)", value: $reps, in: 1...50)
                        .font(.caption)
                }
            }

            if !isAccepted {
                HStack(spacing: 16) {
                    Button("Accept", action: onAccept)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.primary)
                    Button(isEditing ? "Done editing" : "Edit") { isEditing.toggle() }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func valueBlock(title: String, weight: Double, reps: Int, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Color(.tertiaryLabel))
            Text(weight > 0 ? "\(weight.weightDisplay) kg × \(reps)" : "\(reps) reps")
                .font(.subheadline.weight(muted ? .regular : .semibold))
                .foregroundColor(muted ? .secondary : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
