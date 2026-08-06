import Foundation

// MARK: - Shared Coach Tip

/// The coach's current line, as the widget sees it.
///
/// Mirrors `WidgetSync.WidgetCoachTip` field for field. The two are separate
/// declarations because the widget extension can't see the app's types, which
/// is also true of `WidgetHabit` — and the same warning applies: rename a
/// property on one side without the other and decoding fails silently, leaving
/// the placeholder on screen with no error anywhere.
struct SharedCoachTip: Codable {
    let headline: String
    let summary: String
    /// "gemini" | "onDevice" | "offlineFallback" | "usageLimited".
    let origin: String
    let generatedAt: Date

    /// The label under the tip.
    ///
    /// The widget must never imply Gemini wrote something the rules produced.
    /// That rule is enforced on the card by `CoachProvenance`; here it has to be
    /// enforced again, because a widget has no explanation sheet behind it and
    /// a wrong label would go uncorrected.
    var originLabel: String {
        switch origin {
        case "gemini":           return "Gemini"
        case "onDevice":         return "On-device"
        case "offlineFallback":  return "Offline suggestion"
        case "usageLimited":     return "On-device · AI limit reached"
        default:                 return "Suggestion"
        }
    }

    var originIcon: String {
        switch origin {
        case "gemini":          return "sparkles"
        case "onDevice":        return "iphone"
        case "offlineFallback": return "wifi.slash"
        case "usageLimited":    return "gauge.with.dots.needle.33percent"
        default:                return "lightbulb"
        }
    }

    /// Yesterday's advice is not advice.
    ///
    /// The app clears the tip when it changes, but a widget can outlive the
    /// process that wrote it — an old tip left on a lock screen looks current,
    /// and coaching that looks current when it isn't is worse than none.
    var isStale: Bool {
        Date().timeIntervalSince(generatedAt) > 24 * 60 * 60
    }
}

enum SharedCoachTipStore {
    static let appGroup = "group.uk.co.prolineroofingandsolar.life"
    static let key = "life_widget_coach_tip"

    static func read() -> SharedCoachTip? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let tip = try? decoder.decode(SharedCoachTip.self, from: data) else { return nil }
        return tip.isStale ? nil : tip
    }
}
