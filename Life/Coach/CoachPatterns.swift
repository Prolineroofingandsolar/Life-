import Foundation

// MARK: - Coach Patterns

/// The connections between one part of someone's life and another.
///
/// This is the material a coach reasons with and a fact-reciter doesn't have.
/// "You slept 7h 12m" is a reading. "You train two days out of three when
/// you've slept over seven hours, and one day out of three when you haven't"
/// is a *reason to go to bed*, and it is the kind of thing the app can work out
/// from records it already holds and the model cannot work out from a snapshot
/// of today.
///
/// Found deterministically, and every one carries its sample size. That matters
/// more here than anywhere else in the app: a correlation over four days is
/// noise wearing a lab coat, and a model handed one will happily build a
/// paragraph of advice on it. The thresholds below are what stop that.
///
/// **Not causal, and worded so.** Every pattern is "on days when X, Y tends to
/// be Z" — a description of the record, never a claim about why. The model is
/// instructed the same way, and the wording here is what it echoes.
enum CoachPatterns {

    // MARK: A pattern

    struct Pattern: Codable, Equatable, Sendable, Identifiable {
        var id: String { key }
        /// Stable identifier, so the same finding is recognisable across days.
        var key: String
        /// The observation, in the app's own words. Sent as prose because the
        /// model's job is to decide whether it matters today, not to phrase it.
        var statement: String
        /// Days or sessions behind it. Sent so the model can hedge — and so a
        /// thin finding reads as thin rather than as fact.
        var samples: Int
        /// How strong the difference is: `slight`, `clear`, `strong`.
        var strength: Strength

        enum Strength: String, Codable, Sendable {
            case slight, clear, strong
        }
    }

    // MARK: Thresholds

    /// Days on each side of a comparison before it is worth reporting.
    ///
    /// Five. Below that a "pattern" is a fortnight with one good week in it, and
    /// the honest thing is silence.
    static let minimumDaysPerSide = 5
    /// Proportional difference before a comparison says anything at all.
    static let slightDifference = 0.12
    static let clearDifference = 0.25
    static let strongDifference = 0.4
    /// How far back to look.
    static let windowDays = 56
    /// The most patterns worth sending. A coach that lists nine correlations is
    /// a spreadsheet.
    static let maximum = 4

    // MARK: Finding them

    @MainActor
    static func patterns(
        appState: AppState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Pattern] {
        var found: [Pattern] = []

        if let sleepAndSteps = sleepVersusActivity(appState: appState, now: now, calendar: calendar) {
            found.append(sleepAndSteps)
        }
        if let sleepAndTraining = sleepVersusTraining(appState: appState, now: now, calendar: calendar) {
            found.append(sleepAndTraining)
        }
        if let trainingAndSleep = trainingVersusSleep(appState: appState, now: now, calendar: calendar) {
            found.append(trainingAndSleep)
        }
        if let weekday = strongestWeekday(appState: appState, now: now, calendar: calendar) {
            found.append(weekday)
        }
        if let habits = habitsVersusSleep(appState: appState, now: now, calendar: calendar) {
            found.append(habits)
        }

        // Strongest first — if only two survive the size cap, they should be
        // the two worth acting on.
        let order: [Pattern.Strength: Int] = [.strong: 0, .clear: 1, .slight: 2]
        return found
            .sorted { (order[$0.strength] ?? 3, $0.key) < (order[$1.strength] ?? 3, $1.key) }
            .prefix(maximum)
            .map { $0 }
    }

    // MARK: Sleep → activity

    @MainActor
    private static func sleepVersusActivity(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> Pattern? {
        var wellSlept: [Int] = []
        var poorlySlept: [Int] = []

        for offset in 1...windowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DayKey.string(for: day, calendar: calendar)
            guard let sleep = appState.healthDays[key]?.sleepMin, sleep > 0 else { continue }
            guard let steps = appState.careDays[key]?.steps, steps > 0 else { continue }

            if sleep >= 7 * 60 { wellSlept.append(steps) } else { poorlySlept.append(steps) }
        }

        guard let comparison = compare(wellSlept, poorlySlept) else { return nil }
        return Pattern(
            key: "sleep-steps",
            statement: comparison.higher
                ? "On days after seven hours' sleep or more, they average \(comparison.aAverage) steps; after less, \(comparison.bAverage)."
                : "Steps are about the same whether they slept well or not (\(comparison.aAverage) against \(comparison.bAverage)).",
            samples: wellSlept.count + poorlySlept.count,
            strength: comparison.strength
        )
    }

    // MARK: Sleep → training

    /// Whether a good night predicts a session actually happening.
    @MainActor
    private static func sleepVersusTraining(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> Pattern? {
        let trainedKeys = Set(
            appState.completedWorkouts.compactMap { session -> String? in
                guard let finishedAt = session.finishedAt else { return nil }
                return DayKey.string(for: finishedAt, calendar: calendar)
            }
        )

        var wellSleptTrained = 0, wellSleptTotal = 0
        var poorlySleptTrained = 0, poorlySleptTotal = 0

        for offset in 1...windowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DayKey.string(for: day, calendar: calendar)
            guard let sleep = appState.healthDays[key]?.sleepMin, sleep > 0 else { continue }

            let trained = trainedKeys.contains(key)
            if sleep >= 7 * 60 {
                wellSleptTotal += 1
                if trained { wellSleptTrained += 1 }
            } else {
                poorlySleptTotal += 1
                if trained { poorlySleptTrained += 1 }
            }
        }

        guard wellSleptTotal >= minimumDaysPerSide, poorlySleptTotal >= minimumDaysPerSide else { return nil }

        let wellRate = Double(wellSleptTrained) / Double(wellSleptTotal)
        let poorRate = Double(poorlySleptTrained) / Double(poorlySleptTotal)
        guard let strength = strength(of: difference(wellRate, poorRate)) else { return nil }

        return Pattern(
            key: "sleep-training",
            statement: wellRate > poorRate
                ? "They train on \(percent(wellRate)) of days following seven hours' sleep, against \(percent(poorRate)) of days following less."
                : "Training happens about as often after a short night as a long one.",
            samples: wellSleptTotal + poorlySleptTotal,
            strength: strength
        )
    }

