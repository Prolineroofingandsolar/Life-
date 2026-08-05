import Testing
import Foundation
@testable import Life

// MARK: - Coach Actions
//
// The coach can now offer to change things. These cover the boundary that makes
// that safe: a proposal is only ever an offer, it is checked against real data
// before it becomes a button, and it is checked again before it becomes a
// change.

@MainActor
struct CoachActionTests {

    private func state() -> AppState {
        let state = AppState()
        state.tasks = []
        state.habits = []
        state.routines = []
        state.taskLists = [
            TaskList(id: "work", name: "Work", emoji: "💼", colorHex: "#5E9BF0", isSystem: true),
            TaskList(id: "personal", name: "Personal", emoji: "🌱", colorHex: "#FF9F0A", isSystem: true)
        ]
        return state
    }

    // MARK: Filtering

    /// An invented id is the failure mode that matters. A model that returns a
    /// well-formed proposal quoting an id it made up would otherwise put a
    /// button on screen that completes something at random.
    @Test("A proposal naming a task that doesn't exist never becomes a button")
    func inventedTaskIdIsDropped() {
        let appState = state()
        appState.tasks = [AppTask(title: "Real task", listId: "work", dueDate: .today)]

        let proposals = [
            CoachProposal(kind: .completeTask, label: "Mark done", targetId: "not-a-real-id")
        ]

        #expect(CoachActions.usable(proposals, appState: appState).isEmpty)
    }

    @Test("A proposal naming a real outstanding task is offered")
    func realTaskIdIsKept() {
        let appState = state()
        let task = AppTask(title: "Real task", listId: "work", dueDate: .today)
        appState.tasks = [task]

        let proposals = [
            CoachProposal(kind: .completeTask, label: "Mark done", targetId: task.id)
        ]

        #expect(CoachActions.usable(proposals, appState: appState).count == 1)
    }

    /// A button offering to finish something already finished does nothing
    /// visible, which reads as the app being broken.
    @Test("Completing an already-completed task isn't offered")
    func completedTaskIsNotOffered() {
        let appState = state()
        var task = AppTask(title: "Done already", listId: "work", dueDate: .today)
        task.done = true
        appState.tasks = [task]

        let proposals = [
            CoachProposal(kind: .completeTask, label: "Mark done", targetId: task.id)
        ]

        #expect(CoachActions.usable(proposals, appState: appState).isEmpty)
    }

    @Test("An empty task title isn't offered")
    func emptyTitleIsDropped() {
        let appState = state()
        let proposals = [CoachProposal(kind: .addTask, label: "Add", title: "   ")]
        #expect(CoachActions.usable(proposals, appState: appState).isEmpty)
    }

    // MARK: Performing

    @Test("Adding a task files it in the list the coach named")
    func addTaskUsesNamedList() {
        let appState = state()
        let outcome = CoachActions.perform(
            CoachProposal(kind: .addTask, label: "Add", title: "Call the plumber", listId: "work", due: "tomorrow"),
            appState: appState
        )

        #expect(outcome != nil)
        #expect(appState.tasks.count == 1)
        #expect(appState.tasks.first?.title == "Call the plumber")
        #expect(appState.tasks.first?.listId == "work")
        #expect(appState.tasks.first?.dueDate == .tomorrow)
    }

    /// A near-miss on the list shouldn't lose the task. The task is what was
    /// asked for; the list is a detail a tap can change.
    @Test("An unknown list falls back to Personal rather than refusing")
    func unknownListFallsBack() {
        let appState = state()
        CoachActions.perform(
            CoachProposal(kind: .addTask, label: "Add", title: "Something", listId: "nonexistent"),
            appState: appState
        )

        #expect(appState.tasks.first?.listId == "personal")
    }

    @Test("Water is clamped to something a person could drink")
    func waterIsClamped() {
        let appState = state()
        appState.careDays = [:]

        CoachActions.perform(
            CoachProposal(kind: .logWater, label: "Log water", count: 500),
            appState: appState
        )

        #expect(appState.today.waterGlasses == 8)
    }

    @Test("A zero count still logs one glass")
    func zeroWaterLogsOne() {
        let appState = state()
        appState.careDays = [:]

        CoachActions.perform(
            CoachProposal(kind: .logWater, label: "Log water", count: 0),
            appState: appState
        )

        #expect(appState.today.waterGlasses == 1)
    }

    /// Valid when the answer arrived, gone by the time the button was pressed.
    @Test("Performing a proposal that has since become invalid does nothing")
    func staleProposalIsRefused() {
        let appState = state()
        let outcome = CoachActions.perform(
            CoachProposal(kind: .completeTask, label: "Mark done", targetId: "vanished"),
            appState: appState
        )

        #expect(outcome == nil)
        #expect(appState.tasks.isEmpty)
    }

    // MARK: Decoding

    /// A kind this version doesn't implement must not survive decoding — it
    /// would otherwise reach a button that appears to do something.
    @Test("An unknown proposal type fails to decode")
    func unknownKindIsRejected() throws {
        let json = #"{"type":"deleteEverything","label":"Do it"}"#
        let data = Data(json.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CoachProposal.self, from: data)
        }
    }

    @Test("A known proposal type decodes with its fields")
    func knownKindDecodes() throws {
        let json = #"{"type":"addTask","label":"Add it","title":"Buy milk","listId":"personal","due":"today"}"#
        let proposal = try JSONDecoder().decode(CoachProposal.self, from: Data(json.utf8))

        #expect(proposal.kind == .addTask)
        #expect(proposal.title == "Buy milk")
        #expect(proposal.due == "today")
    }
}
