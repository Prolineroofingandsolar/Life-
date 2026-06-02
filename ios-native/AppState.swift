import Foundation
import SwiftUI

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
    var careDays: [String: CareDay] = [:]
    var careSettings: CareSettings = CareSettings()
    var workoutSettings: WorkoutSettings = WorkoutSettings()
    var userName: String = ""
}

// MARK: - AppState

@Observable
final class AppState {

    // MARK: Stored Properties

    var latestPR: (exerciseName: String, value: String)? = nil
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
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: PersistenceKey.appState)
        }
        WidgetSync.sync(tasks: tasks)
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
            careDays: careDays,
            careSettings: careSettings,
            workoutSettings: workoutSettings,
            userName: userName
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
        careDays = snapshot.careDays
        careSettings = snapshot.careSettings
        workoutSettings = snapshot.workoutSettings
        userName = snapshot.userName
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
        } else {
            // First launch — seed default data
            exercises = WorkoutSeed.exercises
            routines = WorkoutSeed.routines
            seedDefaults()
        }
    }

    private func seedDefaults() {
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
        tasks[idx].done.toggle()
        tasks[idx].completedAt = tasks[idx].done ? Date() : nil
        save()
    }

    func deleteTask(id: String) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func updateTask(id: String, title: String? = nil, category: TaskCategory? = nil, dueDate: DueDate? = nil, priority: TaskPriority? = nil, notes: String? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let title = title { tasks[idx].title = title }
        if let category = category { tasks[idx].category = category }
        if let dueDate = dueDate { tasks[idx].dueDate = dueDate }
        if let priority = priority { tasks[idx].priority = priority }
        if let notes = notes { tasks[idx].notes = notes }
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
