import Foundation

// MARK: - Plateau Engine

/// An exercise that has stopped moving.
///
/// The detection is the app's; the *explanation* is not anyone's. A plateau has
/// a hundred causes — sleep, stress, a new job, a technique change, ordinary
/// biology — and the app knows none of them. So this reports the observation and
/// the evidence, and neither it nor the model is permitted to claim a cause.
///
/// Comparability is the hard part and most of the code. Four sessions of the
/// same exercise across at least three weeks, incomplete sessions excluded
/// rather than counted as regression: someone who cut a session short because
/// the gym was closing has not got weaker, and treating it as evidence would
/// generate a plateau out of a car park.
///
/// Pure. The single store-reading entry point is `@MainActor`.
enum PlateauEngine {

    // MARK: Findings

    struct Finding: Equatable, Sendable, Identifiable {
        var id: String { exerciseId }
        var exerciseId: String
        var exerciseName: String
        /// Sessions the judgement is based on.
        var sessions: Int
        var weeks: Int
        /// Heaviest working set, first session to last.
        var startWeight: Double
        var currentWeight: Double
        /// Best total working volume in the window, for the case where load is
        /// flat but work is still increasing — which is progress, not a plateau.
        var bestVolume: Double
        var evidence: [String]
    }

    // MARK: Thresholds

    /// Comparable sessions required before "no progress" means anything.
    static let minimumSessions = 4
    /// Distinct weeks those sessions must span.
    static let minimumWeeks = 3
    /// How far back to look.
    static let windowWeeks = 8
    /// Load change below this fraction counts as flat.
    ///
    /// 2% — smaller than the smallest plate on most bars, so it catches "the
    /// same weight" without calling a genuine 2.5 kg step a plateau.
    static let flatThreshold = 0.02
    /// Working sets required for a session to be comparable at all.
    static let minimumWorkingSets = 2

    // MARK: Detection

    @MainActor
    static func findings(
        appState: AppState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Finding] {
        let cutoff = calendar.date(byAdding: .day, value: -7 * windowWeeks, to: now) ?? now

        /// One comparable performance.
        struct Point {
            var date: Date
            var topWeight: Double
            var volume: Double
        }

        var points: [String: [Point]] = [:]

        for session in appState.completedWorkouts {
            guard let finishedAt = session.finishedAt, finishedAt >= cutoff else { continue }

            for performed in session.exercises {
                let working = performed.sets.filter { $0.done && !$0.isWarmup && $0.weight > 0 }
                // Not enough of the exercise happened to compare it with a full
                // session. Excluded, not counted as a step backwards.
                guard working.count >= minimumWorkingSets else { continue }

                let top = working.map(\.weight).max() ?? 0
                let volume = working.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                points[performed.exerciseId, default: []]
                    .append(Point(date: finishedAt, topWeight: top, volume: volume))
            }
        }

        var out: [Finding] = []

        for (exerciseId, unsorted) in points.sorted(by: { $0.key < $1.key }) {
            let sorted = unsorted.sorted { $0.date < $1.date }
            guard sorted.count >= minimumSessions else { continue }

            let weeks = Set(sorted.map { WeeklyReview.startOfWeek(containing: $0.date, calendar: calendar) })
            guard weeks.count >= minimumWeeks else { continue }

            guard let first = sorted.first, let last = sorted.last else { continue }
            guard first.topWeight > 0 else { continue }

            let change = (last.topWeight - first.topWeight) / first.topWeight
            guard change < flatThreshold else { continue }

            // Load flat but volume climbing is progress by another route. Sets
            // and reps are how most people actually progress, and calling that
            // a plateau would be the app failing to recognise the thing it
            // recommends.
            let bestVolume = sorted.map(\.volume).max() ?? 0
            let lastVolume = last.volume
            let earlyBest = sorted.dropLast().map(\.volume).max() ?? 0
            if earlyBest > 0, lastVolume > earlyBest * (1 + flatThreshold) { continue }

            guard let exercise = appState.exercises.first(where: { $0.id == exerciseId }) else { continue }

            out.append(
                Finding(
                    exerciseId: exerciseId,
                    exerciseName: exercise.name,
                    sessions: sorted.count,
                    weeks: weeks.count,
                    startWeight: first.topWeight,
                    currentWeight: last.topWeight,
                    bestVolume: bestVolume,
                    evidence: [
                        "\(sorted.count) sessions over \(weeks.count) weeks.",
                        change < 0
                            ? "Top set down from \(first.topWeight.formatted1)kg to \(last.topWeight.formatted1)kg."
                            : "Top set has stayed at about \(last.topWeight.formatted1)kg.",
                        "Total work per session hasn't grown either.",
                    ]
                )
            )
        }

        // Two is a conversation. Six is a report nobody finishes.
        return Array(out.prefix(2))
    }

