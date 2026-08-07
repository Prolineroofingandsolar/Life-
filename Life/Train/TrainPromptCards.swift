import SwiftUI

// MARK: - Missed Session Card

/// A session that was planned and didn't happen.
///
/// Shown once, for the most recent one, and only while it is still worth
/// moving. An app that keeps a running tally of everything you didn't do is
/// not a coach, and the second missed session is not more information — it is
/// the same information, louder.
struct MissedSessionCard: View {

    @Environment(AppState.self) private var appState

    var onReschedule: (PlannedSession) -> Void

    private var missed: PlannedSession? {
        RescheduleEngine.missedSessions(planned: appState.plannedSessions)
            .first { !RescheduleEngine.isStale($0) }
    }

    var body: some View {
        if let missed {
            Button {
                onReschedule(missed)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(missed.routineName) didn't happen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Text("Planned for \(missed.date.formatted(date: .abbreviated, time: .omitted)). Move it, or let it go.")
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the options for moving this session. Nothing moves until you choose.")
        }
    }
}

// MARK: - Drift Card

/// The programme and the training have parted company.
///
/// Shown at most once a fortnight, and only when the evidence thresholds in
/// `DriftEngine` are met — three occurrences across three separate weeks. An app
/// that offers to redesign your programme every time you skip a Tuesday is not
/// observant, it is nagging, and the dismissal date is what keeps it from
/// becoming that.
struct DriftCard: View {

    @Environment(AppState.self) private var appState

    var onReview: ([DriftEngine.Signal]) -> Void

    @AppStorage("train_drift_dismissed_at") private var dismissedAt: Double = 0

    /// A fortnight. Long enough that the second showing means something changed,
    /// short enough to catch a programme that has genuinely been outgrown.
    private static let quietDays: TimeInterval = 14 * 24 * 60 * 60

    private var signals: [DriftEngine.Signal] {
        guard Date().timeIntervalSince1970 - dismissedAt > Self.quietDays else { return [] }
        return DriftEngine.signals(appState: appState)
    }

    var body: some View {
        let found = signals
        if !found.isEmpty {
            Button {
                dismissedAt = Date().timeIntervalSince1970
                onReview(found)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.title3)
                        .foregroundColor(AppTheme.trainAccent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your programme doesn't match your training")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(found[0].headline + (found.count > 1 ? ", and \(found.count - 1) other thing\(found.count == 2 ? "" : "s")." : "."))
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the evidence. Nothing changes unless you rebuild and confirm.")
        }
    }
}

// MARK: - Deload Card

/// An easier week, offered rarely and reluctantly.
///
/// `DeloadEngine` needs six weeks of history and two independent signals before
/// this can appear at all, and the dismissal is remembered for a month. A
/// deload suggested often is a deload nobody takes seriously.
struct DeloadCard: View {

    @Environment(AppState.self) private var appState

    var onReview: (DeloadEngine.Proposal) -> Void

    @AppStorage("train_deload_dismissed_at") private var dismissedAt: Double = 0

    private static let quietDays: TimeInterval = 30 * 24 * 60 * 60

    private var proposal: DeloadEngine.Proposal? {
        guard Date().timeIntervalSince1970 - dismissedAt > Self.quietDays else { return nil }
        return DeloadEngine.proposal(appState: appState)
    }

    var body: some View {
        if let proposal {
            Button {
                dismissedAt = Date().timeIntervalSince1970
                onReview(proposal)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.right.circle")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Worth an easier week?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(proposal.evidence.first ?? "A few things point that way.")
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the exact reductions before anything changes.")
        }
    }
}

// MARK: - Weekly Review Card

/// "Your week is ready."
///
/// Appears once a week has something in it and disappears once the review has
/// been opened for that week. The week key is stored rather than a boolean, so
/// next Monday brings it back without anything having to reset it.
struct WeeklyReviewCard: View {

    @Environment(AppState.self) private var appState

    var onOpen: () -> Void

    @AppStorage("train_last_reviewed_week") private var lastReviewedWeek = ""

    /// The week being offered for review: the one that just finished.
    private var weekKey: String {
        DayKey.string(for: WeeklyReview.startOfWeek(containing: Date()))
    }

    /// Enough of a week to be worth a review.
    ///
    /// Two sessions. One is a fact, not a pattern, and a "review" of it would be
    /// the app finding something to say.
    private var isWorthShowing: Bool {
        guard lastReviewedWeek != weekKey else { return false }
        let metrics = WeeklyReview.metrics(appState: appState)
        return metrics.isReviewable
    }

    var body: some View {
        if isWorthShowing {
            Button {
                lastReviewedWeek = weekKey
                onOpen()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title3)
                        .foregroundColor(AppTheme.trainAccent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your training week")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text("What you did, what changed, and whether anything's worth adjusting.")
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this week's review.")
        }
    }
}
