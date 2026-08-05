import Foundation

// MARK: - Local Coach

/// Recommendations worked out on the device, with no network and no model.
///
/// This is deliberately not a stub. It serves three purposes and has to be
/// genuinely useful for all of them:
///
/// 1. **The whole feature when cloud AI is off.** Someone who never enables the
///    network still gets a next action, because the app already knows their
///    sleep, steps, tasks and habits — the model adds phrasing and judgement,
///    not knowledge.
/// 2. **The fallback when a call fails.** A coach card that says "error" where
///    a suggestion should be is worse than one that says something sensible and
///    slightly plainer.
/// 3. **The floor on quality.** If the model can't beat these rules it isn't
///    earning its cost, and the comparison is only possible because these exist.
///
/// The rules are ordered by what most deserves attention, and each one refuses
/// to fire on data it doesn't have.
@MainActor
enum LocalCoach {

    /// The single best next action, from rules alone.
    static func recommend(from context: CoachContext) -> CoachRecommendation {
        // Ordered deliberately: recovery before effort, because advising a hard
        // session on a bad recovery day is the one mistake with a physical cost.
        let rules: [(CoachContext) -> CoachRecommendation?] = [
            restIfRecoveryIsDown,
            sleepIfShort,
            logMissingData,
            plannedWorkout,
            importantTask,
            habitAtRisk,
            walkIfBehindOnSteps
        ]

        for rule in rules {
            guard let candidate = rule(context) else { continue }
            // A muted category is skipped here rather than produced and then
            // rejected by validation, so the next-best rule still gets a turn.
            // Filtering only at the end would leave the user with "you're on
            // track" whenever their top suggestion happened to be muted.
            if context.mutedCategories.contains(candidate.category.rawValue) { continue }
            return candidate
        }

        return onTrack(context)
    }

    // MARK: Rules

    /// Recovery below baseline outranks everything else on the list.
    private static func restIfRecoveryIsDown(_ context: CoachContext) -> CoachRecommendation? {
        guard let recovery = context.recovery else { return nil }
        let hrvDown = recovery.hrvStatus == .belowBaseline
        let rhrUp = recovery.restingHeartRateStatus == .aboveBaseline
        // Both signals, not either. One alone is noise often enough that acting
        // on it would have the coach calling for rest most weeks.
        guard hrvDown && rhrUp else { return nil }

        return CoachRecommendation(
            headline: "Take it easy today",
            summary: "Your recovery signals are both below where they usually sit, so today is a better day for something light than something hard.",
            category: .recovery,
            actionType: .rest,
            priority: .high,
            confidence: recovery.confidence.asCoachConfidence,
            evidence: [
                .init(label: "HRV", explanation: "Below your usual range."),
                .init(label: "Resting heart rate", explanation: "Above your usual range.")
            ],
            origin: .local
        )
    }

    /// An hour or more down on the user's own average, not on a guideline.
    private static func sleepIfShort(_ context: CoachContext) -> CoachRecommendation? {
        guard let sleep = context.sleep,
              let deficit = sleep.vsBaselineMinutes,
              deficit <= -60 else { return nil }

        let hours = abs(deficit) / 60
        let minutes = abs(deficit) % 60
        let short = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes) minutes"

