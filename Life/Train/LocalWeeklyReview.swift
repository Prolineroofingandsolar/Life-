import Foundation

// MARK: - Local Weekly Review

/// The review, written by the app.
///
/// Cloud AI is off by default and off for everyone on first run, so a feature
/// that only exists when Gemini answers is a feature most people never see.
/// Every figure in the review is the app's own arithmetic anyway — the model
/// contributes judgement about which of them matters, and this contributes a
/// plainer version of the same judgement using fixed rules.
///
/// Labelled `onDevice` wherever it appears. It is not a degraded Gemini review;
/// it is a different, honest thing.
enum LocalWeeklyReview {

    nonisolated static func review(for metrics: WeeklyReview.Metrics) -> WeeklyReviewResponse {
        WeeklyReviewResponse(
            headline: headline(metrics),
            summary: summary(metrics),
            actions: actions(metrics)
        )
    }

    // MARK: Prose

    private nonisolated static func headline(_ m: WeeklyReview.Metrics) -> String {
        if m.completedSessions == 0 { return "No sessions logged this week" }
        if m.sessionsChange > 0 { return "\(m.completedSessions) sessions — up on last week" }
        if m.sessionsChange < 0 { return "\(m.completedSessions) sessions — down on last week" }
        return "\(m.completedSessions) sessions, same as last week"
    }

    private nonisolated static func summary(_ m: WeeklyReview.Metrics) -> String {
        var lines: [String] = []

        if let adherence = m.adherencePercent {
            lines.append("You completed \(adherence)% of what you planned.")
        } else if m.completedSessions > 0 {
            // The distinction the adherence figure exists to protect. Nothing
            // planned is not poor adherence.
            lines.append("Nothing was planned this week, so there's no adherence figure — only what you did.")
        }

        if let duration = m.averageDurationMinutes {
            lines.append("Sessions averaged \(duration) minutes.")
        }

        if m.personalRecords > 0 {
            lines.append("\(m.personalRecords) personal best\(m.personalRecords == 1 ? "" : "s").")
        }

        if !m.underTargetMuscles.isEmpty {
            let names = m.underTargetMuscles.joined(separator: ", ").lowercased()
            lines.append("Well under target on \(names).")
        }

        if m.incompleteSessions > 0 {
            lines.append("\(m.incompleteSessions) session\(m.incompleteSessions == 1 ? " was" : "s were") started and not finished.")
        }

        if !m.isReviewable {
            lines.append("That's a small sample — not enough to read a trend into.")
        }

        return lines.isEmpty
            ? "Nothing was recorded this week, so there's nothing to review yet."
            : lines.joined(separator: " ")
    }

    // MARK: Actions

    /// At most three, and "keep going" is a real answer rather than a filler
    /// one.
    private nonisolated static func actions(_ m: WeeklyReview.Metrics) -> [ReviewAction] {
        var actions: [ReviewAction] = []

        if let adherence = m.adherencePercent, adherence < 60, m.plannedSessions >= 3 {
            actions.append(
                ReviewAction(
                    kind: .condenseSessions,
                    label: "Try fewer sessions",
                    rationale: "You completed \(adherence)% of \(m.plannedSessions) planned sessions. A week you finish beats a week you admire."
                )
            )
        }

        if let muscle = m.underTargetMuscles.first, let blueprint = BlueprintMuscle(rawValue: muscle) {
            actions.append(
                ReviewAction(
                    kind: .adjustVolume,
                    label: "Add some \(muscle.lowercased()) work",
                    rationale: "\(muscle) came in well under its weekly target.",
                    muscle: blueprint
                )
            )
        }

        if !m.repeatedlySkippedExerciseIds.isEmpty {
            let count = m.repeatedlySkippedExerciseIds.count
            actions.append(
                ReviewAction(
                    kind: .reviewSkippedExercise,
                    label: "Review what you keep skipping",
                    rationale: "\(count) exercise\(count == 1 ? " has" : "s have") been prescribed and skipped at least \(WeeklyReview.skipThreshold) times."
                )
            )
        }

        if actions.isEmpty {
            actions.append(
                ReviewAction(
                    kind: .keepUnchanged,
                    label: "Keep next week as it is",
                    rationale: m.completedSessions > 0
                        ? "Nothing in this week's figures suggests a change."
                        : "Not enough happened this week to justify changing anything."
                )
            )
        }

        return Array(actions.prefix(3))
    }
}
