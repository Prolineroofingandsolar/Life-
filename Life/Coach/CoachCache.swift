import Foundation

// MARK: - Coach Cache

/// Remembers what the coach already said, so it isn't paid for twice — and
/// forgets it the moment the data it was based on stops being true.
///
/// The cache key is `CoachContext.materialHash`: the data the advice was based
/// on, with every timestamp stripped. That last part is the whole design.
/// Timestamps move constantly — a foreground poll stamps `lastSyncedAt` every
/// two minutes whether or not anything arrived — so keying on one turns a cache
/// into a rate-limited passthrough that costs a model call per poll and returns
/// the same sentence each time. Timestamps are *stored beside* the cached output
/// and shown to the user; they are never part of the key.
///
/// The inverse failure is the one this rewrite fixes. The old key was built from
/// the context alone, and the context read some figures directly from the stored
/// models. A health sync that changed sleep from "not recorded" to "7h 51m"
/// could leave the key untouched, and the card went on advising from a night it
/// no longer had. Now a completed sync compares snapshots and supersedes
/// anything built on the old one — see `snapshotDidChange(to:)`.
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
        static let recommendation = "coach_recommendation_v2"
        static let morning = "coach_briefing_morning_v2"
        static let evening = "coach_briefing_evening_v2"
        static let dismissedHashes = "coach_dismissed_hashes_v1"
        /// Entries written by the previous scheme, cleared once on first use.
        static let legacy = [
            "coach_recommendation_v1", "coach_briefing_morning_v1", "coach_briefing_evening_v1"
        ]
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

    // MARK: Stored shapes

    /// A recommendation and the exact situation it was produced from.
    ///
    /// Both hashes are kept. `contextHash` answers "is this still the same
    /// question?"; `snapshotHash` answers "are the health figures behind it
    /// still the ones on screen?". They usually move together, and the times
    /// they don't are the times a user sees two different stories about the
    /// same morning.
    struct StoredRecommendation: Codable, Equatable {
        var recommendation: CoachRecommendation
        var contextHash: String
        var snapshotHash: String
        /// When the health figures behind this were last measured, for the
        /// "Based on data updated …" line. Stored, never keyed on.
        var snapshotTakenAt: Date?
        var storedAt: Date
    }

    /// A briefing, plus whether the day has since contradicted it.
    struct StoredBriefing: Codable, Equatable {
        var briefing: CoachBriefing
        /// The overnight figures at the time it was written.
        var overnightHash: String
        var snapshotTakenAt: Date?

        /// True when sleep or recovery has changed since this was written.
        ///
        /// Not a reason to regenerate — a briefing is a statement about a
        /// morning, and a second briefing about the same morning is worse than
        /// one slightly behind. It is a reason to *say so*, which is what the
        /// card does with it.
        var isOutdated: Bool = false
    }

    // MARK: Recommendations

    /// The stored recommendation, if it was built from this same data, from the
    /// health figures currently on screen, and hasn't been dismissed.
    func recommendation(
        for context: CoachContext,
        snapshot: HealthSnapshot? = nil
    ) -> StoredRecommendation? {
        clearLegacyEntriesOnce()

        guard let data = defaults.data(forKey: Key.recommendation),
              let cached = try? Self.decoder.decode(StoredRecommendation.self, from: data),
              cached.contextHash == context.materialHash,
              !isDismissed(context.materialHash)
        else { return nil }

        // The second gate, and the one the context hash can miss. Advice built
        // before a sync landed is not advice about the data now being shown.
        if let snapshot, !cached.snapshotHash.isEmpty, cached.snapshotHash != snapshot.materialHash {
            return nil
        }

        return cached
    }

    func store(
        _ recommendation: CoachRecommendation,
        for context: CoachContext,
        snapshot: HealthSnapshot? = nil
    ) {
        let cached = StoredRecommendation(
            recommendation: recommendation,
            contextHash: context.materialHash,
            snapshotHash: snapshot?.materialHash ?? "",
            snapshotTakenAt: snapshot?.lastSyncedAt,
            storedAt: Date()
        )
        if let data = try? Self.encoder.encode(cached) {
            defaults.set(data, forKey: Key.recommendation)
        }
    }

    /// Drops the stored recommendation. Used when the data behind it has moved
    /// on, and by "Clear coach history".
    func invalidateRecommendation() {
        defaults.removeObject(forKey: Key.recommendation)
    }

    // MARK: Sync invalidation

    /// Called when a health sync has finished and materially changed things.
    ///
    /// A recommendation is superseded outright: its whole job is to say what to
    /// do *now*, and "now" just changed. A briefing is not regenerated — one per
    /// morning, that was the deal — but if the overnight figures moved, it is
    /// flagged so the card can say the numbers have since been updated instead
    /// of quietly presenting figures the Health tab disagrees with.
    ///
    /// Returns whether anything was actually invalidated, so a caller can decide
    /// whether a refresh is worth triggering.
    @discardableResult
    func snapshotDidChange(to snapshot: HealthSnapshot) -> Bool {
        var changed = false

        if let data = defaults.data(forKey: Key.recommendation),
           let cached = try? Self.decoder.decode(StoredRecommendation.self, from: data),
           !cached.snapshotHash.isEmpty,
           cached.snapshotHash != snapshot.materialHash {
            invalidateRecommendation()
            changed = true
        }

        for key in [Key.morning, Key.evening] {
            guard let data = defaults.data(forKey: key),
                  var stored = try? Self.decoder.decode(StoredBriefing.self, from: data),
                  !stored.overnightHash.isEmpty,
                  stored.overnightHash != snapshot.overnightHash,
                  !stored.isOutdated
            else { continue }
            stored.isOutdated = true
            if let encoded = try? Self.encoder.encode(stored) {
                defaults.set(encoded, forKey: key)
                changed = true
            }
        }

        return changed
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
    /// morning. One per day, then it stands — but see `isOutdated`, which is how
    /// "stands" stops short of "keeps asserting figures that have since been
    /// corrected".
    ///
    /// The day check uses the *snapshot's* day key where one is given, so the
    /// briefing rolls over on the same boundary as everything else rather than
    /// on `Calendar.current` resolved separately here.
    func briefing(
        kind: CoachBriefing.Kind,
        on date: Date = Date(),
        snapshot: HealthSnapshot? = nil
    ) -> StoredBriefing? {
        clearLegacyEntriesOnce()

        let key = kind == .morning ? Key.morning : Key.evening
        guard let data = defaults.data(forKey: key),
              var stored = try? Self.decoder.decode(StoredBriefing.self, from: data)
        else { return nil }

        let sameDay: Bool
        if let snapshot {
            sameDay = DayKey.string(for: stored.briefing.generatedAt) == snapshot.dayKey
        } else {
            sameDay = calendar.isDate(stored.briefing.generatedAt, inSameDayAs: date)
        }
        guard sameDay else { return nil }

        // Recomputed on read as well as on sync. A background refresh can land
        // while the app isn't running to be told about it.
        if let snapshot, !stored.overnightHash.isEmpty,
           stored.overnightHash != snapshot.overnightHash {
            stored.isOutdated = true
        }
        return stored
    }

    func store(_ briefing: CoachBriefing, snapshot: HealthSnapshot? = nil) {
        let key = briefing.kind == .morning ? Key.morning : Key.evening
        let stored = StoredBriefing(
            briefing: briefing,
            overnightHash: snapshot?.overnightHash ?? "",
            snapshotTakenAt: snapshot?.lastSyncedAt,
            isOutdated: false
        )
        if let data = try? Self.encoder.encode(stored) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: Clearing

    /// Wipes everything the coach has said. Backs "Clear coach history" in
    /// settings, and runs on sign-out so one account's advice never appears
    /// under another's.
    func clear() {
        ([Key.recommendation, Key.morning, Key.evening, Key.dismissedHashes] + Key.legacy)
            .forEach { defaults.removeObject(forKey: $0) }
    }

    /// Removes entries written under the previous key scheme.
    ///
    /// They decode to a different shape, so leaving them would mean a dead
    /// blob per key sitting in `UserDefaults` for the life of the install. Once
    /// per process is enough; this runs on the first read of either kind.
    private func clearLegacyEntriesOnce() {
        guard !hasClearedLegacy else { return }
        hasClearedLegacy = true
        Key.legacy.forEach { defaults.removeObject(forKey: $0) }
    }

    private var hasClearedLegacy = false

    /// Clears the cache from outside the main actor, for UI test setup.
    ///
    /// A UI test that inherited the previous run's dismissed suggestion would
    /// fail for a reason having nothing to do with the code under test, and
    /// the failure would look intermittent rather than caused.
    nonisolated static func resetForTesting(defaults: UserDefaults = .standard) {
        ([Key.recommendation, Key.morning, Key.evening, Key.dismissedHashes] + Key.legacy)
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
