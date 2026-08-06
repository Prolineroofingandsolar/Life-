import SwiftUI

// MARK: - Train sections

/// The cards that make up the redesigned Train screen.
///
/// Split out of `TrainView.swift` because that file was already 2,500 lines and
/// the redesign adds five more sections. Nothing here holds state beyond its own
/// disclosure; everything reads `AppState`.

// MARK: - Today's workout

/// The screen's primary action, and the reason people open this tab.
///
/// Replaces `TodayPlannedCard` and `TodayRoutineCard`, which were two nearly
/// identical cards differing only in where the routine came from. One card, one
/// unmistakable button, and — new — the duration and exercise count, which the
/// app can compute and previously never showed.
struct TodaysWorkoutCard: View {

    @Environment(AppState.self) private var appState

    let onStart: () -> Void
    let onViewPlan: () -> Void

    /// Today's session, from a planned entry first and the active programme
    /// second. Planned wins because it is an explicit choice about today; the
    /// programme is a standing rule.
    private var today: (name: String, routine: Routine?, isPlanned: Bool)? {
        if let planned = appState.plannedSessions.first(where: {
            Calendar.current.isDateInToday($0.date) && !$0.completed
        }) {
            let routine = planned.routineId.flatMap { id in
                appState.routines.first { $0.id == id }
            }
            return (planned.routineName, routine, true)
        }
        if let suggested = appState.todaysSuggestedRoutine() {
            return (suggested.name, suggested, false)
        }
        return nil
    }

    private var completedToday: Bool {
        appState.completedWorkouts.contains { $0.startedAt.dayKey == Date().dayKey }
    }

