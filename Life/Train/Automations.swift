import Foundation

// MARK: - Automations

/// The six things the app will check on your behalf.
///
/// Ready-made, not a rule builder. Six specific checks that each map to an
/// engine already written and tested, because a general "when X then Y" builder
/// is a language, and a language whose statements change training data needs to
/// be right in ways six fixed checks do not.
///
/// The rule that shapes the whole type: **every automation proposes, and none of
/// them applies.** That is not a setting. `AutomationOutcome` has no case for a
/// change that has already happened, and there is no code path from a run to a
/// write — approval happens in the sheet each outcome opens, which is the same
/// sheet the user could have opened themselves.
///
/// Every outcome states why it ran, what it looked at, and whether rules or
/// Gemini produced it. An automation that can't say why it fired is a
/// notification, not a coach.
enum AutomationKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case weeklyReview
    case missedWorkout
    case progression
    case plateauReview
    case sessionDuration
    case programmeDrift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeklyReview:    return "Weekly review"
        case .missedWorkout:   return "Missed workouts"
        case .progression:     return "Progression"
        case .plateauReview:   return "Plateau check"
        case .sessionDuration: return "Session length"
        case .programmeDrift:  return "Programme drift"
        }
    }

    var explanation: String {
        switch self {
        case .weeklyReview:
            return "Once your week has two or more sessions in it, sums up what happened."
        case .missedWorkout:
            return "Notices a planned session that didn't happen, and offers days to move it to."
        case .progression:
            return "After a workout, works out next session's numbers from what you lifted."
        case .plateauReview:
            return "Spots a lift that hasn't moved across four sessions and three weeks."
        case .sessionDuration:
            return "Notices a routine that keeps running longer than it claims."
        case .programmeDrift:
            return "Notices when your training and your programme have stopped agreeing."
        }
    }

    /// Whether a model is involved at all. Stated on the card, because "who
    /// wrote this" is the first thing worth knowing about advice.
    var mayUseModel: Bool {
        switch self {
        case .weeklyReview, .plateauReview: return true
        case .missedWorkout, .progression, .sessionDuration, .programmeDrift: return false
        }
    }

    var icon: String {
        switch self {
        case .weeklyReview:    return "chart.line.uptrend.xyaxis"
        case .missedWorkout:   return "calendar.badge.exclamationmark"
        case .progression:     return "arrow.up.right"
        case .plateauReview:   return "chart.line.flattrend.xyaxis"
        case .sessionDuration: return "timer"
        case .programmeDrift:  return "arrow.triangle.branch"
        }
    }
}

/// What one automation found, and what it wants to do about it.
///
/// Note the absence: there is no `applied` case, no `changed` case, no way to
/// express "this automation already did the thing". Approval is the sheet, and
/// the sheet is somewhere else.
struct AutomationOutcome: Equatable, Sendable, Identifiable {
    var id: String { kind.rawValue }

    var kind: AutomationKind
    /// The trigger that fired, in the user's terms, including its threshold.
    /// "Four sessions over three weeks with no increase" — never "we noticed
    /// something".
    var reason: String
    /// What it looked at. Named so the person can check it themselves.
    var dataUsed: String
    /// Rules or Gemini. Carried rather than inferred by the view, for the same
    /// reason `CoachProvenance` is.
    var producedBy: Producer
    /// The headline of what it proposes.
    var proposal: String
    /// Where approving it happens.
    var destination: Destination

    enum Producer: String, Equatable, Sendable {
        case rules
        case gemini

        var label: String {
            switch self {
            case .rules:  return "Worked out by the app"
            case .gemini: return "Written by Gemini from the app's figures"
            }
        }
    }

    /// Every one of these opens something with its own confirm button.
    enum Destination: Equatable, Sendable {
        case weeklyReview
        case reschedule(PlannedSession)
        case progression
        case plateau(PlateauEngine.Finding)
        case adjustRoutine(routineId: String)
        case drift([DriftEngine.Signal])
    }
}

// MARK: - Runner

/// Runs the enabled automations and returns what they found.
///
/// Ordering is fixed rather than by severity: the same six checks in the same
/// order every time, so the list is somewhere a person can learn to look rather
/// than a feed that reshuffles itself.
enum AutomationRunner {

