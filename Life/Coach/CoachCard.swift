import SwiftUI

// MARK: - Coach Card

/// The coach's one place on the Today screen.
///
/// One recommendation, one reason, one button. The brief's "do not overcrowd
/// the Today screen" is the constraint, but it's also the point: a coach that
/// lists five things has decided nothing, and deciding is the only thing it
/// adds over the numbers already on this screen. Everything else — the
/// evidence, the sources, the caveats — lives one tap away behind "Why?".
struct CoachCard: View {

    @Environment(AppState.self) private var appState

    @State private var outcome: CoachService.Outcome?
    @State private var isLoading = false
    @State private var showExplanation = false
    @State private var showConsent = false
    @State private var showAsk = false
    @State private var appliedMessage: String?

    /// Rebuilt from the service each time the underlying data changes, which
    /// the cache turns into a free lookup when nothing material has moved.
    private var service: CoachService { CoachService() }

    private var settings: CoachSettings { appState.coachSettings }

    /// The context this card last loaded from, kept so the sheets can show the
    /// same figures the recommendation was made from.
    @State private var context: CoachContext?

    /// A cheap stand-in for "has anything the coach cares about changed".
    ///
    /// Driving `.task(id:)` off `materialHash` would rebuild the entire context
    /// and run a SHA-256 over it on *every* evaluation of `body` — which
    /// SwiftUI does freely, and which would make scrolling the Today screen do
    /// cryptography. This is a handful of counts, and the real hash is computed
    /// once inside the load it triggers.
    private var refreshToken: String {
        let steps = appState.careDays[appState.todayKey]?.steps ?? 0
        let outstanding = appState.tasks.reduce(into: 0) { $0 += $1.done ? 0 : 1 }
        return "\(appState.todayKey)|\(steps)|\(outstanding)|\(appState.habits.count)|\(appState.healthDays.count)|\(settings.mayUseCloud)"
    }

