import SwiftUI
import Foundation

// MARK: - Task Models

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case high, medium, low, none
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .blue
        case .none:   return .clear
        }
    }
    var icon: String {
        switch self {
        case .high:   return "exclamationmark.2"
        case .medium: return "exclamationmark"
        case .low:    return "minus"
        case .none:   return ""
        }
    }
    var sortOrder: Int {
        switch self { case .high: return 0; case .medium: return 1; case .low: return 2; case .none: return 3 }
    }
}

struct Subtask: Codable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var done: Bool = false
    var createdAt: Date = Date()
}

enum TaskCategory: String, Codable, CaseIterable, Identifiable {
    case work, gym, personal
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .work:     return "💼"
        case .gym:      return "🏋️"
        case .personal: return "🌱"
        }
    }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .work:     return Color(red: 0.37, green: 0.36, blue: 0.90)
        case .gym:      return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .personal: return Color(red: 1.00, green: 0.62, blue: 0.04)
        }
    }
}

enum DueDate: String, Codable, CaseIterable, Identifiable {
    case today, tomorrow, thisWeek
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:    return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This Week"
        }
    }
}

struct AppTask: Codable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var category: TaskCategory
    var done: Bool = false
    var dueDate: DueDate
    var priority: TaskPriority = .none
    var notes: String = ""
    var subtasks: [Subtask] = []
    var createdAt: Date = Date()
    var completedAt: Date? = nil
}

// MARK: - Bill Models

struct Bill: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var amount: Double
    var dayOfMonth: Int
    var notes: String = ""
}

// MARK: - Habit Models

enum HabitKind: String, Codable, CaseIterable, Identifiable {
    case build, `break`
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum HabitCadence: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, specificWeekdays, timesPerWeek, timesPerMonth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily:            return "Daily"
        case .weekly:           return "Weekly"
        case .specificWeekdays: return "Specific Days"
        case .timesPerWeek:     return "Times / Week"
        case .timesPerMonth:    return "Times / Month"
        }
    }
}

enum HabitCategory: String, Codable, CaseIterable, Identifiable {
    case health, fitness, mindset, productivity, sleep, nutrition, custom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var emoji: String {
        switch self {
        case .health:       return "❤️"
        case .fitness:      return "💪"
        case .mindset:      return "🧠"
        case .productivity: return "⚡️"
        case .sleep:        return "😴"
        case .nutrition:    return "🥗"
        case .custom:       return "✨"
        }
    }
    var color: Color {
        switch self {
        case .health:       return Color(hex: "#FF375F")
        case .fitness:      return Color(hex: "#30d158")
        case .mindset:      return Color(hex: "#BF5AF2")
        case .productivity: return Color(hex: "#FF9F0A")
        case .sleep:        return Color(hex: "#5E9BF0")
        case .nutrition:    return Color(hex: "#32ADE6")
        case .custom:       return Color(hex: "#64D2FF")
        }
    }
}

enum HabitTargetType: String, Codable, CaseIterable, Identifiable {
    case yesNo, count, timer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .yesNo:  return "Yes / No"
        case .count:  return "Count"
        case .timer:  return "Timer"
        }
    }
    var icon: String {
        switch self {
        case .yesNo:  return "checkmark.circle"
        case .count:  return "number"
        case .timer:  return "timer"
        }
    }
}

struct HabitLogEntry: Identifiable {
    var id: String = UUID().uuidString
    var dayKey: String
    var count: Int = 1
    var slipped: Bool = false
    var durationSecs: Int = 0
    var note: String = ""
    var completedAt: Date? = nil
}

