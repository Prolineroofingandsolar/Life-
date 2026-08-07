import SwiftUI

// MARK: - Drift Review Sheet

/// "Your actual training no longer matches this programme."
///
/// The evidence comes first and takes up most of the screen, because the claim
/// is about the user's own behaviour and they are entitled to see the working.
/// The only button rebuilds — through the ordinary builder, with its own
/// questions and its own confirmation. There is no path from a drift signal to
/// a saved programme, and there deliberately never will be.
struct DriftReviewSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let signals: [DriftEngine.Signal]
    /// The host presents the builder. This sheet writes nothing at all.
    var onRebuild: (WorkoutBrief) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    ForEach(signals) { signal in
                        signalCard(signal)
                    }

                    note
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Programme check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { rebuildBar }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your training has drifted from your programme")
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Not a criticism — a programme that doesn't match what you do is just paperwork. Here's what the app has noticed.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func signalCard(_ signal: DriftEngine.Signal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(signal.headline)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(signal.evidence, id: \.self) { line in
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

    /// Says what "review" will and won't do, before it is tapped.
    private var note: some View {
        Text("Reviewing opens the builder with these corrections already filled in. You'll see the whole programme before anything is saved, and your current one stays exactly as it is until you replace it.")
            .font(.caption)
            .foregroundColor(Color(.tertiaryLabel))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rebuildBar: some View {
        VStack(spacing: 8) {
            Button {
                HapticManager.impact(.medium)
                onRebuild(DriftEngine.brief(from: signals))
                dismiss()
            } label: {
                Text("Review my programme")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.brandGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())

            Button("It's fine as it is") { dismiss() }
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(.regularMaterial)
    }
}