    var body: some View {
        Group {
            if settings.enabled {
                card
            }
        }
        .sheet(isPresented: $showExplanation) {
            if let outcome, let context {
                CoachExplanationSheet(recommendation: outcome.recommendation, context: context)
            }
        }
        .sheet(isPresented: $showConsent) {
            CoachConsentView { accepted in
                // Accepting is a material change to what's possible, so the
                // recommendation is refreshed rather than left as the local one
                // produced a moment ago.
                if accepted { Task { await load(force: true) } }
            }
        }
        .sheet(isPresented: $showAsk) {
            AskCoachView()
        }
        .task(id: refreshToken) {
            await load()
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isLoading && outcome == nil {
                loadingRow
            } else if let outcome {
                content(for: outcome)
            }
        }
        .padding(16)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: outcome?.recommendation.headline)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.brandGradient)
                .accessibilityHidden(true)
            Text("Your next best action")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                showAsk = true
            } label: {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask the coach a question")
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Working out what matters today…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(for outcome: CoachService.Outcome) -> some View {
        let recommendation = outcome.recommendation

        Text(recommendation.headline)
            .font(.system(size: 19, weight: .bold))
            .fixedSize(horizontal: false, vertical: true)

        Text(recommendation.summary)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        // Shown only when it should temper what's above. A "high confidence"
        // badge on every card is decoration; a "based on partial data" badge on
        // the one that needs it is information.
        if recommendation.confidence != .high {
            CoachConfidenceBadge(confidence: recommendation.confidence)
        }

        if let notice = recommendation.safetyNotice {
            SafetyNotice(text: notice)
        }

        if let message = appliedMessage {
            Text(message)
                .font(.caption)
                .foregroundColor(.green)
                .transition(.opacity)
        }

        actionRow(for: recommendation)
        provenanceLine(for: outcome)
    }

    @ViewBuilder
    private func actionRow(for recommendation: CoachRecommendation) -> some View {
        HStack(spacing: 10) {
            if let title = primaryActionTitle(for: recommendation) {
                Button {
                    apply(recommendation)
                } label: {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(AppTheme.brandGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityHint("Applies this suggestion")
            }

            Button("Why?") { showExplanation = true }
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppTheme.primary)
                .accessibilityLabel("Why this suggestion?")
                .accessibilityHint("Shows the figures behind it")

            Spacer()

            Button("Not today") { dismissToday() }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityHint("Hides this suggestion until something changes")
        }
        .padding(.top, 2)
    }

    /// When the figures were produced and where the words came from.
    ///
    /// The brief asks for a source timestamp; naming the origin matters as
    /// much. Presenting a rule-based line as though a model wrote it would be a
    /// small lie told on every card that failed to reach the network.
    @ViewBuilder
    private func provenanceLine(for outcome: CoachService.Outcome) -> some View {
        let recommendation = outcome.recommendation
        let origin = recommendation.origin == .cloud ? "AI coach" : "Life's own rules"
        let time = recommendation.generatedAt.formatted(date: .omitted, time: .shortened)

        VStack(alignment: .leading, spacing: 2) {
            Text("\(origin) · \(time)")
                .font(.caption2)
                .foregroundColor(Color(.tertiaryLabel))
            if let note = outcome.note {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !settings.mayUseCloud && settings.enabled {
                Button("Turn on AI coaching") { showConsent = true }
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppTheme.primary)
            }
        }
    }

    // MARK: Actions

    /// The button's words, or nil when there is nothing to press.
    ///
    /// `.none` and advice-shaped actions get no button rather than a disabled
    /// one — "you're on track" needs acknowledging, not doing.
    private func primaryActionTitle(for recommendation: CoachRecommendation) -> String? {
        switch recommendation.actionType {
        case .completeTask:    return "Mark done"
        case .completeHabit:   return "Log it"
        case .doPlannedWorkout: return "Start"
        case .scheduleTask, .rescheduleTask: return "Move to today"
        case .logMissingData:  return "Check data"
        case .reviewGoal:      return "Review"
        case .takeWalk, .rest, .reduceWorkoutIntensity, .none: return nil
        }
    }

    /// Applies the suggestion — and only ever because the user pressed it.
    ///
    /// The brief forbids the coach modifying anything on its own, so nothing
    /// here runs automatically. This is the explicit action.
    private func apply(_ recommendation: CoachRecommendation) {
        guard let id = recommendation.relatedItemId else {
            // Actions with no target just navigate; nothing to change.
            if recommendation.actionType == .logMissingData || recommendation.actionType == .reviewGoal {
                appliedMessage = nil
            }
            return
        }

        switch recommendation.actionType {
        case .completeTask:
            appState.toggleTask(id: id)
            appliedMessage = "Marked done."
        case .completeHabit:
            appState.logHabit(id: id)
            appliedMessage = "Logged."
        default:
            return
        }

        HapticManager.success()
        // The state has changed, so the advice should too. The context hash
        // moves with it and `.task(id:)` reloads.
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            appliedMessage = nil
        }
    }

    private func dismissToday() {
        if let context { CoachCache.shared.dismiss(context) }
        outcome = nil
        HapticManager.impact(.light)
    }

    private func load(force: Bool = false) async {
        guard settings.enabled else { return }
        if force { CoachCache.shared.clear() }
        isLoading = true
        // Built once here rather than on every render — see `refreshToken`.
        let built = CoachContextBuilder.build(appState: appState, permissions: .init(settings))
        context = built
        outcome = await service.recommendation(for: built, settings: settings)
        isLoading = false
    }
}

// MARK: - Shared components

/// Says how much to trust the line above it, in words rather than a number.
struct CoachConfidenceBadge: View {
    let confidence: CoachConfidence

    private var text: String {
        switch confidence {
        case .low:    return "Based on limited data"
        case .medium: return "Based on partial data"
        case .high:   return "Based on complete data"
        }
    }

    private var colour: Color {
        switch confidence {
        case .low:    return .orange
        case .medium: return .secondary
        case .high:   return .green
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(colour)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// Never subdued and never collapsed. If the coach has raised something worth
/// seeing a professional about, it is the most important thing on the card.
struct SafetyNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Important: \(text)")
    }
}
