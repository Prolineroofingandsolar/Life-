import SwiftUI

// MARK: - Coach Briefing

/// The morning briefing and the evening review, as a *Daily insight* entry
/// rather than a second card competing with "Do this next".
///
/// One a day each, and cached by day rather than by data: a briefing is a
/// statement about a morning, and regenerating it at eleven because the step
/// count moved would produce a second, different briefing about the same
/// morning. It is meant to be read once.
///
/// Collapsed by default for the same reason it moved down the page. Two
/// full-width cards of prose at the top of Today is one card of prose too many,
/// and the recommendation is the one worth reading first. Expanding is one tap;
/// the headline is visible without it.
struct CoachBriefingView: View {

    @Environment(AppState.self) private var appState

    let kind: CoachBriefing.Kind

    @State private var outcome: CoachService.BriefingOutcome?
    @State private var isLoading = false
    @State private var isExpanded = false
    /// Set once the briefing has been requested for this day, so a failure
    /// isn't retried every time the view reappears. The brief forbids
    /// continuous retry on appearance, and a failing endpoint would otherwise
    /// be called once per scroll.
    @State private var loadedForDay: String?

    private var service: CoachService { CoachService() }
    private var settings: CoachSettings { appState.coachSettings }

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
        // Keyed on the day as well as the kind, so the briefing rolls over at
        // midnight without the view having to be recreated.
        .task(id: "\(kind.rawValue)|\(appState.healthSnapshot.dayKey)") {
            await load()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureRow

            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    /// The whole row is the control, and it says what it is and what it does.
    ///
    /// Previously the card had no control at all and the chevron-shaped
    /// affordances elsewhere on the page were decoration. VoiceOver gets one
    /// element with the title, the headline, the button trait and the expanded
    /// state — not a chevron announced as "chevron down".
    private var disclosureRow: some View {
        Button {
            isExpanded.toggle()
            HapticManager.selection()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind == .morning ? "sun.horizon.fill" : "moon.stars.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(kind == .morning ? .orange : .indigo)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Daily insight")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(summaryLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : 1)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily insight. \(summaryLine)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Collapses the insight" : "Expands the insight")
    }

    /// One line, whatever state the briefing is in.
    private var summaryLine: String {
        if let outcome { return outcome.briefing.headline }
        if appState.isSyncingHealth { return "Updating health data…" }
        if isLoading { return settings.mayUseCloud ? "Asking Gemini…" : "Putting it together…" }
        return kind == .morning ? "Morning briefing" : "Evening review"
    }

    @ViewBuilder
    private var expandedBody: some View {
        if let outcome {
            Text(outcome.briefing.body)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // The briefing stands for the day, but the figures behind it may
            // have been corrected since — a late sync bringing in last night's
            // sleep, say. Saying so is the difference between a briefing that
            // is a little behind and one that is quietly wrong.
            if outcome.isOutdated {
                DataCaveatRow(
                    text: "Your health figures have been updated since this was written. The Health tab has the current ones."
                )
            }

            if let notice = outcome.briefing.safetyNotice {
                SafetyNotice(text: notice)
            }

            CoachProvenanceLabel(provenance: outcome.provenance) {
                Task { await load(force: true) }
            }
        } else if isLoading {
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBar(widthFraction: 0.95, height: 12)
                SkeletonBar(widthFraction: 0.8, height: 12)
            }
            .frame(minHeight: 40, alignment: .top)
        } else {
            Text("Nothing to summarise yet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func load(force: Bool = false) async {
        guard isDue else { return }

        let snapshot = appState.healthSnapshot
        // One request per day per kind. `.task(id:)` re-fires whenever the day
        // key changes — which is what it should do — but it also re-fires when
        // the view is rebuilt, and a failed call retried on every rebuild is
        // exactly the behaviour the brief rules out.
        if !force, loadedForDay == snapshot.dayKey, outcome != nil { return }

        isLoading = true
        defer { isLoading = false }

        let context = CoachContextBuilder.build(
            appState: appState,
            permissions: .init(settings),
            snapshot: snapshot
        )
        outcome = await service.briefing(
            kind: kind, context: context, settings: settings, snapshot: snapshot
        )
        loadedForDay = snapshot.dayKey
    }
}
