import Foundation

// MARK: - Deload Engine

/// When to suggest an easier week, and — far more often — when not to.
///
/// Two rules do all the work here, both from the brief:
///
/// - **Enough history, or nothing.** Six weeks of training before a deload can
///   be suggested at all. Someone four weeks into their first programme does
///   not need a deload; they need their fifth week.
/// - **Never from one bad thing.** Two independent signals, from different
///   sources. One poor session, one heavy week, one bad night — none of those
///   is a reason to tell somebody to back off, and the engine takes no health
///   data at all for the trigger, so a single low HRV reading cannot produce
///   one.
///
/// The proposal is exact: this many fewer sets, this much less load, this much
/// further from failure. Vague advice to "take it easy" is unactionable and
/// unfalsifiable; numbers can be looked at and rejected.
enum DeloadEngine {

    // MARK: Signals

    enum Signal: String, Equatable, Sendable, CaseIterable {
        /// A lift that has stopped moving.
        case plateau
        /// Sustained high fatigue across several muscle groups.
        case sustainedFatigue
        /// Completing far less than what was planned.
        case adherenceDrop
        /// Sets increasingly recorded at or beyond failure.
        case effortCreep

        var text: String {
            switch self {
            case .plateau:          return "A lift has stalled for several weeks."
            case .sustainedFatigue: return "Several muscle groups have stayed fatigued."
            case .adherenceDrop:    return "You've been completing much less than you planned."
            case .effortCreep:      return "More sets are ending at or past failure than usual."
            }
        }
    }

    // MARK: Proposal

    struct Proposal: Equatable, Sendable {
        var signals: [Signal]
        /// Weeks of history behind the judgement.
        var weeksOfHistory: Int
        var setsReductionPercent: Int
        var loadReductionPercent: Int
        var extraRIR: Int
        /// Sessions to drop from the week, where the programme has enough to
        /// spare. Zero means keep the same frequency.
        var sessionsToDrop: Int

        var evidence: [String] { signals.map(\.text) }

        var summary: String {
            "About \(setsReductionPercent)% fewer sets, \(loadReductionPercent)% lighter, and stopping \(extraRIR) reps further from failure — for one week."
        }
    }

    // MARK: Thresholds

    /// Weeks of training before a deload is even a possibility.
    static let minimumWeeksOfHistory = 6
    /// Independent signals required.
    static let minimumSignals = 2
    /// Muscles at or above this fatigue, for the fatigue signal.
    static let fatigueThreshold = 70
    /// How many such muscles.
    static let fatiguedMuscleCount = 3
    /// Adherence below this counts as a drop.
    static let adherenceFloor = 50
    /// Proportion of working sets at failure before effort is "creeping".
    static let failureRate = 0.3

    static let setsReduction = 30
    static let loadReduction = 10
    static let extraRIR = 2

    // MARK: Building

    @MainActor
    static func proposal(
        appState: AppState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Proposal? {
        let weeks = weeksOfHistory(appState: appState, now: now, calendar: calendar)
        guard weeks >= minimumWeeksOfHistory else { return nil }

        var signals: [Signal] = []

        if !PlateauEngine.findings(appState: appState, now: now, calendar: calendar).isEmpty {
            signals.append(.plateau)
        }

        let fatigued = MuscleRecoveryEngine.statuses(appState: appState)
            .filter { $0.hasTrainingHistory && $0.fatigue >= fatigueThreshold }
        if fatigued.count >= fatiguedMuscleCount {
            signals.append(.sustainedFatigue)
        }

        let metrics = WeeklyReview.metrics(appState: appState, now: now, calendar: calendar)
        // Only when there was a plan to fall short of. An absent adherence
        // figure is not a low one.
        if let adherence = metrics.adherencePercent,
           metrics.plannedSessions >= 3,
           adherence < adherenceFloor {
            signals.append(.adherenceDrop)
        }

        if hasEffortCreep(appState: appState, now: now, calendar: calendar) {
            signals.append(.effortCreep)
        }

        guard signals.count >= minimumSignals else { return nil }

        return Proposal(
            signals: signals,
            weeksOfHistory: weeks,
            setsReductionPercent: setsReduction,
            loadReductionPercent: loadReduction,
            extraRIR: extraRIR,
            sessionsToDrop: (appState.activeProgram?.days.filter { $0.routineId != nil }.count ?? 0) >= 5 ? 1 : 0
        )
    }

    @MainActor
    private static func weeksOfHistory(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let weeks = Set(
            appState.completedWorkouts.compactMap { session -> Date? in
                guard let finishedAt = session.finishedAt else { return nil }
                return WeeklyReview.startOfWeek(containing: finishedAt, calendar: calendar)
            }
        )
        return weeks.count
    }

    /// Sets ending at failure, this fortnight against the fortnight before.
    ///
    /// A comparison rather than an absolute: some people train to failure by
    /// design, and telling them their normal training is a warning sign would be
    /// the app misreading a preference as a problem.
    @MainActor
    private static func hasEffortCreep(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let recentStart = calendar.date(byAdding: .day, value: -14, to: now),
              let priorStart = calendar.date(byAdding: .day, value: -28, to: now) else { return false }

        func rate(from: Date, to: Date) -> Double? {
            var total = 0
            var failed = 0
            for session in appState.completedWorkouts {
                guard let finishedAt = session.finishedAt, finishedAt >= from, finishedAt < to else { continue }
                for performed in session.exercises {
                    let working = performed.sets.filter { $0.done && !$0.isWarmup }
                    total += working.count
                    failed += working.filter(\.isFailure).count
                }
            }
            guard total >= 10 else { return nil }
            return Double(failed) / Double(total)
        }

        guard let recent = rate(from: recentStart, to: now),
              let prior = rate(from: priorStart, to: recentStart) else { return false }

        return recent >= failureRate && recent > prior * 1.5
    }

    // MARK: Applying

    /// The deloaded version of a routine. Returned, not saved.
    ///
    /// Reps are untouched on purpose: fewer sets and less load already make the
    /// week easier, and cutting reps as well turns a deload into a week off.
    nonisolated static func deloaded(
        _ exercises: [RoutineExercise],
        proposal: Proposal
    ) -> [RoutineExercise] {
        exercises.map { item in
            var copy = item
            let reduced = Int((Double(item.defaultSets) * (1 - Double(proposal.setsReductionPercent) / 100)).rounded())
            copy.defaultSets = max(1, reduced)
            if item.defaultWeight > 0 {
                let lighter = item.defaultWeight * (1 - Double(proposal.loadReductionPercent) / 100)
                // To the nearest half kilo — the smallest change anyone can
                // actually load on a bar.
                copy.defaultWeight = (lighter * 2).rounded() / 2
            }
            return copy
        }
    }
}
