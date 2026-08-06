import Foundation

// MARK: - Coach Context Builder

/// Turns the app's stored state into the compact summary the coach is sent.
///
/// The rule this file exists to enforce: **read the trusted figures, never
/// recompute them.** Every number here comes from `HealthInsights`,
/// `HealthSync` or the stored models, because those are what the Health tab
/// shows. A second implementation of "how many steps today" that disagreed with
/// the screen next to it would make the coach worse than useless — the user
/// would have no way to tell which of the two was lying.
///
/// It follows that the cleaning the brief asks for happens *before* this runs,
/// not in it: deduplication in `GoogleHealthService`, source selection in
/// `HealthSync`, baselines in `HealthInsights`. This assembles their output.
@MainActor
enum CoachContextBuilder {

    /// What the coach may be told about.
    ///
    /// Task and habit titles are user-written text and can name real people —
    /// "Reply to Mrs Hargreaves about the roof". They're included because the
    /// coach can't recommend a specific task without naming it, but they're a
    /// separate switch from the health figures so that choice stays the user's.
    struct Permissions: Equatable, Sendable {
        var health: Bool = true
        var activity: Bool = true
        var training: Bool = true
        var tasks: Bool = true
        var habits: Bool = true
        /// When false, tasks and habits are counted but never named.
        ///
        /// Defaults to false, matching `CoachSettings.shareTitles`. Two
        /// cautious defaults that disagree are one cautious default and one
        /// trap: any caller taking the default would have started sending the
        /// words while the settings screen showed the switch as off.
        var includeTitles: Bool = false

        /// Categories the user has asked not to be nudged about.
        var mutedCategories: [String] = []

        /// Everything, titles included. Explicit rather than `Permissions()`,
        /// so it stays true to its name if a default changes.
        static let all: Permissions = {
            var permissions = Permissions()
            permissions.includeTitles = true
            return permissions
        }()

        /// The user's settings, expressed as what may be sent.
        ///
        /// One translation, in one place. The alternative — each call site
        /// reading `settings.allowTasks` and remembering to check it — is how a
        /// category ends up being sent by the one path that forgot.
        init(_ settings: CoachSettings) {
            health = settings.allowHealth
            activity = settings.allowActivity
            training = settings.allowTraining
            tasks = settings.allowTasks
            habits = settings.allowHabits
            includeTitles = settings.shareTitles
            mutedCategories = settings.mutedCategories
        }

        init() {}
    }

    /// The most candidates worth sending.
    ///
    /// The coach picks one action, so this is a shortlist, not an inventory.
    /// Sending the whole task list would cost tokens on every request to
    /// transmit items that cannot be chosen.
    private static let maximumCandidates = 5

