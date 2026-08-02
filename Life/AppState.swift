import Foundation
import SwiftUI
import CoreLocation
import UIKit

// MARK: - Persistence Keys

private enum PersistenceKey {
    static let appState = "life_app_state_v2"
    static let lastModified = "life_app_state_last_modified_v1"
}

// MARK: - Planned Session

struct PlannedSession: Identifiable, Codable {
    var id: String = UUID().uuidString
    var date: Date
    var routineId: String?
    var routineName: String
    var notes: String = ""
    var completed: Bool = false
}

// MARK: - Progress Photo (stored separately, not in cloud snapshot)

struct ProgressPhoto: Identifiable, Codable {
    var id: String = UUID().uuidString
    var date: Date
    var label: String
    var imageData: Data
}

// MARK: - Sync State

enum SyncState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case failed(String)
}

// MARK: - Serializable State Snapshot

struct StateSnapshot: Codable {
    var tasks: [AppTask] = []
    var taskLists: [TaskList] = []
    var bills: [Bill] = []
    var incomes: [Income] = []
    var oneOffExpenses: [OneOffExpense] = []
    var moneySettings: MoneySettings = MoneySettings()
    var habits: [Habit] = []
    var exercises: [Exercise] = []
    var routines: [Routine] = []
    var sessions: [WorkoutSession] = []
    var weightEntries: [WeightEntry] = []
    var bodyCompEntries: [BodyCompEntry] = []
    var bodyMeasurements: [BodyMeasurement] = []
    var achievements: [Achievement] = []
    var programs: [WorkoutProgram] = []
    var careDays: [String: CareDay] = [:]
    var careSettings: CareSettings = CareSettings()
    var workoutSettings: WorkoutSettings = WorkoutSettings()
    var userName: String = ""
    var visitedLocations: [VisitedLocation] = []
    var plannedSessions: [PlannedSession] = []
    var supplements: [Supplement] = []
    // Optional on purpose. Swift's synthesized `Codable` calls `decode` (not
    // `decodeIfPresent`) for non-optional properties, so a *missing* key throws
    // rather than falling back to the default value — and `load()` treats a
    // decode failure as "first launch" and seeds defaults. A non-optional field
    // added here would therefore wipe every save written before this version.
    // Optionals get `decodeIfPresent`, so old snapshots decode as nil and
    // `apply(snapshot:)` substitutes the default.
    var healthDays: [String: HealthDay]? = nil
    var healthSettings: HealthSettings? = nil
    var sleepNights: [String: SleepNight]? = nil
    /// Manually entered Google Health scores paired with our estimates.
    var sleepComparisons: [String: SleepScoreComparison]? = nil
}

// MARK: - AppState

@Observable
final class AppState {

    // MARK: Stored Properties

    var latestPR: (exerciseName: String, value: String)? = nil
    var showWorkoutSheet: Bool = false
    var tasks: [AppTask] = []
    var taskLists: [TaskList] = []
    var bills: [Bill] = []
    var incomes: [Income] = []
    var oneOffExpenses: [OneOffExpense] = []
    var moneySettings: MoneySettings = MoneySettings()
    var habits: [Habit] = []
    var exercises: [Exercise] = []
    var routines: [Routine] = []
    var sessions: [WorkoutSession] = []
    var weightEntries: [WeightEntry] = []
    var bodyCompEntries: [BodyCompEntry] = []
    var bodyMeasurements: [BodyMeasurement] = []
    var achievements: [Achievement] = []
    var programs: [WorkoutProgram] = []
    var careDays: [String: CareDay] = [:]
    var careSettings: CareSettings = CareSettings()
    var workoutSettings: WorkoutSettings = WorkoutSettings()
    var userName: String = ""
    var supplements: [Supplement] = []
    var cloudUserId: String? = nil
    var syncState: SyncState = .idle
    var visitedLocations: [VisitedLocation] = []
    var plannedSessions: [PlannedSession] = []
    var progressPhotos: [ProgressPhoto] = []
    var healthDays: [String: HealthDay] = [:]
    var healthSettings: HealthSettings = HealthSettings()
    var sleepNights: [String: SleepNight] = [:]
    var sleepComparisons: [String: SleepScoreComparison] = [:]

    // MARK: Computed Properties

    var todayKey: String { Date().dayKey }

    var today: CareDay {
        get { careDays[todayKey] ?? CareDay(dayKey: todayKey) }
    }

    /// Health days oldest-first, for charting.
    var healthHistory: [HealthDay] {
        healthDays.values.sorted { $0.dayKey < $1.dayKey }
    }

    /// Last night's sleep — today's record if it has one, otherwise the most
    /// recent night on file. Sleep is filed under the morning you woke, so
    /// today's entry is the night just gone.
    var lastNightSleep: HealthDay? {
        if let todayRecord = healthDays[todayKey], todayRecord.sleepMin != nil { return todayRecord }
        return healthHistory.last { $0.sleepMin != nil }
    }

    /// Activity per day, oldest first.
    ///
    /// Steps live on `CareDay` (they drive Today's Move ring) while everything
    /// else lives on `HealthDay`, so this stitches the two together. Days
    /// present in either map are included; a day with only steps is still a day
    /// worth charting.
    var activityHistory: [ActivityDay] {
        var byDay: [String: ActivityDay] = [:]

        for (key, care) in careDays where care.steps > 0 {
            byDay[key] = ActivityDay(dayKey: key, steps: care.steps)
        }
        for (key, health) in healthDays {
            var day = byDay[key] ?? ActivityDay(dayKey: key)
            day.activeEnergyKcal = health.activeEnergyKcal
            day.exerciseMinutes = health.exerciseMinutes
            day.distanceKm = health.distanceKm
            day.flights = health.flights
            byDay[key] = day
        }

        return byDay.values.sorted { $0.dayKey < $1.dayKey }
    }

    /// Mean of the last `days` readings for a metric, excluding today so a
    /// reading can be compared against its own recent baseline. Nil until there
    /// are at least `minimumSamples` readings — a baseline from two nights is
    /// noise, not a baseline.
    func healthBaseline(
        _ metric: (HealthDay) -> Double?,
        days: Int = 7,
        minimumSamples: Int = 3
    ) -> Double? {
        let values = healthHistory
            .filter { $0.dayKey != todayKey }
            .suffix(days)
            .compactMap(metric)
        guard values.count >= minimumSamples else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var activeSession: WorkoutSession? {
        sessions.first { $0.finishedAt == nil }
    }

    // MARK: Init

    init() {
        load()
        // Surface sync errors and success timestamps from FirestoreSync into
        // our observable syncState so the UI can show a banner instead of
        // failures being swallowed silently.
        FirestoreSync.shared.onUploadCompletion = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let date):
                self.syncState = .synced(date)
            case .failure(let error):
                self.syncState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Persistence

    /// When this device's local data last changed. Compared against a cloud
    /// snapshot's `clientUpdatedAt` on sign-in so a stale/empty second device
    /// can't clobber newer local data — see `loadFromCloud`.
    private var localLastModified: Date {
        get { UserDefaults.standard.object(forKey: PersistenceKey.lastModified) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: PersistenceKey.lastModified) }
    }

    private var pendingSaveWork: DispatchWorkItem?

