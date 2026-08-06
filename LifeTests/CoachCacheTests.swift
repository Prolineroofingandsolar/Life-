import Testing
import Foundation
@testable import Life

/// What the cache keeps, what it throws away, and — mostly — what it must not
/// throw away.
///
/// A coach cache has two ways to fail and they pull in opposite directions. Key
/// on too much (a timestamp, say) and every lookup misses: a two-minute
/// foreground poll becomes a paid model call every two minutes, all day, each
/// returning the same sentence. Key on too little and a completed health sync
/// leaves yesterday's advice on screen next to today's figures. Both were
/// present before these tests: the recommendation key was built from a context
/// that read some figures straight out of the store, so a sync could change what
/// the screen showed without changing the key.
@MainActor
struct CoachCacheTests {

    // MARK: Fixtures

    static func isolatedDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func context(steps: Int? = 4_000, taskId: String = "task-1") -> CoachContext {
        CoachContext(
            generatedAt: Date(),
            timeOfDay: .morning,
            goals: [],
            sleep: nil,
            recovery: nil,
            activity: CoachContext.Activity(
                steps: steps,
                stepGoal: 10_000,
                activeMinutes: nil,
                activeMinutesGoal: 30,
                isPartialDay: true,
                source: "Fitbit",
                quality: steps == nil ? .missing : .partial,
                state: steps == nil ? .missing : .partial
            ),
            training: nil,
            tasks: CoachContext.Tasks(
                importantRemaining: 1,
                totalRemainingToday: 1,
                nextDeadline: nil,
                topCandidates: [
                    .init(id: taskId, title: "A task", priority: "high", estimatedMinutes: 20, dueToday: true)
                ]
            ),
            habits: nil,
            dataWarnings: []
        )
    }

    static func recommendation(_ headline: String = "Take a 20-minute walk") -> CoachRecommendation {
        CoachRecommendation(
            headline: headline,
            summary: "You are short of your step goal.",
            category: .activity,
            actionType: .takeWalk,
            origin: .cloud
        )
    }

    static func briefing(
        _ kind: CoachBriefing.Kind = .morning,
        at date: Date = Date()
    ) -> CoachBriefing {
        CoachBriefing(
            kind: kind,
            headline: "A steady night",
            body: "You slept 7h 51m.",
            evidence: [],
            safetyNotice: nil,
            origin: .cloud,
            generatedAt: date,
            contextHash: ""
        )
    }

    static func snapshot(
        sleepMinutes: Int? = 471,
        steps: Int? = 4_000,
        syncedAt: Date? = Date()
    ) -> HealthSnapshot {
        var snapshot = HealthSnapshot(
            dayKey: Date().dayKey,
            generatedAt: Date(),
            timeZoneIdentifier: TimeZone.current.identifier
        )
        snapshot.hasConnectedSource = true
        snapshot.source = "Fitbit"
        snapshot.lastSyncedAt = syncedAt
        if let sleepMinutes {
            snapshot.sleepMinutes = HealthMetric(
                value: sleepMinutes, state: .ready, confidence: .high, dayKey: Date().dayKey
            )
        }
        if let steps {
            snapshot.steps = HealthMetric(
                value: steps, state: .partial, confidence: .high, dayKey: Date().dayKey
            )
        }
        return snapshot
    }

    // MARK: Hits and misses

    @Test("The same data reads back the stored answer")
    func identicalContextHits() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let context = Self.context()
        let snapshot = Self.snapshot()

        cache.store(Self.recommendation(), for: context, snapshot: snapshot)