        return CoachRecommendation(
            headline: "Get to bed earlier tonight",
            summary: "You slept \(short) less than your usual last night. An earlier night is the cheapest thing you can do for tomorrow.",
            category: .sleep,
            actionType: .rest,
            priority: .medium,
            confidence: sleep.confidence.asCoachConfidence,
            evidence: [
                .init(label: "Sleep", explanation: "\(short) below your recent average.")
            ],
            origin: .local
        )
    }

    /// When the data itself is the problem, say so rather than advising into a
    /// gap. A coach confidently recommending a walk because "you've done no
    /// steps" when the band simply hasn't synced is the failure this prevents.
    private static func logMissingData(_ context: CoachContext) -> CoachRecommendation? {
        guard context.activity?.quality == .missing, context.sleep == nil else { return nil }

        return CoachRecommendation(
            headline: "Sync your tracker",
            summary: "There's nothing recorded for today or last night yet, so there's not much to go on. Open your tracker's app to let it sync.",
            category: .general,
            actionType: .logMissingData,
            priority: .medium,
            confidence: .high,
            evidence: [
                .init(label: "Data", explanation: "No sleep or activity recorded yet.")
            ],
            origin: .local
        )
    }

    private static func plannedWorkout(_ context: CoachContext) -> CoachRecommendation? {
        guard let planned = context.training?.plannedWorkout else { return nil }
        return CoachRecommendation(
            headline: planned,
            summary: "You've got \(planned) planned for today.",
            category: .training,
            actionType: .doPlannedWorkout,
            priority: .medium,
            confidence: .high,
            evidence: [
                .init(label: "Training", explanation: "Planned for today.")
            ],
            origin: .local
        )
    }

    private static func importantTask(_ context: CoachContext) -> CoachRecommendation? {
        guard let candidate = context.tasks?.topCandidates.first(where: { $0.priority == "high" })
                ?? context.tasks?.topCandidates.first(where: { $0.dueToday })
        else { return nil }

        return CoachRecommendation(
            headline: candidate.title,
            summary: candidate.dueToday
                ? "This one's due today."
                : "This is the most important thing outstanding.",
            category: .tasks,
            actionType: .completeTask,
            relatedItemId: candidate.id,
            durationMinutes: candidate.estimatedMinutes,
            priority: candidate.priority == "high" ? .high : .medium,
            confidence: .high,
            evidence: [
                .init(label: "Tasks", explanation: candidate.dueToday ? "Due today." : "Highest priority outstanding.")
            ],
            origin: .local
        )
    }

    /// The longest streak still unfinished — the one with most to lose today.
    private static func habitAtRisk(_ context: CoachContext) -> CoachRecommendation? {
        guard let candidate = context.habits?.atRisk.first, candidate.streak > 0 else { return nil }
        return CoachRecommendation(
            headline: candidate.title,
            summary: "You're \(candidate.streak) days into this one. Worth not breaking it today.",
            category: .habits,
            actionType: .completeHabit,
            relatedItemId: candidate.id,
            priority: .medium,
            confidence: .high,
            evidence: [
                .init(label: "Streak", explanation: "\(candidate.streak) days running.")
            ],
            origin: .local
        )
    }

    /// Only fires on a *recorded* shortfall, and only late enough in the day
    /// for the shortfall to mean anything. Being under your step goal at nine
    /// in the morning is not news.
    private static func walkIfBehindOnSteps(_ context: CoachContext) -> CoachRecommendation? {
        guard context.timeOfDay != .morning,
              let activity = context.activity,
              activity.quality != .missing,
              let steps = activity.steps,
              let goal = activity.stepGoal,
              goal > 0 else { return nil }

        let shortfall = goal - steps
        guard shortfall > 2_000 else { return nil }

        return CoachRecommendation(
            headline: "Take a 20-minute walk",
            summary: "You're \(shortfall.formatted()) steps short of your goal with some of the day left.",
            category: .activity,
            actionType: .takeWalk,
            durationMinutes: 20,
            priority: .low,
            // The day isn't over, so this is a nudge rather than a verdict.
            confidence: .medium,
            evidence: [
                .init(label: "Steps", explanation: "\(steps.formatted()) of \(goal.formatted()) so far today.")
            ],
            origin: .local
        )
    }

    /// Nothing needs attention. Saying so is a real answer — a coach that
    /// always finds a problem is a coach nobody believes.
    private static func onTrack(_ context: CoachContext) -> CoachRecommendation {
        CoachRecommendation(
            headline: "You're on track",
            summary: "Nothing's flagging today. Carry on as you are.",
            category: .general,
            actionType: .none,
            priority: .low,
            confidence: .medium,
            evidence: [],
            origin: .local
        )
    }

    // MARK: Briefings

    static func briefing(kind: CoachBriefing.Kind, from context: CoachContext) -> CoachBriefing {
        var lines: [String] = []
        var evidence: [CoachEvidence] = []

        if let sleep = context.sleep, let minutes = sleep.durationMinutes {
            lines.append("You slept \(HealthInsights.formatDuration(minutes)).")
            evidence.append(.init(label: "Sleep", explanation: HealthInsights.formatDuration(minutes)))
        }

        if let readiness = context.recovery?.readinessScore {
            lines.append("Readiness is \(readiness) out of 100.")
            evidence.append(.init(label: "Readiness", explanation: "\(readiness)/100"))
        }

        if let steps = context.activity?.steps {
            lines.append("\(steps.formatted()) steps so far.")
            evidence.append(.init(label: "Steps", explanation: steps.formatted()))
        }

        if let tasks = context.tasks, tasks.totalRemainingToday > 0 {
            lines.append("\(tasks.totalRemainingToday) task\(tasks.totalRemainingToday == 1 ? "" : "s") due today.")
        }

        if let habits = context.habits, habits.remaining > 0 {
            lines.append("\(habits.remaining) habit\(habits.remaining == 1 ? "" : "s") left.")
        }

        // Never hidden. A briefing built on half-recorded data that doesn't say
        // so is the thing this whole design is arranged to prevent.
        if !context.dataWarnings.isEmpty {
            lines.append(context.dataWarnings.joined(separator: " "))
        }

        let headline = kind == .morning ? "Good morning" : "How today went"
        return CoachBriefing(
            kind: kind,
            headline: headline,
            body: lines.isEmpty
                ? "Not much recorded yet today."
                : lines.joined(separator: " "),
            evidence: evidence,
            safetyNotice: nil,
            origin: .local,
            generatedAt: Date(),
            contextHash: context.materialHash
        )
    }
}

// MARK: - Confidence bridging

private extension CoachContext.Confidence {
    /// The context's confidence in a figure becomes the recommendation's
    /// confidence in the advice. Advice cannot be surer than what it rests on.
    var asCoachConfidence: CoachConfidence {
        switch self {
        case .low:    return .low
        case .medium: return .medium
        case .high:   return .high
        }
    }
}
