import SwiftUI

// MARK: - Deload Sheet

/// An easier week, proposed in numbers.
///
/// Every routine in the active programme is shown before and after, because
/// "take a deload" is unactionable advice and "three sets instead of four, 10%
/// lighter, stopping two reps short" is something a person can look at and
/// disagree with.
///
/// Applying rewrites the routines for the week. That is a real change to saved
/// data, so it happens once, on a button, under a visible diff — and the sheet
/// says plainly that putting the numbers back afterwards is manual, because it
/// is.
struct DeloadSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let proposal: DeloadEngine.Proposal

    @State private var applied = false

    /// The routines a deload would touch: the active programme's, or all of
    /// them when there is no programme.
    private var routines: [Routine] {
        guard let programme = appState.activeProgram else { return appState.routines }
        let ids = Set(programme.days.compactMap(\.routineId))
        let matching = appState.routines.filter { ids.contains($0.id) }
        return matching.isEmpty ? appState.routines : matching
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    evidence
                    changes
                    caveat
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("A lighter week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(applied ? "Done" : "Not now") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !applied { applyBar }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(proposal.summary)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Based on \(proposal.weeksOfHistory) weeks of training and \(proposal.signals.count) separate signs — never on one bad session.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHY")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            ForEach(proposal.evidence, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color(.tertiaryLabel))
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT CHANGES")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(routines) { routine in
                let after = DeloadEngine.deloaded(routine.exercises, proposal: proposal)
                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.name)
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(zip(routine.exercises, after)), id: \.0.id) { before, updated in
                        HStack(spacing: 8) {
                            Text(name(of: before))
                                .font(.caption)
                                .foregroundColor(.primary)
                            Spacer(minLength: 0)
                            Text(description(before))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(Color(.tertiaryLabel))
                                .accessibilityHidden(true)
                            Text(description(updated))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(AppTheme.trainAccent)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var caveat: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reps stay where they are — fewer sets and less load already make the week easier, and cutting reps as well turns a deload into a week off.")
            Text("Putting the numbers back next week is manual. The app won't quietly restore them.")
        }
        .font(.caption)
        .foregroundColor(Color(.tertiaryLabel))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var applyBar: some View {
        Button {
            apply()
        } label: {
            Text("Apply to \(routines.count) routine\(routines.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.brandGradient)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(routines.isEmpty)
        .padding(16)
        .background(.regularMaterial)
    }

    // MARK: Helpers

    private func name(of item: RoutineExercise) -> String {
        appState.exercises.first { $0.id == item.exerciseId }?.name ?? "Exercise"
    }

    private func description(_ item: RoutineExercise) -> String {
        item.defaultWeight > 0
            ? "\(item.defaultSets)×\(item.repRangeMin)–\(item.repRangeMax) @ \(item.defaultWeight.formatted1)kg"
            : "\(item.defaultSets)×\(item.repRangeMin)–\(item.repRangeMax)"
    }

    /// The one write, on a tap, after the diff.
    private func apply() {
        for routine in routines {
            appState.updateRoutine(
                id: routine.id,
                exercises: DeloadEngine.deloaded(routine.exercises, proposal: proposal)
            )
        }
        HapticManager.success()
        applied = true
    }
}
