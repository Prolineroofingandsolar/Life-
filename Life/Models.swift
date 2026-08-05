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

/// Recurring monthly income (salary, etc.) — same shape as Bill, paid in rather than out.
struct Income: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var amount: Double
    var dayOfMonth: Int
    var notes: String = ""
}

/// A single non-recurring expense on a specific date.
struct OneOffExpense: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var amount: Double
    var date: Date = Date()
    var notes: String = ""
}

enum CurrencyCode: String, Codable, CaseIterable, Identifiable {
    case gbp = "GBP"
    case usd = "USD"
    case eur = "EUR"
    case cad = "CAD"
    case aud = "AUD"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .gbp: return "£"
        case .usd: return "$"
        case .eur: return "€"
        case .cad: return "CA$"
        case .aud: return "AU$"
        }
    }
}

struct MoneySettings: Codable {
    var currency: CurrencyCode = .gbp
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
        case .streak7: return "#2FD4C0"
        case .streak30: return "#FFD700"
        case .totalSets100, .totalSets1000: return "#5E9BF0"
        case .volumePR, .weightPR: return "#FF375F"
        case .consistency4Weeks: return "#2FD4C0"
        case .totalSessions10, .totalSessions50, .totalSessions100: return "#BF5AF2"
        }
    }

    /// How to unlock this achievement, shown while it's still locked.
    var unlockHint: String {
        switch self {
        case .firstWorkout:     return "Finish your first workout"
        case .streak7:          return "Reach a 7-day workout streak"
        case .streak30:         return "Reach a 30-day workout streak"
        case .totalSets100:     return "Log 100 sets total"
        case .totalSets1000:    return "Log 1,000 sets total"
        case .volumePR:         return "Beat your best session's total volume"
        case .weightPR:         return "Set a new weight PR on any exercise"
        case .consistency4Weeks: return "Work out in 3 of the last 4 weeks"
        case .totalSessions10:  return "Complete 10 workouts"
        case .totalSessions50:  return "Complete 50 workouts"
        case .totalSessions100: return "Complete 100 workouts"
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
    var colorHex: String = "#2FD4C0"
    var emoji: String = "💪"
    var photoData: Data? = nil
}

// MARK: - Set Kind

/// What a logged set is: an ordinary working set, a warm-up, a drop set, or one
/// half of a superset.
///
/// These were four separate mechanisms with four different ways in. Warm-up was
/// a boolean behind a long-press context menu; drop set was a boolean plus a
/// "Add Drop Set" action that inserted a *new* row rather than changing the one
/// in front of you; superset lived on the exercise and could only be created by
/// pairing with whatever happened to be next. There was no way to look at a set
/// and say what it was, and no single place to change it.
///
/// The four are now one property with one picker. The underlying booleans stay
/// as the storage — see `LoggedSet.kind` — so every existing saved workout and
/// every statistic that filters on `isWarmup` keeps working unchanged.
enum SetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case warmup
    case drop
    case superset

    var id: String { rawValue }

    /// The name in the picker.
    var label: String {
        switch self {
        case .normal:   return "Normal"
        case .warmup:   return "Warm-up"
        case .drop:     return "Drop set"
        case .superset: return "Superset"
        }
    }

    /// The one- or two-character badge on the set row.
    var badge: String {
        switch self {
        case .normal:   return ""
        case .warmup:   return "W"
        case .drop:     return "↓"
        case .superset: return "S"
        }
    }

    var icon: String {
        switch self {
        case .normal:   return "circle"
        case .warmup:   return "flame"
        case .drop:     return "arrow.down.circle"
        case .superset: return "arrow.triangle.2.circlepath"
        }
    }

    /// Whether the set counts towards working volume, personal records and
    /// progression. Warm-ups and drop sets are deliberately excluded: both are
    /// performed at reduced load by design, and counting them drags every
    /// average down and hides real progress.
    var countsAsWorkingSet: Bool {
        switch self {
        case .normal, .superset: return true
        case .warmup, .drop:     return false
        }
    }
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
    /// Marks a set performed back-to-back with another exercise.
    ///
    /// Optional rather than a plain `Bool` on purpose: Swift's synthesized
    /// `Codable` calls `decode` for non-optional properties, so adding one here
    /// would throw on every set saved before this version — and a decode failure
    /// is treated as "first launch", which would wipe the whole save file. An
    /// optional gets `decodeIfPresent` and reads back as nil.
    var isSupersetSet: Bool? = nil

    /// The set's type, derived from and written back to the stored flags.
    ///
    /// Reading is ordered rather than exclusive because the flags aren't
    /// mutually exclusive in old data — a set could have been marked both warm-up
    /// and drop by two different code paths. Warm-up wins that tie, being the
    /// one that changes how the set is counted most.
    var kind: SetKind {
        get {
            if isWarmup { return .warmup }
            if isDropSet { return .drop }
            if isSupersetSet == true { return .superset }
            return .normal
        }
        set {
            isWarmup = newValue == .warmup
            isDropSet = newValue == .drop
            isSupersetSet = newValue == .superset
        }
    }
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

    /// Combines two devices' record of the same day.
    ///
    /// Counters take the larger of the two rather than the preferred side's.
    /// These only ever go up during a day, so a phone that hasn't synced since
    /// this morning holding four glasses of water doesn't mean the day's count
    /// dropped to four — it means that device stopped counting at four. The
    /// same reasoning covers steps, which is why a sync catching a source
    /// mid-import can't push the figure backwards.
    static func merging(_ incoming: CareDay, onto existing: CareDay) -> CareDay {
        var out = incoming
        out.dayKey = incoming.dayKey.isEmpty ? existing.dayKey : incoming.dayKey
        out.waterGlasses = max(incoming.waterGlasses, existing.waterGlasses)
        out.breaksTaken = max(incoming.breaksTaken, existing.breaksTaken)
        out.steps = max(incoming.steps, existing.steps)
        // Whichever device logged more meals has the fuller list; meals aren't
        // individually identified, so they can't be unioned safely.
        out.meals = incoming.meals.count >= existing.meals.count ? incoming.meals : existing.meals
        out.lastBreakAt = [incoming.lastBreakAt, existing.lastBreakAt].compactMap { $0 }.max()
        return out
    }
}

