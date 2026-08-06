import SwiftUI
import Foundation

// MARK: - Date Extensions

// MARK: Day keys

/// The app's day boundary, in one place.
///
/// Every "which day is this?" question in Life resolves here, and it resolves
/// through `Calendar` rather than through a formatter. That is the whole point
/// of the type.
///
/// A `DateFormatter` captures `TimeZone.current` *when it is created* and never
/// looks again. A single long-lived formatter built at launch therefore keeps
/// answering in the launch time zone: cross a zone boundary, or sit through the
/// DST change, and `Date().dayKey` starts naming a day the user is no longer
/// in. Every consumer — habit logs, care days, health days, streaks — silently
/// files against the wrong key, and the symptom is "yesterday's data won't go
/// away" rather than anything that points at a formatter.
///
/// `Calendar.current` is re-resolved on each access and honours both the zone
/// and any DST offset in force on the date being asked about, so the same
/// instant asked about twice either side of a change gives the right answer
/// both times.
enum DayKey {

    /// The calendar all day boundaries are measured with.
    ///
    /// Gregorian explicitly, so a device set to a Buddhist or Japanese calendar
    /// doesn't produce keys like "2569-08-06" that sort and parse differently
    /// from every key already stored. The *time zone* still comes from the
    /// user's current locale, because the day boundary that matters is the one
    /// they're living in.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// "yyyy-MM-dd" for the local day containing `date`.
    static func string(for date: Date, calendar: Calendar = DayKey.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The start of the local day a key names, or nil if the key is malformed.
    ///
    /// Returns local midnight rather than midnight UTC. Parsing "2026-08-06" as
    /// a UTC instant and then formatting it back in a negative offset yields
    /// the 5th, which is how a stored key can decay by a day each round trip.
    static func date(from key: String, calendar: Calendar = DayKey.calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        // Midday, then rounded down. Asking for hour 0 directly fails on the
        // spring-forward date in zones that skip midnight itself (Santiago,
        // Beirut), where 00:00 does not exist and `date(from:)` returns nil.
        components.hour = 12
        guard let noon = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: noon)
    }

    /// Today's key, in the time zone in force right now.
    static func today(_ now: Date = Date(), calendar: Calendar = DayKey.calendar) -> String {
        string(for: now, calendar: calendar)
    }
}

extension Date {
    /// The local day this instant falls in, as "yyyy-MM-dd".
    var dayKey: String {
        DayKey.string(for: self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// The last instant of the local day.
    ///
    /// Derived by stepping to the next day's start and going back a second,
    /// rather than by adding 23:59:59 — on a day that gains or loses an hour to
    /// DST, "start plus a day" is 23 or 25 hours, and only the calendar knows
    /// which.
    var endOfDay: Date {
        let calendar = Calendar.current
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return self }
        return nextDay.addingTimeInterval(-1)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }
}

// MARK: - Color from Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Muscle Color

extension String {
    var muscleColor: Color {
        switch self.lowercased() {
        case "chest":      return .red
        case "back":       return Color(hex: "#30d158")
        case "shoulders":  return .blue
        case "biceps":     return .orange
        case "triceps":    return .purple
        case "legs", "quads", "hamstrings", "glutes", "calves": return .pink
        case "core", "abs": return .yellow
        case "cardio":     return .cyan
        default:           return .secondary
        }
    }
}

// MARK: - Double Formatting

extension Double {
    var formatted1: String {
        if self.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        }
        return String(format: "%.1f", self)
    }
}

// MARK: - String Extensions

extension String {
    var categoryColor: Color {
        switch self {
        case "work":     return Color(red: 0.37, green: 0.36, blue: 0.90)
        case "gym":      return Color(red: 0.19, green: 0.82, blue: 0.35)
        case "personal": return Color(red: 1.00, green: 0.62, blue: 0.04)
        default:         return .secondary
        }
    }
}

// MARK: - Codable Enum Fallback Decoders
// Prevents a single unrecognized persisted value from wiping the entire app state.

extension TaskPriority {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskPriority(rawValue: raw) ?? .none
    }
}
extension RecurrenceType {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RecurrenceType(rawValue: raw) ?? .weekly
    }
}
extension DueDate {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DueDate(rawValue: raw) ?? .today
    }
}
extension HabitKind {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HabitKind(rawValue: raw) ?? .build
    }
}
extension HabitCadence {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HabitCadence(rawValue: raw) ?? .daily
    }
}
extension HabitCategory {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HabitCategory(rawValue: raw) ?? .health
    }
}
extension HabitTargetType {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HabitTargetType(rawValue: raw) ?? .yesNo
    }
}
extension ExerciseKind {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExerciseKind(rawValue: raw) ?? .weight
    }
}
extension ExerciseEquipment {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExerciseEquipment(rawValue: raw) ?? .other
    }
}
extension AchievementKind {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AchievementKind(rawValue: raw) ?? .firstWorkout
    }
}
extension MovementType {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MovementType(rawValue: raw) ?? .compound
    }
}
extension WeightUnit {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WeightUnit(rawValue: raw) ?? .kg
    }
}

// MARK: - View Helpers

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Int Formatting

extension Int {
    var formattedDuration: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDurationShort: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Workout Share Text

extension WorkoutSession {
    /// Plain-text summary suitable for sharing (Messages, Notes, etc.).
    func shareText(exercises: [Exercise], unit: WeightUnit) -> String {
        var lines: [String] = []
        lines.append("💪 \(name)")
        lines.append(startedAt.formatted(date: .abbreviated, time: .omitted))
        lines.append("")
        lines.append("Duration: \(durationSeconds.formattedDuration)")
        lines.append("Sets: \(totalSets)")
        let volume = totalVolumeKg
        lines.append("Volume: \(volume >= 1000 ? String(format: "%.1fT", volume / 1000) : "\(Int(volume))kg")")

        for ex in self.exercises {
            let doneSets = ex.sets.filter(\.done)
            guard !doneSets.isEmpty, let exercise = exercises.first(where: { $0.id == ex.exerciseId }) else { continue }
            lines.append("")
            lines.append(exercise.name)
            for set in doneSets {
                if exercise.kind == .cardio {
                    var parts: [String] = []
                    if set.durationSec > 0 { parts.append("\(set.durationSec / 60) min") }
                    if set.distanceKm > 0 { parts.append("\(set.distanceKm.formatted1) km") }
                    lines.append("  " + parts.joined(separator: ", "))
                } else {
                    let w = WeightUnit.kg.convert(set.weight, to: unit)
                    lines.append("  \(w.formatted1)\(unit.label.lowercased()) × \(set.reps)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Haptic Manager

enum HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Pressable Button Style

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - InfoRow (iOS 15 compatible LabeledContent replacement)

struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}