    static func build(
        appState: AppState,
        permissions: Permissions = Permissions(),
        now: Date = Date(),
        calendar: Calendar = .current,
        snapshot: HealthSnapshot? = nil
    ) -> CoachContext {
        var warnings: [String] = []

        // One snapshot for every health figure below. Passed in wherever the
        // caller already holds one — the card, the briefing and Ask Coach all
        // render from the same instance, so a figure cannot differ between them
        // because one of them rebuilt half a second later. The fallback builds
        // against the `now` that was passed rather than the wall clock, so a
        // test can pin the moment and get a context and a snapshot describing it.
        let health = snapshot ?? HealthSnapshotBuilder.build(appState: appState, now: now)

        let sleep = permissions.health
            ? sleepSection(health, warnings: &warnings)
            : nil
        let recovery = permissions.health
            ? recoverySection(health, warnings: &warnings)
            : nil
        let activity = permissions.activity
            ? activitySection(health, appState: appState, warnings: &warnings)
            : nil
        let training = permissions.training
            ? trainingSection(appState: appState, now: now, calendar: calendar)
            : nil
        let tasks = permissions.tasks
            ? tasksSection(appState: appState, permissions: permissions, now: now, calendar: calendar)
            : nil
        let habits = permissions.habits
            ? habitsSection(appState: appState, permissions: permissions, dayKey: health.dayKey)
            : nil

        if !health.isFresh && health.hasConnectedSource {
            warnings.append(
                "Health data hasn't refreshed recently — \(health.freshnessStatement)."
            )
        }
        if !health.hasConnectedSource {
            warnings.append("No tracker is connected, so there are no health measurements at all.")
        }
        for failure in health.syncFailures {
            warnings.append("\(failure) didn't come through on the last sync.")
        }

        var context = CoachContext(
            generatedAt: now,
            timeOfDay: .from(now, calendar: calendar),
            goals: goals(appState: appState),
            sleep: sleep,
            recovery: recovery,
            activity: activity,
            training: training,
            tasks: tasks,
            habits: habits,
            dataWarnings: warnings,
            mutedCategories: permissions.mutedCategories
        )

        context.dayKey = health.dayKey
        context.timeZoneIdentifier = health.timeZoneIdentifier
        context.dataSource = permissions.health || permissions.activity ? health.source : nil
        context.dataUpdatedAt = permissions.health || permissions.activity ? health.lastSyncedAt : nil
        context.dataIsFresh = health.isFresh
        context.comparisons = comparisons(
            health, appState: appState, permissions: permissions, now: now, calendar: calendar
        )

        return context
    }

    // MARK: Comparisons

    /// Today against yesterday, this week against last, as a few integers.
    ///
    /// Gated by the same permissions as the figures they compare — a delta is
    /// still the data, just arithmetic away.
    private static func comparisons(
        _ health: HealthSnapshot,
        appState: AppState,
        permissions: Permissions,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Comparisons? {
        var out = CoachContext.Comparisons()

        if permissions.health {
            out.sleepVsYesterdayMinutes = health.sleepChangeSinceYesterdayMinutes
            out.restingHeartRateVsYesterday = health.restingHeartRateChangeSinceYesterday
        }
        if permissions.activity {
            out.stepsVsYesterday = health.stepsChangeSinceYesterday
        }
        if permissions.training {
            let finished = appState.completedWorkouts.compactMap(\.finishedAt)
            if let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
               let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) {
                out.workoutsThisWeek = finished.filter { $0 >= thisWeekStart }.count
                out.workoutsLastWeek = finished.filter { $0 >= lastWeekStart && $0 < thisWeekStart }.count
            }
        }

        return out == CoachContext.Comparisons() ? nil : out
    }

    // MARK: Goals

    /// Life has no goals feature, so these are assembled from the targets the
    /// user has actually set. Nothing is invented: a target that hasn't been
    /// set produces no goal rather than a default one, because "your goal is
    /// 10,000 steps" is a lie if they never chose it.
    private static func goals(appState: AppState) -> [CoachContext.Goal] {
        var out: [CoachContext.Goal] = []
        let care = appState.careSettings
        let healthSettings = appState.healthSettings

        if let goalWeight = appState.workoutSettings.goalWeightKg {
            out.append(.init(
                id: "goal-weight",
                category: "body",
                summary: "Reach a body weight of \(goalWeight.weightDisplay) kg"
            ))
        }

        if care.stepGoal > 0 {
            out.append(.init(
                id: "goal-steps",
                category: "activity",
                summary: "Walk \(care.stepGoal.formatted()) steps a day"
            ))
        }

        out.append(.init(
            id: "goal-sleep",
            category: "sleep",
            summary: "Sleep \(HealthInsights.formatDuration(healthSettings.sleepGoalMinutes)) a night"
        ))

        out.append(.init(
            id: "goal-active-minutes",
            category: "fitness",
            summary: "\(healthSettings.exerciseGoalMinutes) active minutes a day"
        ))

        return out
    }

    // MARK: Sleep

