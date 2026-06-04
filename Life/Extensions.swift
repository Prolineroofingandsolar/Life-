import SwiftUI
import Foundation

// MARK: - App Design System

enum AppTheme {
    // Brand colours
    static let primary     = Color(hex: "#30d158")
    static let danger      = Color(hex: "#FF375F")
    static let warning     = Color(hex: "#FF9F0A")

    // Surfaces
    static let cardBg      = Color(.systemBackground)
    static let pageBg      = Color(.systemGroupedBackground)
    static let fillBg      = Color(.systemFill)

    // Shape
    static let cardRadius:   CGFloat = 18
    static let chipRadius:   CGFloat = 12
    static let buttonRadius: CGFloat = 14
}

extension View {
    /// Wraps a view in the standard app card surface (white bg, corner radius, shadow).
    func appCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(AppTheme.cardBg)
            .cornerRadius(AppTheme.cardRadius)
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Date Extensions

extension Date {
    var dayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        var comps = DateComponents()
        comps.day = 1
        comps.second = -1
        return Calendar.current.date(byAdding: comps, to: startOfDay) ?? self
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