extension HabitLogEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, dayKey, count, slipped, durationSecs, note, completedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(String.self,  forKey: .id)           ?? UUID().uuidString
        dayKey       = try c.decode(String.self,            forKey: .dayKey)
        count        = try c.decodeIfPresent(Int.self,     forKey: .count)         ?? 1
        slipped      = try c.decodeIfPresent(Bool.self,    forKey: .slipped)       ?? false
        durationSecs = try c.decodeIfPresent(Int.self,     forKey: .durationSecs)  ?? 0
        note         = try c.decodeIfPresent(String.self,  forKey: .note)          ?? ""
        completedAt  = try c.decodeIfPresent(Date.self,    forKey: .completedAt)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,          forKey: .id)
        try c.encode(dayKey,      forKey: .dayKey)
        try c.encode(count,       forKey: .count)
        try c.encode(slipped,     forKey: .slipped)
        try c.encode(durationSecs, forKey: .durationSecs)
        try c.encode(note,        forKey: .note)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}

struct Habit: Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var emoji: String = "⭐️"
    var kind: HabitKind = .build
    var cadence: HabitCadence = .daily
    var targetCount: Int = 1
    var isArchived: Bool = false
    var logs: [HabitLogEntry] = []
    var createdAt: Date = Date()
    // v2 fields — custom decoder uses decodeIfPresent for backward compatibility
    var category: HabitCategory = .health
    var targetType: HabitTargetType = .yesNo
    var targetUnit: String = ""
    var reminderTime: Date? = nil
    var reminderEnabled: Bool = false
    var notes: String = ""
    var startDate: Date = Date()
    var endDate: Date? = nil
    var weekdays: [Int] = []       // 1=Mon…7=Sun for specificWeekdays
    var timesPerPeriod: Int = 1    // for timesPerWeek / timesPerMonth
}

extension Habit: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, kind, cadence, targetCount, isArchived, logs, createdAt
        case category, targetType, targetUnit
        case reminderTime, reminderEnabled, notes, startDate, endDate, weekdays, timesPerPeriod
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decodeIfPresent(String.self,           forKey: .id)             ?? UUID().uuidString
        name           = try c.decode(String.self,                     forKey: .name)
        emoji          = try c.decodeIfPresent(String.self,           forKey: .emoji)          ?? "⭐️"
        kind           = try c.decodeIfPresent(HabitKind.self,        forKey: .kind)           ?? .build
        cadence        = try c.decodeIfPresent(HabitCadence.self,     forKey: .cadence)        ?? .daily
        targetCount    = try c.decodeIfPresent(Int.self,              forKey: .targetCount)    ?? 1
        isArchived     = try c.decodeIfPresent(Bool.self,             forKey: .isArchived)     ?? false
        logs           = try c.decodeIfPresent([HabitLogEntry].self,  forKey: .logs)           ?? []
        createdAt      = try c.decodeIfPresent(Date.self,             forKey: .createdAt)      ?? Date()
        category       = try c.decodeIfPresent(HabitCategory.self,   forKey: .category)       ?? .health
        targetType     = try c.decodeIfPresent(HabitTargetType.self, forKey: .targetType)     ?? .yesNo
        targetUnit     = try c.decodeIfPresent(String.self,           forKey: .targetUnit)     ?? ""
        reminderTime   = try c.decodeIfPresent(Date.self,             forKey: .reminderTime)
        reminderEnabled = try c.decodeIfPresent(Bool.self,            forKey: .reminderEnabled) ?? false
        notes          = try c.decodeIfPresent(String.self,           forKey: .notes)          ?? ""
        startDate      = try c.decodeIfPresent(Date.self,             forKey: .startDate)      ?? Date()
        endDate        = try c.decodeIfPresent(Date.self,             forKey: .endDate)
        weekdays       = try c.decodeIfPresent([Int].self,            forKey: .weekdays)       ?? []
        timesPerPeriod = try c.decodeIfPresent(Int.self,              forKey: .timesPerPeriod) ?? 1
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(name,            forKey: .name)
        try c.encode(emoji,           forKey: .emoji)
        try c.encode(kind,            forKey: .kind)
        try c.encode(cadence,         forKey: .cadence)
        try c.encode(targetCount,     forKey: .targetCount)
        try c.encode(isArchived,      forKey: .isArchived)
        try c.encode(logs,            forKey: .logs)
        try c.encode(createdAt,       forKey: .createdAt)
        try c.encode(category,        forKey: .category)
        try c.encode(targetType,      forKey: .targetType)
        try c.encode(targetUnit,      forKey: .targetUnit)
        try c.encodeIfPresent(reminderTime,  forKey: .reminderTime)
        try c.encode(reminderEnabled, forKey: .reminderEnabled)
        try c.encode(notes,           forKey: .notes)
        try c.encode(startDate,       forKey: .startDate)
        try c.encodeIfPresent(endDate, forKey: .endDate)
        try c.encode(weekdays,        forKey: .weekdays)
        try c.encode(timesPerPeriod,  forKey: .timesPerPeriod)
    }
}

