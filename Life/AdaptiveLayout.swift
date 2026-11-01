import SwiftUI

// MARK: - Adaptive layout (iPhone Duo and other wide windows)

/// Layout decisions keyed to the width the app actually has, not to the device.
///
/// The iPhone Duo is the reason this exists. Folded, its outer display is an
/// ordinary phone (about 466pt wide). Unfolded, the inner display is roughly
/// 669 × 951pt (measured on the Duo simulator) — square-ish, wider than any iPhone in portrait — and in
/// landscape it is wider still. It also runs two apps side by side, so the
/// same device can hand Life a full inner screen, half of one, or the narrow
/// outer screen, and can switch between them while the app is open.
///
/// Size classes don't answer that question well: they are coarse, they differ
/// between the two screens in ways Apple doesn't document for a new device,
/// and Split View changes them under you. The window's width does answer it,
/// so it is measured once at the root and handed down through the
/// environment. Every screen reads `isWideLayout` rather than measuring itself,
/// which keeps them all switching at the same moment when the phone is folded
/// or unfolded.
enum AdaptiveLayout {
    /// At or above this width a screen has room for two columns. Comfortably
    /// above the widest phone in portrait (Pro Max, 440pt) and the Duo's outer
    /// display, and below the Duo's inner display in portrait.
    static let wideThreshold: CGFloat = 600

    /// At or above this width a screen splits into two full columns of cards.
    ///
    /// Above the Duo's inner display held upright (669pt) and below it turned
    /// on its side (951pt). Upright, two columns would leave each about 300pt
    /// of content — narrower than an iPhone SE — and task titles get cut off.
    /// So upright the Duo shows extra side by side only where the pieces are
    /// small (the health tiles), and keeps lists full width; on its side each
    /// column is about as wide as a phone, which is what the cards were built
    /// for.
    static let twoColumnThreshold: CGFloat = 800

    /// The widest a single column of cards is allowed to get. Rows of text and
    /// a chevron stretched across a landscape inner display are harder to read
    /// than the same rows on a phone, not easier.
    static let readableWidth: CGFloat = 700

    /// The widest a two-column layout is allowed to get, for the same reason.
    static let wideReadableWidth: CGFloat = 1_040

    /// Used before the first measurement arrives, so the very first frame lays
    /// out as a phone rather than as a zero-width window.
    static let fallbackWidth: CGFloat = 390
}

private struct LayoutWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = AdaptiveLayout.fallbackWidth
}

extension EnvironmentValues {
    /// The width of the app's window in points, as measured at the root.
    var layoutWidth: CGFloat {
        get { self[LayoutWidthKey.self] }
        set { self[LayoutWidthKey.self] = newValue }
    }

    /// True when the window is wider than any phone — the Duo unfolded, in
    /// either orientation, or any other window at least 600pt wide.
    var isWideLayout: Bool { layoutWidth >= AdaptiveLayout.wideThreshold }

    /// True when there is room for two full columns of cards — the Duo's inner
    /// display turned on its side, or any window at least 800pt wide.
    var isTwoColumnLayout: Bool { layoutWidth >= AdaptiveLayout.twoColumnThreshold }
}

// MARK: - Measuring

private struct LayoutWidthReader: ViewModifier {
    @State private var width: CGFloat = AdaptiveLayout.fallbackWidth

    func body(content: Content) -> some View {
        content
            .environment(\.layoutWidth, width)
            .background {
                // A background reader rather than wrapping the content in a
                // GeometryReader, which would change how the content is sized.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { update(proxy.size.width) }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            update(newWidth)
                        }
                }
                .accessibilityHidden(true)
            }
    }

    private func update(_ newWidth: CGFloat) {
        // Zero arrives while a window is being torn down or rebuilt during a
        // fold; keeping the last real width avoids a one-frame phone layout.
        guard newWidth > 0, abs(newWidth - width) >= 1 else { return }
        width = newWidth
    }
}

extension View {
    /// Measures this view's width and publishes it as `layoutWidth` to
    /// everything inside. Applied once, at the root of the app.
    func measuresLayoutWidth() -> some View {
        modifier(LayoutWidthReader())
    }

    /// Caps a column of content at a readable width and centres it, so it
    /// doesn't stretch edge to edge on the unfolded Duo or in landscape. Has no
    /// effect on a phone, which is narrower than the cap.
    func readableContentWidth(_ maxWidth: CGFloat = AdaptiveLayout.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
