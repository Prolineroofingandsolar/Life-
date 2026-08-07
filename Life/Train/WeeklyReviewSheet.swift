import SwiftUI

// MARK: - Weekly Review Sheet

/// Last week, and what to do about it.
///
/// The figures come first and the prose second, deliberately. A review that
/// leads with a paragraph asks to be trusted; one that shows the week beside
/// what it says about it can be checked — and a model that contradicts a number
/// on the same screen is caught by the reader rather than believed.
///
/// Every action opens something. None of them writes.
struct WeeklyReviewSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// What the sheet asks its host to open. The sheet itself changes nothing.
    var onOpenBuilder: ((WorkoutBrief) -> Void)?
    var onOpenSchedule: (() -> Void)?

    @State private var state: LoadState = .loading

    private var settings: CoachSettings { appState.coachSettings }
    private var service: WorkoutBuilderService { WorkoutBuilderService() }

    enum LoadState {
        case loading
        case ready(WeeklyReviewOutcome)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading: loading
                case .ready(let outcome): review(outcome)
                }
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Adding up your week…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Review

    private func review(_ outcome: WeeklyReviewOutcome) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                figures(outcome.metrics)

                VStack(alignment: .leading, spacing: 8) {
                    Text(outcome.headline)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(outcome.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                if !outcome.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What to do about it")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                        ForEach(outcome.actions) { action in
                            actionRow(action)
                        }
                    }
                }

                CoachProvenanceLabel(provenance: outcome.provenance)
            }
            .padding(20)
        }
    }

    /// The week, as the app counted it.
    private func figures(_ metrics: WeeklyReview.Metrics) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                figure("Sessions", "\(metrics.completedSessions)", change: metrics.sessionsChange)
                figure(
                    "Adherence",
                    metrics.adherencePercent.map { "\($0)%" },
                    // The distinction this whole app is built on: nothing
                    // planned is not zero per cent.
                    absence: "nothing planned"
                )
            }
            HStack(spacing: 10) {
                figure("Average", metrics.averageDurationMinutes.map { "\($0)m" }, absence: "no timings")
                figure("Personal bests", "\(metrics.personalRecords)")
            }
        }
    }

    private func figure(
        _ title: String,
        _ value: String?,
        change: Int? = nil,
        absence: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            if let value {
                Text(value)
                    .font(.title2.weight(.bold))
                if let change, change != 0 {
                    Text(change > 0 ? "+\(change) on last week" : "\(change) on last week")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("—")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.secondary)
                Text(absence ?? "no data")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func actionRow(_ action: ReviewAction) -> some View {
        Button {
            perform(action)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: action.kind.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.trainAccent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Text(action.rationale)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if action.kind != .keepUnchanged {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color(.tertiaryLabel))
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(action.kind == .keepUnchanged)
        .accessibilityHint(
            action.kind == .keepUnchanged
                ? "Nothing to do."
                : "Opens the next step. Nothing is changed until you confirm there."
        )
    }

    // MARK: Actions

    /// Opens; never writes.
    ///
    /// Each branch hands off to a flow that has its own preview and its own
    /// confirmation. A review button that quietly rewrote next week would be the
    /// exact thing this design exists to prevent, and it would be invisible.
    private func perform(_ action: ReviewAction) {
        switch action.kind {
        case .keepUnchanged:
            dismiss()

        case .condenseSessions:
            var brief = WorkoutBrief()
            brief.daysPerWeek = max(2, (state.metrics?.completedSessions ?? 3))
            brief.text = "Fewer sessions than last week, same overall work."
            onOpenBuilder?(brief)
            dismiss()

        case .adjustVolume:
            var brief = WorkoutBrief()
            if let muscle = action.muscle { brief.focusMuscles = [muscle] }
            brief.text = action.rationale
            onOpenBuilder?(brief)
            dismiss()

        case .moveTrainingDay, .reviewSkippedExercise:
            onOpenSchedule?()
            dismiss()
        }
    }

    private func load() async {
        let metrics = WeeklyReview.metrics(appState: appState)
        let context = CoachContextBuilder.build(
            appState: appState,
            permissions: .init(settings),
            snapshot: appState.healthSnapshot
        )
        state = .ready(
            await service.weeklyReview(metrics: metrics, context: context, settings: settings)
        )
    }
}

private extension WeeklyReviewSheet.LoadState {
    var metrics: WeeklyReview.Metrics? {
        if case .ready(let outcome) = self { return outcome.metrics }
        return nil
    }
}
