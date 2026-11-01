import Foundation
import FirebaseAuth
import Security
import SwiftUI
import UIKit

// MARK: - Grok Bot
//
// Grok Bot (x.ai/bot) works by using websites, and Life is an iPhone app, so
// the server gives it a private web page instead (`functions/src/lifeBot.ts`).
// Whatever Grok Bot asks for there waits in an inbox until this app is open,
// and this file is what carries it out: through `CoachActions` for the small
// things, and by saving a routine for a new workout.
//
// The page is reached by a secret link made here, in Settings. The link is the
// only key, so it lives in the Keychain and can be replaced or switched off.

// MARK: Transport

/// Calls the `lifeBotApp` callable over plain HTTPS, the same way the coach
/// does, so no extra Firebase package is needed. Main-actor isolated because
/// `AuthManager` is, and every caller is already on the main actor.
@MainActor
enum LifeBotAPI {

    enum Failure: LocalizedError {
        case notSignedIn
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to connect Grok Bot."
            case .server(let message): return message
            }
        }
    }

    static func call(_ body: [String: Any]) async throws -> [String: Any] {
        guard AuthManager.isFirebaseReady, let user = Auth.auth().currentUser else {
            throw Failure.notSignedIn
        }
        let token = try await user.getIDToken()
        guard let url = CoachEndpoint.url(for: "lifeBotApp") else {
            throw Failure.server("The server address isn't set.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": body])

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw Failure.server(message ?? "Grok Bot's connection isn't working yet. Has the server been updated?")
        }
        return json?["result"] as? [String: Any] ?? [:]
    }
}

// MARK: Link storage

/// The secret link, kept in the Keychain so it can be copied again later.
enum LifeBotLinkStore {

    private static let service = "uk.co.prolineroofingandsolar.life.grokbot"
    private static let account = "link"

    static var link: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(base as CFDictionary)
            guard let newValue else { return }
            var add = base
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

// MARK: Inbox

/// Collects what Grok Bot asked for and does it, while the app is open.
@MainActor
@Observable
final class LifeBotInbox {

    static let shared = LifeBotInbox()

    /// What Grok Bot has done lately, newest first, for Settings.
    struct LogEntry: Codable, Identifiable, Equatable {
        var id: String
        var date: Date
        var message: String
        var ok: Bool
    }

    private(set) var log: [LogEntry] = []
    private var loop: Task<Void, Never>?
    private var isDraining = false

    private static let logKey = "lifeBot.log.v1"
    private static let enabledKey = "lifeBot.enabled"

    /// Whether this device should look for requests. Set when a link is made
    /// here, cleared when it is switched off.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.logKey),
           let saved = try? JSONDecoder().decode([LogEntry].self, from: data) {
            log = saved
        }
    }

