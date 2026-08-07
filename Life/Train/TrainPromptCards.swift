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
