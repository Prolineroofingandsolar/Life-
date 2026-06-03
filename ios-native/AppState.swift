import Foundation
import SwiftUI
import WidgetKit

// MARK: - Persistence Keys

private enum PersistenceKey {
    static let appState = "life_app_state_v2"
}

// MARK: - Serializable State Snapshot

struct StateSnapshot: Codable {
    var tasks: [AppTask] = []
    var bills: [Bill] = []
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
    var taskLists: [TaskList]? = nil  // optional for backward compat with existing saves
}

// MARK: - AppState

@Observable
final class AppState {

    // MARK: Stored Properties

    var latestPR: (exerciseName: String, value: String)? = nil
    var tasks: [AppTask] = []
    var taskLists: [TaskList] = []
    var bills: [Bill] = []
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
    var cloudUserId: String? = nil

    // MARK: Computed Properties

    var todayKey: String { Date().dayKey }

    var today: CareDay {
        get { careDays[todayKey] ?? CareDay(dayKey: todayKey) }
    }

    var activeSession: WorkoutSession? {
        sessions.first { $0.finishedAt == nil }
    }

    // MARK: Init

    init() {
        load()
    }

    // MARK: Persistence

    func save() {
        let snapshot = makeSnapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            UserDefaults.standard.set(data, forKey: PersistenceKey.appState)
        }
        WidgetSync.sync(tasks: tasks)
        syncHabitsToWidget()
        if let uid = cloudUserId {
            FirestoreSync.shared.scheduleUpload(snapshot, userId: uid)
        }
    }

    func makeSnapshot() -> StateSnapshot {
        StateSnapshot(
            tasks: tasks,
            bills: bills,
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
            taskLists: taskLists
        )
    }

    func apply(snapshot: StateSnapshot) {
        tasks = snapshot.tasks
        bills = snapshot.bills
        habits = snapshot.habits
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
        if let lists = snapshot.taskLists, !lists.isEmpty {
            taskLists = lists
        } else {
            taskLists = Self.defaultTaskLists
        }
    }

    // MARK: Cloud Sync

    func loadFromCloud(userId: String) async {
        cloudUserId = userId
        do {
            if let snapshot = try await FirestoreSync.shared.download(userId: userId) {
                await MainActor.run { apply(snapshot: snapshot) }
            } else {
                // First sign-in — upload existing local data to the cloud
                FirestoreSync.shared.scheduleUpload(makeSnapshot(), userId: userId)
            }
        } catch {
            // Network unavailable — carry on with local data
        }
    }

    func disableCloudSync() {
        cloudUserId = nil
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: PersistenceKey.appState),
           let snapshot = try? decoder.decode(StateSnapshot.self, from: data) {
            apply(snapshot: snapshot)
        } else {
            // First launch — seed default data
            exercises = WorkoutSeed.exercises
            routines = WorkoutSeed.routines
            seedDefaults()
        }
    }

    static let defaultTaskLists: [TaskList] = [
        TaskList(id: "work",     name: "Work",     emoji: "💼", colorHex: "#5E5CE6", isSystem: true),
        TaskList(id: "gym",      name: "Gym",      emoji: "💪", colorHex: "#30d158", isSystem: true),
        TaskList(id: "personal", name: "Personal", emoji: "🌱", colorHex: "#FF9F0A", isSystem: true),
        TaskList(id: "home",     name: "Home",     emoji: "🏠", colorHex: "#5E9BF0", isSystem: false),
        TaskList(id: "health",   name: "Health",   emoji: "❤️", colorHex: "#FF375F", isSystem: false),
    ]

    private func seedDefaults() {
        taskLists = Self.defaultTaskLists
        tasks = [
            AppTask(title: "Reply to client email", listId: "work", dueDate: .today),
            AppTask(title: "Push session — legs",   listId: "gym",      dueDate: .today),
            AppTask(title: "Refill water bottle",   listId: "personal", dueDate: .today),
        ]
        bills = [
            Bill(name: "Rent", amount: 1200, dayOfMonth: 1),
            Bill(name: "Electricity", amount: 85, dayOfMonth: 15),
            Bill(name: "Internet", amount: 45, dayOfMonth: 20),
            Bill(name: "Phone", amount: 35, dayOfMonth: 28),
        ]
        habits = [
            Habit(name: "Drink 8 glasses of water", emoji: "💧", kind: .build, cadence: .daily, targetCount: 8,
                  category: .nutrition, targetType: .count, targetUnit: "glasses"),
            Habit(name: "Read for 20 minutes", emoji: "📚", kind: .build, cadence: .daily, targetCount: 20,
                  category: .mindset, targetType: .timer),
            Habit(name: "No social media after 9pm", emoji: "📵", kind: .break, cadence: .daily, targetCount: 1,
                  category: .mindset, targetType: .yesNo),
            Habit(name: "Exercise", emoji: "🏃", kind: .build, cadence: .weekly, targetCount: 4,
                  category: .fitness, targetType: .count, targetUnit: "sessions"),
            Habit(name: "Morning meditation", emoji: "🧘", kind: .build, cadence: .daily, targetCount: 10,
                  category: .mindset, targetType: .timer),
        ]
        save()
    }

    // MARK: - Task Mutations

    func addTask(title: String, listId: String = "personal", dueDate: DueDate? = .today, dueDateOverride: Date? = nil, priority: TaskPriority = .none, notes: String = "", reminderDate: Date? = nil) {
        var task = AppTask(title: title, listId: listId, dueDate: dueDate)
        task.dueDateOverride = dueDateOverride
        task.priority = priority
        task.notes = notes
        task.reminderDate = reminderDate
        tasks.append(task)
        save()
    }

    func toggleTask(id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].done.toggle()
        tasks[idx].completedAt = tasks[idx].done ? Date() : nil
        save()
    }

    func deleteTask(id: String) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func updateTask(id: String, title: String? = nil, listId: String? = nil, dueDate: DueDate?? = nil, dueDateOverride: Date?? = nil, priority: TaskPriority? = nil, notes: String? = nil, reminderDate: Date?? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let title = title { tasks[idx].title = title }
        if let listId = listId { tasks[idx].listId = listId }
        if let dueDate = dueDate { tasks[idx].dueDate = dueDate }
        if let dueDateOverride = dueDateOverride { tasks[idx].dueDateOverride = dueDateOverride }
        if let priority = priority { tasks[idx].priority = priority }
        if let notes = notes { tasks[idx].notes = notes }
        if let reminderDate = reminderDate { tasks[idx].reminderDate = reminderDate }
        save()
    }

    // MARK: - Task List Mutations

    func addTaskList(name: String, emoji: String, colorHex: String) {
        let list = TaskList(name: name, emoji: emoji, colorHex: colorHex, isSystem: false)
        taskLists.append(list)
        save()
    }

    func updateTaskList(id: String, name: String, emoji: String, colorHex: String) {
        guard let idx = taskLists.firstIndex(where: { $0.id == id }) else { return }
        taskLists[idx].name = name
        taskLists[idx].emoji = emoji
        taskLists[idx].colorHex = colorHex
        save()
    }

    func deleteTaskList(id: String) {
        guard let list = taskLists.first(where: { $0.id == id }), !list.isSystem else { return }
        for idx in tasks.indices where tasks[idx].listId == id {
            tasks[idx].listId = "personal"
        }
        taskLists.removeAll { $0.id == id }
        save()
    }

    func taskList(for task: AppTask) -> TaskList? {
        taskLists.first { $0.id == task.listId }
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

    // MARK: - Habit Mutations

    func addHabit(
        name: String, emoji: String,
        category: HabitCategory = .health,
        kind: HabitKind, cadence: HabitCadence,
        targetType: HabitTargetType = .yesNo,
        targetCount: Int = 1, targetUnit: String = "",
        reminderEnabled: Bool = false, reminderTime: Date? = nil,
        notes: String = ""
    ) {
        var habit = Habit(name: name, emoji: emoji, kind: kind, cadence: cadence, targetCount: targetCount)
        habit.category = category
        habit.targetType = targetType
        habit.targetUnit = targetUnit
        habit.reminderEnabled = reminderEnabled
        habit.reminderTime = reminderTime
        habit.notes = notes
        habits.append(habit)
        if reminderEnabled, let time = reminderTime {
            HabitReminderManager.shared.scheduleReminder(for: habit, at: time)
        }
        save()
    }

    func updateHabit(
        id: String, name: String? = nil, emoji: String? = nil,
        category: HabitCategory? = nil,
        kind: HabitKind? = nil, cadence: HabitCadence? = nil,
        targetType: HabitTargetType? = nil,
        targetCount: Int? = nil, targetUnit: String? = nil,
        reminderEnabled: Bool? = nil, reminderTime: Date? = nil,
        notes: String? = nil
    ) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { habits[idx].name = name }
        if let emoji = emoji { habits[idx].emoji = emoji }
        if let category = category { habits[idx].category = category }
        if let kind = kind { habits[idx].kind = kind }
        if let cadence = cadence { habits[idx].cadence = cadence }
        if let tt = targetType { habits[idx].targetType = tt }
        if let target = targetCount { habits[idx].targetCount = target }
        if let unit = targetUnit { habits[idx].targetUnit = unit }
        if let re = reminderEnabled { habits[idx].reminderEnabled = re }
        if let rt = reminderTime { habits[idx].reminderTime = rt }
        if let notes = notes { habits[idx].notes = notes }
        let h = habits[idx]
        if h.reminderEnabled, let time = h.reminderTime {
            HabitReminderManager.shared.scheduleReminder(for: h, at: time)
        } else {
            HabitReminderManager.shared.cancelReminder(habitId: id)
        }
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
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: habits[idx].targetCount, completedAt: Date()))
        }
        save()
    }

    func incHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].count += 1
            if habits[idx].logs[logIdx].count >= habits[idx].targetCount {
                habits[idx].logs[logIdx].completedAt = Date()
            }
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: 1))
        }
        save()
    }

    func setHabitCount(id: String, count: Int, dayKey: String? = nil) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = dayKey ?? todayKey
        let clampedCount = max(0, count)
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            if clampedCount == 0 {
                habits[idx].logs.remove(at: logIdx)
            } else {
                habits[idx].logs[logIdx].count = clampedCount
                if clampedCount >= habits[idx].targetCount {
                    habits[idx].logs[logIdx].completedAt = Date()
                }
            }
        } else if clampedCount > 0 {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: clampedCount))
        }
        save()
    }

    func completeHabitTimer(id: String, seconds: Int, dayKey: String? = nil) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = dayKey ?? todayKey
        let targetSecs = habits[idx].targetCount * 60
        let count = seconds >= targetSecs ? habits[idx].targetCount : max(1, seconds / 60)
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].count = count
            habits[idx].logs[logIdx].durationSecs = seconds
            habits[idx].logs[logIdx].completedAt = Date()
        } else {
            var entry = HabitLogEntry(dayKey: key, count: count)
            entry.durationSecs = seconds
            entry.completedAt = Date()
            habits[idx].logs.append(entry)
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

    func undoHabitCompletion(id: String, dayKey: String? = nil) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = dayKey ?? todayKey
        habits[idx].logs.removeAll { $0.dayKey == key }
        save()
    }

    func addNoteToTodayLog(id: String, note: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].note = note
        } else {
            var entry = HabitLogEntry(dayKey: key, count: habits[idx].targetCount, completedAt: Date())
            entry.note = note
            habits[idx].logs.append(entry)
        }
        save()
    }

    // MARK: - Habit Analytics

    func streakFor(_ habit: Habit) -> Int {
        let cal = Calendar.current
        var streak = 0
        var date = Date()
        while true {
            let key = date.dayKey
            if let log = habit.logs.first(where: { $0.dayKey == key }) {
                let done = habit.kind == .break ? !log.slipped : (log.count >= habit.targetCount && !log.slipped)
                if done { streak += 1 } else { break }
            } else {
                if cal.isDateInToday(date) { date = cal.date(byAdding: .day, value: -1, to: date) ?? date; continue }
                break
            }
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return streak
    }

    func bestStreakFor(_ habit: Habit) -> Int {
        let cal = Calendar.current
        guard !habit.logs.isEmpty else { return 0 }
        let sortedLogs = habit.logs.sorted { $0.dayKey < $1.dayKey }
        var best = 0, current = 0
        var prevDate: Date? = nil
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
        for log in sortedLogs {
            let done = habit.kind == .break ? !log.slipped : (log.count >= habit.targetCount && !log.slipped)
            guard done, let date = fmt.date(from: log.dayKey) else { current = 0; prevDate = nil; continue }
            if let prev = prevDate, let expected = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(expected, inSameDayAs: date) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            prevDate = date
        }
        return best
    }

    func weeklyCompletionFor(_ habit: Habit) -> Double {
        let cal = Calendar.current
        var done = 0
        for i in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let key = date.dayKey
            if let log = habit.logs.first(where: { $0.dayKey == key }) {
                let completed = habit.kind == .break ? !log.slipped : (log.count >= habit.targetCount && !log.slipped)
                if completed { done += 1 }
            }
        }
        return Double(done) / 7.0
    }

    func totalCompletionsFor(_ habit: Habit) -> Int {
        habit.logs.filter { log in
            habit.kind == .break ? !log.slipped : (log.count >= habit.targetCount && !log.slipped)
        }.count
    }

    func applyPendingWidgetCompletions() {
        let pending = SharedHabitStore.popPendingCompletions()
        guard !pending.isEmpty else { return }
        let key = Date().dayKey
        for habitId in pending {
            guard let idx = habits.firstIndex(where: { $0.id == habitId }) else { continue }
            if habits[idx].logs.first(where: { $0.dayKey == key }) == nil {
                habits[idx].logs.append(HabitLogEntry(dayKey: key, count: habits[idx].targetCount, completedAt: Date()))
            }
        }
        save()
    }

    private func syncHabitsToWidget() {
        let todayKey = Date().dayKey
        let pending = SharedHabitStore.pendingIDs()
        let widgetHabits: [WidgetHabit] = habits.filter { !$0.isArchived }.map { h in
            let log = h.logs.first { $0.dayKey == todayKey }
            let currentCount = (log?.count ?? 0)
            let slipped = log?.slipped ?? false
            let completed: Bool
            if pending.contains(h.id) {
                completed = true
            } else if h.kind == .break {
                completed = !slipped
            } else {
                completed = currentCount >= h.targetCount && !slipped
            }
            let progress = h.kind == .build
                ? min(Double(currentCount) / Double(max(h.targetCount, 1)), 1.0)
                : (completed ? 1.0 : 0.0)
            return WidgetHabit(
                id: h.id,
                name: h.name,
                emoji: h.emoji,
                category: h.category.rawValue,
                kind: h.kind.rawValue,
                targetType: h.targetType.rawValue,
                targetCount: h.targetCount,
                targetUnit: h.targetUnit,
                currentCount: currentCount,
                isCompleted: completed,
                isSlipped: slipped,
                streak: streakFor(h),
                progress: progress
            )
        }
        SharedHabitStore.write(widgetHabits)
        WidgetCenter.shared.reloadTimelines(ofKind: "LifeHabitsWidget")
    }

    // MARK: - Routine Mutations

    func addRoutine(name: String, exercises: [RoutineExercise] = []) {
        let routine = Routine(name: name, exercises: exercises)
        routines.append(routine)
        save()
    }

    func updateRoutine(id: String, name: String? = nil, exercises: [RoutineExercise]? = nil) {
        guard let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { routines[idx].name = name }
        if let exercises = exercises { routines[idx].exercises = exercises }
        save()
    }

    func deleteRoutine(id: String) {
        routines.removeAll { $0.id == id }
        save()
    }

    // MARK: - Workout Session Mutations

    func startSession(name: String, routineId: String? = nil) {
        sessions.removeAll { $0.finishedAt == nil }

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
        sessionExercise.sets = [LoggedSet(weight: 0, reps: 0), LoggedSet(weight: 0, reps: 0), LoggedSet(weight: 0, reps: 0)]
        sessions[sIdx].exercises.append(sessionExercise)
        save()
    }

    func removeExerciseFromSession(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[sIdx].exercises.removeAll { $0.id == exerciseId }
        save()
    }

    func finishSession(sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].finishedAt = Date()
        checkAndGrantAchievements()
        save()
    }

    func updateSessionNotes(sessionId: String, notes: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].notes = notes
        save()
    }

    func rateSession(sessionId: String, rating: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].rating = rating
        save()
    }

    func discardSession(sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
        save()
    }

    func renameSession(sessionId: String, name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].name = name
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

    func addCustomExercise(name: String, muscle: String, kind: ExerciseKind) {
        let exercise = Exercise(name: name, muscle: muscle, kind: kind, isCustom: true)
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

    var workoutStreak: Int {
        let finished = sessions.filter { $0.finishedAt != nil }
        guard !finished.isEmpty else { return 0 }
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())
        let cal = Calendar.current
        let dayKeys = Set(finished.compactMap { $0.finishedAt }.map { cal.startOfDay(for: $0) })
        // Walk backwards day by day
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
            case .addWeight: return Color(hex: "#30d158")
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
            case .recovered:  return Color(hex: "#30d158")
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
            let hit = session.exercises.contains { ex in
                exercises.first(where: { $0.id == ex.exerciseId })?.muscle == muscle
            }
            if hit, let fin = session.finishedAt {
                return cal.dateComponents([.day], from: cal.startOfDay(for: fin), to: today).day ?? 0
            }
        }
        return nil
    }

    func recoveryStatus(muscle: String) -> RecoveryStatus {
        guard let days = daysSinceLastTrained(muscle: muscle) else { return .fresh }
        switch days {
        case 0:  return .fatigued
        case 1:  return .recovering
        default: return .recovered
        }
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
        let finished = sessions.filter { $0.finishedAt != nil }
        return finished.count * 100 + workoutStreak * 10 + achievements.count * 50
    }
    var xpLevel: Int  { max(1, xpPoints / 500) }
    var xpProgress: Double { Double(xpPoints % 500) / 500.0 }

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
        let finishedSessions = sessions.filter { $0.finishedAt != nil }
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

    func weeklyWorkoutCounts(weeks: Int) -> [(weekLabel: String, count: Int)] {
        let cal = Calendar.current
        let now = Date()
        return (0..<weeks).reversed().map { offset in
            let weekAgo = cal.date(byAdding: .weekOfYear, value: -offset, to: now) ?? now
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekAgo)) ?? weekAgo
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let count = sessions.filter {
                guard let fin = $0.finishedAt else { return false }
                return fin >= weekStart && fin < weekEnd
            }.count
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return (weekLabel: formatter.string(from: weekStart), count: count)
        }
    }

    // MARK: - Reset

    func resetAllData() {
        tasks = []
        bills = []
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
        seedDefaults()
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