    /// Debounced save — coalesces rapid text-field changes (title, notes) into a single disk write.
    func saveDebounced(delay: Double = 0.4) {
        pendingSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func save() {
        pendingSaveWork?.cancel()
        pendingSaveWork = nil
        let snapshot = makeSnapshot()
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: PersistenceKey.appState)
        }
        localLastModified = Date()
        WidgetSync.sync(tasks: tasks, taskLists: taskLists)
        WidgetSync.syncHabits(habits: habits, todayKey: todayKey, streakFor: streakFor)
        syncHabitReminderSummaries()
        if let uid = cloudUserId {
            syncState = .syncing
            FirestoreSync.shared.scheduleUpload(snapshot, userId: uid)
        }
    }

    func taskList(for task: AppTask) -> TaskList? {
        taskLists.first { $0.id == task.listId }
    }

    func makeSnapshot() -> StateSnapshot {
        StateSnapshot(
            tasks: tasks,
            taskLists: taskLists,
            bills: bills,
            incomes: incomes,
            oneOffExpenses: oneOffExpenses,
            moneySettings: moneySettings,
            habits: habits,
            exercises: exercises,
            routines: routines,
            sessions: sessions,
            weightEntries: weightEntries,
            bodyCompEntries: bodyCompEntries,
            bodyMeasurements: bodyMeasurements,
            achievements: achievements,
            programs: programs,
            careDays: careDays,
            careSettings: careSettings,
            workoutSettings: workoutSettings,
            userName: userName,
            visitedLocations: visitedLocations,
            plannedSessions: plannedSessions,
            supplements: supplements,
            healthDays: healthDays,
            healthSettings: healthSettings,
            sleepNights: sleepNights,
            sleepComparisons: sleepComparisons
        )
    }

    func apply(snapshot: StateSnapshot) {
        tasks = snapshot.tasks
        taskLists = snapshot.taskLists.isEmpty ? Self.defaultTaskLists : snapshot.taskLists
        bills = snapshot.bills
        incomes = snapshot.incomes
        oneOffExpenses = snapshot.oneOffExpenses
        moneySettings = snapshot.moneySettings
        habits = snapshot.habits
        supplements = snapshot.supplements
        exercises = WorkoutSeed.mergeExercises(into: snapshot.exercises)
        routines = snapshot.routines.isEmpty ? WorkoutSeed.routines : snapshot.routines
        sessions = snapshot.sessions
        weightEntries = snapshot.weightEntries
        bodyCompEntries = snapshot.bodyCompEntries
        bodyMeasurements = snapshot.bodyMeasurements
        achievements = snapshot.achievements
        programs = snapshot.programs
        careDays = snapshot.careDays
        careSettings = snapshot.careSettings
        workoutSettings = snapshot.workoutSettings
        userName = snapshot.userName
        visitedLocations = snapshot.visitedLocations
        plannedSessions = snapshot.plannedSessions
        healthDays = snapshot.healthDays ?? [:]
        healthSettings = snapshot.healthSettings ?? HealthSettings()
        sleepNights = snapshot.sleepNights ?? [:]
        sleepComparisons = snapshot.sleepComparisons ?? [:]
    }

    // MARK: Cloud Sync

    func loadFromCloud(userId: String) async {
        cloudUserId = userId
        await MainActor.run { syncState = .syncing }
        do {
            if let downloaded = try await FirestoreSync.shared.download(userId: userId) {
                if localLastModified > downloaded.updatedAt {
                    // This device has changes the cloud doesn't know about yet
                    // (e.g. made while offline, or after another device's last
                    // sync) — applying the cloud snapshot here would silently
                    // discard them. Keep local data and push it up instead so
                    // the cloud catches up.
                    await MainActor.run {
                        syncState = .syncing
                        FirestoreSync.shared.scheduleUpload(makeSnapshot(), userId: userId)
                    }
                } else {
                    await MainActor.run {
                        apply(snapshot: downloaded.snapshot)
                        localLastModified = downloaded.updatedAt
                        syncState = .synced(Date())
                    }
                }
            } else {
                // First sign-in — upload existing local data to the cloud
                FirestoreSync.shared.scheduleUpload(makeSnapshot(), userId: userId)
                await MainActor.run { syncState = .synced(Date()) }
            }
        } catch {
            // Network unavailable — carry on with local data, but surface the
            // failure so the UI can show a "Sync failed" banner with retry.
            await MainActor.run { syncState = .failed(error.localizedDescription) }
        }
    }

    func disableCloudSync() {
        // Cancel any queued upload so a debounced write from the previous
        // session can't fire after sign-out and leak data into the cloud.
        FirestoreSync.shared.cancelPending()
        cloudUserId = nil
        syncState = .idle
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: PersistenceKey.appState),
           let snapshot = try? JSONDecoder().decode(StateSnapshot.self, from: data) {
            apply(snapshot: snapshot)
            if taskLists.isEmpty { taskLists = Self.defaultTaskLists }
        } else {
            // First launch — seed default data
            exercises = WorkoutSeed.exercises
            routines = WorkoutSeed.routines
            seedDefaults()
        }
        loadPhotos()
        // Defer notification scheduling off the synchronous launch path.
        let habitsSnapshot = habits
        DispatchQueue.main.async { [weak self] in
            HabitReminderManager.shared.syncReminders(for: habitsSnapshot)
            self?.syncHabitReminderSummaries()
        }
    }

    /// Schedules (or cancels) the daily morning-summary and evening-nudge
    /// habit notifications based on CareSettings and today's completion
    /// state. Uses the same "is this habit done today" rule as the widget
    /// (WidgetSync.syncHabits) so the notification and widget agree.
    private func syncHabitReminderSummaries() {
        let unfinishedToday = habits.filter { habit in
            guard !habit.isArchived else { return false }
            let todayLog = habit.logs.first { $0.dayKey == todayKey }
            let count = todayLog?.count ?? 0
            let slipped = todayLog?.slipped == true
            let isCompleted = habit.kind == .break ? !slipped : (!slipped && count >= habit.targetCount)
            return !isCompleted
        }

        if careSettings.morningSummaryEnabled {
            HabitReminderManager.shared.scheduleMorningSummary(activeCount: unfinishedToday.count)
        } else {
            HabitReminderManager.shared.cancelMorningSummary()
        }

        if careSettings.eveningNudgeEnabled {
            HabitReminderManager.shared.scheduleEveningNudge(unfinishedNames: unfinishedToday.map(\.name))
        } else {
            HabitReminderManager.shared.cancelEveningNudge()
        }
    }

    static let defaultTaskLists: [TaskList] = [
        TaskList(id: "work",     name: "Work",     emoji: "💼", colorHex: "#5E9BF0", isSystem: true),
        TaskList(id: "gym",      name: "Gym",      emoji: "🏋️", colorHex: "#2FD4C0", isSystem: true),
        TaskList(id: "personal", name: "Personal", emoji: "🌱", colorHex: "#FF9F0A", isSystem: true),
    ]

    private func seedDefaults() {
        taskLists = Self.defaultTaskLists
        tasks = [
            AppTask(title: "Reply to client email", listId: "work", dueDate: .today),
            AppTask(title: "Push session — legs", listId: "gym", dueDate: .today),
            AppTask(title: "Refill water bottle", listId: "personal", dueDate: .today),
        ]
        bills = [
            Bill(name: "Rent", amount: 1200, dayOfMonth: 1),
            Bill(name: "Electricity", amount: 85, dayOfMonth: 15),
            Bill(name: "Internet", amount: 45, dayOfMonth: 20),
            Bill(name: "Phone", amount: 35, dayOfMonth: 28),
        ]
        habits = [
            Habit(name: "Drink 8 glasses of water", emoji: "💧", kind: .build, cadence: .daily, targetCount: 8),
            Habit(name: "Read for 20 minutes", emoji: "📚", kind: .build, cadence: .daily, targetCount: 1),
            Habit(name: "No social media after 9pm", emoji: "📵", kind: .break, cadence: .daily, targetCount: 1),
            Habit(name: "Exercise 4x per week", emoji: "🏃", kind: .build, cadence: .weekly, targetCount: 4),
        ]
        save()
    }

    // MARK: - Task Mutations

    func addTask(title: String, listId: String = "personal", dueDate: DueDate, priority: TaskPriority = .none, notes: String = "", dueDateOverride: Date? = nil) {
        var task = AppTask(title: title, listId: listId, dueDate: dueDate)
        task.priority = priority
        task.notes = notes
        task.dueDateOverride = dueDateOverride
        tasks.append(task)
        save()
    }

    func toggleTask(id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let wasRecurring = tasks[idx].isRecurring
        let recurrenceType = tasks[idx].recurrenceType
        tasks[idx].done.toggle()
        tasks[idx].completedAt = tasks[idx].done ? Date() : nil
        if tasks[idx].done { NotificationsManager.shared.cancelTaskReminder(taskId: id) }

        // Advance recurring task to next period when checked off
        if tasks[idx].done, wasRecurring, let rt = recurrenceType {
            let base = tasks[idx].dueDateOverride ?? tasks[idx].dueDate?.date ?? Date()
            let cal = Calendar.current
            let nextDate: Date?
            switch rt {
            case .daily:    nextDate = cal.date(byAdding: .day, value: 1, to: base)
            case .weekly:   nextDate = cal.date(byAdding: .weekOfYear, value: 1, to: base)
            case .biweekly: nextDate = cal.date(byAdding: .weekOfYear, value: 2, to: base)
            case .monthly:  nextDate = cal.date(byAdding: .month, value: 1, to: base)
            case .yearly:   nextDate = cal.date(byAdding: .year, value: 1, to: base)
            }
            if let next = nextDate {
                tasks[idx].done = false
                tasks[idx].completedAt = nil
                tasks[idx].dueDateOverride = cal.startOfDay(for: next)
                tasks[idx].dueDate = nil

                // Carry the reminder forward to the next occurrence so
                // recurring tasks don't silently lose their notifications.
                if let oldReminder = tasks[idx].reminderDate {
                    let delta = next.timeIntervalSince(base)
                    let newReminder = oldReminder.addingTimeInterval(delta)
                    tasks[idx].reminderDate = newReminder
                    NotificationsManager.shared.scheduleTaskReminder(
                        taskId: tasks[idx].id,
                        title: tasks[idx].title,
                        at: newReminder
                    )
                }
            }
        }
        save()
    }

    func deleteTask(id: String) {
        NotificationsManager.shared.cancelTaskReminder(taskId: id)
        tasks.removeAll { $0.id == id }
        save()
    }

    func updateTask(id: String, title: String? = nil, dueDate: DueDate?? = nil, priority: TaskPriority? = nil, notes: String? = nil, listId: String? = nil, dueDateOverride: Date?? = nil, reminderDate: Date?? = nil, scheduledTime: Date?? = nil, estimatedMinutes: Int?? = nil, isRecurring: Bool? = nil, recurrenceType: RecurrenceType?? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        // Track whether this update is text-only (title/notes) to debounce disk writes.
        let isTextOnly = title != nil || notes != nil
        var otherFieldsChanged = false
        if let title = title { tasks[idx].title = title }
        if let dueDate = dueDate { tasks[idx].dueDate = dueDate; otherFieldsChanged = true }
        if let priority = priority { tasks[idx].priority = priority; otherFieldsChanged = true }
        if let notes = notes { tasks[idx].notes = notes }
        if let listId = listId { tasks[idx].listId = listId; otherFieldsChanged = true }
        if let override = dueDateOverride { tasks[idx].dueDateOverride = override; otherFieldsChanged = true }
        if let rd = reminderDate {
            tasks[idx].reminderDate = rd
            otherFieldsChanged = true
            if let date = rd {
                NotificationsManager.shared.scheduleTaskReminder(taskId: id, title: tasks[idx].title, at: date)
            } else {
                NotificationsManager.shared.cancelTaskReminder(taskId: id)
            }
        }
        if let st = scheduledTime { tasks[idx].scheduledTime = st; otherFieldsChanged = true }
        if let em = estimatedMinutes { tasks[idx].estimatedMinutes = em; otherFieldsChanged = true }
        if let rec = isRecurring { tasks[idx].isRecurring = rec; otherFieldsChanged = true }
        if let rt = recurrenceType { tasks[idx].recurrenceType = rt; otherFieldsChanged = true }
        if isTextOnly && !otherFieldsChanged {
            saveDebounced()
        } else {
            save()
        }
    }

    // MARK: - Subtask Mutations

    func addSubtask(taskId: String, title: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].subtasks.append(Subtask(title: title))
        save()
    }

    func toggleSubtask(taskId: String, subtaskId: String) {
        guard let tIdx = tasks.firstIndex(where: { $0.id == taskId }),
              let sIdx = tasks[tIdx].subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
        tasks[tIdx].subtasks[sIdx].done.toggle()
        save()
    }

    func deleteSubtask(taskId: String, subtaskId: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].subtasks.removeAll { $0.id == subtaskId }
        save()
    }

    // MARK: - Bill Mutations

    func addBill(name: String, amount: Double, dayOfMonth: Int, notes: String = "") {
        let bill = Bill(name: name, amount: amount, dayOfMonth: dayOfMonth, notes: notes)
        bills.append(bill)
        save()
    }

    func deleteBill(id: String) {
        bills.removeAll { $0.id == id }
        save()
    }

    func updateBill(id: String, name: String? = nil, amount: Double? = nil, dayOfMonth: Int? = nil, notes: String? = nil) {
        guard let idx = bills.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { bills[idx].name = name }
        if let amount = amount { bills[idx].amount = amount }
        if let day = dayOfMonth { bills[idx].dayOfMonth = day }
        if let notes = notes { bills[idx].notes = notes }
        save()
    }

    // MARK: - Income Mutations

    func addIncome(name: String, amount: Double, dayOfMonth: Int, notes: String = "") {
        incomes.append(Income(name: name, amount: amount, dayOfMonth: dayOfMonth, notes: notes))
        save()
    }

    func deleteIncome(id: String) {
        incomes.removeAll { $0.id == id }
        save()
    }

    func updateIncome(id: String, name: String? = nil, amount: Double? = nil, dayOfMonth: Int? = nil, notes: String? = nil) {
        guard let idx = incomes.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { incomes[idx].name = name }
        if let amount = amount { incomes[idx].amount = amount }
        if let day = dayOfMonth { incomes[idx].dayOfMonth = day }
        if let notes = notes { incomes[idx].notes = notes }
        save()
    }

    // MARK: - One-Off Expense Mutations

    func addOneOffExpense(name: String, amount: Double, date: Date = Date(), notes: String = "") {
        oneOffExpenses.append(OneOffExpense(name: name, amount: amount, date: date, notes: notes))
        save()
    }

    func deleteOneOffExpense(id: String) {
        oneOffExpenses.removeAll { $0.id == id }
        save()
    }

    func updateOneOffExpense(id: String, name: String? = nil, amount: Double? = nil, date: Date? = nil, notes: String? = nil) {
        guard let idx = oneOffExpenses.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { oneOffExpenses[idx].name = name }
        if let amount = amount { oneOffExpenses[idx].amount = amount }
        if let date = date { oneOffExpenses[idx].date = date }
        if let notes = notes { oneOffExpenses[idx].notes = notes }
        save()
    }

    func setMoneySettings(_ settings: MoneySettings) {
        moneySettings = settings
        save()
    }

    // MARK: - Habit Analytics

    func streakFor(_ habit: Habit) -> Int {
        var count = 0
        let cal = Calendar.current
        let todayKey = Date().dayKey
        let todayLog = habit.logs.first(where: { $0.dayKey == todayKey })
        let todaySuccess: Bool = {
            if habit.kind == .break { return todayLog?.slipped != true }
            return todayLog != nil && (todayLog?.count ?? 0) >= habit.targetCount && todayLog?.slipped != true
        }()
        // If today isn't done yet, start from yesterday so streak persists until midnight
        var date: Date = todaySuccess ? Date() : (cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        // Lower bound: never walk before the habit was created. Critical for break
        // habits, where a no-log day counts as success — without this the loop
        // would walk backward forever and freeze the main thread.
        let startBound = cal.startOfDay(for: habit.createdAt)
        while date >= startBound {
            let key = date.dayKey
            let log = habit.logs.first(where: { $0.dayKey == key })
            let success: Bool
            if habit.kind == .break {
                success = log?.slipped != true
            } else {
                success = log != nil && (log?.count ?? 0) >= habit.targetCount && log?.slipped != true
            }
            if success {
                count += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
                date = prev
            } else {
                break
            }
        }
        return count
    }

    func bestStreakFor(_ habit: Habit) -> Int {
        let cal = Calendar.current
        let fmt = _dayKeyFormatter

        if habit.kind == .break {
            // For break habits, find the longest run of days without a slip
            // Walk from the earliest log date to today
            guard let earliest = habit.logs.compactMap({ fmt.date(from: $0.dayKey) }).min() else { return 0 }
            let slippedKeys = Set(habit.logs.filter { $0.slipped }.map { $0.dayKey })
            var best = 0, current = 0
            var date = earliest
            let today = cal.startOfDay(for: Date())
            while date <= today {
                if !slippedKeys.contains(date.dayKey) {
                    current += 1
                    best = max(best, current)
                } else {
                    current = 0
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
            return best
        }

        guard !habit.logs.isEmpty else { return 0 }
        let sortedDays = habit.logs
            .filter { $0.count >= habit.targetCount && !$0.slipped }
            .compactMap { fmt.date(from: $0.dayKey) }
            .sorted()
        guard !sortedDays.isEmpty else { return 0 }
        var best = 1, current = 1
        for i in 1..<sortedDays.count {
            let diff = cal.dateComponents([.day], from: sortedDays[i-1], to: sortedDays[i]).day ?? 0
            if diff == 1 { current += 1; best = max(best, current) } else { current = 1 }
        }
        return best
    }

    func totalCompletionsFor(_ habit: Habit) -> Int {
        if habit.kind == .break {
            // Count days with a log that didn't slip (maintained days)
            return habit.logs.filter { !$0.slipped }.count
        }
        return habit.logs.filter { $0.count >= habit.targetCount && !$0.slipped }.count
    }

    func weeklyCompletionFor(_ habit: Habit) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var completed = 0
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = day.dayKey
            let log = habit.logs.first(where: { $0.dayKey == key })
            if habit.kind == .break {
                if log?.slipped != true { completed += 1 }
            } else if let log = log, log.count >= habit.targetCount, !log.slipped {
                completed += 1
            }
        }
        return Double(completed) / 7.0
    }

    // MARK: - Habit Mutations

    func addHabit(name: String, emoji: String, kind: HabitKind, cadence: HabitCadence, targetCount: Int) {
        let habit = Habit(name: name, emoji: emoji, kind: kind, cadence: cadence, targetCount: targetCount)
        habits.append(habit)
        save()
    }

    func updateHabit(id: String, name: String? = nil, emoji: String? = nil, kind: HabitKind? = nil, cadence: HabitCadence? = nil, targetCount: Int? = nil, reminderEnabled: Bool? = nil, reminderTime: Date?? = nil) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { habits[idx].name = name }
        if let emoji = emoji { habits[idx].emoji = emoji }
        if let kind = kind { habits[idx].kind = kind }
        if let cadence = cadence { habits[idx].cadence = cadence }
        if let target = targetCount { habits[idx].targetCount = target }
        if let enabled = reminderEnabled { habits[idx].reminderEnabled = enabled }
        if let time = reminderTime { habits[idx].reminderTime = time }
        HabitReminderManager.shared.syncReminders(for: [habits[idx]])
        save()
    }

    func deleteHabit(id: String) {
        HabitReminderManager.shared.cancelReminder(habitId: id)
        habits.removeAll { $0.id == id }
        save()
    }

    func toggleArchiveHabit(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[idx].isArchived.toggle()
        HabitReminderManager.shared.syncReminders(for: [habits[idx]])
        save()
    }

    func logHabit(id: String, dayKey: String? = nil, count: Int = 1) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = dayKey ?? todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].count += count
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: count))
        }
        save()
    }

    func toggleHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs.remove(at: logIdx)
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: 1))
        }
        save()
    }

    /// Mark a habit complete for today (idempotent). Used to apply completions
    /// queued by the widget's interactive button.
    func completeHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if habits[idx].kind == .break {
            if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
                habits[idx].logs[logIdx].slipped = false
            }
            // No log for a break habit already counts as maintained.
        } else {
            let target = max(1, habits[idx].targetCount)
            if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
                habits[idx].logs[logIdx].slipped = false
                if habits[idx].logs[logIdx].count < target {
                    habits[idx].logs[logIdx].count = target
                }
            } else {
                habits[idx].logs.append(HabitLogEntry(dayKey: key, count: target))
            }
        }
        save()
    }

    /// Apply any habit completions the widget queued (its interactive button
    /// writes ids to the App Group; the app logs them next time it's active).
    func drainPendingHabitCompletions() {
        let appGroup = "group.uk.co.prolineroofingandsolar.life"
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.string(forKey: "life_pending_completions_date") == todayKey else { return }
        let pending = (defaults.array(forKey: "life_pending_completions_v1") as? [String]) ?? []
        guard !pending.isEmpty else { return }
        defaults.set([String](), forKey: "life_pending_completions_v1")
        for id in pending { completeHabitToday(id: id) }
    }

    func incHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].count += 1
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: 1))
        }
        // If this is a water-tracking habit, also increment the hydration ring
        if habits[idx].name.lowercased().contains("water") {
            addWater()
            return // save() already called inside addWater()
        }
        save()
    }

    func undoHabitCompletion(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        habits[idx].logs.removeAll { $0.dayKey == key }
        save()
    }

    func setHabitCount(id: String, count: Int) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        let clamped = max(0, count)
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            if clamped == 0 {
                habits[idx].logs.remove(at: logIdx)
            } else {
                habits[idx].logs[logIdx].count = clamped
            }
        } else if clamped > 0 {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: clamped))
        }
        save()
    }

    func completeHabitTimer(id: String, seconds: Int) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        let minutes = max(1, seconds / 60)
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].count = minutes
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: minutes))
        }
        save()
    }

    func slipHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].slipped = true
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: 1, slipped: true))
        }
        save()
    }

    func decHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        guard let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) else { return }
        if habits[idx].logs[logIdx].count > 1 {
            habits[idx].logs[logIdx].count -= 1
        } else {
            habits[idx].logs.remove(at: logIdx)
        }
        save()
        // Also undo water ring if applicable
        if habits[idx].name.lowercased().contains("water") {
            removeWater()
        }
    }

    func unslipHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        habits[idx].logs.removeAll { $0.dayKey == key }
        save()
    }

    // MARK: - Supplement Mutations

    func addSupplement(_ supplement: Supplement) {
        supplements.append(supplement)
        save()
    }

    func updateSupplement(_ supplement: Supplement) {
        guard let idx = supplements.firstIndex(where: { $0.id == supplement.id }) else { return }
        var updated = supplement
        updated.logs = supplements[idx].logs // preserve existing dose logs
        supplements[idx] = updated
        save()
    }

    func deleteSupplement(id: String) {
        supplements.removeAll { $0.id == id }
        save()
    }

    func logDose(supplementId: String) {
        guard let idx = supplements.firstIndex(where: { $0.id == supplementId }) else { return }
        let key = Date().dayKey
        if let logIdx = supplements[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            supplements[idx].logs[logIdx].dosesTaken += 1
        } else {
            supplements[idx].logs.append(DoseLog(dayKey: key, dosesTaken: 1))
        }
        save()
    }

    func undoDose(supplementId: String) {
        guard let idx = supplements.firstIndex(where: { $0.id == supplementId }) else { return }
        let key = Date().dayKey
        guard let logIdx = supplements[idx].logs.firstIndex(where: { $0.dayKey == key }) else { return }
        if supplements[idx].logs[logIdx].dosesTaken > 1 {
            supplements[idx].logs[logIdx].dosesTaken -= 1
        } else {
            supplements[idx].logs.remove(at: logIdx)
        }
        save()
    }

    func dosesToday(for supplement: Supplement) -> Int {
        supplement.logs.first(where: { $0.dayKey == Date().dayKey })?.dosesTaken ?? 0
    }

    func isDueToday(_ supplement: Supplement) -> Bool {
        guard !supplement.isArchived else { return false }
        if supplement.scheduleDays.isEmpty { return true }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let mon1 = ((weekday + 5) % 7) + 1
        return supplement.scheduleDays.contains(mon1)
    }

    // MARK: - Routine Mutations

    func addRoutine(name: String, exercises: [RoutineExercise] = []) {
        let routine = Routine(name: name, exercises: exercises)
        routines.append(routine)
        save()
    }

    func updateRoutine(id: String, name: String? = nil, exercises: [RoutineExercise]? = nil, colorHex: String? = nil, emoji: String? = nil, photoData: Data? = nil, clearPhoto: Bool = false) {
        guard let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { routines[idx].name = name }
        if let exercises = exercises { routines[idx].exercises = exercises }
        if let colorHex = colorHex { routines[idx].colorHex = colorHex }
        if let emoji = emoji { routines[idx].emoji = emoji }
        if clearPhoto { routines[idx].photoData = nil }
        else if let photoData = photoData { routines[idx].photoData = photoData }
        save()
    }

    func deleteRoutine(id: String) {
        routines.removeAll { $0.id == id }
        save()
    }

    // MARK: - Workout Session Mutations

    func startSession(name: String, routineId: String? = nil) {
        // Safety: if a workout is already in progress, do nothing instead of
        // silently destroying it. Callers should inspect `activeSession` first
        // and either resume it or prompt the user to finish/discard.
        guard activeSession == nil else { return }

        var session = WorkoutSession(name: name, routineId: routineId)

        if let routineId = routineId,
           let routine = routines.first(where: { $0.id == routineId }) {
            session.exercises = routine.exercises.map { re in
                var sessionExercise = SessionExercise(exerciseId: re.exerciseId)
                let suggested = suggestedWeight(for: re.exerciseId)
                let sugReps = suggestedReps(for: re.exerciseId)
                let weight = suggested > 0 ? suggested : re.defaultWeight
                let reps = sugReps > 0 ? sugReps : re.defaultReps
                sessionExercise.targetRepMin = re.repRangeMin
                sessionExercise.targetRepMax = re.repRangeMax
                sessionExercise.sets = (0..<re.defaultSets).map { _ in
                    LoggedSet(weight: weight, reps: reps)
                }
                return sessionExercise
            }
        }

        sessions.append(session)
        if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.start(workoutName: session.name, startedAt: session.startedAt)
        }
        save()
    }

    func updateSet(sessionId: String, exerciseId: String, setId: String, weight: Double? = nil, reps: Int? = nil, durationSec: Int? = nil, distanceKm: Double? = nil, isWarmup: Bool? = nil, isDropSet: Bool? = nil, rpe: Int? = nil) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        if let weight = weight { sessions[sIdx].exercises[eIdx].sets[setIdx].weight = weight }
        if let reps = reps { sessions[sIdx].exercises[eIdx].sets[setIdx].reps = reps }
        if let dur = durationSec { sessions[sIdx].exercises[eIdx].sets[setIdx].durationSec = dur }
        if let dist = distanceKm { sessions[sIdx].exercises[eIdx].sets[setIdx].distanceKm = dist }
        if let warmup = isWarmup { sessions[sIdx].exercises[eIdx].sets[setIdx].isWarmup = warmup }
        if let drop = isDropSet { sessions[sIdx].exercises[eIdx].sets[setIdx].isDropSet = drop }
        if let rpe = rpe { sessions[sIdx].exercises[eIdx].sets[setIdx].rpe = rpe == 0 ? nil : rpe }
        save()
    }

    func toggleSetDone(sessionId: String, exerciseId: String, setId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        let isDone = !sessions[sIdx].exercises[eIdx].sets[setIdx].done
        sessions[sIdx].exercises[eIdx].sets[setIdx].done = isDone
        sessions[sIdx].exercises[eIdx].sets[setIdx].completedAt = isDone ? Date() : nil
        if isDone {
            let set = sessions[sIdx].exercises[eIdx].sets[setIdx]
            let exId = sessions[sIdx].exercises[eIdx].exerciseId
            let prevPR = computePRs(for: exId)
            let new1RM = set.weight * (1 + Double(set.reps) / 30.0)
            if set.weight > prevPR.bestWeight || new1RM > prevPR.best1RM {
                let name = exercises.first(where: { $0.id == exId })?.name ?? "Exercise"
                latestPR = (exerciseName: name, value: "\(set.weight.formatted1)kg × \(set.reps)")
                if !achievements.contains(where: { $0.kind == .weightPR }) || set.weight > prevPR.bestWeight {
                    let unlocked = Set(achievements.map(\.kind))
                    if !unlocked.contains(.weightPR) {
                        achievements.append(Achievement(kind: .weightPR, title: AchievementKind.weightPR.title, detail: "\(name): \(set.weight.formatted1)kg"))
                    }
                }
            }
        }
        save()
    }

    func toggleSetFailure(sessionId: String, exerciseId: String, setId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        sessions[sIdx].exercises[eIdx].sets[setIdx].isFailure.toggle()
        save()
    }

    func addSet(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let lastSet = sessions[sIdx].exercises[eIdx].sets.last
        // Prefer last set in current session; fall back to previous session history
        let weight: Double
        let reps: Int
        if let last = lastSet, last.weight > 0 {
            weight = last.weight
            reps = last.reps
        } else {
            weight = suggestedWeight(for: exerciseId)
            reps = suggestedReps(for: exerciseId)
        }
        sessions[sIdx].exercises[eIdx].sets.append(LoggedSet(weight: weight, reps: reps))
        save()
    }

    func removeSet(sessionId: String, exerciseId: String, setId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        sessions[sIdx].exercises[eIdx].sets.removeAll { $0.id == setId }
        save()
    }

    func addExerciseToSession(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var sessionExercise = SessionExercise(exerciseId: exerciseId)
        let w = suggestedWeight(for: exerciseId)
        let r = suggestedReps(for: exerciseId)
        sessionExercise.sets = [LoggedSet(weight: w, reps: r)]
        sessions[sIdx].exercises.append(sessionExercise)
        save()
    }

    func removeExerciseFromSession(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[sIdx].exercises.removeAll { $0.id == exerciseId }
        save()
    }

    func addDropSet(sessionId: String, exerciseId: String, afterSetId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == afterSetId }) else { return }
        let parent = sessions[sIdx].exercises[eIdx].sets[setIdx]
        let drop = LoggedSet(weight: max(0, parent.weight - 5), reps: parent.reps, isDropSet: true)
        sessions[sIdx].exercises[eIdx].sets.insert(drop, at: setIdx + 1)
        save()
    }

    func setSupersetGroup(sessionId: String, exerciseIds: [String], groupId: String?) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        for eIdx in sessions[sIdx].exercises.indices {
            if exerciseIds.contains(sessions[sIdx].exercises[eIdx].id) {
                sessions[sIdx].exercises[eIdx].supersetGroupId = groupId
            }
        }
        save()
    }

    func finishSession(sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].finishedAt = Date()
        // Mark any planned session for today as completed
        let todayStart = Calendar.current.startOfDay(for: Date())
        if let pIdx = plannedSessions.firstIndex(where: {
            Calendar.current.startOfDay(for: $0.date) == todayStart && !$0.completed
        }) {
            plannedSessions[pIdx].completed = true
        }
        checkAndGrantAchievements()
        if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.end()
        }
        save()
    }

    func updateSessionNotes(sessionId: String, notes: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].notes = notes
        save()
    }

    func deleteFinishedSession(sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
        save()
    }

    func rateSession(sessionId: String, rating: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].rating = rating
        save()
    }

    func discardSession(sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
        if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.end()
        }
        save()
    }

    func renameSession(sessionId: String, name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].name = name
        save()
    }

    func reorderExercises(sessionId: String, from: IndexSet, to: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].exercises.move(fromOffsets: from, toOffset: to)
        save()
    }

    /// Adjust a (finished) workout's date and duration. Sets `finishedAt` to the
    /// chosen date and back-dates `startedAt` so the stored duration is preserved.
    func setSessionTimes(sessionId: String, date: Date, durationSeconds: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].finishedAt = date
        sessions[idx].startedAt = date.addingTimeInterval(-TimeInterval(max(0, durationSeconds)))
        save()
    }

    func addWarmupSets(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let workingWeight = sessions[sIdx].exercises[eIdx].sets.first(where: { !$0.isWarmup })?.weight
                            ?? suggestedWeight(for: exerciseId)
        guard workingWeight > 0 else { return }
        let warmupSpecs: [(pct: Double, reps: Int)] = [(0.4, 5), (0.6, 3), (0.8, 2)]
        let newSets = warmupSpecs.map { w -> LoggedSet in
            var s = LoggedSet()
            s.weight = (workingWeight * w.pct / 2.5).rounded() * 2.5
            s.reps = w.reps
            s.isWarmup = true
            return s
        }
        sessions[sIdx].exercises[eIdx].sets.insert(contentsOf: newSets, at: 0)
        save()
    }

    // MARK: - Body / Weight Mutations

    func logBodyWeight(valueKg: Double, date: Date = Date()) {
        let entry = WeightEntry(date: date, valueKg: valueKg)
        weightEntries.append(entry)
        weightEntries.sort { $0.date < $1.date }
        save()
    }

    func deleteWeightEntry(id: String) {
        weightEntries.removeAll { $0.id == id }
        save()
    }

    func mergeBodyCompEntries(_ newEntries: [BodyCompEntry]) {
        for entry in newEntries {
            // Match by date (same day)
            let key = entry.date.dayKey
            if let idx = bodyCompEntries.firstIndex(where: { $0.date.dayKey == key }) {
                // Merge fields
                if let bf = entry.bodyFatPct { bodyCompEntries[idx].bodyFatPct = bf }
                if let lm = entry.leanMassKg { bodyCompEntries[idx].leanMassKg = lm }
                if let bmi = entry.bmi { bodyCompEntries[idx].bmi = bmi }
            } else {
                bodyCompEntries.append(entry)
            }
        }
        bodyCompEntries.sort { $0.date < $1.date }
        save()
    }

    func deleteBodyCompEntry(id: String) {
        bodyCompEntries.removeAll { $0.id == id }
        save()
    }

    func setGoalWeight(kg: Double?) {
        workoutSettings.goalWeightKg = kg
        save()
    }

    // MARK: - Care Day Mutations

    func addWater() {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        day.waterGlasses += 1
        careDays[todayKey] = day
        save()
    }

    func removeWater() {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        if day.waterGlasses > 0 { day.waterGlasses -= 1 }
        careDays[todayKey] = day
        save()
    }

    func addMeal(name: String = "") {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        day.meals.append(name.isEmpty ? "Meal \(day.meals.count + 1)" : name)
        careDays[todayKey] = day
        save()
    }

    func markBreak() {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        day.lastBreakAt = Date()
        day.breaksTaken += 1
        careDays[todayKey] = day
        save()
    }

    func syncSteps(_ steps: Int) {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        day.steps = max(0, steps)
        careDays[todayKey] = day
        save()
    }

    /// Backfills step counts for past days without touching anything else on
    /// those records.
    func mergeSteps(_ stepsByDay: [String: Int]) {
        guard !stepsByDay.isEmpty else { return }
        for (key, steps) in stepsByDay {
            var day = careDays[key] ?? CareDay(dayKey: key)
            // Today is still being counted, and a sync that catches the source
            // mid-import can return less than it did a minute ago — which made
            // the step count visibly go *down* during the day. Keep the higher
            // figure for today only.
            //
            // Past days stay a straight overwrite: there the source is
            // authoritative and a correction should be allowed to reduce the
            // number, which a max() would silently block forever.
            day.steps = key == todayKey ? max(day.steps, max(0, steps)) : max(0, steps)
            careDays[key] = day
        }
        save()
    }

    // MARK: - Health Mutations

    /// How much health history to keep. The whole `StateSnapshot` is uploaded as
    /// a single Firestore document with a 1 MB ceiling, and `healthDays` is the
    /// one collection that grows by a record every day forever — so it gets a
    /// hard cap rather than being allowed to creep up on the limit.
    private static let healthDayRetention = 400

    /// Merges a sync into stored history field by field, so a short 7-day pull
    /// never blanks values an earlier full import found. Only non-nil incoming
    /// values overwrite.
    func mergeHealthDays(_ days: [HealthDay]) {
        guard !days.isEmpty else { return }

        for incoming in days where !incoming.dayKey.isEmpty {
            let existing = healthDays[incoming.dayKey] ?? HealthDay(dayKey: incoming.dayKey)
            healthDays[incoming.dayKey] = HealthDay.merging(incoming, onto: existing)
        }

        pruneHealthDays()
        save()
    }

    /// Stores a day's heart-rate range and mean, derived from the sample curve
    /// that `HeartRateStore` holds in memory.
    ///
    /// Writes only when a figure actually moved. This is called after every
    /// poll while the Health tab is open, and saving on each tick would push a
    /// Firestore write a minute for numbers that barely change.
    func recordHeartRateAggregates(dayKey: String, min: Double, max: Double, average: Double) {
        guard !dayKey.isEmpty else { return }
        var day = healthDays[dayKey] ?? HealthDay(dayKey: dayKey)

        let rounded = (min.rounded(), max.rounded(), (average * 10).rounded() / 10)
        guard day.hrMin != rounded.0 || day.hrMax != rounded.1 || day.hrAverage != rounded.2 else {
            return
        }
        day.hrMin = rounded.0
        day.hrMax = rounded.1
        day.hrAverage = rounded.2
        healthDays[dayKey] = day
        save()
    }

    /// Hypnogram segments are roughly thirty records a night against a handful
    /// of numbers on `HealthDay`, so they get a much shorter memory. A year of
    /// them would be most of the 1 MB Firestore document on its own.
    private static let sleepNightRetention = 30

    /// Replaces stored nights outright rather than merging field by field: a
    /// night's stage list is a single indivisible reading, and a re-sync of the
    /// same night should supersede it, not interleave with it.
    func mergeSleepNights(_ nights: [SleepNight]) {
        guard !nights.isEmpty else { return }
        for night in nights where !night.dayKey.isEmpty && !night.segments.isEmpty {
            sleepNights[night.dayKey] = night
        }
        if sleepNights.count > Self.sleepNightRetention {
            let keep = Set(sleepNights.keys.sorted().suffix(Self.sleepNightRetention))
            sleepNights = sleepNights.filter { keep.contains($0.key) }
        }
        save()
    }

    // MARK: - Sleep score comparisons

    /// Saves a manually entered Google Health score for a night.
    ///
    /// Returns the reason it was refused, or nil on success. Validation lives in
    /// `SleepComparisonValidator` so the same rules apply here and at training
    /// time.
    @discardableResult
    func saveSleepComparison(googleScore: Int, for day: HealthDay) -> SleepComparisonValidator.Rejection? {
        let baselines = SleepFeatureBuilder.baselines(from: healthHistory, excluding: day.dayKey)
        let features = SleepFeatureBuilder.features(for: day, history: healthHistory, baselines: baselines)

        // Editing an existing entry is allowed; only a *new* duplicate is not.
        var existing = sleepComparisons
        existing.removeValue(forKey: day.dayKey)
        if let rejection = SleepComparisonValidator.validateEntry(
            googleScore: googleScore, features: features, existing: existing
        ) { return rejection }

        guard let result = SleepScore.calculate(features: features, baselines: baselines) else {
            return .missingStages
        }

        sleepComparisons[day.dayKey] = SleepScoreComparison(
            features: features, result: result, googleScore: googleScore
        )
        save()
        return nil
    }

    func removeSleepComparison(for dayKey: String) {
        guard sleepComparisons[dayKey] != nil else { return }
        sleepComparisons.removeValue(forKey: dayKey)
        save()
    }

    /// The calibration model fitted from currently valid comparisons.
    ///
    /// Re-validated on every fit rather than trusting what was stored: a night
    /// can be reprocessed by the source after a score was entered, and training
    /// on a stale pairing teaches the wrong correction.
    var sleepCalibrationModel: SleepScoreCalibration.Model {
        let history = healthHistory
        var featuresByDay: [String: SleepFeatures] = [:]
        for day in history where sleepComparisons[day.dayKey] != nil {
            let baselines = SleepFeatureBuilder.baselines(from: history, excluding: day.dayKey)
            featuresByDay[day.dayKey] = SleepFeatureBuilder.features(
                for: day, history: history, baselines: baselines
            )
        }
        let valid = SleepComparisonValidator.validTrainingSet(
            Array(sleepComparisons.values), featuresByDay: featuresByDay
        )
        return SleepScoreCalibration.fit(valid)
    }

    private func pruneHealthDays() {
        guard healthDays.count > Self.healthDayRetention else { return }
        let keep = Set(healthDays.keys.sorted().suffix(Self.healthDayRetention))
        healthDays = healthDays.filter { keep.contains($0.key) }
    }

    func setHealthSettings(_ transform: (inout HealthSettings) -> Void) {
        transform(&healthSettings)
        save()
    }

    // MARK: - Settings Mutations

    func setName(_ name: String) {
        userName = name
        save()
    }

    func setCareSettings(_ settings: CareSettings) {
        careSettings = settings
        save()
    }

    func setWorkoutSettings(_ settings: WorkoutSettings) {
        workoutSettings = settings
        save()
    }

    // MARK: - Exercise Mutations

    func addCustomExercise(name: String, muscle: String, kind: ExerciseKind,
                            equipment: ExerciseEquipment = .barbell,
                            movementType: MovementType = .compound) {
        let exercise = Exercise(name: name, muscle: muscle, kind: kind, isCustom: true,
                                equipment: equipment, movementType: movementType)
        exercises.append(exercise)
        save()
    }

    // MARK: - Previous Session Helpers

    func previousSets(for exerciseId: String) -> [LoggedSet] {
        let finished = sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        for session in finished {
            if let ex = session.exercises.first(where: { $0.exerciseId == exerciseId }) {
                let done = ex.sets.filter(\.done)
                if !done.isEmpty { return done }
            }
        }
        return []
    }

    func suggestedWeight(for exerciseId: String) -> Double {
        previousSets(for: exerciseId).first?.weight ?? 0
    }

    func suggestedReps(for exerciseId: String) -> Int {
        previousSets(for: exerciseId).first?.reps ?? 0
    }

    // MARK: - Workout Analytics

    /// A session counts as a real workout only if it's finished AND has at least
    /// one completed set. Excludes empty/accidental finishes so counts aren't
    /// inflated (all-time total, this-week, streak, achievements all use this).
    var completedWorkouts: [WorkoutSession] {
        sessions.filter { $0.finishedAt != nil && $0.totalSets > 0 }
    }

    var workoutStreak: Int {
        let finished = completedWorkouts
        guard !finished.isEmpty else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dayKeys = Set(finished.compactMap { $0.finishedAt }.map { cal.startOfDay(for: $0) })
        // Start from today; if no workout today, start from yesterday so streak persists until midnight
        var checkDate = dayKeys.contains(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        var streak = 0
        while dayKeys.contains(checkDate) {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    func volumeThisWeekByMuscle() -> [(muscle: String, volumeKg: Double)] {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let thisWeek = sessions.filter {
            guard let fin = $0.finishedAt else { return false }
            return fin >= weekStart
        }
        var map: [String: Double] = [:]
        for session in thisWeek {
            for ex in session.exercises {
                guard let exercise = exercises.first(where: { $0.id == ex.exerciseId }) else { continue }
                let vol = ex.sets.filter(\.done).reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                map[exercise.muscle, default: 0] += vol
            }
        }
        return map.map { (muscle: $0.key, volumeKg: $0.value) }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    /// Completed sets per muscle so far this (calendar) week.
    func setsThisWeekByMuscle() -> [(muscle: String, sets: Int)] {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let thisWeek = sessions.filter {
            guard let fin = $0.finishedAt else { return false }
            return fin >= weekStart
        }
        var map: [String: Int] = [:]
        for session in thisWeek {
            for ex in session.exercises {
                guard let exercise = exercises.first(where: { $0.id == ex.exerciseId }) else { continue }
                let sets = ex.sets.filter(\.done).count
                guard sets > 0 else { continue }
                map[exercise.muscle, default: 0] += sets
            }
        }
        return map.map { (muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets > $1.sets }
    }

    /// Weekly set-volume landmarks per muscle group for hypertrophy —
    /// roughly minimum-effective to near-maximum-recoverable volume, per
    /// commonly cited strength & conditioning volume landmarks (e.g.
    /// Renaissance Periodization / Schoenfeld-style guidance). "Legs" here
    /// covers both quads and hamstrings, so its range sits higher than a
    /// single-muscle target would.
    private static let weeklySetTargets: [String: (min: Int, max: Int)] = [
        "Chest":     (10, 20),
        "Back":      (10, 20),
        "Shoulders": (8, 16),
        "Biceps":    (8, 14),
        "Triceps":   (8, 14),
        "Legs":      (12, 20),
        "Glutes":    (6, 16),
        "Calves":    (8, 16),
        "Core":      (0, 15),
    ]

    func weeklySetTarget(forMuscle muscle: String) -> (min: Int, max: Int) {
        Self.weeklySetTargets[muscle] ?? (8, 16)
    }

    // MARK: - Progressive Overload

    enum OverloadSuggestion: Equatable {
        case addWeight(by: Double)
        case addReps
        case addSet
        case deload
        case maintain

        var label: String {
            switch self {
            case .addWeight(let by): return "+\(by.formatted1)kg"
            case .addReps:           return "+1 rep"
            case .addSet:            return "+1 set"
            case .deload:            return "Deload"
            case .maintain:          return "Maintain"
            }
        }
        var icon: String {
            switch self {
            case .addWeight: return "arrow.up.circle.fill"
            case .addReps:   return "plus.circle.fill"
            case .addSet:    return "square.stack.fill"
            case .deload:    return "arrow.down.circle.fill"
            case .maintain:  return "equal.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .addWeight: return AppTheme.primary
            case .addReps:   return .blue
            case .addSet:    return .orange
            case .deload:    return .red
            case .maintain:  return .secondary
            }
        }
    }

    func progressiveOverloadSuggestion(for exerciseId: String, targetRepMax: Int) -> OverloadSuggestion {
        let pastSets: [[LoggedSet]] = sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .compactMap { session in
                guard let ex = session.exercises.first(where: { $0.exerciseId == exerciseId }) else { return nil }
                let working = ex.sets.filter { $0.done && !$0.isWarmup }
                return working.isEmpty ? nil : working
            }

        guard let recent = pastSets.first, !recent.isEmpty else { return .addWeight(by: 2.5) }

        let avgReps = Double(recent.map(\.reps).reduce(0, +)) / Double(recent.count)
        let maxWeight = recent.map(\.weight).max() ?? 0

        if pastSets.count >= 3 {
            let weights = pastSets.prefix(3).map { $0.map(\.weight).max() ?? 0 }
            let reps    = pastSets.prefix(3).map { $0.map(\.reps).reduce(0, +) }
            if weights[0] == weights[1] && weights[1] == weights[2] &&
               reps[0] <= reps[1] && reps[1] <= reps[2] {
                return .deload
            }
        }

        if avgReps >= Double(targetRepMax) {
            return .addWeight(by: maxWeight >= 100 ? 5.0 : 2.5)
        }
        if avgReps >= Double(targetRepMax) - 1.5 {
            return .addReps
        }
        if pastSets.count >= 2 {
            let prevAvg = Double(pastSets[1].map(\.reps).reduce(0, +)) / Double(pastSets[1].count)
            if abs(avgReps - prevAvg) < 1 { return .addSet }
        }
        return .maintain
    }

    // MARK: - Muscle Recovery

    enum RecoveryStatus {
        case fresh, recovered, recovering, fatigued
        var label: String {
            switch self {
            case .fresh:      return "Fresh"
            case .recovered:  return "Ready"
            case .recovering: return "Recovering"
            case .fatigued:   return "Fatigued"
            }
        }
        var color: Color {
            switch self {
            case .fresh:      return Color(.tertiaryLabel)
            case .recovered:  return AppTheme.primary
            case .recovering: return .orange
            case .fatigued:   return .red
            }
        }
    }

    func daysSinceLastTrained(muscle: String) -> Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for session in sessions.filter({ $0.finishedAt != nil })
            .sorted(by: { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }) {
            // Starting a routine pre-populates every one of its exercises as a
            // session entry, even ones never actually performed — only count
            // it if at least one set was completed, or every muscle in that
            // routine would register as "trained today" regardless of what
            // was actually done.
            let hit = session.exercises.contains { ex in
                guard ex.sets.contains(where: \.done) else { return false }
                return exercises.first(where: { $0.id == ex.exerciseId })?.muscle == muscle
            }
            if hit, let fin = session.finishedAt {
                return cal.dateComponents([.day], from: cal.startOfDay(for: fin), to: today).day ?? 0
            }
        }
        return nil
    }

    struct MuscleTrainingInfo {
        let sessionId: String
        let daysAgo: Int
        let completedSets: Int
        /// Σ weight × reps across completed sets (Σ reps alone for bodyweight
        /// exercises, where weight is 0) — the actual load moved for this
        /// muscle in its most recent trained session.
        let volume: Double
        /// (completed sets, volume moved, exercise kind), in the order first encountered.
        /// `kind` lets UI skip showing a weight figure for bodyweight/cardio exercises.
        let exerciseBreakdown: [(name: String, sets: Int, volume: Double, kind: ExerciseKind)]
    }

    private func setVolume(_ set: LoggedSet) -> Double {
        set.weight > 0 ? set.weight * Double(set.reps) : Double(set.reps)
    }

    /// Total volume (Σ weight × reps of completed sets) moved for `muscle`
    /// in one session.
    private func sessionVolume(_ session: WorkoutSession, muscle: String) -> Double {
        session.exercises.reduce(0) { total, ex in
            guard let exercise = exercises.first(where: { $0.id == ex.exerciseId }), exercise.muscle == muscle else { return total }
            return total + ex.sets.filter(\.done).reduce(0) { $0 + setVolume($1) }
        }
    }

    /// Like `daysSinceLastTrained`, but also reports how much was actually
    /// done (sets + volume per exercise) in that most recent session, so
    /// recovery UI can show a real metric (e.g. "2 sets of Bicep Curls · 60kg")
    /// instead of just a day count, and scale fatigue by how much was moved
    /// rather than treating one light set the same as a full session.
    func lastTrainingInfo(muscle: String) -> MuscleTrainingInfo? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for session in sessions.filter({ $0.finishedAt != nil })
            .sorted(by: { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }) {
            var totalSets = 0
            var totalVolume: Double = 0
            var setsByName: [String: Int] = [:]
            var volumeByName: [String: Double] = [:]
            var kindByName: [String: ExerciseKind] = [:]
            var order: [String] = []
            for ex in session.exercises {
                guard let exercise = exercises.first(where: { $0.id == ex.exerciseId }),
                      exercise.muscle == muscle else { continue }
                let doneSets = ex.sets.filter(\.done)
                guard !doneSets.isEmpty else { continue }
                totalSets += doneSets.count
                let vol = doneSets.reduce(0) { $0 + setVolume($1) }
                totalVolume += vol
                if setsByName[exercise.name] == nil { order.append(exercise.name) }
                setsByName[exercise.name, default: 0] += doneSets.count
                volumeByName[exercise.name, default: 0] += vol
                kindByName[exercise.name] = exercise.kind
            }
            guard totalSets > 0, let fin = session.finishedAt else { continue }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: fin), to: today).day ?? 0
            return MuscleTrainingInfo(
                sessionId: session.id,
                daysAgo: days,
                completedSets: totalSets,
                volume: totalVolume,
                exerciseBreakdown: order.map { ($0, setsByName[$0] ?? 0, volumeByName[$0] ?? 0, kindByName[$0] ?? .weight) }
            )
        }
        return nil
    }

    /// Highest single-session volume ever recorded for `muscle`, used to
    /// express a session's intensity as "how much of your best effort was
    /// this" rather than an arbitrary absolute threshold. Excludes
    /// `excludingSessionId` (the session currently being evaluated) so it's a
    /// genuine comparison against prior history rather than including itself.
    func personalBestVolume(muscle: String, excludingSessionId: String? = nil) -> Double {
        sessions
            .filter { $0.finishedAt != nil && $0.id != excludingSessionId }
            .map { sessionVolume($0, muscle: muscle) }
            .max() ?? 0
    }

    /// Typical full-recovery time (days) per muscle group. Smaller/isolation
    /// muscles (biceps, triceps, calves, core) bounce back faster than large
    /// compound groups (back, legs) that take more systemic recovery,
    /// per common strength & conditioning / DOMS recovery guidance. Any
    /// muscle not listed falls back to a 2-day default.
    private static let muscleRecoveryDays: [String: Double] = [
        "Biceps":    1.5,
        "Triceps":   1.5,
        "Calves":    1.5,
        "Core":      1.5,
        "Shoulders": 2.0,
        "Chest":     2.5,
        "Glutes":    2.5,
        "Back":      3.0,
        "Legs":      3.0,
    ]

    func recoveryDays(forMuscle muscle: String) -> Double {
        Self.muscleRecoveryDays[muscle] ?? 2.0
    }

    func recoveryStatus(muscle: String) -> RecoveryStatus {
        guard let days = daysSinceLastTrained(muscle: muscle) else { return .fresh }
        if days == 0 { return .fatigued }
        return Double(days) < recoveryDays(forMuscle: muscle) ? .recovering : .recovered
    }

    // MARK: - Weekly Sessions Calendar

    func sessionsThisWeek() -> [Date: [WorkoutSession]] {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
        var map: [Date: [WorkoutSession]] = [:]
        for session in sessions where session.finishedAt != nil {
            guard let fin = session.finishedAt, fin >= weekStart, fin < weekEnd else { continue }
            let day = cal.startOfDay(for: fin)
            map[day, default: []].append(session)
        }
        return map
    }

    // MARK: - XP / Level

    var xpPoints: Int {
        return completedWorkouts.count * 100 + workoutStreak * 10 + achievements.count * 50
    }
    var xpLevel: Int  { xpPoints / 500 + 1 }
    var xpProgress: Double { Double(xpPoints % 500) / 500.0 }

    // MARK: - Progress Screen Helpers

    struct DatedValue: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    struct MuscleCount: Identifiable {
        let id = UUID()
        let muscle: String
        let count: Int
    }

    private var weekStartDate: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }

    private var finishedSessionsSorted: [WorkoutSession] {
        completedWorkouts
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    var workoutsThisWeekCount: Int {
        let start = weekStartDate
        return completedWorkouts.filter { ($0.finishedAt ?? .distantPast) >= start }.count
    }

    var trainingSecondsThisWeek: Int {
        let start = weekStartDate
        return sessions
            .filter { ($0.finishedAt ?? .distantPast) >= start }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    var volumeThisWeekKg: Double {
        let start = weekStartDate
        return sessions
            .filter { ($0.finishedAt ?? .distantPast) >= start }
            .reduce(0.0) { $0 + $1.totalVolumeKg }
    }

    func recentFinishedSessions(limit: Int = 5) -> [WorkoutSession] {
        Array(finishedSessionsSorted.prefix(limit))
    }

    /// Muscle → number of sets logged this week, sorted by volume.
    func muscleCountsThisWeek() -> [MuscleCount] {
        let start = weekStartDate
        var counts: [String: Int] = [:]
        for session in sessions where (session.finishedAt ?? .distantPast) >= start {
            for ex in session.exercises {
                guard let muscle = exercises.first(where: { $0.id == ex.exerciseId })?.muscle else { continue }
                counts[muscle, default: 0] += ex.sets.filter(\.done).count
            }
        }
        return counts.map { MuscleCount(muscle: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Exercises performed most often across all finished sessions.
    func topExercises(limit: Int = 6) -> [Exercise] {
        var counts: [String: Int] = [:]
        for session in sessions where session.finishedAt != nil {
            for ex in session.exercises { counts[ex.exerciseId, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }
            .compactMap { pair in exercises.first { $0.id == pair.key } }
            .prefix(limit)
            .map { $0 }
    }

    /// Estimated 1RM per session over time for an exercise (oldest first).
    func oneRMHistory(for exerciseId: String) -> [DatedValue] {
        var points: [DatedValue] = []
        for session in finishedSessionsSorted.reversed() {
            guard let fin = session.finishedAt else { continue }
            var best1RM = 0.0
            for ex in session.exercises where ex.exerciseId == exerciseId {
                for set in ex.sets where set.done && !set.isWarmup {
                    best1RM = max(best1RM, set.weight * (1 + Double(set.reps) / 30.0))
                }
            }
            if best1RM > 0 { points.append(DatedValue(date: fin, value: best1RM)) }
        }
        return points
    }

    /// Improvement in all-time best 1RM contributed by the most recent session.
    func prDelta(for exerciseId: String) -> Double {
        let history = oneRMHistory(for: exerciseId)
        guard history.count >= 2 else { return 0 }
        let allTime = history.map(\.value).max() ?? 0
        let priorBest = history.dropLast().map(\.value).max() ?? 0
        return max(0, allTime - priorBest)
    }

    // Body helpers
    var latestWeightKg: Double? { weightEntries.sorted { $0.date > $1.date }.first?.valueKg }

    var weightChangeKg: Double? {
        let sorted = weightEntries.sorted { $0.date > $1.date }
        guard sorted.count >= 2 else { return nil }
        return sorted[0].valueKg - sorted[1].valueKg
    }

    var latestBodyFatPct: Double? {
        bodyCompEntries.sorted { $0.date > $1.date }.first { $0.bodyFatPct != nil }?.bodyFatPct
    }

    var latestLeanMassKg: Double? {
        bodyCompEntries.sorted { $0.date > $1.date }.first { $0.leanMassKg != nil }?.leanMassKg
    }

    func weightTrend(days: Int) -> [DatedValue] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return weightEntries
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .map { DatedValue(date: $0.date, value: $0.valueKg) }
    }

    // MARK: - Body Measurements

    func addBodyMeasurement(_ measurement: BodyMeasurement) {
        bodyMeasurements.append(measurement)
        bodyMeasurements.sort { $0.date > $1.date }
        save()
    }

    func deleteBodyMeasurement(id: String) {
        bodyMeasurements.removeAll { $0.id == id }
        save()
    }

    // MARK: - Achievements

    func checkAndGrantAchievements() {
        let finishedSessions = completedWorkouts
        let totalSets = finishedSessions.reduce(0) { $0 + $1.totalSets }
        let unlocked = Set(achievements.map(\.kind))

        func grant(_ kind: AchievementKind, detail: String = "") {
            guard !unlocked.contains(kind) else { return }
            achievements.append(Achievement(kind: kind, title: kind.title, detail: detail))
        }

        if !finishedSessions.isEmpty { grant(.firstWorkout) }
        if workoutStreak >= 7 { grant(.streak7) }
        if workoutStreak >= 30 { grant(.streak30) }
        if totalSets >= 100 { grant(.totalSets100) }
        if totalSets >= 1000 { grant(.totalSets1000) }
        if finishedSessions.count >= 10 { grant(.totalSessions10) }
        if finishedSessions.count >= 50 { grant(.totalSessions50) }
        if finishedSessions.count >= 100 { grant(.totalSessions100) }

        // 4-week consistency: worked out in at least 3 of the past 4 calendar weeks
        let cal = Calendar.current
        let now = Date()
        let weeksWithWorkout = (0..<4).filter { weekOffset in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: now),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return false }
            return finishedSessions.contains { s in
                guard let fin = s.finishedAt else { return false }
                return fin >= weekStart && fin < weekEnd
            }
        }.count
        if weeksWithWorkout >= 3 { grant(.consistency4Weeks) }

        // Volume PR: check if most recent session has a higher total volume than any previous session
        if let latest = finishedSessions.max(by: { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }) {
            let previousMax = finishedSessions
                .filter { $0.id != latest.id }
                .map(\.totalVolumeKg)
                .max() ?? 0
            if latest.totalVolumeKg > previousMax && latest.totalVolumeKg > 0 {
                grant(.volumePR, detail: "\(Int(latest.totalVolumeKg))kg total volume")
            }
        }
    }

    // MARK: - PR Computation

    struct PRResult {
        var bestWeight: Double
        var bestReps: Int
        var best1RM: Double
    }

    func computePRs(for exerciseId: String) -> PRResult {
        var bestWeight: Double = 0
        var bestReps: Int = 0
        var best1RM: Double = 0

        for session in sessions where session.finishedAt != nil {
            for exercise in session.exercises where exercise.exerciseId == exerciseId {
                for set in exercise.sets where set.done && !set.isWarmup {
                    if set.weight > bestWeight {
                        bestWeight = set.weight
                        bestReps = set.reps
                    }
                    // Epley formula: 1RM = weight * (1 + reps/30)
                    let estimated1RM = set.weight * (1 + Double(set.reps) / 30.0)
                    if estimated1RM > best1RM {
                        best1RM = estimated1RM
                    }
                }
            }
        }
        return PRResult(bestWeight: bestWeight, bestReps: bestReps, best1RM: best1RM)
    }

    // MARK: - Workout Programs

    func addProgram(name: String, days: [ProgramDay] = []) {
        let prog = WorkoutProgram(name: name, days: days)
        programs.append(prog)
        save()
    }

    func updateProgram(id: String, name: String, days: [ProgramDay]) {
        guard let idx = programs.firstIndex(where: { $0.id == id }) else { return }
        programs[idx].name = name
        programs[idx].days = days
        save()
    }

    func deleteProgram(id: String) {
        programs.removeAll { $0.id == id }
        save()
    }

    func setActiveProgram(id: String?) {
        for idx in programs.indices {
            programs[idx].isActive = programs[idx].id == id
        }
        save()
    }

    var activeProgram: WorkoutProgram? {
        programs.first { $0.isActive }
    }

    func todaysSuggestedRoutine() -> Routine? {
        guard let prog = activeProgram else { return nil }
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar weekday: 1=Sunday, convert to 1=Monday
        let mondayBased = weekday == 1 ? 7 : weekday - 1
        guard let day = prog.days.first(where: { $0.weekday == mondayBased }),
              let routineId = day.routineId else { return nil }
        return routines.first { $0.id == routineId }
    }

    // MARK: - Weekly Workout Counts (P3.3)

    private static let weekLabelFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    func weeklyWorkoutCounts(weeks: Int) -> [(weekLabel: String, count: Int)] {
        let cal = Calendar.current
        let now = Date()
        let fmt = Self.weekLabelFmt
        return (0..<weeks).reversed().map { offset in
            let weekAgo = cal.date(byAdding: .weekOfYear, value: -offset, to: now) ?? now
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekAgo)) ?? weekAgo
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let count = completedWorkouts.filter {
                guard let fin = $0.finishedAt else { return false }
                return fin >= weekStart && fin < weekEnd
            }.count
            return (weekLabel: fmt.string(from: weekStart), count: count)
        }
    }

    // MARK: - Planned Sessions

    func planSession(date: Date, routineId: String?, name: String) {
        let plan = PlannedSession(
            date: Calendar.current.startOfDay(for: date),
            routineId: routineId,
            routineName: name
        )
        plannedSessions.append(plan)
        save()
    }

    func deletePlannedSession(id: String) {
        plannedSessions.removeAll { $0.id == id }
        save()
    }

    // MARK: - Progress Photos (stored separately, not cloud-synced)
    //
    // Storage layout:
    //   - Image bytes: one JPEG per photo under Documents/progress_photos/<id>.jpg
    //   - Metadata only (id, date, label) in UserDefaults under photosKeyV2
    //
    // Rationale: UserDefaults isn't designed for large blobs. With raw camera
    // photos (~5–10 MB each), the previous design re-encoded and re-wrote the
    // entire array on every add/delete and risked silent truncation. Each
    // image is also compressed to ~500 KB at insert time.

    private let photosKey = "life_progress_photos_v1"     // legacy (full bytes)
    private let photosKeyV2 = "life_progress_photos_v2"   // metadata only

    private struct ProgressPhotoMetadata: Codable {
        var id: String
        var date: Date
        var label: String
    }

    private static let photoDirectory: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("progress_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func photoURL(for id: String) -> URL {
        Self.photoDirectory.appendingPathComponent("\(id).jpg")
    }

    /// Down-scale the image and re-encode as JPEG so we don't store
    /// multi-megabyte camera originals on disk.
    private static func compressedJPEG(from data: Data, maxDimension: CGFloat = 2000, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1.0
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality)
    }

    func addProgressPhoto(imageData: Data, label: String) {
        let compressed = Self.compressedJPEG(from: imageData) ?? imageData
        let photo = ProgressPhoto(date: Date(), label: label, imageData: compressed)
        progressPhotos.append(photo)
        try? compressed.write(to: photoURL(for: photo.id), options: .atomic)
        saveMetadata()
    }

    func deleteProgressPhoto(id: String) {
        progressPhotos.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: photoURL(for: id))
        saveMetadata()
    }

    private func saveMetadata() {
        let metadata = progressPhotos.map {
            ProgressPhotoMetadata(id: $0.id, date: $0.date, label: $0.label)
        }
        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: photosKeyV2)
        }
    }

    func loadPhotos() {
        // Prefer the v2 metadata-only format.
        if let data = UserDefaults.standard.data(forKey: photosKeyV2),
           let metadata = try? JSONDecoder().decode([ProgressPhotoMetadata].self, from: data) {
            progressPhotos = metadata.compactMap { meta in
                guard let bytes = try? Data(contentsOf: photoURL(for: meta.id)) else { return nil }
                return ProgressPhoto(id: meta.id, date: meta.date, label: meta.label, imageData: bytes)
            }
            return
        }
        // Legacy migration: pull from v1 (full bytes in UserDefaults) and rewrite to disk.
        if let data = UserDefaults.standard.data(forKey: photosKey),
           let legacy = try? JSONDecoder().decode([ProgressPhoto].self, from: data) {
            progressPhotos = legacy
            for photo in legacy {
                try? photo.imageData.write(to: photoURL(for: photo.id), options: .atomic)
            }
            saveMetadata()
            UserDefaults.standard.removeObject(forKey: photosKey)
        }
    }

    // Backwards-compat shim; old call sites called savePhotos() directly.
    private func savePhotos() { saveMetadata() }

    // MARK: - Reset

    func resetAllData() {
        // Disable cloud sync first so the subsequent save() doesn't push the
        // empty/seed state to Firestore and wipe data on other devices.
        // User can sign in again afterwards to re-sync the reset state.
        disableCloudSync()
        tasks = []
        bills = []
        incomes = []
        oneOffExpenses = []
        moneySettings = MoneySettings()
        habits = []
        exercises = WorkoutSeed.exercises
        routines = WorkoutSeed.routines
        sessions = []
        weightEntries = []
        bodyCompEntries = []
        bodyMeasurements = []
        achievements = []
        programs = []
        careDays = [:]
        careSettings = CareSettings()
        workoutSettings = WorkoutSettings()
        userName = ""
        visitedLocations = []
        plannedSessions = []
        progressPhotos = []
        healthDays = [:]
        healthSettings = HealthSettings()
        sleepNights = [:]
        sleepComparisons = [:]
        savePhotos()
        seedDefaults()
    }

    // MARK: - Travel

    func recordVisit(lat: Double, lon: Double) {
        let newLoc = CLLocation(latitude: lat, longitude: lon)
        let tooClose = visitedLocations.contains { existing in
            let existingLoc = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
            return existingLoc.distance(from: newLoc) < 500
        }
        guard !tooClose else { return }
        visitedLocations.append(VisitedLocation(latitude: lat, longitude: lon))
        save()
    }

    // MARK: - Export

    var exportData: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(makeSnapshot())
    }

    func importData(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(StateSnapshot.self, from: data)
        apply(snapshot: snapshot)
        save()
    }
}