    private var isRestDay: Bool {
        appState.plannedSessions.contains {
            !$0.completed && $0.date.dayKey == Date().dayKey && $0.isRestDay
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let today, !isRestDay {
                Button(action: onStart) {
                    Text(appState.activeSession != nil ? "Resume workout" : "Start workout")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppTheme.brandGradient)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("\(appState.activeSession != nil ? "Resume" : "Start") \(today.name)")

                if today.routine != nil {
                    Button("View plan", action: onViewPlan)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppTheme.primary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // "Today's workout" is the heading; the routine's name belongs
                // on the detail line beside its length. The card is answering
                // "what am I doing today", and the answer is the whole line —
                // "Push A · 42 min · 6 exercises" — not just the name.
                Text(headingText)
                    .font(.system(size: 22, weight: .bold))
                Text(metaText)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                if let focus = focusText {
                    Text(focus)
                        .font(.system(size: 15))
                        .foregroundColor(Color(.tertiaryLabel))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconTint)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // Four different days, four different sentences. "Rest" used to appear
    // whenever nothing had been completed, which said the same thing about a
    // planned rest day and a hard session still ahead of it.
    private var headingText: String {
        if completedToday { return "Workout done" }
        if isRestDay { return "Rest day" }
        if today == nil { return "No workout planned" }
        return "Today's workout"
    }

    private var metaText: String {
        if completedToday { return "Logged today" }
        if isRestDay { return "Scheduled rest — nothing to do" }
        guard let today else { return "Build one, or start from a routine" }

        guard let routine = today.routine else {
            return today.isPlanned ? "\(today.name) · planned for today" : today.name
        }
        let minutes = estimatedMinutes(for: routine)
        let count = routine.exercises.count
        return "\(today.name) · \(minutes) min · \(count) exercise\(count == 1 ? "" : "s")"
    }

    /// The muscles the session covers, named from its own exercises rather than
    /// from the routine's title.
    private var focusText: String? {
        guard !completedToday, !isRestDay, let routine = today?.routine else { return nil }
        let muscles = routine.exercises
            .compactMap { prescription in
                appState.exercises.first { $0.id == prescription.exerciseId }?.muscle
            }
        var seen: Set<String> = []
        let ordered = muscles.filter { seen.insert($0).inserted }
        guard !ordered.isEmpty else { return nil }
        return ordered.prefix(3).joined(separator: ", ")
    }

    private var iconName: String {
        if completedToday { return "checkmark.circle.fill" }
        if isRestDay { return "moon.zzz.fill" }
        return "dumbbell.fill"
    }

    private var iconTint: Color {
        if completedToday { return .green }
        if isRestDay { return .indigo }
        return AppTheme.trainAccent
    }

    /// Same arithmetic as `WorkoutResolver.estimatedMinutes`, so a generated
    /// session's stated length doesn't change once it has been saved.
    private func estimatedMinutes(for routine: Routine) -> Int {
        let seconds = routine.exercises.reduce(0) { total, exercise in
            let reps = (exercise.repRangeMin + exercise.repRangeMax) / 2
            let working = reps * WorkoutResolver.ResolvedWorkout.secondsPerRep
            return total + exercise.defaultSets * (working + exercise.restSeconds)
        }
        return max(1, (seconds + routine.exercises.count * 60) / 60)
    }
}

// MARK: - Coach suggestion

/// One suggestion, from the deterministic engines, with Review and Dismiss.
///
/// Fed by `ProgressionEngine` — which decides entirely by rule. Gemini has no
/// vote in what this card says; when it eventually phrases the sentence, the
/// decision underneath will still be the rules'.
///
/// Hidden entirely when there is nothing to say. A card that is permanently
/// present and usually empty teaches people to stop looking at it.
struct CoachSuggestionCard: View {

    @Environment(AppState.self) private var appState

    let onReview: ([ProgressionEngine.Proposal]) -> Void

    @AppStorage("train_suggestion_dismissed_v1") private var dismissedKey = ""

    /// Proposals from the most recent finished session.
    ///
    /// Only the last one: a suggestion about a workout from three weeks ago is
    /// archaeology, not coaching.
    private var proposals: [ProgressionEngine.Proposal] {
        guard let latest = appState.completedWorkouts
            .sorted(by: { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) })
            .first
        else { return [] }
        return ProgressionEngine.proposals(forSessionId: latest.id, appState: appState)
    }

    /// Identifies the current suggestion, so dismissing it doesn't also dismiss
    /// the different one that follows the next session.
    private var suggestionKey: String {
        proposals.map(\.exerciseId).sorted().joined(separator: ",")
    }

    private var isDismissed: Bool {
        !suggestionKey.isEmpty && dismissedKey == suggestionKey
    }

    var body: some View {
        if !proposals.isEmpty && !isDismissed {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.brandGradient)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach suggestion")
                        .font(.system(size: 15, weight: .semibold))
                    Text(summaryText)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                // Beside the message rather than under it. The actions belong to
                // the sentence, and a separate row below pushed the card taller
                // than the suggestion warranted.
                VStack(alignment: .trailing, spacing: 10) {
                    Button("Review") { onReview(proposals) }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.primary)

                    Button("Dismiss") { dismissedKey = suggestionKey }
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .accessibilityHint("Hides this until your next workout")
                }
                .fixedSize()
            }

            // The provenance line, in miniature. These come from rules, and
            // saying so is the difference between a suggestion you can check and
            // one you have to take on faith.
            Text("Based on your training history")
                .font(.system(size: 11))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// One sentence, however many proposals there are.
    ///
    /// Listing four exercises on a summary card is a list nobody reads; the
    /// detail is behind Review.
    private var summaryText: String {
        guard let first = proposals.first else { return "" }
        if proposals.count == 1 {
            return "\(first.exerciseName): \(first.action.headline.lowercased()) next time."
        }
        return "\(first.exerciseName) and \(proposals.count - 1) other"
            + "\(proposals.count == 2 ? "" : "s") ready to move on."
    }
}

// MARK: - Train your way

/// The four things you can start from, as a 2×2 grid.
///
/// Replaces a row of four unlabelled toolbar glyphs and a sparkles menu. Two of
/// these — building a workout and building a programme — are the most valuable
/// actions on the screen and were previously behind an icon that gave no clue
/// they existed.
struct TrainYourWayGrid: View {

    let onBuildProgramme: () -> Void
    let onBuildWorkout: () -> Void
    let onScanMachine: () -> Void
    let onExerciseLibrary: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ActionTile(
                icon: "calendar.badge.plus",
                tint: AppTheme.trainAccent,
                title: "Build a programme",
                subtitle: "Create a personalised plan",
                isCompact: true,
                action: onBuildProgramme
            )
            ActionTile(
                icon: "timer",
                tint: AppTheme.trainAccent,
                title: "Build today's workout",
                subtitle: "Fit your time and equipment",
                isCompact: true,
                action: onBuildWorkout
            )
            ActionTile(
                icon: "camera.viewfinder",
                tint: AppTheme.trainAccent,
                title: "Scan a machine",
                subtitle: "Identify and add an exercise",
                isCompact: true,
                action: onScanMachine
            )
            ActionTile(
                icon: "books.vertical",
                tint: AppTheme.trainAccent,
                title: "Exercise library",
                subtitle: "Browse and learn",
                isCompact: true,
                action: onExerciseLibrary
            )
        }
    }
}