    /// What the model is told, and it is only this.
    ///
    /// Numbers and an exercise name — no dates, no session log, and nothing
    /// about health. The model's job is to pick remedies from a closed list and
    /// explain them; it has no material with which to speculate about a cause,
    /// which is the point.
    nonisolated static func promptText(for finding: Finding) -> String {
        """
        Exercise: \(finding.exerciseName). \
        \(finding.sessions) comparable sessions over \(finding.weeks) weeks. \
        Top working set started at \(finding.startWeight.formatted1)kg and is now \
        \(finding.currentWeight.formatted1)kg. Total working volume has not increased.
        """
    }
}

// MARK: - Plateau advice

/// What the model may suggest about a plateau: six remedies and a sentence.
///
/// Strict `Codable`. A remedy this version doesn't implement fails to decode, so
/// it can never reach a button that appears to perform it.
struct PlateauAdvice: Codable, Equatable, Sendable {

    enum Remedy: String, Codable, CaseIterable, Sendable {
        case smallerIncrements
        case repRangeChange
        case orderChange
        case volumeAdjust
        case substitute
        case lighterWeek

        var label: String {
            switch self {
            case .smallerIncrements: return "Add less each time"
            case .repRangeChange:    return "Change the rep range"
            case .orderChange:       return "Move it earlier in the session"
            case .volumeAdjust:      return "Change the number of sets"
            case .substitute:        return "Swap it for something similar"
            case .lighterWeek:       return "Take a lighter week"
            }
        }

        /// Which of these the app can actually carry out, and where.
        var isActionable: Bool {
            switch self {
            case .substitute, .lighterWeek, .volumeAdjust: return true
            case .smallerIncrements, .repRangeChange, .orderChange: return false
            }
        }
    }

    var remedies: [Remedy]
    /// One or two sentences. Describes the options, never the cause.
    var explanation: String

    enum CodingKeys: String, CodingKey { case remedies, explanation }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""

        let raw = try c.decodeIfPresent([String].self, forKey: .remedies) ?? []
        // Unknown remedies are dropped rather than throwing: the explanation is
        // still worth reading, and a missing option is a smaller loss than an
        // error page. The closed enum is what stops an unimplemented one being
        // offered.
        remedies = raw.compactMap { Remedy(rawValue: $0) }
    }

    init(remedies: [Remedy], explanation: String) {
        self.remedies = remedies
        self.explanation = explanation
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(remedies.map(\.rawValue), forKey: .remedies)
        try c.encode(explanation, forKey: .explanation)
    }
}

// MARK: - Local advice

/// The same six remedies, chosen by rule.
///
/// Exists because cloud AI is off by default, and a plateau card that only
/// appears for people who enabled Gemini is a feature most users never meet.
enum LocalPlateauAdvice {

    nonisolated static func advice(for finding: PlateauEngine.Finding) -> PlateauAdvice {
        var remedies: [PlateauAdvice.Remedy] = [.smallerIncrements, .repRangeChange]

        // Losing ground rather than merely holding it.
        if finding.currentWeight < finding.startWeight {
            remedies.append(.lighterWeek)
        } else {
            remedies.append(.volumeAdjust)
        }

        return PlateauAdvice(
            remedies: remedies,
            explanation: "\(finding.exerciseName) hasn't moved in \(finding.weeks) weeks. These are the usual things to try — the app can't tell you why it stalled, only that it has."
        )
    }
}
