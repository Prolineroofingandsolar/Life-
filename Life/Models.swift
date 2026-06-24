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

enum RecurrenceType: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, biweekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily:     return "Daily"
        case .weekly:    return "Weekly"
        case .biweekly:  return "Every 2 Weeks"
        case .monthly:   return "Monthly"
        case .yearly:    return "Yearly"
        }
    }
}

struct TaskList: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var emoji: String = "📋"
    var colorHex: String = "#5E9BF0"
    var isSystem: Bool = false
    var createdAt: Date = Date()

    var color: Color { Color(hex: colorHex) }
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

    var date: Date {
        let cal = Calendar.current
        switch self {
        case .today:    return cal.startOfDay(for: Date())
        case .tomorrow: return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        case .thisWeek: return cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: Date())) ?? Date()
        }
    }
}

struct AppTask: Codable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var category: TaskCategory = .personal
    var listId: String = "personal"
    var done: Bool = false
    var dueDate: DueDate? = .today
    var dueDateOverride: Date? = nil
    var priority: TaskPriority = .none
    var notes: String = ""
    var subtasks: [Subtask] = []
    var scheduledTime: Date? = nil
    var estimatedMinutes: Int? = nil
    var isRecurring: Bool = false
    var recurrenceType: RecurrenceType? = nil
    var recurrenceInterval: Int? = nil
    var reminderDate: Date? = nil
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    var resolvedDate: Date? {
        if let override = dueDateOverride { return override }
        return dueDate?.date
    }

    var dueDateLabel: String {
        if let override = dueDateOverride {
            let cal = Calendar.current
            if cal.isDateInToday(override) { return "Today" }
            if cal.isDateInTomorrow(override) { return "Tomorrow" }
            return override.formatted(.dateTime.month(.abbreviated).day())
        }
        return dueDate?.label ?? ""
    }
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
    case daily, weekly, timesPerWeek, specificWeekdays, timesPerMonth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily:            return "Daily"
        case .weekly:           return "Weekly"
        case .timesPerWeek:     return "Times/Week"
        case .specificWeekdays: return "Specific Days"
        case .timesPerMonth:    return "Times/Month"
        }
    }
}

enum HabitCategory: String, Codable, CaseIterable, Identifiable {
    case health, fitness, mindset, productivity, sleep, nutrition
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
        }
    }
    var color: Color {
        switch self {
        case .health:       return Color(red: 1.0,  green: 0.22, blue: 0.37)
        case .fitness:      return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .mindset:      return Color(red: 0.75, green: 0.35, blue: 0.95)
        case .productivity: return Color(red: 1.0,  green: 0.62, blue: 0.04)
        case .sleep:        return Color(red: 0.37, green: 0.60, blue: 0.95)
        case .nutrition:    return Color(red: 0.20, green: 0.67, blue: 0.90)
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
        case .count:  return "number.circle"
        case .timer:  return "timer"
        }
    }
}

struct HabitLogEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var dayKey: String
    var count: Int = 1
    var slipped: Bool = false
    var note: String = ""
}

struct Habit: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var emoji: String = "⭐️"
    var category: HabitCategory = .health
    var kind: HabitKind = .build
    var cadence: HabitCadence = .daily
    var targetType: HabitTargetType = .yesNo
    var targetCount: Int = 1
    var targetUnit: String = ""
    var weekdays: [Int] = []
    var isArchived: Bool = false
    var reminderEnabled: Bool = false
    var reminderTime: Date? = nil
    var notes: String = ""
    var logs: [HabitLogEntry] = []
    var createdAt: Date = Date()
}

// MARK: - Supplement Models

struct Supplement: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var emoji: String = "💊"
    var dosesPerDay: Int = 1
    var scheduleDays: [Int] = []  // empty = every day; 1=Mon…7=Sun
    var doseUnit: String = "dose"
    var notes: String = ""
    var logs: [DoseLog] = []
    var isArchived: Bool = false
}

struct DoseLog: Identifiable, Codable {
    var id: String = UUID().uuidString
    var dayKey: String = Date().dayKey
    var dosesTaken: Int = 0
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
        case .barbell:    return "Barbell"
        case .dumbbell:   return "Dumbbell"
        case .cable:      return "Cable"
        case .machine:    return "Machine"
        case .bodyweight: return "Bodyweight"
        case .kettlebell: return "Kettlebell"
        case .band:       return "Band"
        case .ezBar:      return "EZ Bar"
        case .other:      return "Other"
        }
    }
    var icon: String {
        switch self {
        case .barbell:    return "figure.strengthtraining.traditional"
        case .dumbbell:   return "dumbbell.fill"
        case .cable:      return "cable.connector"
        case .machine:    return "gearshape.fill"
        case .bodyweight: return "figure.stand"
        case .kettlebell: return "dumbbell"
        case .band:       return "arrow.left.and.right"
        case .ezBar:      return "wave.3.right"
        case .other:      return "questionmark.circle"
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
    var color: String {
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

enum MovementType: String, Codable, CaseIterable, Identifiable {
    case compound, isolation, cardio
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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
    var difficulty: Int = 2
    var movementType: MovementType = .compound
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
    var colorHex: String = "#30d158"
    var emoji: String = "💪"
    var photoData: Data? = nil
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
    var rating: Int? = nil
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
    var goalWeightKg: Double? = nil
}

// MARK: - Workout Programs / Splits

struct ProgramDay: Codable, Identifiable {
    var id: String = UUID().uuidString
    var weekday: Int
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

// MARK: - Travel Models

struct VisitedLocation: Codable, Identifiable {
    var id: String = UUID().uuidString
    var latitude: Double
    var longitude: Double
    var timestamp: Date = Date()
    var revealRadiusKm: Double = 2.0
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
