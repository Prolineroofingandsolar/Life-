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
        calendar: Calendar = .current
    ) -> CoachContext {
        var warnings: [String] = []

        let health = appState.healthHistory
        let settings = appState.healthSettings

        let sleep = permissions.health
            ? sleepSection(appState: appState, health: health, settings: settings, warnings: &warnings)
            : nil
        let recovery = permissions.health
            ? recoverySection(appState: appState, health: health, settings: settings, warnings: &warnings)
            : nil
        let activity = permissions.activity
            ? activitySection(appState: appState, settings: settings, warnings: &warnings)
            : nil
        let training = permissions.training
            ? trainingSection(appState: appState, now: now, calendar: calendar)
            : nil
        let tasks = permissions.tasks
            ? tasksSection(appState: appState, permissions: permissions, now: now, calendar: calendar)
            : nil
        let habits = permissions.habits
            ? habitsSection(appState: appState, permissions: permissions)
            : nil

        return CoachContext(
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
        appState: AppState,
        health: [HealthDay],
        settings: HealthSettings,
        warnings: inout [String]
    ) -> CoachContext.Sleep? {
        guard let night = appState.lastNightSleep else {
            warnings.append("No sleep recorded for last night.")
            return nil
        }

        // Read, don't recompute. This is the same score the Sleep screen shows.
        let score = HealthInsights.sleepScore(health, settings: settings)?.value

        // The user's own recent average, not a population figure. Nil until
        // there are enough nights for an average to mean anything.
        let baseline = appState.healthBaseline({ $0.sleepMin.map(Double.init) })
        let vsBaseline: Int? = {
            guard let minutes = night.sleepMin, let baseline else { return nil }
            return Int((Double(minutes) - baseline).rounded())
        }()

        // Stage coverage is the honest measure of whether a night was properly
        // recorded. A band that lost contact for three hours still reports a
        // duration; it just isn't one worth being confident about.
        let coverage = night.stageCoverage
        let confidence: CoachContext.Confidence
        let quality: CoachContext.DataQuality
        switch coverage {
        case .some(let value) where value >= 0.8:
            confidence = .high
            quality = .verified
        case .some(let value) where value >= 0.5:
            confidence = .medium
            quality = .partial
            warnings.append("Last night's sleep stages are only \(Int(value * 100))% covered.")
        case .some(let value):
            confidence = .low
            quality = .partial
            warnings.append("Last night's sleep is poorly recorded — \(Int(value * 100))% stage coverage.")
        case nil:
            // No stage breakdown at all. A total duration is still useful.
            confidence = night.sleepMin == nil ? .low : .medium
            quality = night.sleepMin == nil ? .missing : .partial
        }

        if vsBaseline == nil {
            warnings.append("Not enough sleep history yet to compare last night against your usual.")
        }

        return CoachContext.Sleep(
            score: score,
            durationMinutes: night.sleepMin,
            vsBaselineMinutes: vsBaseline,
            efficiencyPercent: night.sleepEfficiency.map { Int(($0 * 100).rounded()) },
            confidence: confidence,
            quality: quality
        )
    }

    // MARK: Recovery

    private static func recoverySection(
        appState: AppState,
        health: [HealthDay],
        settings: HealthSettings,
        warnings: inout [String]
    ) -> CoachContext.Recovery? {
        let hrvTrend = HealthInsights.trend(health, metric: { $0.hrvMs })
        let rhrTrend = HealthInsights.trend(health, metric: { $0.restingHr })
        let readiness = HealthInsights.readinessScore(health, settings: settings)?.value

        guard hrvTrend != nil || rhrTrend != nil || readiness != nil else {
            warnings.append("No recovery data — nothing recorded for HRV or resting heart rate.")
            return nil
        }

        // Both trends nil-out below a minimum sample count, so a status here
        // always rests on a real baseline rather than one or two readings.
        let confidence: CoachContext.Confidence = (hrvTrend != nil && rhrTrend != nil)
            ? .high
            : .medium

        return CoachContext.Recovery(
            hrvStatus: status(for: hrvTrend, higherIsBetter: true),
            restingHeartRateStatus: status(for: rhrTrend, higherIsBetter: false),
            readinessScore: readiness,
            confidence: confidence,
            quality: (hrvTrend != nil && rhrTrend != nil) ? .verified : .partial
        )
    }

    /// Turns a trend into a word.
    ///
    /// `isMeaningful` is what stops a 1% wobble being reported as a change —
    /// the brief's "avoid dramatic conclusions from one reading", enforced here
    /// rather than left to the model's judgement.
    private static func status(
        for trend: HealthInsights.Trend?,
        higherIsBetter: Bool
    ) -> CoachContext.Recovery.BaselineStatus? {
        guard let trend else { return nil }
        guard trend.isMeaningful else { return .normal }
        let above = trend.delta > 0
        return above ? .aboveBaseline : .belowBaseline
    }

    // MARK: Activity

    private static func activitySection(
        appState: AppState,
        settings: HealthSettings,
        warnings: inout [String]
    ) -> CoachContext.Activity? {
        let todayKey = appState.todayKey
        let care = appState.careDays[todayKey]
        let today = appState.healthDays[todayKey]

        // Zero steps stored is not the same as no steps recorded, and the
        // difference decides whether the right advice is "get moving" or "your
        // tracker hasn't synced". `CareDay.steps` is non-optional and defaults
        // to 0, so absence is inferred from the record not existing.
        let hasStepRecord = (care?.steps ?? 0) > 0

        if !hasStepRecord {
            warnings.append("No steps recorded today yet — the tracker may not have synced.")
        }

        return CoachContext.Activity(
            steps: hasStepRecord ? care?.steps : nil,
            stepGoal: appState.careSettings.stepGoal > 0 ? appState.careSettings.stepGoal : nil,
            activeMinutes: today?.exerciseMinutes,
            activeMinutesGoal: settings.exerciseGoalMinutes,
            // Any figure for today is still accumulating, by definition.
            isPartialDay: true,
            source: HealthSync.source(for: settings).provider?.detailedName,
            quality: hasStepRecord ? .partial : .missing
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
            importantRemaining: important.count,
            totalRemainingToday: dueToday.count,
            nextDeadline: nextDeadline,
            topCandidates: Array(candidates)
        )
    }

    // MARK: Habits

    private static func habitsSection(
        appState: AppState,
        permissions: Permissions
    ) -> CoachContext.Habits? {
        let active = appState.habits.filter { !$0.isArchived }
        guard !active.isEmpty else { return nil }

        let todayKey = appState.todayKey

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