// MARK: - Exercise / Workout Models

enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
    case weight, bodyweight, cardio
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ExerciseEquipment: String, Codable, CaseIterable, Identifiable {
    case barbell, dumbbell, cable, machine, bodyweight, kettlebell, band, ezBar, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .cable: return "Cable"
        case .machine: return "Machine"
        case .bodyweight: return "Bodyweight"
        case .kettlebell: return "Kettlebell"
        case .band: return "Band"
        case .ezBar: return "EZ Bar"
        case .other: return "Other"
        }
    }
    var icon: String {
        switch self {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .cable: return "cable.connector"
        case .machine: return "gearshape.fill"
        case .bodyweight: return "figure.stand"
        case .kettlebell: return "dumbbell"
        case .band: return "arrow.left.and.right"
        case .ezBar: return "wave.3.right"
        case .other: return "questionmark.circle"
        }
    }
}

enum AchievementKind: String, Codable, CaseIterable {
    case firstWorkout = "First Workout"
    case streak7 = "7-Day Streak"
    case streak30 = "30-Day Streak"
    case totalSets100 = "100 Sets Logged"
    case totalSets1000 = "1,000 Sets Logged"
    case volumePR = "New Volume PR"
    case weightPR = "New Weight PR"
    case consistency4Weeks = "4 Weeks Consistent"
    case totalSessions10 = "10 Workouts"
    case totalSessions50 = "50 Workouts"
    case totalSessions100 = "100 Workouts"

    var title: String { rawValue }
    var icon: String {
        switch self {
        case .firstWorkout: return "flame.fill"
        case .streak7: return "calendar.badge.checkmark"
        case .streak30: return "star.fill"
        case .totalSets100, .totalSets1000: return "checkmark.seal.fill"
        case .volumePR, .weightPR: return "trophy.fill"
        case .consistency4Weeks: return "chart.bar.fill"
        case .totalSessions10, .totalSessions50, .totalSessions100: return "dumbbell.fill"
        }
    }
    var color: String { // hex
        switch self {
        case .firstWorkout: return "#FF6B35"
        case .streak7: return "#30d158"
        case .streak30: return "#FFD700"
        case .totalSets100, .totalSets1000: return "#5E9BF0"
        case .volumePR, .weightPR: return "#FF375F"
        case .consistency4Weeks: return "#30d158"
        case .totalSessions10, .totalSessions50, .totalSessions100: return "#BF5AF2"
        }
    }
}

struct Exercise: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var muscle: String
    var kind: ExerciseKind
    var isCustom: Bool = false
    var equipment: ExerciseEquipment = .barbell
    var isFavorite: Bool = false
    var instructions: String = ""
    var difficulty: Int = 2  // 1=beginner, 2=intermediate, 3=advanced
}

struct RoutineExercise: Codable, Identifiable {
    var id: String = UUID().uuidString
    var exerciseId: String
    var defaultSets: Int = 3
    var defaultReps: Int = 10
    var defaultWeight: Double = 0
    var notes: String = ""
    var repRangeMin: Int = 8
    var repRangeMax: Int = 12
    var restSeconds: Int = 90
    var supersetGroupId: String? = nil
}

