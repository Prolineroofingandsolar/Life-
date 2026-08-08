import Testing
import Foundation
@testable import Life

@MainActor
struct LifeAutopilotTests {

    private func emptyState() -> AppState {
        let state = AppState()
        state.tasks = []
        state.habits = []
        state.sessions = []
        state.plannedSessions = []
        state.careDays = [:]
        state.healthDays = [:]
        return state
    }

    @Test("An active workout is always the next action")
    func activeWorkoutWins() {
        let state = emptyState()
        state.sessions = [WorkoutSession(name: "Push A")]
        state.tasks = [AppTask(title: "Ordinary task", dueDate: .today)]

        let plan = LifeAutopilotEngine.plan(appState: state)

        #expect(plan.first?.id == "active-workout")
        #expect(plan.first?.title == "Resume Push A")
    }

    @Test("An overdue high-priority task is protected in today's plan")
    func overdueTaskAppears() {
        let state = emptyState()
        var task = AppTask(title: "Send roofing quote", dueDate: nil)
        task.priority = .high
        task.dueDateOverride = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        task.estimatedMinutes = 15
        state.tasks = [task]

        let plan = LifeAutopilotEngine.plan(appState: state)

        #expect(plan.first?.id == "task-\(task.id)")
        #expect(plan.first?.durationMinutes == 15)
        #expect(plan.first?.reason.contains("overdue") == true)
    }

    @Test("Adjusting an item removes it from the rebuilt plan")
    func exclusionsReplanTheDay() {
        let state = emptyState()
        let task = AppTask(title: "Call supplier", dueDate: .today)
        state.tasks = [task]

        let plan = LifeAutopilotEngine.plan(
            appState: state,
            excluding: ["task-\(task.id)"]
        )

        #expect(!plan.contains { $0.relatedItemId == task.id })
    }

    @Test("Habits stay in Today and are not duplicated in Autopilot")
    func habitsAreNotDuplicated() {
        let state = emptyState()
        state.habits = [Habit(name: "Read", emoji: "📚", kind: .build)]

        let plan = LifeAutopilotEngine.plan(appState: state)

        #expect(!plan.contains { $0.kind == .habit })
    }

    @Test("A validated Gemini custom action can be pinned, but not executed")
    func customActionPinsIntoAutopilot() {
        defer { AutopilotQueue.complete() }
        let state = emptyState()
        let recommendation = CoachRecommendation(
            headline: "Lay out tomorrow's gym clothes",
            summary: "Preparing tonight may make the planned morning session easier to start.",
            category: .training,
            actionType: .custom,
            durationMinutes: 5,
            evidence: [],
            origin: .cloud
        )

        AutopilotQueue.pin(recommendation)
        let plan = LifeAutopilotEngine.plan(appState: state)

        #expect(plan.first?.kind == .custom)
        #expect(plan.first?.title == recommendation.headline)
        #expect(plan.first?.durationMinutes == 5)
    }
}
