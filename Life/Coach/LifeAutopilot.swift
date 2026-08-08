import SwiftUI

// MARK: - Life Autopilot

/// A small, explainable plan for the rest of today. The model-facing Coach
/// still decides the single most important recommendation; Autopilot turns the
/// app's trusted, structured data into a timeline around it. Nothing here
/// changes user data without a tap.
struct AutopilotItem: Identifiable, Equatable {
    enum Kind: String {
        case task, workout, walk, habit, recovery, custom
    }

    var id: String
    var kind: Kind
    var title: String
    var reason: String
    var scheduledAt: Date
    var durationMinutes: Int
    var relatedItemId: String?

    var icon: String {
        switch kind {
        case .task: return "checkmark.circle"
        case .workout: return "dumbbell.fill"
        case .walk: return "figure.walk"
        case .habit: return "repeat"
        case .recovery: return "heart.fill"
        case .custom: return "sparkles"
        }
    }

    var actionTitle: String {
        switch kind {
        case .task: return "Mark done"
        case .workout: return "Start"
        case .habit: return "Log it"
        case .walk: return "Plan walk"
        case .recovery: return "Review plan"
        case .custom: return "Mark finished"
        }
    }
}

@MainActor
enum LifeAutopilotEngine {

    static func plan(
        appState: AppState,
        now: Date = Date(),
        excluding: Set<String> = []
    ) -> [AutopilotItem] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let health = appState.healthSnapshot
        var candidates: [(score: Int, item: AutopilotItem)] = []

        if let pinned = AutopilotQueue.current,
           !excluding.contains("custom-\(pinned.id)") {
            candidates.append((
                200,
                AutopilotItem(
                    id: "custom-\(pinned.id)", kind: .custom,
                    title: pinned.title, reason: pinned.reason,
                    scheduledAt: nextQuarter(after: now),
                    durationMinutes: pinned.durationMinutes
                )
            ))
        }

        let openTasks = appState.tasks.filter { !$0.done && !excluding.contains("task-\($0.id)") }
        for task in openTasks {
            let due = task.resolvedDate
            let isOverdue = due.map { calendar.startOfDay(for: $0) < startOfToday } ?? false
            let isToday = due.map { calendar.isDateInToday($0) } ?? false
            guard isOverdue || isToday else { continue }

            let priorityScore: Int
            switch task.priority {
            case .high: priorityScore = 35
            case .medium: priorityScore = 20
            case .low: priorityScore = 8
            case .none: priorityScore = 0
            }
            let duration = max(5, min(task.estimatedMinutes ?? 20, 180))
            let time = task.scheduledTime.map { max($0, now) } ?? nextQuarter(after: now)
            let reason = isOverdue
                ? "This is overdue, so Autopilot has protected time for it first."
                : task.priority == .high
                    ? "This is one of today's highest-priority commitments."
                    : "This is due today and fits into the time available."
            candidates.append((
                80 + priorityScore + (isOverdue ? 30 : 0) + preference(appState, .task),
                AutopilotItem(
                    id: "task-\(task.id)", kind: .task, title: task.title,
                    reason: reason, scheduledAt: time, durationMinutes: duration,
                    relatedItemId: task.id
                )
            ))
        }

        if let active = appState.activeSession, !excluding.contains("active-workout") {
            candidates.append((
                150,
                AutopilotItem(
                    id: "active-workout", kind: .workout,
                    title: "Resume \(active.name)",
                    reason: "This workout is already in progress, so finishing it takes priority.",
                    scheduledAt: now, durationMinutes: 30
                )
            ))
        } else if let session = appState.plannedSessions.first(where: {
            !$0.completed && !$0.isRestDay && calendar.isDateInToday($0.date)
        }), !excluding.contains("workout-\(session.id)") {
            let readiness = health.readiness.value
            let lowRecovery = readiness.map { $0 < 45 } ?? false
            candidates.append((
                lowRecovery ? 62 : 105 + preference(appState, .workout),
                AutopilotItem(
                    id: "workout-\(session.id)",
                    kind: lowRecovery ? .recovery : .workout,
                    title: lowRecovery ? "Review today's \(session.routineName)" : session.routineName,
                    reason: lowRecovery
                        ? "Fitbit readiness is low. Review the session before deciding whether to reduce it or move it."
                        : "This workout is planned for today and your current recovery does not flag a reason to move it.",
                    scheduledAt: max(session.date, nextQuarter(after: now)),
                    durationMinutes: 45,
                    relatedItemId: session.id
                )
            ))
        }

        if let steps = health.steps.value,
           steps > 0,
           steps < Int(Double(appState.careSettings.stepGoal) * 0.6),
           calendar.component(.hour, from: now) >= 14,
           !excluding.contains("walk-today") {
            candidates.append((
                65 + preference(appState, .walk),
                AutopilotItem(
                    id: "walk-today", kind: .walk, title: "Take a 10-minute walk",
                    reason: "Fitbit shows \(steps.formatted()) steps, below 60% of your daily goal at this time of day.",
                    scheduledAt: nextQuarter(after: now), durationMinutes: 10
                )
            ))
        }