    private static func sleepSection(
        _ health: HealthSnapshot,
        warnings: inout [String]
    ) -> CoachContext.Sleep? {
        let duration = health.sleepMinutes
        guard duration.state.hasValue, let minutes = duration.value else {
            warnings.append(
                health.hasConnectedSource
                    ? "No sleep recorded for last night."
                    : "No sleep recorded — no tracker is connected."
            )
            return nil
        }

        if duration.state == .stale, let day = duration.dayKey {
            warnings.append("The most recent sleep on file is from \(day), not last night.")
        }
        switch duration.confidence {
        case .low:
            warnings.append("Last night's sleep is poorly recorded, so treat the figure as approximate.")
        case .medium where duration.state == .partial:
            warnings.append("Last night's sleep stages are only partly covered.")
        default:
            break
        }

        let vsBaseline = health.sleepVsBaselineMinutes
        if vsBaseline.state == .insufficientHistory {
            warnings.append(
                "Not enough sleep history yet to compare last night against your usual — "
                + "\(vsBaseline.sampleCount) of \(vsBaseline.requiredSamples) nights recorded."
            )
        }

        return CoachContext.Sleep(
            score: health.sleepScore.value,
            durationMinutes: minutes,
            // Formatted once, here, from the same helper the Today screen uses.
            durationText: HealthInsights.formatDuration(minutes),
            vsBaselineMinutes: vsBaseline.value,
            efficiencyPercent: health.sleepEfficiencyPercent.value,
            confidence: duration.confidence.asContextConfidence,
            quality: duration.state.asDataQuality,
            state: duration.state
        )
    }

    // MARK: Recovery

    /// Recovery, whenever a measurement exists.
    ///
    /// The old version returned nil unless a baseline could be computed, and the
    /// warning it emitted in that case said "No recovery data". So the coach
    /// denied readings the Health tab was displaying at that exact moment. A
    /// measurement without a baseline is now sent, marked
    /// `insufficientHistory`, and the sentence that goes with it comes from
    /// `HealthSnapshot.recoveryStatement` so the coach and the screen say the
    /// same thing.
    private static func recoverySection(
        _ health: HealthSnapshot,
        warnings: inout [String]
    ) -> CoachContext.Recovery? {
        let hrv = health.hrvMs
        let rhr = health.restingHeartRate

        guard hrv.state.hasValue || rhr.state.hasValue else {
            warnings.append(health.recoveryStatement)
            return nil
        }

        let readiness = health.readiness
        if readiness.state == .insufficientHistory || readiness.state == .missing {
            warnings.append(health.recoveryStatement)
        }
        if hrv.state == .stale || rhr.state == .stale {
            warnings.append("Recovery figures are not from today.")
        }

        // The section's own state is the weaker of the two readings: advice can
        // be no surer than the shakier half of what it rests on.
        let state = [hrv.state, rhr.state]
            .filter { $0.hasValue }
            .min(by: { rank($0) < rank($1) }) ?? .missing

        let bothInterpretable = hrv.state == .ready && rhr.state == .ready

        return CoachContext.Recovery(
            hrvStatus: status(for: health.hrvBaseline),
            restingHeartRateStatus: status(for: health.restingHeartRateBaseline),
            readinessScore: readiness.value,
            confidence: bothInterpretable ? .high : .medium,
            quality: state.asDataQuality,
            state: state,
            hasHrvMeasurement: hrv.state.hasValue,
            hasRestingHeartRateMeasurement: rhr.state.hasValue,
            baselineNightsRecorded: max(hrv.sampleCount, rhr.sampleCount),
            baselineNightsRequired: HealthSnapshot.baselineSampleRequirement
        )
    }

    /// Orders states worst-first, so "the weaker of the two" has a definition.
    private static func rank(_ state: MetricState) -> Int {
        switch state {
        case .missing:              return 0
        case .stale:                return 1
        case .insufficientHistory:  return 2
        case .partial:              return 3
        case .ready:                return 4
        }
    }