struct CareSettings: Codable {
    var waterGoal: Int = 8
    var mealGoal: Int = 3
    var breakIntervalMinutes: Int = 60
    var waterReminderEnabled: Bool = false
    var waterReminderIntervalMinutes: Int = 60
    var stepGoal: Int = 10000
    var breakReminderEnabled: Bool = false
    var morningSummaryEnabled: Bool = false
    var eveningNudgeEnabled: Bool = false
}

// MARK: - Health Models

/// One day of Apple Health metrics, keyed by `Date.dayKey`.
///
/// Every metric is optional and `nil` means "not recorded that day" — which is
/// different from zero. A day with no tracker worn should chart as a gap, not
/// as a reading of 0.
///
/// The `CodingKeys` are deliberately terse. The whole `StateSnapshot` is
/// encoded into a single Firestore document with a hard 1 MB ceiling (see
/// `FirestoreSync.SyncError`), and this is the only type that grows by one
/// record every day forever. Short keys plus `JSONEncoder` skipping nil
/// optionals keeps a year of history down to tens of KB rather than hundreds.
struct HealthDay: Codable {
    var dayKey: String = ""

    // Sleep. Minutes, attributed to the morning the night ended.
    var sleepMin: Int? = nil
    var deepMin: Int? = nil
    var remMin: Int? = nil
    var lightMin: Int? = nil
    var awakeMin: Int? = nil
    var bedtime: Date? = nil
    var wakeTime: Date? = nil
    /// Bedtime to wake, including time awake. The honest denominator for
    /// efficiency, rather than inferring it from asleep + awake.
    var timeInBedMin: Int? = nil
    /// How long it took to drop off.
    var latencyMin: Int? = nil
    /// Number of separate awake segments — how broken the night was.
    var awakenings: Int? = nil
    /// "STAGES" or "CLASSIC". Classic nights have no stage breakdown, so the UI
    /// hides the hypnogram rather than drawing an empty one, and the score drops
    /// its quality term instead of scoring it zero.
    var sleepType: String? = nil

    /// An official sleep score supplied by the source, stored verbatim.
    ///
    /// **Nothing populates this today.** The Google Health API v4 schema has no
    /// score field on any sleep type — verified across every schema in the
    /// discovery document — and Google doesn't publish the formula. The field
    /// exists so that if a source ever does provide one, it can be shown as-is
    /// rather than recalculated, averaged, normalised or blended with Life's
    /// own estimate.
    var officialSleepScore: Int? = nil
    /// Who provided `officialSleepScore` — e.g. GOOGLE_HEALTH, FITBIT.
    var officialSleepScoreSource: String? = nil
    /// Device that measured the night, for display alongside the figures.
    var sleepSourceDevice: String? = nil

