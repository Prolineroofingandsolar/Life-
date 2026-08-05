import SwiftUI

// MARK: - Coach Consent

/// Shown once, before anything is ever sent.
///
/// Written to be read rather than dismissed. It names the categories that
/// leave the device, the categories that never do, and the one thing people
/// most need to hear about a health app with an AI in it — that it is not
/// medical advice. Declining is a first-class outcome, not a dead end: the
/// coach still works from local rules, which is why the decline button says
/// what you get rather than just "No".
struct CoachConsentView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Called with true when accepted, so the caller can carry on with
    /// whatever it was about to do.
    var onDecision: ((Bool) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    sentSection
                    notSentSection
                    disclaimer
                    controlSection
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { decline() }
                        .accessibilityLabel("Not now")
                        .accessibilityHint("Keeps the coach working from local rules only")
                }
            }
            .safeAreaInset(edge: .bottom) {
                acceptBar
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.brandGradient)
                .accessibilityHidden(true)
            Text("Let the coach use AI?")
                .font(.title2.bold())
            Text("Life can send a short summary of your day to Google's Gemini to write your briefing and pick your next action. You can turn this off at any time.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sentSection: some View {
        ConsentCard(title: "What gets sent", icon: "arrow.up.circle.fill", colour: .orange) {
            ConsentRow("Sleep length, quality and how it compares to your usual")
            ConsentRow("Recovery signals, as words like “above your usual” rather than raw numbers")
            ConsentRow("Steps, active minutes and your goals")
            ConsentRow("Whether you have a workout planned and how much you've trained lately")
            ConsentRow("How many tasks and habits are outstanding")
            ConsentRow("A note of anything missing or partly recorded, so it doesn't guess")
        }
    }

    private var notSentSection: some View {
        ConsentCard(title: "What never leaves your phone", icon: "lock.fill", colour: .green) {
            ConsentRow("Your name, email or account details")
            ConsentRow("Raw health records from Apple Health or Fitbit")
            ConsentRow("Your location, photos or notes")
            ConsentRow("Your Fitbit or Google sign-in")
            ConsentRow("Task and habit names, unless you switch that on separately")
        }
    }

    private var disclaimer: some View {
        ConsentCard(title: "This is not medical advice", icon: "cross.case.fill", colour: .red) {
            Text("The coach gives general wellbeing suggestions from your own numbers. It can't diagnose anything and it doesn't know your medical history. If something is worrying you, speak to a doctor.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controlSection: some View {
        ConsentCard(title: "You stay in control", icon: "slider.horizontal.3", colour: AppTheme.primary) {
            ConsentRow("Turn AI off and the coach keeps working from your own data on this phone")
            ConsentRow("Choose which categories it may use")
            ConsentRow("Clear its history and everything it remembers, whenever you like")
            ConsentRow("There's a monthly spending cap you can't accidentally exceed")
        }
    }

    private var acceptBar: some View {
        VStack(spacing: 10) {
            Button {
                accept()
            } label: {
                Text("Use AI coaching")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.brandGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use AI coaching")
            .accessibilityHint("Allows the summary described above to be sent to Gemini")

            Button("Keep it on this phone only") { decline() }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityHint("The coach works from local rules and sends nothing")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    // MARK: Actions

    private func accept() {
        appState.setCoachSettings {
            $0.hasConsented = true
            $0.cloudEnabled = true
        }
        HapticManager.success()
        onDecision?(true)
        dismiss()
    }

    /// Declining records that the screen was *answered*, not that it was
    /// ignored — so it isn't shown again every time the card appears — while
    /// leaving the cloud switched off.
    private func decline() {
        appState.setCoachSettings {
            $0.hasConsented = true
            $0.cloudEnabled = false
        }
        onDecision?(false)
        dismiss()
    }
}

// MARK: - Components

private struct ConsentCard<Content: View>: View {
    let title: String
    let icon: String
    let colour: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colour)
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

private struct ConsentRow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
