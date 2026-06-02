import SwiftUI
import Foundation

// MARK: - Task Models

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
    case daily, weekly
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct HabitLogEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var dayKey: String
    var count: Int = 1
    var slipped: Bool = false
}

struct Habit: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var emoji: String = "⭐️"
    var kind: HabitKind = .build
    var cadence: HabitCadence = .daily
    var targetCount: Int = 1
    var isArchived: Bool = false
    var logs: [HabitLogEntry] = []
    var createdAt: Date = Date()
}

// MARK: - Exercise / Workout Models

enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
    case weight, bodyweight, cardio
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct Exercise: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var muscle: String
    var kind: ExerciseKind
    var isCustom: Bool = false
}

struct RoutineExercise: Codable, Identifiable {
    var id: String = UUID().uuidString
    var exerciseId: String
    var defaultSets: Int = 3
    var defaultReps: Int = 10
    var defaultWeight: Double = 0
    var notes: String = ""
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
    var done: Bool = false
    var completedAt: Date? = nil
}

struct SessionExercise: Codable, Identifiable {
    var id: String = UUID().uuidString
    var exerciseId: String
    var sets: [LoggedSet] = []
    var notes: String = ""
}

struct WorkoutSession: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var routineId: String? = nil
    var exercises: [SessionExercise] = []
    var startedAt: Date = Date()
    var finishedAt: Date? = nil
    var notes: String = ""

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
