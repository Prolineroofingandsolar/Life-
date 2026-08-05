import Foundation

// MARK: - Coach Cache

/// Remembers what the coach already said, so it isn't paid for twice.
///
/// The cache key is `CoachContext.materialHash` — the data the advice was based
/// on, with the timestamp excluded. If the sleep, steps, tasks and habits are
/// unchanged, the advice would be unchanged too, so the stored answer is
/// returned and no call is made. Opening the Today screen four times in a
/// morning costs one request, not four, and that single fact is most of the
/// difference between pennies a month and pounds.
///
/// Stored in `UserDefaults` rather than on `StateSnapshot` on purpose. The
/// snapshot is uploaded to Firestore as one document with a hard 1 MB ceiling
/// (see `FirestoreSync.SyncError.payloadTooLarge`), and coach output is
/// regenerable, device-local and worthless on another phone — exactly the kind
/// of thing that shouldn't be spending that budget.
@MainActor
final class CoachCache {

    static let shared = CoachCache()

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    private enum Key {
        static let recommendation = "coach_recommendation_v1"
        static let morning = "coach_briefing_morning_v1"
        static let evening = "coach_briefing_evening_v1"
        static let dismissedHashes = "coach_dismissed_hashes_v1"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Recommendations

    private struct CachedRecommendation: Codable {
        var recommendation: CoachRecommendation
        var contextHash: String
    }

    /// The stored recommendation, if it was built from this same data and
    /// hasn't been dismissed.
    func recommendation(for context: CoachContext) -> CoachRecommendation? {
        guard let data = defaults.data(forKey: Key.recommendation),
              let cached = try? Self.decoder.decode(CachedRecommendation.self, from: data),
              cached.contextHash == context.materialHash,
              !isDismissed(context.materialHash)
        else { return nil }
        return cached.recommendation
    }

    func store(_ recommendation: CoachRecommendation, for context: CoachContext) {
        let cached = CachedRecommendation(
            recommendation: recommendation,
            contextHash: context.materialHash
        )
        if let data = try? Self.encoder.encode(cached) {
            defaults.set(data, forKey: Key.recommendation)
        }
    }

    // MARK: Dismissal

    /// "Not today" suppresses advice for *this data*, not forever.
    ///
    /// Keyed by hash so that dismissing a suggestion to walk doesn't also
    /// suppress the different suggestion that follows once something changes —
    /// while a dismissal does survive the screen being reopened, which a
    /// simple in-memory flag would not.
    func dismiss(_ context: CoachContext) {
        var hashes = dismissedHashes()
        hashes.insert(context.materialHash)
        // Bounded: this grows by one per dismissal and is never otherwise
        // pruned, and an unbounded set in UserDefaults is a slow leak.
        let trimmed = Array(hashes.suffix(50))
        defaults.set(trimmed, forKey: Key.dismissedHashes)
    }

    func isDismissed(_ hash: String) -> Bool {
        dismissedHashes().contains(hash)
    }

    private func dismissedHashes() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.dismissedHashes) ?? [])
    }

    // MARK: Briefings

    /// A briefing is cached for the day rather than by hash.
    ///
    /// Different from a recommendation on purpose: a morning briefing is a
    /// statement about the morning, and regenerating it at eleven because the
    /// step count moved would make it a different briefing about the same
    /// morning. One per day, then it stands.
    func briefing(kind: CoachBriefing.Kind, on date: Date = Date()) -> CoachBriefing? {
        let key = kind == .morning ? Key.morning : Key.evening
        guard let data = defaults.data(forKey: key),
              let cached = try? Self.decoder.decode(CoachBriefing.self, from: data),
              calendar.isDate(cached.generatedAt, inSameDayAs: date)
        else { return nil }
        return cached
    }

    func store(_ briefing: CoachBriefing) {
        let key = briefing.kind == .morning ? Key.morning : Key.evening
        if let data = try? Self.encoder.encode(briefing) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: Clearing

    /// Wipes everything the coach has said. Backs "Clear coach history" in
    /// settings, and runs on sign-out so one account's advice never appears
    /// under another's.
    func clear() {
        [Key.recommendation, Key.morning, Key.evening, Key.dismissedHashes]
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
