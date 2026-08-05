import Foundation

// MARK: - Coach Usage

/// What the coach has cost this month, recorded on the device.
///
/// The server keeps the authoritative counters and enforces the ceiling — a
/// limit the client polices is not a limit, since a bug or a reinstall walks
/// straight past it. This copy exists so the settings screen can show a figure
/// without a network round trip, and so the app can stop *asking* once it knows
/// the answer will be refused.
///
/// The two can disagree, briefly and harmlessly: this one is updated from each
/// response, the server's from each call. The server's is the one that decides.
@MainActor
final class CoachUsage {

    static let shared = CoachUsage()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let month = "coach_usage_month_v1"
        static let calls = "coach_usage_calls_v1"
        static let promptTokens = "coach_usage_prompt_tokens_v1"
        static let outputTokens = "coach_usage_output_tokens_v1"
        static let cost = "coach_usage_cost_v1"
        static let ceiling = "coach_usage_ceiling_v1"
    }

    struct Snapshot: Equatable {
        var calls: Int
        var promptTokens: Int
        var outputTokens: Int
        var cost: Double
        var ceiling: Double

        var isOverCeiling: Bool { ceiling > 0 && cost >= ceiling }

        /// For the settings row. Sub-penny figures round to "under 1p" rather
        /// than "£0.00", which reads as free rather than as cheap.
        var costDescription: String {
            if cost <= 0 { return "Nothing yet" }
            if cost < 0.01 { return "Under 1p" }
            return String(format: "£%.2f", cost)
        }
    }

    /// The current month as `2026-08`, in UTC to match the server's key.
    private func monthKey(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Zeroes the counters when the month turns.
    ///
    /// Checked on read rather than scheduled, because a timer that has to fire
    /// at midnight on the first of the month is a timer that will eventually
    /// not fire — the app may not be running, and the counters would carry into
    /// a month they don't belong to.
    private func rolloverIfNeeded(_ now: Date = Date()) {
        let current = monthKey(now)
        guard defaults.string(forKey: Key.month) != current else { return }
        defaults.set(current, forKey: Key.month)
        defaults.set(0, forKey: Key.calls)
        defaults.set(0, forKey: Key.promptTokens)
        defaults.set(0, forKey: Key.outputTokens)
        defaults.set(0.0, forKey: Key.cost)
    }

    func snapshot(now: Date = Date()) -> Snapshot {
        rolloverIfNeeded(now)
        return Snapshot(
            calls: defaults.integer(forKey: Key.calls),
            promptTokens: defaults.integer(forKey: Key.promptTokens),
            outputTokens: defaults.integer(forKey: Key.outputTokens),
            cost: defaults.double(forKey: Key.cost),
            ceiling: defaults.double(forKey: Key.ceiling)
        )
    }

    /// Adds one completed call.
    func record(promptTokens: Int, outputTokens: Int, cost: Double, now: Date = Date()) {
        rolloverIfNeeded(now)
        defaults.set(defaults.integer(forKey: Key.calls) + 1, forKey: Key.calls)
        defaults.set(defaults.integer(forKey: Key.promptTokens) + promptTokens, forKey: Key.promptTokens)
        defaults.set(defaults.integer(forKey: Key.outputTokens) + outputTokens, forKey: Key.outputTokens)
        defaults.set(defaults.double(forKey: Key.cost) + cost, forKey: Key.cost)
    }

    /// The server's ceiling, learned from a response rather than configured
    /// twice. Two copies of the same number are two numbers that can disagree.
    func setCeiling(_ ceiling: Double) {
        defaults.set(ceiling, forKey: Key.ceiling)
    }

    /// Whether it's worth making a call at all.
    ///
    /// Not a substitute for the server's check — it's a way to avoid a round
    /// trip that is certain to be refused, and to let the UI say why before the
    /// user presses anything.
    func canAffordCall(now: Date = Date()) -> Bool {
        !snapshot(now: now).isOverCeiling
    }

    func reset() {
        [Key.month, Key.calls, Key.promptTokens, Key.outputTokens, Key.cost]
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
