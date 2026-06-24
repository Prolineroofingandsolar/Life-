import Foundation
import SwiftUI
import CoreLocation

// MARK: - Persistence Keys

private enum PersistenceKey {
    static let appState = "life_app_state_v2"
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

// MARK: - Serializable State Snapshot

struct StateSnapshot: Codable {
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
    var visitedLocations: [VisitedLocation] = []
    var plannedSessions: [PlannedSession] = []
    var supplements: [Supplement] = []
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
    var visitedLocations: [VisitedLocation] = []
    var plannedSessions: [PlannedSession] = []
    var progressPhotos: [ProgressPhoto] = []

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
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: PersistenceKey.appState)
        }
        WidgetSync.sync(tasks: tasks)
        WidgetSync.syncHabits(habits: habits, todayKey: todayKey)
        if let uid = cloudUserId {
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
            supplements: supplements
        )
    }

    func apply(snapshot: StateSnapshot) {
        tasks = snapshot.tasks
        taskLists = snapshot.taskLists.isEmpty ? Self.defaultTaskLists : snapshot.taskLists
        bills = snapshot.bills
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
    }

    static let defaultTaskLists: [TaskList] = [
        TaskList(id: "work",     name: "Work",     emoji: "💼", colorHex: "#5E9BF0", isSystem: true),
        TaskList(id: "gym",      name: "Gym",      emoji: "🏋️", colorHex: "#30d158", isSystem: true),
        TaskList(id: "personal", name: "Personal", emoji: "🌱", colorHex: "#FF9F0A", isSystem: true),
    ]

    private func seedDefaults() {
        taskLists = Self.defaultTaskLists
        tasks = [
            AppTask(title: "Reply to client email", category: .work, dueDate: .today),
            AppTask(title: "Push session — legs", category: .gym, dueDate: .today),
            AppTask(title: "Refill water bottle", category: .personal, dueDate: .today),
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

    func addTask(title: String, category: TaskCategory, dueDate: DueDate, priority: TaskPriority = .none, notes: String = "") {
        var task = AppTask(title: title, category: category, dueDate: dueDate)
        task.priority = priority
        task.notes = notes
        tasks.append(task)
        save()
    }

    func toggleTask(id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let wasRecurring = tasks[idx].isRecurring
        let recurrenceType = tasks[idx].recurrenceType
        tasks[idx].done.toggle()
        tasks[idx].completedAt = tasks[idx].done ? Date() : nil

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
            }
        }
        save()
    }

    func deleteTask(id: String) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func updateTask(id: String, title: String? = nil, category: TaskCategory? = nil, dueDate: DueDate?? = nil, priority: TaskPriority? = nil, notes: String? = nil, listId: String? = nil, dueDateOverride: Date?? = nil, reminderDate: Date?? = nil, scheduledTime: Date?? = nil, estimatedMinutes: Int?? = nil, isRecurring: Bool? = nil, recurrenceType: RecurrenceType?? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let title = title { tasks[idx].title = title }
        if let category = category { tasks[idx].category = category }
        if let dueDate = dueDate { tasks[idx].dueDate = dueDate }
        if let priority = priority { tasks[idx].priority = priority }
        if let notes = notes { tasks[idx].notes = notes }
        if let listId = listId { tasks[idx].listId = listId }
        if let override = dueDateOverride { tasks[idx].dueDateOverride = override }
        if let rd = reminderDate { tasks[idx].reminderDate = rd }
        if let st = scheduledTime { tasks[idx].scheduledTime = st }
        if let em = estimatedMinutes { tasks[idx].estimatedMinutes = em }
        if let rec = isRecurring { tasks[idx].isRecurring = rec }
        if let rt = recurrenceType { tasks[idx].recurrenceType = rt }
        save()
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

    // MARK: - Habit Analytics

    func streakFor(_ habit: Habit) -> Int {
        var count = 0
        let cal = Calendar.current
        var date = Date()
        while true {
            let key = date.dayKey
            let log = habit.logs.first(where: { $0.dayKey == key })
            let success: Bool
            if habit.kind == .break {
                // No log or non-slipped log = success (didn't slip)
                success = log?.slipped != true
            } else {
                success = log != nil && (log?.count ?? 0) >= habit.targetCount && log?.slipped != true
            }
            if success {
                count += 1
                date = cal.date(byAdding: .day, value: -1, to: date) ?? date
            } else {
                break
            }
        }
        return count
    }

    func bestStreakFor(_ habit: Habit) -> Int {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")

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
                date = cal.date(byAdding: .day, value: 1, to: date) ?? date
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

    func updateHabit(id: String, name: String? = nil, emoji: String? = nil, kind: HabitKind? = nil, cadence: HabitCadence? = nil, targetCount: Int? = nil) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { habits[idx].name = name }
        if let emoji = emoji { habits[idx].emoji = emoji }
        if let kind = kind { habits[idx].kind = kind }
        if let cadence = cadence { habits[idx].cadence = cadence }
        if let target = targetCount { habits[idx].targetCount = target }
        save()
    }

    func deleteHabit(id: String) {
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
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: 1))
        }
        save()
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
        sessions.filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    var workoutsThisWeekCount: Int {
        let start = weekStartDate
        return sessions.filter { ($0.finishedAt ?? .distantPast) >= start }.count
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

    func weeklyWorkoutCounts(weeks: Int) -> [(weekLabel: String, count: Int)] {
        let cal = Calendar.current
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return (0..<weeks).reversed().map { offset in
            let weekAgo = cal.date(byAdding: .weekOfYear, value: -offset, to: now) ?? now
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekAgo)) ?? weekAgo
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let count = sessions.filter {
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

    private let photosKey = "life_progress_photos_v1"

    func addProgressPhoto(imageData: Data, label: String) {
        let photo = ProgressPhoto(date: Date(), label: label, imageData: imageData)
        progressPhotos.append(photo)
        savePhotos()
    }

    func deleteProgressPhoto(id: String) {
        progressPhotos.removeAll { $0.id == id }
        savePhotos()
    }

    private func savePhotos() {
        if let data = try? JSONEncoder().encode(progressPhotos) {
            UserDefaults.standard.set(data, forKey: photosKey)
        }
    }

    func loadPhotos() {
        if let data = UserDefaults.standard.data(forKey: photosKey),
           let photos = try? JSONDecoder().decode([ProgressPhoto].self, from: data) {
            progressPhotos = photos
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
        visitedLocations = []
        plannedSessions = []
        progressPhotos = []
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