        let ranked = candidates.sorted {
            if $0.score == $1.score { return $0.item.scheduledAt < $1.item.scheduledAt }
            return $0.score > $1.score
        }.prefix(3).map(\.item)

        // Keep the ranking, but prevent three items all claiming the same time.
        var cursor = nextQuarter(after: now)
        return ranked.map { item in
            var item = item
            item.scheduledAt = max(item.scheduledAt, cursor)
            cursor = item.scheduledAt.addingTimeInterval(TimeInterval(item.durationMinutes * 60 + 10 * 60))
            return item
        }
    }

    private static func nextQuarter(after date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let add = 15 - (minute % 15)
        return calendar.date(byAdding: .minute, value: add, to: date) ?? date
    }

    private static func preference(_ appState: AppState, _ kind: AutopilotItem.Kind) -> Int {
        let accepted = UserDefaults.standard.integer(forKey: "life_autopilot_accepted_\(kind.rawValue)")
        let delayed = UserDefaults.standard.integer(forKey: "life_autopilot_delayed_\(kind.rawValue)")
        return max(-20, min(20, (accepted - delayed) * 3))
    }

    static func record(_ response: String, for kind: AutopilotItem.Kind) {
        let key = "life_autopilot_\(response)_\(kind.rawValue)"
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
}

/// The explicit bridge from a Gemini proposal to Autopilot. A queued action is
/// text and timing only: no selector, command, URL or mutation can be encoded.
enum AutopilotQueue {
    struct Pinned: Codable, Equatable {
        var id: String
        var title: String
        var reason: String
        var durationMinutes: Int
        var createdAt: Date
    }

    private static let key = "life_autopilot_pinned_action_v1"
    static let changed = Notification.Name("LifeAutopilotQueueChanged")

    static var current: Pinned? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Pinned.self, from: data)
    }

    static func pin(_ recommendation: CoachRecommendation) {
        guard recommendation.actionType == .custom else { return }
        let value = Pinned(
            id: UUID().uuidString,
            title: recommendation.headline,
            reason: recommendation.summary,
            durationMinutes: max(1, min(recommendation.durationMinutes ?? 10, 240)),
            createdAt: Date()
        )
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    static func complete() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

struct LifeAutopilotCard: View {
    @Environment(AppState.self) private var appState

    var onStartWorkout: () -> Void

    @State private var excluded: Set<String> = []
    @State private var explaining: AutopilotItem?
    @State private var completedMessage: String?
    @State private var queueToken = UUID()

    private var plan: [AutopilotItem] {
        _ = queueToken
        return LifeAutopilotEngine.plan(appState: appState, excluding: excluded)
    }

    /// Gemini owns the single prominent next decision above this card. This is
    /// deliberately only the quieter remainder of the day.
    private var laterPlan: [AutopilotItem] {
        // A Gemini action explicitly pinned by the user belongs here; otherwise
        // the first ranked item is already represented by the coach above.
        if AutopilotQueue.current != nil { return Array(plan.prefix(2)) }
        return Array(plan.dropFirst().prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Later today", systemImage: "clock")
                    .font(.headline)
                Spacer()
                Text("Suggested order")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.primary.opacity(0.7))
            }

            Text("A preview of what could follow your main recommendation.")
                .font(.caption)
                .foregroundColor(.primary.opacity(0.72))

            if laterPlan.isEmpty {
                Text("Nothing else needs organising right now.")
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.72))
            } else {
                ForEach(Array(laterPlan.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    timelineRow(item)
                }
            }

            if let completedMessage {
                Text(completedMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(16)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .sheet(item: $explaining) { item in
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    Label(item.title, systemImage: item.icon).font(.title2.bold())
                    Text(item.reason).font(.body)
                    Text("Life used only data already stored in the app. It will never change your day without you approving an action.")
                        .font(.footnote).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(20)
                .navigationTitle("Why this?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { explaining = nil } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AutopilotQueue.changed)) { _ in
            queueToken = UUID()
        }
    }

    private func timelineRow(_ item: AutopilotItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: item.icon)
                    .foregroundColor(AppTheme.primary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.scheduledAt, format: .dateTime.hour().minute())
                        .font(.caption.weight(.semibold)).foregroundColor(AppTheme.primary)
                    Text(item.title).font(.subheadline.weight(.semibold))
                    Text("About \(item.durationMinutes) min")
                        .font(.caption2).foregroundColor(.primary.opacity(0.68))
                }
                Spacer()
                Button("Why this?") { explaining = item }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
            }
            if item.kind == .custom {
                Button(item.actionTitle) { apply(item) }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
                    .padding(.leading, 33)
            }
        }
    }

    private func apply(_ item: AutopilotItem) {
        switch item.kind {
        case .task:
            if let id = item.relatedItemId { appState.toggleTask(id: id) }
        case .habit:
            if let id = item.relatedItemId { appState.logHabit(id: id) }
        case .workout:
            onStartWorkout()
        case .custom:
            AutopilotQueue.complete()
            excluded.insert(item.id)
        case .walk, .recovery:
            excluded.insert(item.id)
        }
        LifeAutopilotEngine.record("accepted", for: item.kind)
        completedMessage = "Plan updated from your choice."
        HapticManager.success()
    }

}