    /// Turns a baseline comparison into a word.
    ///
    /// `isMeaningful` is what stops a 1% wobble being reported as a change —
    /// the brief's "avoid dramatic conclusions from one reading", enforced here
    /// rather than left to the model's judgement.
    private static func status(
        for comparison: BaselineComparison?
    ) -> CoachContext.Recovery.BaselineStatus? {
        guard let comparison else { return nil }
        guard comparison.isMeaningful else { return .normal }
        return comparison.direction == .above ? .aboveBaseline : .belowBaseline
    }

    // MARK: Activity

    private static func activitySection(
        _ health: HealthSnapshot,
        appState: AppState,
        warnings: inout [String]
    ) -> CoachContext.Activity? {
        let steps = health.steps

        if !steps.state.hasValue {
            warnings.append(
                health.hasConnectedSource
                    ? "No steps recorded today yet — the tracker may not have synced."
                    : "No steps recorded — no tracker is connected."
            )
        }

        return CoachContext.Activity(
            steps: steps.value,
            stepGoal: appState.careSettings.stepGoal > 0 ? appState.careSettings.stepGoal : nil,
            activeMinutes: health.activeMinutes.value,
            activeMinutesGoal: appState.healthSettings.exerciseGoalMinutes,
            // Any figure for today is still accumulating, by definition.
            isPartialDay: true,
            source: health.source,
            quality: steps.state.asDataQuality,
            state: steps.state
        )
    }

    // MARK: Training

    private static func trainingSection(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Training? {
        let finished = appState.completedWorkouts
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }

        let planned = appState.plannedSessions.first {
            calendar.isDateInToday($0.date) && !$0.completed
        }

        let lastDaysAgo = finished.first?.finishedAt.flatMap {
            calendar.dateComponents([.day], from: $0, to: now).day
        }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        let thisWeek = finished.filter { session in
            guard let start = weekStart, let finishedAt = session.finishedAt else { return false }
            return finishedAt >= start
        }

        guard planned != nil || !finished.isEmpty else { return nil }

        return CoachContext.Training(
            plannedWorkout: planned?.routineName,
            routines: appState.routines.prefix(maximumCandidates).map {
                CoachContext.Named(id: $0.id, name: $0.name)
            },
            lastWorkoutDaysAgo: lastDaysAgo,
            recentLoad: load(sessionsThisWeek: thisWeek.count),
            sessionsThisWeek: thisWeek.count
        )
    }

    /// Load by session count rather than volume.
    ///
    /// Volume in kilograms isn't comparable across a leg day and an arm day, so
    /// totalling it and calling the result "heavy" would say more about which
    /// muscles were trained than about how hard the week was.
    private static func load(sessionsThisWeek: Int) -> CoachContext.Training.Load {
        switch sessionsThisWeek {
        case ...1: return .light
        case 2...3: return .moderate
        default:   return .heavy
        }
    }

    // MARK: Tasks

    private static func tasksSection(
        appState: AppState,
        permissions: Permissions,
        now: Date,
        calendar: Calendar
    ) -> CoachContext.Tasks? {
        let outstanding = appState.tasks.filter { !$0.done }
        guard !outstanding.isEmpty else {
            return CoachContext.Tasks(
                lists: taskLists(appState: appState, permissions: permissions),
                importantRemaining: 0,
                totalRemainingToday: 0,
                nextDeadline: nil,
                topCandidates: []
            )
        }

        let dueToday = outstanding.filter { task in
            guard let date = task.resolvedDate else { return false }
            return calendar.isDateInToday(date)
        }

        let important = outstanding.filter { $0.priority == .high }

        let nextDeadline = outstanding
            .compactMap(\.resolvedDate)
            .filter { $0 >= calendar.startOfDay(for: now) }
            .min()

        // Ordered the way the app itself would: high priority first, then by
        // due date. The coach picks from the top of a shortlist rather than
        // being handed everything and asked to sort.
        let ranked = outstanding.sorted { a, b in
            if a.priority != b.priority { return a.priority.rank > b.priority.rank }
            switch (a.resolvedDate, b.resolvedDate) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return false
            }
        }

