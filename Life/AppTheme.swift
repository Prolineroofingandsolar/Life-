import SwiftUI

// MARK: - App Theme

enum AppTheme {
    // MARK: Brand palette (derived from the app logo)
    static let brandPurple  = Color(hex: "#7B7FF0")
    static let brandBlue    = Color(hex: "#5A8CF0")
    static let brandTeal    = Color(hex: "#2FD4C0")
    static let brandInk     = Color(hex: "#101030")

    /// Solid accent for small controls (buttons, tints, checkmarks, rings).
    static let primary      = brandTeal
    /// Hero gradient for large/celebratory surfaces (splash, CTAs, summary cards).
    static let brandGradient = LinearGradient(
        colors: [brandPurple, brandBlue, brandTeal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardBg       = Color(.secondarySystemGroupedBackground)
    static let pageBg       = Color(.systemGroupedBackground)
    static let cardRadius:   CGFloat = 16
    static let chipRadius:   CGFloat = 10
    static let buttonRadius: CGFloat = 14
    static let danger       = Color.red

    static let trainAccent = brandTeal
    static let trainCard   = Color(.secondarySystemBackground)
    static let trainBg     = Color(.systemGroupedBackground)
}