// MARK: - Your programme

/// Where you are in the current week of your active programme.
struct ProgrammeProgressCard: View {

    @Environment(AppState.self) private var appState
    let onTap: () -> Void

    private var progress: TrainingStats.ProgrammeProgress? {
        TrainingStats.programmeProgress(appState: appState)
    }

    var body: some View {
        if let progress {
            Button(action: onTap) {
                content(progress)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(progress.name), \(progress.completedThisWeek) of \(progress.plannedThisWeek) this week"
            )
            .accessibilityAddTraits(.isButton)
        }
    }

    private func content(_ progress: TrainingStats.ProgrammeProgress) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.trainAccent.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.trainAccent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(progress.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("\(progress.completedThisWeek) of \(progress.plannedThisWeek) this week")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Segments rather than a bar: a programme is a countable number
                // of sessions, and four discrete blocks say that better than a
                // continuous fill.
                HStack(spacing: 4) {
                    ForEach(0..<max(progress.plannedThisWeek, 1), id: \.self) { index in
                        Capsule()
                            .fill(index < progress.completedThisWeek
                                  ? AppTheme.trainAccent
                                  : AppTheme.trainAccent.opacity(0.18))
                            .frame(height: 5)
                    }
                }
            }

            Spacer(minLength: 4)

            if !progress.upcoming.isEmpty {
                Text(progress.upcoming.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 110, alignment: .trailing)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(14)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Progress

/// Three figures and a trend line.
///
/// Each figure renders its own absence. A month with no workouts genuinely has
/// zero and shows it; adherence with nothing scheduled shows a dash and says
/// why, because telling a consistent trainer they are at 0% because they never
/// used the planner is worse than telling them nothing.
struct TrainingProgressCard: View {

    @Environment(AppState.self) private var appState
    let onTap: () -> Void

    private var summary: TrainingStats.Summary {
        TrainingStats.summary(appState: appState)
    }

    var body: some View {
        let stats = summary

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                figure(stats.workouts)
                figure(stats.personalRecords)
                figure(stats.adherence)

                Sparkline(values: stats.trend)
                    .frame(width: 96, height: 40)
                    .accessibilityHidden(true)
            }
            .padding(14)

            Divider().padding(.leading, 14)

            Button(action: onTap) {
                HStack {
                    Text("View training progress")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppTheme.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func figure(_ figure: TrainingStats.Figure) -> some View {
        VStack(spacing: 2) {
            Text(figure.value ?? "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(figure.hasValue ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(figure.label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            figure.hasValue
                ? "\(figure.value ?? "") \(figure.label)"
                : "\(figure.label), \(figure.absenceReason ?? "not available")"
        )
    }
}

/// An eight-week trend line, drawn from whatever range the data occupies.
private struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { proxy in
            let points = normalised(in: proxy.size)
            ZStack {
                if points.count >= 2 {
                    // A soft fill under the line. It carries no extra
                    // information — it makes the line read as a quantity rather
                    // than a squiggle, which at this size is most of the value.
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.trainAccent.opacity(0.22), AppTheme.trainAccent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(AppTheme.trainAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if let last = points.last {
                        Circle()
                            .fill(AppTheme.trainAccent)
                            .frame(width: 6, height: 6)
                            .position(last)
                    }
                }
            }
        }
    }

    /// Scaled to the data's own range rather than to zero.
    ///
    /// Someone training three or four times a week every week has a real,
    /// readable line here; anchored at zero it would be a flat stripe near the
    /// top telling them nothing.
    private func normalised(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let lowest = values.min() ?? 0
        let highest = values.max() ?? 1
        let span = max(1, highest - lowest)
        let step = size.width / CGFloat(values.count - 1)

        return values.enumerated().map { index, value in
            let fraction = CGFloat(value - lowest) / CGFloat(span)
            return CGPoint(
                x: CGFloat(index) * step,
                y: size.height - (fraction * (size.height - 6)) - 3
            )
        }
    }
}