    // MARK: Training → sleep

    /// The other direction, which is a different question and often a more
    /// useful one.
    @MainActor
    private static func trainingVersusSleep(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> Pattern? {
        let trainedKeys = Set(
            appState.completedWorkouts.compactMap { session -> String? in
                guard let finishedAt = session.finishedAt else { return nil }
                return DayKey.string(for: finishedAt, calendar: calendar)
            }
        )

        var afterTraining: [Int] = []
        var afterRest: [Int] = []

        for offset in 1...windowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now),
                  let previous = calendar.date(byAdding: .day, value: -1, to: day) else { continue }
            let key = DayKey.string(for: day, calendar: calendar)
            guard let sleep = appState.healthDays[key]?.sleepMin, sleep > 0 else { continue }

            if trainedKeys.contains(DayKey.string(for: previous, calendar: calendar)) {
                afterTraining.append(sleep)
            } else {
                afterRest.append(sleep)
            }
        }

        guard let comparison = compare(afterTraining, afterRest) else { return nil }
        guard comparison.strength != .slight else { return nil }

        return Pattern(
            key: "training-sleep",
            statement: comparison.higher
                ? "They sleep about \(comparison.aAverage - comparison.bAverage) minutes longer on nights after training."
                : "They sleep about \(comparison.bAverage - comparison.aAverage) minutes less on nights after training.",
            samples: afterTraining.count + afterRest.count,
            strength: comparison.strength
        )
    }

    // MARK: Weekday

    /// The day of the week training actually happens on, against the rest.
    @MainActor
    private static func strongestWeekday(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> Pattern? {
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: now) else { return nil }

        var counts: [Int: Int] = [:]
        var total = 0
        for session in appState.completedWorkouts {
            guard let finishedAt = session.finishedAt, finishedAt >= cutoff else { continue }
            counts[calendar.component(.weekday, from: finishedAt), default: 0] += 1
            total += 1
        }

        // Eight sessions across eight weeks is the floor for saying anything
        // about which day someone prefers.
        guard total >= 8 else { return nil }
        guard let (weekday, best) = counts.max(by: { $0.value < $1.value }) else { return nil }
        guard let (_, worst) = counts.min(by: { $0.value < $1.value }) else { return nil }
        guard best >= worst * 2, best >= 3 else { return nil }

        let name = calendar.weekdaySymbols[max(0, weekday - 1)]
        return Pattern(
            key: "weekday",
            statement: "\(name) is their most reliable training day — \(best) of the last \(total) sessions.",
            samples: total,
            strength: best >= worst * 3 ? .strong : .clear
        )
    }

    // MARK: Habits → sleep

    @MainActor
    private static func habitsVersusSleep(
        appState: AppState,
        now: Date,
        calendar: Calendar
    ) -> Pattern? {
        var goodNights: [Int] = []
        var badNights: [Int] = []

        for offset in 1...windowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DayKey.string(for: day, calendar: calendar)
            guard let sleep = appState.healthDays[key]?.sleepMin, sleep > 0 else { continue }

            let active = appState.habits.filter { !$0.isArchived }
            guard !active.isEmpty else { return nil }
            let completed = active.filter { habit in
                habit.logs.contains { $0.dayKey == key && !$0.slipped && $0.count >= habit.targetCount }
            }.count

            // "Most of them" rather than "all", which almost never happens and
            // would compare a handful of perfect days against everything else.
            if Double(completed) / Double(active.count) >= 0.6 {
                goodNights.append(sleep)
            } else {
                badNights.append(sleep)
            }
        }

        guard let comparison = compare(goodNights, badNights) else { return nil }
        guard comparison.strength != .slight else { return nil }

        return Pattern(
            key: "habits-sleep",
            statement: comparison.higher
                ? "On days they keep most of their habits, they sleep about \(comparison.aAverage - comparison.bAverage) minutes longer."
                : "Sleep is no longer on days they keep their habits.",
            samples: goodNights.count + badNights.count,
            strength: comparison.strength
        )
    }

    // MARK: Comparison arithmetic

    private struct Comparison {
        var aAverage: Int
        var bAverage: Int
        var higher: Bool
        var strength: Pattern.Strength
    }

    /// Two groups, compared only if both are big enough to mean something.
    private static func compare(_ a: [Int], _ b: [Int]) -> Comparison? {
        guard a.count >= minimumDaysPerSide, b.count >= minimumDaysPerSide else { return nil }

        let aAverage = a.reduce(0, +) / a.count
        let bAverage = b.reduce(0, +) / b.count
        guard bAverage > 0 else { return nil }

        guard let strength = strength(of: difference(Double(aAverage), Double(bAverage))) else { return nil }
        return Comparison(
            aAverage: aAverage,
            bAverage: bAverage,
            higher: aAverage > bAverage,
            strength: strength
        )
    }

    private static func difference(_ a: Double, _ b: Double) -> Double {
        guard b > 0 else { return 0 }
        return abs(a - b) / b
    }

    private static func strength(of difference: Double) -> Pattern.Strength? {
        if difference >= strongDifference { return .strong }
        if difference >= clearDifference { return .clear }
        if difference >= slightDifference { return .slight }
        // Below the slight threshold there is no finding, and reporting one
        // anyway is how an app ends up telling someone that a 3% difference in
        // step count means something.
        return nil
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