struct Routine: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var exercises: [RoutineExercise] = []
    var createdAt: Date = Date()
}

struct LoggedSet: Codable, Identifiable {
    var id: String = UUID().uuidString
    var weight: Double = 0
    var reps: Int = 0
    var durationSec: Int = 0
    var distanceKm: Double = 0
    var isWarmup: Bool = false
    var isDropSet: Bool = false
    var isFailure: Bool = false
    var tempoString: String = ""
    var done: Bool = false
    var completedAt: Date? = nil
    var rpe: Int? = nil
    var notes: String = ""
}

struct SessionExercise: Codable, Identifiable {
    var id: String = UUID().uuidString
    var exerciseId: String
    var sets: [LoggedSet] = []
    var notes: String = ""
    var supersetGroupId: String? = nil
    var targetRepMin: Int = 8
    var targetRepMax: Int = 12
}

struct WorkoutSession: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var routineId: String? = nil
    var exercises: [SessionExercise] = []
    var startedAt: Date = Date()
    var finishedAt: Date? = nil
    var notes: String = ""
    var rating: Int? = nil   // 1-5 stars post-workout
    var bodyweightKg: Double? = nil

    var durationSeconds: Int {
        let end = finishedAt ?? Date()
        return Int(end.timeIntervalSince(startedAt))
    }

    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.filter(\.done).count }
    }

    var totalVolumeKg: Double {
        exercises.reduce(0.0) { total, ex in
            total + ex.sets.filter(\.done).reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        }
    }
}

// MARK: - Body Models

struct WeightEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var valueKg: Double
    var source: String = "manual"
}

struct BodyCompEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var bodyFatPct: Double? = nil
    var leanMassKg: Double? = nil
    var bmi: Double? = nil
    var source: String = "healthkit"
}

// MARK: - Body Measurements

struct BodyMeasurement: Codable, Identifiable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    var chestCm: Double? = nil
    var waistCm: Double? = nil
    var hipsCm: Double? = nil
    var leftArmCm: Double? = nil
    var rightArmCm: Double? = nil
    var leftThighCm: Double? = nil
    var rightThighCm: Double? = nil
    var neckCm: Double? = nil
    var shouldersCm: Double? = nil
    var notes: String = ""
}

// MARK: - Achievements

struct Achievement: Codable, Identifiable {
    var id: String = UUID().uuidString
    var kind: AchievementKind
    var unlockedAt: Date = Date()
    var title: String = ""
    var detail: String = ""
}

// MARK: - Care / Daily Models

struct CareDay: Codable {
    var dayKey: String = ""
    var waterGlasses: Int = 0
    var meals: [String] = []
    var lastBreakAt: Date? = nil
    var breaksTaken: Int = 0
    var steps: Int = 0
}

struct CareSettings: Codable {
    var waterGoal: Int = 8
    var mealGoal: Int = 3
    var breakIntervalMinutes: Int = 60
    var waterReminderEnabled: Bool = false
    var waterReminderIntervalMinutes: Int = 60
    var stepGoal: Int = 10000
}

struct WorkoutSettings: Codable {
    var restTimerEnabled: Bool = true
    var defaultRestSeconds: Int = 90
    var weightUnit: WeightUnit = .kg
}

// MARK: - Workout Programs / Splits

struct ProgramDay: Codable, Identifiable {
    var id: String = UUID().uuidString
    var weekday: Int    // 1 = Monday … 7 = Sunday
    var routineId: String? = nil
    var label: String = ""
}

struct WorkoutProgram: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var days: [ProgramDay] = []
    var isActive: Bool = false
    var createdAt: Date = Date()
}

// MARK: - Weight Unit

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg, lbs
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }

    func convert(_ value: Double, to target: WeightUnit) -> Double {
        if self == target { return value }
        switch (self, target) {
        case (.kg, .lbs): return value * 2.20462
        case (.lbs, .kg): return value / 2.20462
        default: return value
        }
    }
}
