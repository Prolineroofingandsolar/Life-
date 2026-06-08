import SwiftUI

// MARK: - App Theme

enum AppTheme {
    static let primary      = Color(hex: "#30d158")
    static let cardBg       = Color(.secondarySystemGroupedBackground)
    static let pageBg       = Color(.systemGroupedBackground)
    static let cardRadius:   CGFloat = 16
    static let chipRadius:   CGFloat = 10
    static let buttonRadius: CGFloat = 14
    static let danger       = Color.red

    // Train tab — always-dark aesthetic
    static let trainAccent = Color(hex: "#FFD700")
    static let trainCard   = Color(hex: "#1C1E27")
    static let trainBg     = Color(hex: "#111318")
}