        let candidates = ranked.prefix(maximumCandidates).map { task in
            CoachContext.Tasks.Candidate(
                id: task.id,
                title: permissions.includeTitles ? task.title : "A task",
                priority: task.priority.contextLabel,
                estimatedMinutes: task.estimatedMinutes,
                dueToday: task.resolvedDate.map { calendar.isDateInToday($0) } ?? false
            )
        }

        return CoachContext.Tasks(
            lists: taskLists(appState: appState, permissions: permissions),
            importantRemaining: important.count,
            totalRemainingToday: dueToday.count,
            nextDeadline: nextDeadline,
            topCandidates: Array(candidates)
        )
    }

    private static func taskLists(
        appState: AppState, permissions: Permissions
    ) -> [CoachContext.Named] {
        guard permissions.includeTitles else { return [] }
        return appState.taskLists.map { CoachContext.Named(id: $0.id, name: $0.name) }
    }

    // MARK: Habits

    private static func habitsSection(
        appState: AppState,
        permissions: Permissions,
        dayKey todayKey: String
    ) -> CoachContext.Habits? {
        let active = appState.habits.filter { !$0.isArchived }
        guard !active.isEmpty else { return nil }

        // The day key comes from the snapshot rather than being recomputed. A
        // context built either side of midnight would otherwise count habits
        // against one day and sleep against another.
        func isComplete(_ habit: Habit) -> Bool {
            let log = habit.logs.first { $0.dayKey == todayKey }
            let slipped = log?.slipped == true
            if habit.kind == .break { return !slipped }
            return !slipped && (log?.count ?? 0) >= habit.targetCount
        }

        let outstanding = active.filter { !isComplete($0) }

        // A streak is what makes an unfinished habit worth mentioning today
        // rather than tomorrow, so the shortlist is the longest streaks at
        // risk — those are the ones with something to lose.
        let atRisk = outstanding
            .map { (habit: $0, streak: appState.streakFor($0)) }
            .sorted { $0.streak > $1.streak }
            .prefix(maximumCandidates)
            .map { entry in
                CoachContext.Habits.Candidate(
                    id: entry.habit.id,
                    title: permissions.includeTitles ? entry.habit.name : "A habit",
                    streak: entry.streak
                )
            }

        return CoachContext.Habits(
            remaining: outstanding.count,
            completedToday: active.count - outstanding.count,
            atRisk: Array(atRisk)
        )
    }
}

// MARK: - Supporting

/// Bridges the snapshot's vocabulary to the coach's.
///
/// Two enums rather than one because they answer different questions and are
/// consumed by different things — `MetricState` is what the app holds, and
/// `DataQuality` is what the model is told. The mapping lives here, once, so a
/// new state can't reach the wire as an unconsidered default.
extension MetricState {
    var asDataQuality: CoachContext.DataQuality {
        switch self {
        case .missing:             return .missing
        case .stale:               return .suspect
        case .insufficientHistory: return .partial
        case .partial:             return .partial
        case .ready:               return .verified
        }
    }
}

extension DataConfidence {
    var asContextConfidence: CoachContext.Confidence {
        switch self {
        case .low:    return .low
        case .medium: return .medium
        case .high:   return .high
        }
    }
}

private extension TaskPriority {
    /// Ordering weight. `TaskPriority` is a display type, so the ranking lives
    /// here rather than being read off the enum's declaration order.
    var rank: Int {
        switch self {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        case .none:   return 0
        }
    }

    /// The word sent to the coach — lowercase and stable, independent of
    /// whatever the UI happens to call it.
    var contextLabel: String {
        switch self {
        case .high:   return "high"
        case .medium: return "medium"
        case .low:    return "low"
        case .none:   return "none"
        }
    }
}