    @MainActor
    static func run(
        appState: AppState,
        enabled: Set<AutomationKind>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AutomationOutcome] {
        var out: [AutomationOutcome] = []

        for kind in AutomationKind.allCases where enabled.contains(kind) {
            switch kind {
            case .weeklyReview:
                let metrics = WeeklyReview.metrics(appState: appState, now: now, calendar: calendar)
                guard metrics.isReviewable else { continue }
                out.append(
                    AutomationOutcome(
                        kind: kind,
                        reason: "\(metrics.completedSessions) sessions logged this week.",
                        dataUsed: "Your finished and planned sessions for the week.",
                        producedBy: appState.coachSettings.mayUseCloud ? .gemini : .rules,
                        proposal: "Read this week's review.",
                        destination: .weeklyReview
                    )
                )

            case .missedWorkout:
                let missed = RescheduleEngine.missedSessions(
                    planned: appState.plannedSessions, now: now, calendar: calendar
                )
                guard let first = missed.first(where: {
                    !RescheduleEngine.isStale($0, now: now, calendar: calendar)
                }) else { continue }
                out.append(
                    AutomationOutcome(
                        kind: kind,
                        reason: "\(first.routineName) was planned for \(first.date.formatted(date: .abbreviated, time: .omitted)) and not completed.",
                        dataUsed: "Your planned sessions.",
                        producedBy: .rules,
                        proposal: "Move it, or let it go.",
                        destination: .reschedule(first)
                    )
                )

            case .progression:
                guard let session = appState.completedWorkouts
                    .sorted(by: { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) })
                    .first,
                    let finishedAt = session.finishedAt,
                    // Only about a session recent enough to still be acting on.
                    calendar.dateComponents([.day], from: finishedAt, to: now).day ?? 99 <= 2
                else { continue }
                out.append(
                    AutomationOutcome(
                        kind: kind,
                        reason: "You finished \(session.name) and it has comparable history.",
                        dataUsed: "The sets, reps and effort you logged.",
                        producedBy: .rules,
                        proposal: "Next session's numbers, worked out from that one.",
                        destination: .progression
                    )
                )

            case .plateauReview:
                guard let finding = PlateauEngine.findings(
                    appState: appState, now: now, calendar: calendar
                ).first else { continue }
                out.append(
                    AutomationOutcome(
                        kind: kind,
                        reason: "\(finding.exerciseName): \(finding.sessions) sessions over \(finding.weeks) weeks with no increase.",
                        dataUsed: "Working sets for that exercise only.",
                        producedBy: appState.coachSettings.mayUseCloud ? .gemini : .rules,
                        proposal: "Some things to try.",
                        destination: .plateau(finding)
                    )
                )

            case .sessionDuration:
                let overruns = DriftEngine.signals(appState: appState, now: now, calendar: calendar)
                    .compactMap { signal -> AutomationOutcome? in
                        guard case .overrunsDuration(let routineId, let name, let minutes, let times) = signal
                        else { return nil }
                        return AutomationOutcome(
                            kind: kind,
                            reason: "\(name) has run about \(minutes) minutes over, \(times) times.",
                            dataUsed: "How long those sessions actually took against the routine's estimate.",
                            producedBy: .rules,
                            proposal: "Trim it to the time it actually gets.",
                            destination: .adjustRoutine(routineId: routineId)
                        )
                    }
                if let first = overruns.first { out.append(first) }

            case .programmeDrift:
                let signals = DriftEngine.signals(appState: appState, now: now, calendar: calendar)
                    .filter { signal in
                        // The duration signal has its own automation above.
                        if case .overrunsDuration = signal { return false }
                        return true
                    }
                guard !signals.isEmpty else { continue }
                out.append(
                    AutomationOutcome(
                        kind: kind,
                        reason: signals[0].headline + ".",
                        dataUsed: "Your last six weeks of sessions against your programme.",
                        producedBy: .rules,
                        proposal: "Review the programme against what you actually do.",
                        destination: .drift(signals)
                    )
                )
            }
        }

        return out
    }

    /// The set enabled by default.
    ///
    /// All six. They cost nothing until they find something — every one is
    /// arithmetic over data already in memory, and the two that can involve
    /// Gemini only do so once the user opens what they found.
    static let defaultEnabled: Set<AutomationKind> = Set(AutomationKind.allCases)
}