    // Derived sleep measurements (see `SleepAnalysis`).
    var restlessMinutes: Int? = nil
    var interruptionMinutes: Int? = nil
    var stageTransitions: Int? = nil
    var sleepMidpoint: Date? = nil
    /// Source record identifier, for tying calibration comparisons to the exact
    /// session they were made against and spotting when it's been re-imported.
    var sleepRecordID: String? = nil
    /// Overnight heart-rate statistics across the sleep window.
    var sleepingHrAverage: Double? = nil
    var sleepingHrMinimum: Double? = nil
    /// Standard deviation of overnight heart rate — steadiness, not rate.
    var sleepingHrStability: Double? = nil
    /// Share of the sleep window described by stage intervals, 0–1. Below
    /// `SleepAnalysis.minimumStageCoverage` the night isn't scored.
    var stageCoverage: Double? = nil

    // Heart and recovery.
    var restingHr: Double? = nil
    /// The day's heart-rate range and mean, derived from the sample curve.
    ///
    /// Only these three numbers are kept. The samples they come from — up to
    /// 1,440 a day — are held in memory by `HeartRateStore` and never stored,
    /// because `StateSnapshot` is one Firestore document with a 1 MB ceiling.
    var hrMin: Double? = nil
    var hrMax: Double? = nil
    var hrAverage: Double? = nil
    /// Minutes spent in each heart-rate zone, from `timeInHeartRateZone`.
    var hrZoneLightMin: Int? = nil
    var hrZoneModerateMin: Int? = nil
    var hrZoneVigorousMin: Int? = nil
    var hrZonePeakMin: Int? = nil
    var hrvMs: Double? = nil
    var respiratoryRate: Double? = nil
    var spo2Pct: Double? = nil
    var wristTempC: Double? = nil
    var vo2Max: Double? = nil
    /// Breathing rate split by stage — REM breathing differs from deep, and the
    /// gap between them is itself a signal.
    var breathingRem: Double? = nil
    var breathingDeep: Double? = nil
    var breathingLight: Double? = nil
    /// HRV measured specifically during deep sleep, the cleanest window for it.
    var deepSleepHrvMs: Double? = nil
    /// Your own median nightly skin temperature, so `wristTempC` can be shown as
    /// a deviation rather than a bare number nobody can interpret.
    var tempBaselineC: Double? = nil

    // Activity.
    var activeEnergyKcal: Double? = nil
    var exerciseMinutes: Int? = nil
    var distanceKm: Double? = nil
    var flights: Int? = nil

    enum CodingKeys: String, CodingKey {
        case dayKey = "k"
        case sleepMin = "sl", deepMin = "dp", remMin = "rm", lightMin = "lt", awakeMin = "aw"
        case bedtime = "bt", wakeTime = "wt"
        case timeInBedMin = "ib", latencyMin = "lc", awakenings = "wk", sleepType = "st"
        case officialSleepScore = "os", officialSleepScoreSource = "op", sleepSourceDevice = "sd"
        case restlessMinutes = "rl", interruptionMinutes = "im", stageTransitions = "tr"
        case sleepMidpoint = "mp", stageCoverage = "cv"
        case sleepRecordID = "ri"
        case sleepingHrAverage = "ha", sleepingHrMinimum = "hm", sleepingHrStability = "hs"
        case restingHr = "rh", hrvMs = "hv", respiratoryRate = "rr"
        case hrMin = "hl", hrMax = "hh", hrAverage = "hg"
        case hrZoneLightMin = "z1", hrZoneModerateMin = "z2"
        case hrZoneVigorousMin = "z3", hrZonePeakMin = "z4"
        case spo2Pct = "ox", wristTempC = "tp", vo2Max = "vo"
        case breathingRem = "br", breathingDeep = "bd", breathingLight = "bl"
        case deepSleepHrvMs = "dh", tempBaselineC = "tb"
        case activeEnergyKcal = "ae", exerciseMinutes = "em"
        case distanceKm = "ds", flights = "fl"
    }

    /// Proportion of time in bed actually spent asleep, 0–1.
    ///
    /// Prefers the reported time in bed, which counts the whole period between
    /// getting in and getting up. Falls back to asleep + awake, which is
    /// slightly flattering because it misses the time before sleep onset.
    var sleepEfficiency: Double? {
        if let timeInBedMin, timeInBedMin > 0, let sleepMin {
            return min(1, Double(sleepMin) / Double(timeInBedMin))
        }
        guard let sleepMin, let awakeMin else { return nil }
        let total = sleepMin + awakeMin
        guard total > 0 else { return nil }
        return Double(sleepMin) / Double(total)
    }

