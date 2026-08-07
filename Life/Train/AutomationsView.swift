import SwiftUI

// MARK: - Automations View

/// What the app is watching for, what it has found, and how to make it stop.
///
/// Two halves on purpose. The top is what ran and what it proposes; the bottom
/// is every automation with a switch beside it, including the ones that found
/// nothing — because "why did I get this?" and "how do I turn it off?" are the
/// two questions any automated suggestion has to be able to answer on the same
/// screen.
struct AutomationsView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var outcomes: [AutomationOutcome] = []
    @State private var dismissed: Set<String> = []
    @State private var showMemory = false

    /// Handed back to Train, which owns the sheets these open.
    var onOpen: (AutomationOutcome.Destination) -> Void

    private var settings: CoachSettings { appState.coachSettings }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    findings
                    switches
                    memoryLink
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Automations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { refresh() }
    }

    private var intro: some View {
        Text("These run on your device, on data that's already there. None of them changes anything on its own — each one opens a preview you approve or dismiss.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    // MARK: Findings

    @ViewBuilder
    private var findings: some View {
        let visible = outcomes.filter { !dismissed.contains($0.id) }
        VStack(alignment: .leading, spacing: 10) {
            Text("FOUND NOW")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            if visible.isEmpty {
                Text("Nothing to report. That's the usual state, and it's a good one.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(visible) { outcome in
                    outcomeCard(outcome)
                }
            }
        }
    }

    /// Everything the brief asks an automation to show, on one card.
    private func outcomeCard(_ outcome: AutomationOutcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: outcome.kind.icon)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.trainAccent)
                    .accessibilityHidden(true)
                Text(outcome.kind.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            detail("Why it ran", outcome.reason)
            detail("What it used", outcome.dataUsed)
            detail("Who wrote it", outcome.producedBy.label)
            detail("What it proposes", outcome.proposal)

            HStack(spacing: 10) {
                Button {
                    onOpen(outcome.destination)
                    dismiss()
                } label: {
                    Text("Review")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.brandGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button("Dismiss") { dismissed.insert(outcome.id) }
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Turn off") { disable(outcome.kind) }
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Switches

    private var switches: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT TO WATCH FOR")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(AutomationKind.allCases.enumerated()), id: \.element.id) { index, kind in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Toggle(isOn: binding(for: kind)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.subheadline)
                            Text(kind.explanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if kind.mayUseModel {
                                Text(settings.mayUseCloud
                                     ? "Uses Gemini when you open it."
                                     : "Uses the app's own rules — AI is off.")
                                    .font(.caption2)
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // The line that is true of every one of them, said once and plainly.
            Text("No automation can change your training without you approving it first. There is no setting for that.")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The learning layer is a different thing from the automations, and it
    /// lives one tap away rather than on this screen: one is what the app
    /// watches for, the other is what it has concluded about you.
    private var memoryLink: some View {
        Button {
            showMemory = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "brain")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.trainAccent)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What Life has learned about you")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text("Exercises you keep turning down, your own pace and load jumps.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMemory) { TrainingMemoryView() }
    }

    private func binding(for kind: AutomationKind) -> Binding<Bool> {
        Binding(
            get: { appState.coachSettings.isAutomationEnabled(kind) },
            set: { isOn in
                appState.setCoachSettings { settings in
                    var disabled = Set(settings.disabledAutomations)
                    if isOn {
                        disabled.remove(kind.rawValue)
                    } else {
                        disabled.insert(kind.rawValue)
                    }
                    settings.disabledAutomations = disabled.sorted()
                }
                refresh()
            }
        )
    }

    private func disable(_ kind: AutomationKind) {
        binding(for: kind).wrappedValue = false
    }

    private func refresh() {
        outcomes = AutomationRunner.run(
            appState: appState,
            enabled: settings.enabledAutomations
        )
    }
}
