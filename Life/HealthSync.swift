import Foundation

// MARK: - Health Sync

/// The single place that decides where health data comes from.
///
/// Fitbit wins when it's connected, because it's the device actually on the
/// wrist — Apple Health would otherwise contribute an iPhone-only step count
/// that's lower than the truth, and `mergeHealthDays` would let whichever synced
/// last overwrite the other. Without one authority the two sources ping-pong.
///
/// Both Today (every five minutes) and the Health tab (on demand) route through
/// here so they can't disagree about the answer.
@MainActor
enum HealthSync {

    enum Source: String {
        case fitbit = "Fitbit"
        case appleHealth = "Apple Health"
        case none = "no source"

        /// The provider this source corresponds to, so every screen naming it
        /// spells it the same way. Nil for `.none`, which isn't a provider.
        var provider: HealthProvider? {
            switch self {
            case .fitbit:      return .fitbit
            case .appleHealth: return .appleHealth
            case .none:        return nil
            }
        }

        /// What the user reads. Routes through `HealthProvider` so "Fitbit",
        /// "Google Health" and "Google Fit" can't reappear as three names for
        /// one thing.
        var displayName: String { provider?.displayName ?? "No source connected" }

        /// The fuller attribution, for the Sources card and data check screen.
        var detailedName: String { provider?.detailedName ?? "No source connected" }
    }

    /// The device the user has chosen, falling back to what's actually
    /// available.
    ///
    /// An explicit choice is honoured even when the other source is also
    /// connected — that's the whole point of choosing. It's only ignored when
    /// the chosen device isn't there at all, because reporting no steps would
    /// be worse than reporting the other device's.
    static func source(for settings: HealthSettings) -> Source {
        switch settings.stepSource {
        case .fitbit where GoogleHealthService.shared.isConnected:
            return .fitbit
        case .iphone where HKHealthStoreAvailability.isAvailable:
            return .appleHealth
        default:
            return automaticSource
        }
    }

    /// Fitbit whenever it's connected: it's the device actually on the wrist,
    /// and Apple Health would otherwise contribute an iPhone-only step count
    /// that's lower than the truth.
    static var automaticSource: Source {
        if GoogleHealthService.shared.isConnected { return .fitbit }
        if HKHealthStoreAvailability.isAvailable { return .appleHealth }
        return .none
    }

    struct Outcome {
        var source: Source
        var dayCount: Int
        /// Nil when everything worked. Shown to the user verbatim, so it should
        /// say what to do, not just what broke.
        var message: String?
    }

    /// Pulls `daysBack` days from whichever source is active and merges the
    /// result into `appState`.
    ///
    /// Never throws — a background refresh that blows up shouldn't take a screen
    /// with it. Problems come back in `message`.
    @discardableResult
    static func run(
        appState: AppState,
        healthKit: HealthKitManager,
        daysBack: Int
    ) async -> Outcome {
        switch source(for: appState.healthSettings) {
        case .fitbit:      return await syncFitbit(appState: appState, daysBack: daysBack)
        case .appleHealth: return await syncAppleHealth(appState: appState, healthKit: healthKit, daysBack: daysBack)
        case .none:        return Outcome(source: .none, dayCount: 0, message: nil)
        }
    }

    /// How stale data has to be before returning to the app triggers a fetch.
    ///
    /// Short enough that the figures on screen are current, long enough that
    /// flicking between apps doesn't produce a sync per switch — which on the
    /// Fitbit path would spend the hourly request budget on nothing.
    private static let stalenessThreshold: TimeInterval = 2 * 60

    /// Syncs only if the last one was long enough ago to be worth it.
    ///
    /// Called when the app comes back to the foreground, which can happen many
    /// times a minute.
    @discardableResult
    static func runIfStale(appState: AppState) async -> Outcome? {
        let settings = appState.healthSettings
        if let until = settings.rateLimitedUntil, until > Date() { return nil }
        if let last = settings.lastSyncedAt,
           Date().timeIntervalSince(last) < stalenessThreshold { return nil }

        return await run(
            appState: appState,
            healthKit: HealthKitManager.shared,
            daysBack: settings.hasBackfilled ? 7 : 365
        )
    }

    // MARK: Fitbit