    /// Deep plus REM as a share of time asleep.
    ///
    /// Called *restorative*, never "sound sleep". Google's sound-sleep figure is
    /// derived from epoch-level heart rate and movement data this app doesn't
    /// receive; deep + REM is a stage-only approximation and isn't equivalent.
    ///
    /// Nil for CLASSIC nights, which carry no stage breakdown.
    var restorativeShare: Double? {
        guard let sleepMin, sleepMin > 0, deepMin != nil || remMin != nil else { return nil }
        return Double((deepMin ?? 0) + (remMin ?? 0)) / Double(sleepMin)
    }

    /// Nightly skin temperature relative to your own baseline, in °C. This is
    /// the form worth showing — an absolute wrist temperature means nothing
    /// without knowing what's normal for you.
    var tempDeviationC: Double? {
        guard let wristTempC, let tempBaselineC else { return nil }
        return wristTempC - tempBaselineC
    }

    /// True when the day carries no readings at all, so empty records can be
    /// dropped rather than synced.
    var isEmpty: Bool {
        sleepMin == nil && restingHr == nil && hrvMs == nil && respiratoryRate == nil
            && spo2Pct == nil && wristTempC == nil && vo2Max == nil
            && activeEnergyKcal == nil && exerciseMinutes == nil
            && distanceKm == nil && flights == nil
            && hrMin == nil && hrMax == nil && hrAverage == nil
            && hrZoneLightMin == nil && hrZoneModerateMin == nil
            && hrZoneVigorousMin == nil && hrZonePeakMin == nil
    }

    /// Overlays everything a sync actually returned onto what's already stored,
    /// leaving stored values alone wherever the incoming record was nil.
    ///
    /// Done through the encoded form rather than field by field on purpose.
    /// The field-by-field version silently dropped every property added after
    /// it was written — a short seven-day sync was blanking latency,
    /// awakenings, time in bed, stage coverage and every overnight vital that
    /// a full import had found, because none of them were on its list. A list
    /// you have to remember to extend is a list that will be wrong again.
    ///
    /// `JSONEncoder` omits nil optionals, so a key present in the incoming
    /// dictionary is by definition a value the source returned.
    static func merging(_ incoming: HealthDay, onto existing: HealthDay) -> HealthDay {
        guard let existingData = try? JSONEncoder().encode(existing),
              let incomingData = try? JSONEncoder().encode(incoming),
              let existingObject = try? JSONSerialization.jsonObject(with: existingData),
              let incomingObject = try? JSONSerialization.jsonObject(with: incomingData),
              var merged = existingObject as? [String: Any],
              let update = incomingObject as? [String: Any]
        else {
            // Encoding a struct of optionals shouldn't fail, but preferring the
            // fresher record beats returning something half-merged.
            return incoming
        }

        for (key, value) in update { merged[key] = value }

        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let out = try? JSONDecoder().decode(HealthDay.self, from: mergedData)
        else { return incoming }
        return out
    }
}

// MARK: - Sleep Stages

/// One contiguous stretch of a single sleep stage.
struct SleepSegment: Codable, Identifiable, Equatable {
    var start: Date
    var minutes: Int
    /// DEEP, REM, LIGHT, AWAKE, or ASLEEP on classic-tracked nights.
    var stage: String

    var id: String { "\(stage)-\(start.timeIntervalSince1970)" }
    var end: Date { start.addingTimeInterval(Double(minutes) * 60) }

    enum CodingKeys: String, CodingKey {
        case start = "s", minutes = "m", stage = "t"
    }
}

/// The stage-by-stage shape of one night — what the hypnogram is drawn from.
///
/// Kept separately from `HealthDay` because it's an order of magnitude larger:
/// roughly thirty segments a night against a handful of numbers. Only the most
/// recent nights are retained (see `AppState.sleepNightRetention`); older nights
/// keep their totals on `HealthDay` and simply don't offer a hypnogram.
struct SleepNight: Codable {
    var dayKey: String = ""
    var segments: [SleepSegment] = []
    /// Times out of bed during the night. These can overlap stage segments, so
    /// they're kept apart rather than merged in.
    var outOfBed: [SleepSegment] = []

    enum CodingKeys: String, CodingKey {
        case dayKey = "k", segments = "g", outOfBed = "o"
    }

    var start: Date? { segments.map(\.start).min() }
    var end: Date? { segments.map(\.end).max() }
    var hasStages: Bool { segments.contains { $0.stage != "ASLEEP" } }
}

