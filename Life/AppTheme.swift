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

// MARK: - Shared Action Tile

/// Icon, title, subtitle, chevron — the shape every "go and do a thing" row in
/// this app already has.
///
/// Promoted here because it existed three times already: `MoreRowLabel` in
/// `MoreView`, `QuickStartCard` in `TrainView`, and a near-identical `StatCard`
/// duplicated between `HealthView` and `TrainProgressHubView` — the last of
/// which carries a comment at `HealthView.swift:696` acknowledging the
/// duplication. All were `private`, so each new screen added a fourth copy
/// rather than reusing one.
///
/// Works as a grid cell or a full-width row. `ActionTile` is the tappable
/// version; the label is separate so a `NavigationLink` can supply its own.
struct ActionTile: View {

    let icon: String
    let tint: Color
    let title: String
    var subtitle: String?
    /// Fills the available width and stacks vertically — for a 2×2 grid.
    var isCompact: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            ActionTileLabel(
                icon: icon, tint: tint, title: title,
                subtitle: subtitle, isCompact: isCompact
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "\(title). \($0)" } ?? title)
        .accessibilityAddTraits(.isButton)
    }
}

struct ActionTileLabel: View {

    let icon: String
    let tint: Color
    let title: String
    var subtitle: String?
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            // Hidden in a grid cell: at half width the chevron competes with the
            // text for room it doesn't have, and a tile that is obviously a
            // button doesn't need one.
            if !isCompact {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: isCompact ? 76 : 60, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
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
