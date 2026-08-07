import SwiftUI

// MARK: - Swap Exercise Sheet

/// Pick something else for this slot.
///
/// The candidate list is `SubstitutionEngine`'s, which means it is built from
/// the user's own library by deterministic rules and shows *why* each one is a
/// reasonable stand-in. No model is involved and none needs to be: the question
/// "what else trains this muscle with the equipment I have" is one the app can
/// answer exactly.
struct SwapExerciseSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let replacing: Exercise
    /// Already in this workout, so nothing is offered twice.
    var idsInWorkout: Set<String> = []
    var onChoose: (Exercise) -> Void

    private var candidates: [SubstitutionEngine.Candidate] {
        SubstitutionEngine.candidates(
            for: SubstitutionEngine.Request(
                replacing: replacing,
                library: appState.exercises,
                idsInWorkout: idsInWorkout,
                trainedIds: Set(appState.completedWorkouts.flatMap { $0.exercises.map(\.exerciseId) }),
                favouriteIds: Set(appState.exercises.filter(\.isFavorite).map(\.id))
            )
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Swap \(replacing.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button {
                        onChoose(candidate.exercise)
                        dismiss()
                    } label: {
                        row(candidate)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Replaces \(replacing.name) with \(candidate.exercise.name).")
                }
            }
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .padding(16)
        }
    }

    private func row(_ candidate: SubstitutionEngine.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(candidate.exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
                Text(candidate.exercise.equipment.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Why it matches, and where it differs. Both shown — a substitution
            // list that only argues for itself is a list you can't judge.
            ForEach(candidate.reasons.prefix(2), id: \.self) { reason in
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(candidate.differences.prefix(2), id: \.self) { difference in
                Text(difference)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("Nothing in your library stands in for \(replacing.name).")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Adding one from the exercise library — or scanning a machine — gives this something to offer.")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