        let hit = cache.recommendation(for: context, snapshot: snapshot)
        #expect(hit?.recommendation.headline == "Take a 20-minute walk")
    }

    @Test("Different data misses")
    func differentContextMisses() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let snapshot = Self.snapshot()

        cache.store(Self.recommendation(), for: Self.context(taskId: "task-1"), snapshot: snapshot)

        #expect(cache.recommendation(for: Self.context(taskId: "task-2"), snapshot: snapshot) == nil)
    }

    @Test("A later clock reading alone still hits")
    func timestampsAloneDoNotMiss() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let context = Self.context()
        let stored = Self.snapshot(syncedAt: Date().addingTimeInterval(-3600))

        cache.store(Self.recommendation(), for: context, snapshot: stored)

        // Same figures, synced again a moment ago. Every poll stamps
        // `lastSyncedAt` whether or not anything arrived; if that alone missed,
        // the cache would be a rate limiter that charges for each request.
        let polled = Self.snapshot(syncedAt: Date())
        #expect(cache.recommendation(for: context, snapshot: polled) != nil)
    }

    @Test("A changed health figure misses even when the context is identical")
    func changedSnapshotMisses() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let context = Self.context()

        cache.store(Self.recommendation(), for: context, snapshot: Self.snapshot(sleepMinutes: 471))

        // The context is byte-identical; only the health snapshot moved. The old
        // key would have hit here and gone on advising from a night the app no
        // longer had.
        let afterSync = Self.snapshot(sleepMinutes: 617)
        #expect(cache.recommendation(for: context, snapshot: afterSync) == nil)
    }

    @Test("A dismissed suggestion stays dismissed for that data")
    func dismissalSuppressesTheSameData() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let context = Self.context()
        let snapshot = Self.snapshot()

        cache.store(Self.recommendation(), for: context, snapshot: snapshot)
        cache.dismiss(context)

        #expect(cache.recommendation(for: context, snapshot: snapshot) == nil)
        // But only for that data. Something changing is what earns a new go.
        #expect(cache.isDismissed(Self.context(taskId: "task-2").materialHash) == false)
    }

    // MARK: Sync invalidation

    @Test("A sync that changes the figures supersedes the stored recommendation")
    func syncInvalidatesRecommendation() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let context = Self.context()

        cache.store(Self.recommendation(), for: context, snapshot: Self.snapshot(sleepMinutes: 471))
        let changed = cache.snapshotDidChange(to: Self.snapshot(sleepMinutes: 617))

        #expect(changed)
        // Advice built before the sync is not advice about the data now on
        // screen, and its whole job is to say what to do *now*.
        #expect(cache.recommendation(for: context, snapshot: Self.snapshot(sleepMinutes: 617)) == nil)
    }

    @Test("A sync that changes nothing leaves the cache alone")
    func unchangedSyncKeepsTheCache() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let context = Self.context()
        let snapshot = Self.snapshot()

        cache.store(Self.recommendation(), for: context, snapshot: snapshot)
        let changed = cache.snapshotDidChange(to: Self.snapshot(syncedAt: Date().addingTimeInterval(120)))

        #expect(changed == false)
        #expect(cache.recommendation(for: context, snapshot: snapshot) != nil)
    }

    // MARK: Briefings

    @Test("A briefing written today is reused today")
    func briefingIsReusedWithinTheDay() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let snapshot = Self.snapshot()

        cache.store(Self.briefing(), snapshot: snapshot)

        let stored = cache.briefing(kind: .morning, snapshot: snapshot)
        #expect(stored?.briefing.headline == "A steady night")
        #expect(stored?.isOutdated == false)
    }

    @Test("A briefing from yesterday is not today's briefing")
    func briefingDoesNotSurviveTheDayRollover() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        cache.store(Self.briefing(.morning, at: yesterday), snapshot: Self.snapshot())

        #expect(cache.briefing(kind: .morning, snapshot: Self.snapshot()) == nil)
    }

    @Test("Steps climbing during the day does not make a briefing outdated")
    func stepsDoNotOutdateABriefing() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        cache.store(Self.briefing(), snapshot: Self.snapshot(steps: 800))

        let later = Self.snapshot(steps: 9_400)
        let stored = cache.briefing(kind: .morning, snapshot: later)

        // A morning briefing is a statement about the morning. Walking during
        // the day is not a correction to it.
        #expect(stored != nil)
        #expect(stored?.isOutdated == false)
    }

    @Test("Overnight figures arriving late do make a briefing outdated")
    func lateSleepOutdatesABriefing() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        // Written before the tracker synced last night's sleep.
        cache.store(Self.briefing(), snapshot: Self.snapshot(sleepMinutes: nil))

        let stored = cache.briefing(kind: .morning, snapshot: Self.snapshot(sleepMinutes: 471))

        // Still returned — one briefing per morning, that was the deal — but
        // flagged, so the card can say the figures have since been updated
        // rather than quietly asserting ones the Health tab disagrees with.
        #expect(stored != nil)
        #expect(stored?.isOutdated == true)
    }

    @Test("A sync flags an existing briefing rather than replacing it")
    func syncFlagsBriefing() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        cache.store(Self.briefing(), snapshot: Self.snapshot(sleepMinutes: nil))

        _ = cache.snapshotDidChange(to: Self.snapshot(sleepMinutes: 471))

        let stored = cache.briefing(kind: .morning, snapshot: Self.snapshot(sleepMinutes: 471))
        #expect(stored?.briefing.headline == "A steady night")
        #expect(stored?.isOutdated == true)
    }

    @Test("Morning and evening are cached separately")
    func briefingKindsDoNotCollide() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let snapshot = Self.snapshot()

        cache.store(Self.briefing(.morning), snapshot: snapshot)

        #expect(cache.briefing(kind: .morning, snapshot: snapshot) != nil)
        #expect(cache.briefing(kind: .evening, snapshot: snapshot) == nil)
    }

    // MARK: Clearing

    @Test("Clearing removes everything, including dismissals")
    func clearRemovesEverything() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let context = Self.context()
        let snapshot = Self.snapshot()

        cache.store(Self.recommendation(), for: context, snapshot: snapshot)
        cache.store(Self.briefing(), snapshot: snapshot)
        cache.dismiss(context)

        cache.clear()

        #expect(cache.recommendation(for: context, snapshot: snapshot) == nil)
        #expect(cache.briefing(kind: .morning, snapshot: snapshot) == nil)
        #expect(cache.isDismissed(context.materialHash) == false)
    }

    // MARK: Provenance survives the round trip

    @Test("A cached local suggestion is not relabelled as Gemini output")
    func cachedOriginSurvives() {
        let cache = CoachCache(defaults: Self.isolatedDefaults())
        let context = Self.context()
        let snapshot = Self.snapshot()

        var local = Self.recommendation()
        local.origin = .local
        cache.store(local, for: context, snapshot: snapshot)

        let hit = cache.recommendation(for: context, snapshot: snapshot)
        // The silent fallback's whole problem was output that lied about where
        // it came from. Reading it back must not launder it.
        #expect(hit?.recommendation.origin == .local)
    }
}
