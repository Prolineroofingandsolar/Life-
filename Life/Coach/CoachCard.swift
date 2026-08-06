import SwiftUI

// MARK: - Coach Card

/// The Today screen's one prominent action: "Do this next".
///
/// One recommendation, one primary button. The brief's "do not overcrowd the
/// Today screen" is the constraint, but it is also the point — a coach that
/// lists five things has decided nothing, and deciding is the only thing it adds
/// over the numbers already on this screen. Everything else — the evidence, the
/// sources, the caveats — lives one tap away behind "Why?".
///
/// What changed from the previous version, and why:
///
/// - **Provenance is never implied.** The card used to print "AI coach" over
///   output the rules had written after a failed call, so Gemini looked useless
///   and the fallback got the credit. `CoachProvenanceLabel` states which of the
///   four paths produced the words.
/// - **Loading is two different states.** "Updating health data…" and "Asking
///   Gemini…" take different lengths of time and mean different things, and the
///   skeleton reserves the height either way so the page doesn't jump when the
///   answer lands.
/// - **Data problems are shown here rather than inferred from odd advice.** A
///   disconnected tracker, a stale sync or a baseline that isn't ready yet each
///   get a plain sentence, because the alternative is advice that reads as wrong
///   for a reason the user can't see.
struct CoachCard: View {

    @Environment(AppState.self) private var appState

    @State private var outcome: CoachService.Outcome?
    @State private var isAsking = false
    @State private var showExplanation = false
    @State private var showConsent = false
    @State private var showAsk = false
    @State private var appliedMessage: String?

    /// Rebuilt from the service each time the underlying data changes, which
    /// the cache turns into a free lookup when nothing material has moved.
    private var service: CoachService { CoachService() }

    private var settings: CoachSettings { appState.coachSettings }

    /// The context and snapshot this card last loaded from, kept so the sheets
    /// show the same figures the recommendation was made from — and so a
    /// dismissal is keyed to the right data.
    @State private var context: CoachContext?
    @State private var snapshot: HealthSnapshot?

    /// A cheap stand-in for "has anything the coach cares about changed".
    ///
    /// Driving `.task(id:)` off `materialHash` would rebuild the entire context
    /// and run a SHA-256 over it on *every* evaluation of `body` — which
    /// SwiftUI does freely, and which would make scrolling the Today screen do
    /// cryptography. This is a handful of counts and one timestamp; the real
    /// hash is computed once inside the load it triggers, and the cache absorbs
    /// the cost of a rebuild that turns out to change nothing.
    ///
    /// It errs towards rebuilding. Every material input the cache keys on is
    /// represented here at least indirectly, because a token that misses a
    /// change leaves stale advice on screen, while a token that fires too often
    /// costs one cache lookup.
    private var refreshToken: String {
        let completedToday = appState.completedWorkouts.reduce(into: 0) {
            $0 += $1.startedAt.dayKey == appState.todayKey ? 1 : 0
        }
        let outstanding = appState.tasks.reduce(into: 0) { $0 += $1.done ? 0 : 1 }
        let habitLogs = appState.habits.reduce(into: 0) { total, habit in
            total += habit.logs.contains { $0.dayKey == appState.todayKey } ? 1 : 0
        }
        let plannedToday = appState.plannedSessions.reduce(into: 0) {
            $0 += (!$1.completed && $1.date.dayKey == appState.todayKey) ? 1 : 0
        }
        return [
            appState.healthSnapshotToken,
            "\(outstanding)", "\(habitLogs)", "\(appState.habits.count)",
            "\(completedToday)", "\(plannedToday)",
            "\(appState.activeSession != nil)",
            "\(appState.careSettings.stepGoal)", "\(appState.healthSettings.sleepGoalMinutes)",
            "\(appState.healthSettings.exerciseGoalMinutes)",
            "\(settings.enabled)", "\(settings.mayUseCloud)",
            settings.permissionsToken
        ].joined(separator: "|")
    }

