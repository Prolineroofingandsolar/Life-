import SwiftUI

// MARK: - Coach Briefing

/// The morning briefing and the evening review.
///
/// One a day each, and cached by day rather than by data: a briefing is a
/// statement about a morning, and regenerating it at eleven because the step
/// count moved would produce a second, different briefing about the same
/// morning. It is meant to be read once.
struct CoachBriefingView: View {

    @Environment(AppState.self) private var appState

    let kind: CoachBriefing.Kind

    @State private var briefing: CoachBriefing?
    @State private var isLoading = false

    private var service: CoachService { CoachService() }
    private var settings: CoachSettings { appState.coachSettings }

    private var context: CoachContext {
        CoachContextBuilder.build(appState: appState, permissions: .init(settings))
    }

    /// The hour a morning briefing may first appear.
    ///
    /// `hour < 12` alone put "Good morning — you slept 8h 28m" on screen at
    /// 12:02 AM, two minutes into a day the person hadn't slept through yet,
    /// describing the night before last. Midnight to four is the end of the
    /// previous day by any reasonable reading, and a briefing then is wrong
    /// twice over: wrong greeting, and last night's sleep hasn't happened.
    private static let morningStartHour = 4

    /// Whether this briefing belongs on screen at all.
    ///
    /// Time-gated as well as switch-gated: an evening review at nine in the
    /// morning is a review of nothing, and a morning briefing at bedtime has
    /// been overtaken by the day it describes.
    private var isDue: Bool {
        guard settings.enabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        switch kind {
        case .morning:
            return settings.morningBriefingEnabled
                && hour >= Self.morningStartHour
                && hour < 12
        case .evening:
            // Runs to midnight and no further. After that it's tomorrow's
            // small hours, and neither briefing belongs on screen.
            return settings.eveningReviewEnabled && hour >= 18
        }
    }

    var body: some View {
        Group {
            if isDue {
                card
            }
        }
        .task(id: kind) {
            guard isDue else { return }
            isLoading = true
            briefing = await service.briefing(kind: kind, context: context, settings: settings)
            isLoading = false
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: kind == .morning ? "sun.horizon.fill" : "moon.stars.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(kind == .morning ? .orange : .indigo)
                    .accessibilityHidden(true)
                Text(kind == .morning ? "Morning briefing" : "Evening review")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if isLoading && briefing == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Putting it together…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if let briefing {
                Text(briefing.headline)
                    .font(.system(size: 17, weight: .semibold))
                Text(briefing.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let notice = briefing.safetyNotice {
                    SafetyNotice(text: notice)
                }

                Text(briefing.origin == .cloud ? "AI coach" : "Life's own rules")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}
