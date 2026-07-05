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

// MARK: - Shared Empty State

/// A consistent icon + title + subtitle (+ optional action) placeholder for
/// empty lists, used in place of each screen hand-rolling its own spacing,
/// icon size, and font weights.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.subheadline.bold())
                        .foregroundColor(AppTheme.primary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
