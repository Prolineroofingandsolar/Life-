import SwiftUI

// MARK: - Plateau Sheet

/// A lift that has stopped moving, and some things to try.
///
/// What this screen will not do is tell you why. The app doesn't know, the
/// model doesn't know, and the honest version of that sentence is on the card
/// rather than left implied — because an app that says "you may be
/// overtrained" has made a medical claim out of four numbers.
struct PlateauSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let finding: PlateauEngine.Finding
    /// Substituting is a real change, so it happens where substitutions
    /// normally happen. This sheet only opens it.
    var onSubstitute: ((Exercise) -> Void)?

    @State private var advice: PlateauAdvice?
    @State private var provenance: CoachProvenance?

    private var settings: CoachSettings { appState.coachSettings }
    private var service: WorkoutBuilderService { WorkoutBuilderService() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    evidence
                    if let advice {
                        remedies(advice)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                    if let provenance {
                        CoachProvenanceLabel(provenance: provenance)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Stalled lift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.exerciseName)
                .font(.title3.weight(.bold))
            Text("\(finding.startWeight.formatted1)kg → \(finding.currentWeight.formatted1)kg over \(finding.weeks) weeks")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(finding.evidence, id: \.self) { line in
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

    private func remedies(_ advice: PlateauAdvice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(advice.explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(advice.remedies.enumerated()), id: \.element) { index, remedy in
                    if index > 0 { Divider().padding(.leading, 16) }
                    remedyRow(remedy)
                }
            }
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Said outright, because the absence of a reason is the most
            // conspicuous thing about this screen.
            Text("Why it stalled isn't something the app can tell you. Sleep, stress, technique, a busy month — these are the usual things to try, not a diagnosis.")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func remedyRow(_ remedy: PlateauAdvice.Remedy) -> some View {
        let exercise = appState.exercises.first { $0.id == finding.exerciseId }

        if remedy == .substitute, let exercise, onSubstitute != nil {
            Button {
                onSubstitute?(exercise)
                dismiss()
            } label: {
                row(remedy, showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            row(remedy, showsChevron: false)
        }
    }

    private func row(_ remedy: PlateauAdvice.Remedy, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Text(remedy.label)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        guard advice == nil else { return }
        let context = CoachContextBuilder.build(
            appState: appState,
            permissions: .init(settings),
            snapshot: appState.healthSnapshot
        )
        let result = await service.plateauAdvice(
            for: finding, context: context, settings: settings
        )
        advice = result.advice
        provenance = result.provenance
    }
}
