import SwiftUI

// MARK: - Coach Explanation Sheet

/// Why the coach said what it said.
///
/// The card has room for one sentence of reasoning. This has room for the rest,
/// and the rest is what makes the suggestion checkable rather than something to
/// be taken on faith: which figures were used, where each came from, what was
/// missing, and when it was worked out.
///
/// A suggestion you can audit is one you can disagree with, which is the only
/// way the coach earns trust it should have and loses trust it shouldn't.
struct CoachExplanationSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let recommendation: CoachRecommendation
    let context: CoachContext

    @State private var feedback: Feedback?

    enum Feedback: String { case useful, notUseful }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headline
                    if let notice = recommendation.safetyNotice {
                        SafetyNotice(text: notice)
                    }
                    evidenceSection
                    sourcesSection
                    warningsSection
                    generatedSection
                    feedbackSection
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Why this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done")
                }
            }
        }
    }

    // MARK: Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recommendation.headline)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(recommendation.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CoachConfidenceBadge(confidence: recommendation.confidence)
        }
    }

    @ViewBuilder
    private var evidenceSection: some View {
        ExplanationCard(title: "What this is based on", icon: "list.bullet.rectangle") {
            if recommendation.evidence.isEmpty {
                // An empty list is said out loud rather than left as a blank
                // space, because "no stated reason" is itself worth knowing.
                Text("No specific figures were cited for this one.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(recommendation.evidence) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.label)
                            .font(.footnote.weight(.semibold))
                            .frame(width: 96, alignment: .leading)
                        Text(item.explanation)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var sourcesSection: some View {
        ExplanationCard(title: "Where the numbers came from", icon: "antenna.radiowaves.left.and.right") {
            if let source = context.activity?.source {
                ExplanationRow(label: "Activity", value: source)
            }
            if context.sleep != nil {
                ExplanationRow(label: "Sleep", value: sleepQualityText)
            }
            if context.recovery != nil {
                ExplanationRow(label: "Recovery", value: recoveryQualityText)
            }
            ExplanationRow(
                label: "Wording",
                value: recommendation.origin == .cloud
                    ? "Written by Gemini from the figures above"
                    : "Written by Life on this phone, no AI involved"
            )
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        if !context.dataWarnings.isEmpty {
            ExplanationCard(title: "What was missing", icon: "exclamationmark.circle") {
                ForEach(context.dataWarnings, id: \.self) { warning in
                    Text("• " + warning)
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Gaps are stated rather than filled in. A missing reading is never counted as a zero.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var generatedSection: some View {
        ExplanationCard(title: "When", icon: "clock") {
            ExplanationRow(
                label: "Worked out",
                value: recommendation.generatedAt.formatted(date: .abbreviated, time: .shortened)
            )
            Text("Figures are only as fresh as your last sync.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        ExplanationCard(title: "Was this useful?", icon: "hand.thumbsup") {
            HStack(spacing: 12) {
                FeedbackButton(
                    title: "Useful",
                    icon: "hand.thumbsup.fill",
                    isSelected: feedback == .useful
                ) { feedback = .useful; HapticManager.impact(.light) }

                FeedbackButton(
                    title: "Not useful",
                    icon: "hand.thumbsdown.fill",
                    isSelected: feedback == .notUseful
                ) { feedback = .notUseful; HapticManager.impact(.light) }
            }
            if feedback != nil {
                // Honest about what it does. Pretending a thumbs-down retrains
                // something would be a nicer sentence and a false one.
                Text("Noted. This is kept on your phone and isn't sent anywhere.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Helpers

    private var sleepQualityText: String {
        guard let sleep = context.sleep else { return "Not recorded" }
        switch sleep.quality {
        case .verified: return "Fully recorded"
        case .partial:  return "Partly recorded"
        case .suspect:  return "Recorded, but looks off"
        case .missing:  return "Not recorded"
        }
    }

    private var recoveryQualityText: String {
        guard let recovery = context.recovery else { return "Not recorded" }
        return recovery.quality == .verified
            ? "HRV and resting heart rate, against your own baselines"
            : "Partly recorded — only some signals available"
    }
}

// MARK: - Components

private struct ExplanationCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct ExplanationRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.footnote)
            Spacer(minLength: 12)
            Text(value)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct FeedbackButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.footnote.weight(.medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.primary : Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