    /// Checks now and then every minute while the app is in front.
    func start(appState: AppState) {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.drain(appState: appState)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func drain(appState: AppState) async {
        guard Self.isEnabled, !isDraining, appState.cloudUserId != nil else { return }
        isDraining = true
        defer { isDraining = false }

        guard let result = try? await LifeBotAPI.call(["action": "claim"]),
              let items = result["items"] as? [[String: Any]], !items.isEmpty else { return }

        var results: [[String: Any]] = []
        for item in items {
            guard let id = item["id"] as? String else { continue }
            let outcome = perform(item, appState: appState)
            results.append(["id": id, "ok": outcome.ok, "message": outcome.message])
            log.insert(LogEntry(id: id, date: Date(), message: outcome.message, ok: outcome.ok), at: 0)
        }
        log = Array(log.prefix(20))
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: Self.logKey)
        }
        _ = try? await LifeBotAPI.call(["action": "complete", "results": results])
    }

    // MARK: Carrying out one request

    private func perform(_ item: [String: Any], appState: AppState) -> (ok: Bool, message: String) {
        let kind = item["kind"] as? String ?? ""
        let createdAt = Self.date(item["createdAt"] as? String) ?? Date()

        switch kind {
        case "createWorkout":
            return createWorkout(item, createdAt: createdAt, appState: appState)

        case "planWorkout":
            guard let id = item["routineId"] as? String,
                  let routine = appState.routines.first(where: { $0.id == id }) else {
                return (false, "That routine isn't in Life any more.")
            }
            let day = Self.day(for: item["when"] as? String, createdAt: createdAt)
            appState.planSession(date: day, routineId: id, name: routine.name)
            return (true, "Planned \(routine.name) for \(Self.describe(day)).")

        case "logMeal":
            // Not through CoachActions, which trims a meal to 60 characters:
            // calories and protein ride on the end of the name.
            let name = String((item["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
            appState.addMeal(name: name)
            return (true, name.isEmpty ? "Logged a meal." : "Logged \(name).")

        case "updateTask":
            guard let id = item["targetId"] as? String,
                  let task = appState.tasks.first(where: { $0.id == id }) else {
                return (false, "That task isn't in Life any more.")
            }
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }
            let notes = item["notes"] as? String
            let listId = (item["listId"] as? String).flatMap { id in
                appState.taskLists.contains(where: { $0.id == id }) ? id : nil
            }
            let relative = (item["due"] as? String).flatMap(DueDate.init(rawValue:))
            let exact = (item["dueDate"] as? String).flatMap(Self.day(fromKey:))
            appState.updateTask(id: id, title: title, notes: notes, listId: listId)
            // A due date is stored as a fixed day, the way the coach moves a
            // task, so "tomorrow" doesn't slide forward every day.
            if let exact {
                appState.scheduleTask(id: id, on: exact)
            } else if let relative {
                appState.scheduleTask(id: id, on: relative.fixedDate())
            }
            return (true, "Updated “\(title ?? task.title)”.")

        case "deleteTask":
            guard let id = item["targetId"] as? String,
                  let task = appState.tasks.first(where: { $0.id == id }) else {
                return (false, "That task was already gone.")
            }
            appState.deleteTask(id: id)
            return (true, "Deleted the task “\(task.title)”.")

        case "updateRoutine":
            guard let id = item["targetId"] as? String,
                  let routine = appState.routines.first(where: { $0.id == id }) else {
                return (false, "That routine isn't in Life any more.")
            }
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
            var exercises: [RoutineExercise]?
            if let rows = item["exercises"] as? [[String: Any]] {
                let built = routineExercises(rows, appState: appState)
                guard !built.isEmpty else { return (false, "None of those exercises are in Life's library.") }
                exercises = built
            }
            appState.updateRoutine(id: id, name: name, exercises: exercises)
            return (true, "Updated the routine \(name ?? routine.name).")

        case "deleteRoutine":
            guard let id = item["targetId"] as? String,
                  let routine = appState.routines.first(where: { $0.id == id }) else {
                return (false, "That routine was already gone.")
            }
            appState.deleteRoutine(id: id)
            return (true, "Deleted the routine \(routine.name). Past workouts are kept.")

        case "deletePlannedWorkout":
            guard let id = item["targetId"] as? String,
                  let plan = appState.plannedSessions.first(where: { $0.id == id }) else {
                return (false, "That planned workout was already gone.")
            }
            appState.deletePlannedSession(id: id)
            return (true, "Removed \(plan.routineName) from \(Self.describe(plan.date))'s plan.")

        case "updateWeight":
            guard let id = item["targetId"] as? String,
                  let kg = (item["weightKg"] as? NSNumber)?.doubleValue,
                  (25...300).contains(kg),
                  let index = appState.weightEntries.firstIndex(where: { $0.id == id }) else {
                return (false, "That weight entry couldn't be corrected.")
            }
            let old = appState.weightEntries[index].valueKg
            appState.weightEntries[index].valueKg = kg
            appState.save()
            return (true, String(format: "Corrected a weight from %.1f kg to %.1f kg.", old, kg))

        case "deleteWeight":
            guard let id = item["targetId"] as? String,
                  let entry = appState.weightEntries.first(where: { $0.id == id }) else {
                return (false, "That weight entry was already gone.")
            }
            appState.deleteWeightEntry(id: id)
            return (true, String(format: "Deleted the %.1f kg weight entry.", entry.valueKg))

        default:
            guard let proposal = Self.proposal(kind: kind, item: item) else {
                return (false, "This version of Life doesn't know how to do that.")
            }
            switch CoachActions.perform(proposal, appState: appState) {
            case .changed(let message): return (true, message)
            case .opensBuilder, .unavailable: return (false, "That couldn't be done. It may already be done or no longer exist.")
            }
        }
    }

    private func createWorkout(_ item: [String: Any], createdAt: Date, appState: AppState) -> (ok: Bool, message: String) {
        let exercises = routineExercises(item["exercises"] as? [[String: Any]] ?? [], appState: appState)
        guard !exercises.isEmpty else {
            return (false, "None of those exercises are in Life's library.")
        }

        let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Grok Bot workout"
        appState.addRoutine(name: name, exercises: exercises)
        guard let routine = appState.routines.last, routine.name == name else {
            return (false, "The workout couldn't be saved.")
        }
        appState.updateRoutine(id: routine.id, emoji: "🤖")

        let when = item["when"] as? String ?? "today"
        if when == "none" {
            return (true, "Saved the routine \(name) (\(exercises.count) exercises).")
        }
        let day = Self.day(for: when, createdAt: createdAt)
        appState.planSession(date: day, routineId: routine.id, name: name)
        return (true, "Created \(name) (\(exercises.count) exercises) and planned it for \(Self.describe(day)).")
    }

    private func routineExercises(_ rows: [[String: Any]], appState: AppState) -> [RoutineExercise] {
        let known = Set(appState.exercises.map(\.id))
        return rows.compactMap { row in
            guard let exerciseId = row["exerciseId"] as? String, known.contains(exerciseId) else { return nil }
            let sets = min(max(row["sets"] as? Int ?? 3, 1), 10)
            let low = min(max(row["repsMin"] as? Int ?? 10, 1), 100)
            let high = min(max(row["repsMax"] as? Int ?? low, low), 100)
            let rest = min(max(row["restSeconds"] as? Int ?? 90, 15), 600)
            return RoutineExercise(
                exerciseId: exerciseId,
                defaultSets: sets,
                defaultReps: high,
                repRangeMin: low,
                repRangeMax: high,
                restSeconds: rest
            )
        }
    }

    /// The small requests are the coach's own actions, so they get the same
    /// checks against real data before anything changes.
    private static func proposal(kind: String, item: [String: Any]) -> CoachProposal? {
        let title = item["title"] as? String
        let targetId = item["targetId"] as? String
        let count = item["count"] as? Int
        switch kind {
        case "addTask":
            return CoachProposal(kind: .addTask, label: "Add task", title: title,
                                 listId: item["listId"] as? String, due: item["due"] as? String)
        case "completeTask":
            return CoachProposal(kind: .completeTask, label: "Complete task", targetId: targetId)
        case "logHabit":
            return CoachProposal(kind: .addHabitLog, label: "Log habit", targetId: targetId, count: count)
        case "logWater":
            return CoachProposal(kind: .logWater, label: "Log water", count: count)
        case "logMeal":
            return CoachProposal(kind: .logMeal, label: "Log meal", title: title)
        case "logWeight":
            return CoachProposal(kind: .logWeight, label: "Log weight",
                                 weightKg: (item["weightKg"] as? NSNumber)?.doubleValue)
        case "logSupplement":
            return CoachProposal(kind: .logSupplement, label: "Log supplement", targetId: targetId)
        default:
            return nil
        }
    }

    // MARK: Dates

    /// "Today" means the day Grok Bot asked, not the day the app happened to
    /// open, but never a day that has already gone.
    private static func day(for when: String?, createdAt: Date) -> Date {
        let cal = Calendar.current
        let base = cal.startOfDay(for: createdAt)
        let asked = when == "tomorrow" ? (cal.date(byAdding: .day, value: 1, to: base) ?? base) : base
        return max(asked, cal.startOfDay(for: Date()))
    }

    /// A "2026-11-05" from the page, as the start of that day here.
    private static func day(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func describe(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "today" }
        if cal.isDateInTomorrow(day) { return "tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

// MARK: - Settings

/// Make, copy, replace or switch off Grok Bot's link.
struct GrokBotSettingsSection: View {

    @Environment(AppState.self) private var appState
    @State private var link: String? = LifeBotLinkStore.link
    @State private var working = false
    @State private var error: String?
    @State private var copied = false
    @State private var confirmOff = false

    private var inbox: LifeBotInbox { .shared }

    var body: some View {
        Section {
            if let link {
                Button {
                    UIPasteboard.general.string = link
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy Grok Bot's link", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                ShareLink(item: link) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
                Button("Make a new link") { Task { await makeLink() } }
                    .disabled(working)
                Button("Switch off Grok Bot", role: .destructive) { confirmOff = true }
                    .disabled(working)
            } else {
                Button {
                    Task { await makeLink() }
                } label: {
                    Label("Connect Grok Bot", systemImage: "link")
                }
                .disabled(working || appState.cloudUserId == nil)
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if !inbox.log.isEmpty {
                ForEach(inbox.log.prefix(5)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message).font(.subheadline)
                            .foregroundStyle(entry.ok ? Color.primary : Color.red)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Grok Bot")
        } footer: {
            Text(link == nil
                 ? "Gives Grok Bot a private page where it can see your workouts, habits and meals, and add, edit or delete workouts, routines, tasks and logs. Needs you to be signed in."
                 : "Give this link to Grok Bot, then tell it what to do, for example \"make me a new workout every morning\". Anyone with the link can add, change and delete things in Life, so keep it private. If it ever leaks, tap Make a new link and the old one stops working.")
        }
        .confirmationDialog("Switch off Grok Bot?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Switch off", role: .destructive) { Task { await switchOff() } }
        } message: {
            Text("The link stops working straight away. You can make a new one at any time.")
        }
    }

    private func makeLink() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let result = try await LifeBotAPI.call(["action": "createLink"])
            guard let url = result["url"] as? String else { throw LifeBotAPI.Failure.server("No link came back.") }
            LifeBotLinkStore.link = url
            LifeBotInbox.isEnabled = true
            link = url
            copied = false
            LifeBotInbox.shared.start(appState: appState)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func switchOff() async {
        working = true
        error = nil
        defer { working = false }
        do {
            _ = try await LifeBotAPI.call(["action": "revokeLink"])
            LifeBotLinkStore.link = nil
            LifeBotInbox.isEnabled = false
            LifeBotInbox.shared.stop()
            link = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