    private static func syncFitbit(appState: AppState, daysBack: Int) async -> Outcome {
        do {
            // Fans out across a dozen data types, each paginated — sleep is
            // capped at 25 points per page — so a year-long pull is a lot of
            // requests against an hourly budget that a long sync can exhaust.
            //
            // Whatever didn't arrive last time goes first this time. The order
            // used to be fixed, so once the budget ran out it ran out at the
            // same point on every sync, and the metrics after that point were
            // never fetched at all — not occasionally, never.
            let settings = appState.healthSettings
            let result = try await GoogleHealthService.shared.sync(
                daysBack: daysBack,
                retryFirst: settings.lastSyncSkipped + settings.lastSyncFailures,
                syncedThrough: settings.metricSyncedThrough
            )
            appState.mergeHealthDays(result.days)
            appState.mergeSleepNights(result.nights)
            appState.mergeSteps(result.steps)

            let retryAt = result.rateLimitedRetryAfter.map { retryAfter in
                Date().addingTimeInterval(TimeInterval(retryAfter ?? 3600))
            }

            appState.setHealthSettings {
                $0.hasBackfilled = true
                $0.lastSyncedAt = Date()
                $0.lastSyncSource = Source.fitbit.rawValue
                $0.lastSyncFailures = result.failures
                $0.lastSyncSkipped = result.skipped
                $0.rateLimitedUntil = retryAt
                // Merged, not replaced: this run only reports watermarks for
                // the metrics it actually fetched, and the ones it skipped must
                // keep the marks they already had or they'd re-download their
                // whole history on the next attempt.
                $0.metricSyncedThrough.merge(result.syncedThrough) { _, new in new }
            }

            return Outcome(
                source: .fitbit,
                dayCount: result.days.count,
                message: message(for: result, isFirstSync: settings.metricSyncedThrough.isEmpty)
            )
        } catch {
            let text = (error as? GoogleHealthError)?.errorDescription ?? error.localizedDescription
            if let healthError = error as? GoogleHealthError,
               case .rateLimited(let retryAfter) = healthError {
                appState.setHealthSettings {
                    $0.rateLimitedUntil = Date().addingTimeInterval(TimeInterval(retryAfter ?? 3600))
                }
            }
            return Outcome(source: .fitbit, dayCount: 0, message: text)
        }
    }

    /// What to tell the user about a partial sync.
    ///
    /// A metric that was refused and a metric that was never reached read the
    /// same on a chart — a gap — but they need opposite responses, so they are
    /// never lumped together here. Running out of quota isn't a fault to report
    /// as one; it's a queue, and it says where in the queue it stopped.
    private static func message(
        for result: GoogleHealthService.SyncResult,
        isFirstSync: Bool
    ) -> String? {
        var parts: [String] = []

        // Only worth saying on a first sync. Once the app holds history, a sync
        // that returns nothing means there was nothing new since the last one —
        // which is the normal, correct outcome of an incremental fetch, not a
        // fault to warn about.
        if isFirstSync && result.days.isEmpty && result.steps.isEmpty && result.nights.isEmpty {
            parts.append("Fitbit returned no data. If you've only just set the device up, it may not have synced to Fitbit's servers yet.")
        }

        if !result.failures.isEmpty {
            parts.append("These didn't come through: \(result.failures.joined(separator: ", ")).")
        }

        if result.rateLimitedRetryAfter != nil {
            let waited = result.rateLimitedRetryAfter.flatMap { $0 }
            let when = waited.map { seconds -> String in
                let minutes = max(1, Int((Double(seconds) / 60).rounded(.up)))
                return "in \(minutes) minute\(minutes == 1 ? "" : "s")"
            } ?? "in an hour"

            if result.skipped.isEmpty {
                parts.append("Google's hourly request limit was reached. Try again \(when).")
            } else {
                parts.append(
                    "Google's hourly request limit was reached, so \(result.skipped.joined(separator: ", ")) "
                    + "weren't fetched. Nothing is wrong with them — sync again \(when) and they go first."
                )
            }
        } else if !result.skipped.isEmpty {
            parts.append("Not fetched this time: \(result.skipped.joined(separator: ", ")). They go first next sync.")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Apple Health

    private static func syncAppleHealth(
        appState: AppState,
        healthKit: HealthKitManager,
        daysBack: Int
    ) async -> Outcome {
        // Deliberately not gated on the result: HealthKit reports success even
        // when a type is denied, and a previously-granted read still works if
        // this call errors. Queries simply return empty without access.
        _ = await healthKit.requestPermissions()

        let days = await healthKit.fetchDailyMetrics(daysBack: daysBack)
        let steps = await healthKit.fetchDailySteps(daysBack: daysBack)

        appState.mergeHealthDays(Array(days.values))
        appState.mergeSteps(steps)
        appState.setHealthSettings {
            $0.hasBackfilled = true
            $0.lastSyncedAt = Date()
            $0.lastSyncSource = Source.appleHealth.rawValue
            // HealthKit reports success even for denied types, so there's no
            // per-metric failure list to record here — an empty list means
            // "nothing known to have failed", not "everything arrived".
            $0.lastSyncFailures = []
        }

        let message = (days.isEmpty && steps.isEmpty)
            ? "Apple Health returned nothing. Check your tracker is writing into the Health app, and that Life has read access under Settings ▸ Health ▸ Data Access & Devices."
            : nil
        return Outcome(source: .appleHealth, dayCount: days.count, message: message)
    }
}

/// Tiny shim so `HealthSync` can ask about HealthKit without importing it and
/// forcing every caller to do the same.
enum HKHealthStoreAvailability {
    static var isAvailable: Bool { HealthKitManager.isHealthDataAvailable }
}