    var body: some View {
        // The master switch means no coach at all — not a greyed-out card, and
        // not a local suggestion under a different label. `CoachSettings.enabled`
        // is documented as "no coach at all, not even local suggestions", and a
        // UI test holds that line.
        //
        // Cloud AI being off is a different setting and a different state: the
        // card stays, the suggestion comes from the rules, and the provenance
        // line says "On-device suggestion" rather than implying a model wrote it.
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
                    // recommendation is refreshed rather than left as the local
                    // one produced a moment ago.
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

            if let outcome {
                content(for: outcome)
            } else {
                loadingSkeleton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        // A heavier shadow than the cards below it. This is the one thing on the
        // page meant to be acted on, and it has to look like it without being a
        // different colour from everything else.
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.primary.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: outcome?.recommendation.headline)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.brandGradient)
                .accessibilityHidden(true)
            Text("Do this next")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
            askCoachButton
        }
        .accessibilityElement(children: .contain)
    }

    /// A labelled control rather than a bare glyph.
    ///
    /// The previous version was a 14-point SF Symbol with an accessibility label
    /// and nothing else — invisible as an affordance to anyone not already
    /// looking for it, and the single most useful thing on the card.
    private var askCoachButton: some View {
        Button {
            showAsk = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Ask Coach")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(AppTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.primary.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Coach")
        .accessibilityHint("Opens a conversation about your data")
    }

    // MARK: Loading

    /// Reserves the height the answer will occupy.
    ///
    /// Without this the card is a single line while it loads and three lines
    /// afterwards, so everything below it jumps down the moment the answer
    /// arrives — usually just as someone is reaching for it.
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(loadingMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            SkeletonBar(widthFraction: 0.9, height: 20)
            SkeletonBar(widthFraction: 0.65, height: 14)
        }
        .frame(minHeight: 96, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loadingMessage)
    }

    /// Two different waits, named as two different things.
    private var loadingMessage: String {
        if appState.isSyncingHealth { return "Updating health data…" }
        if isAsking && settings.mayUseCloud && settings.enabled { return "Asking Gemini…" }
        return "Working out what matters today…"
    }

    // MARK: Content

    @ViewBuilder
    private func content(for outcome: CoachService.Outcome) -> some View {
        let recommendation = outcome.recommendation

        Text(recommendation.headline)
            .font(.system(size: 20, weight: .bold))
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

        if let snapshot, let caveat = dataCaveat(for: snapshot) {
            DataCaveatRow(text: caveat)
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

        CoachProvenanceLabel(provenance: outcome.provenance) {
            Task { await load(force: true) }
        }

        if !settings.mayUseCloud {
            Button("Turn on AI coaching") { showConsent = true }
                .font(.caption2.weight(.medium))
                .foregroundColor(AppTheme.primary)
        }
    }

    /// The one sentence worth saying about the data behind this advice.
    ///
    /// At most one. A card stacked with four caveats has buried the advice, and
    /// these are ordered by which most changes what the advice is worth: no
    /// tracker at all beats a stale sync, which beats a baseline that isn't
    /// ready yet.
    private func dataCaveat(for snapshot: HealthSnapshot) -> String? {
        if !snapshot.hasConnectedSource {
            return "No tracker is connected, so this is based on your tasks and habits only."
        }
        if !snapshot.hasAnyMeasurement {
            // Nothing has *ever* arrived from a source the app believes is
            // connected. On the Apple Health path that is very often a denied
            // read permission rather than an empty Health app: HealthKit reports
            // success for types it has refused, and the queries just come back
            // empty. Naming the likely cause is the difference between a dead
            // end and a two-tap fix.
            if snapshot.lastSyncedAt == nil {
                return "No health data has arrived yet from \(snapshot.source ?? "your tracker")."
            }
            return "\(snapshot.source ?? "Your tracker") synced but returned nothing — check Life still has permission to read your health data."
        }
        if !snapshot.isFresh {
            return "Health figures are from \(snapshot.freshnessStatement.lowercased())."
        }
        if snapshot.sleepMinutes.state == .stale || snapshot.hrvMs.state == .stale {
            return "Some health figures aren't from today."
        }
        if snapshot.readiness.state == .insufficientHistory {
            return snapshot.recoveryStatement
        }
        return nil
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
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
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
        // Dismissed here means dismissed everywhere. Leaving it on the home
        // screen after it was swiped away on Today would be the app arguing.
        WidgetSync.syncCoachTip(nil)
        HapticManager.impact(.light)
    }

    /// Loads the recommendation.
    ///
    /// `force` is the only path that clears the cache, and it is only reached by
    /// an explicit tap — consenting to cloud AI, or pressing Retry. Nothing here
    /// retries on appearance: `.task(id:)` fires when the *data* changes, and a
    /// failed call that re-fired on every appearance would spend a request each
    /// time the view scrolled back into existence, which the brief forbids.
    private func load(force: Bool = false) async {
        guard settings.enabled else { return }
        if force { CoachCache.shared.invalidateRecommendation() }
        isAsking = true
        defer { isAsking = false }

        // Built once here rather than on every render — see `refreshToken`. One
        // snapshot serves the context, the card's caveat line and the cache key,
        // so all three describe the same instant.
        let health = appState.healthSnapshot
        let built = CoachContextBuilder.build(
            appState: appState,
            permissions: .init(settings),
            snapshot: health
        )
        snapshot = health
        context = built
        let result = await service.recommendation(for: built, settings: settings, snapshot: health)
        outcome = result
        publishToWidget(result)
    }

    /// Puts the same words, with the same provenance, on the home screen.
    ///
    /// The provenance travels with them because a widget is where a mislabelled
    /// suggestion would do the most quiet damage: no explanation sheet behind
    /// it, no Retry beside it, nothing to correct the impression that a model
    /// wrote a line the rules produced.
    private func publishToWidget(_ outcome: CoachService.Outcome?) {
        guard let outcome else {
            WidgetSync.syncCoachTip(nil)
            return
        }
        WidgetSync.syncCoachTip(
            WidgetSync.WidgetCoachTip(
                headline: outcome.recommendation.headline,
                summary: outcome.recommendation.summary,
                origin: outcome.provenance.origin.rawValue,
                generatedAt: outcome.provenance.generatedAt
            )
        )
    }
}

// MARK: - Shared components

/// A grey bar standing in for text that hasn't arrived.
///
/// Sized in fractions of the available width so it reads as "a line of text
/// about this long" at every Dynamic Type size, rather than as a fixed-width box
/// that happens to look right on one device.
struct SkeletonBar: View {
    var widthFraction: CGFloat = 1
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: height / 3, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: proxy.size.width * widthFraction, height: height)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A plain statement about the data behind the advice above it.
///
/// Deliberately not styled as a warning. "Not enough history to assess recovery"
/// is a fact about how long the tracker has been worn, not a fault, and orange
/// triangles on facts train people to ignore orange triangles.
struct DataCaveatRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

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