/// Which device Life takes step counts — and the rest of the daily activity
/// figures — from.
///
/// The iPhone and a wrist tracker both count steps and will never agree: the
/// phone misses everything you do without it on you, and the band misses
/// nothing. Letting whichever synced last win produces a number that jumps
/// around, so exactly one of them is authoritative.
enum StepSource: String, Codable, CaseIterable, Identifiable {
    /// The previous behaviour: the wrist tracker whenever it's connected.
    case automatic
    case fitbit
    case iphone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .fitbit:    return "Fitbit"
        case .iphone:    return "iPhone"
        }
    }
}

struct HealthSettings: Codable {
    var sleepGoalMinutes: Int = 480
    var exerciseGoalMinutes: Int = 30
    var showRecoveryTile: Bool = true
    /// Set once the first full-history import has run, so the 5-minute
    /// foreground sync only ever pulls a short recent window.
    var hasBackfilled: Bool = false
    /// Which device's step count to trust. The iPhone and a wrist tracker both
    /// count steps and never agree — the phone misses everything you do
    /// without it in your pocket — so exactly one of them wins rather than
    /// whichever synced last.
    var stepSource: StepSource = .automatic

    /// When data last actually arrived, which device it came from, and
    /// anything that didn't come through.
    ///
    /// Without these there is no way to tell a stale figure from a broken one
    /// — both look like a number that's too low, and they need opposite
    /// fixes. Every figure on screen is only as fresh as this.
    var lastSyncedAt: Date? = nil
    var lastSyncSource: String? = nil
    var lastSyncFailures: [String] = []

    /// Metrics the last sync never got to, because the request budget ran out
    /// partway through.
    ///
    /// Kept separate from `lastSyncFailures` because it means something
    /// different — not attempted, rather than attempted and refused — and
    /// because it drives the order of the next sync. Without it the same
    /// metrics sit at the end of a fixed queue every time and are starved
    /// every time, which is why steps could go days without updating while
    /// sleep never missed.
    var lastSyncSkipped: [String] = []

    /// When the quota is expected back, if the last sync hit the limit.
    var rateLimitedUntil: Date? = nil

    /// Per metric, the moment its data was last successfully fetched through.
    ///
    /// This is what makes a sync incremental. Every sync used to re-request the
    /// same fixed window — a year, or sixty days — for all fourteen metrics
    /// regardless of what was already stored, which is an enormous number of
    /// requests to spend re-downloading records the app already holds, and it
    /// is why the hourly budget ran out before the end of the list.
    ///
    /// Keyed per metric rather than one timestamp for the lot, because they
    /// don't stay in step: if steps was starved for a week while sleep synced
    /// nightly, steps needs a week and sleep needs a day. A single watermark
    /// would either re-fetch a week of sleep needlessly or leave six days of
    /// steps permanently missing.
    var metricSyncedThrough: [String: Date] = [:]

    enum CodingKeys: String, CodingKey {
        case sleepGoalMinutes, exerciseGoalMinutes, showRecoveryTile, hasBackfilled
        case stepSource
        case lastSyncedAt, lastSyncSource, lastSyncFailures
        case lastSyncSkipped, rateLimitedUntil, metricSyncedThrough
    }

    init() {}

    /// Decodes key by key so a settings blob written by an older version — one
    /// missing a goal added later — still loads. Swift's synthesized decoder
    /// would throw on the absent key instead of using the default above, and a
    /// throw here fails the whole `StateSnapshot`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sleepGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .sleepGoalMinutes) ?? 480
        exerciseGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .exerciseGoalMinutes) ?? 30
        showRecoveryTile = try c.decodeIfPresent(Bool.self, forKey: .showRecoveryTile) ?? true
        hasBackfilled = try c.decodeIfPresent(Bool.self, forKey: .hasBackfilled) ?? false
        // Decoded through its raw value rather than the enum so a value written
        // by a future version doesn't throw and fail the whole snapshot.
        stepSource = StepSource(
            rawValue: try c.decodeIfPresent(String.self, forKey: .stepSource) ?? ""
        ) ?? .automatic
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        lastSyncSource = try c.decodeIfPresent(String.self, forKey: .lastSyncSource)
        lastSyncFailures = try c.decodeIfPresent([String].self, forKey: .lastSyncFailures) ?? []
        lastSyncSkipped = try c.decodeIfPresent([String].self, forKey: .lastSyncSkipped) ?? []
        rateLimitedUntil = try c.decodeIfPresent(Date.self, forKey: .rateLimitedUntil)
        metricSyncedThrough = try c.decodeIfPresent([String: Date].self, forKey: .metricSyncedThrough) ?? [:]
    }
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
