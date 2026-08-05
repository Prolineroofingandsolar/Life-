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

    // MARK: Fitbit

    private static func syncFitbit(appState: AppState, daysBack: Int) async -> Outcome {
        do {
            // Fans out across a dozen data types, each paginated — sleep is
            // capped at 25 points per page — so a year-long pull is a lot of
            // requests. Routine background syncs stay short deliberately.
            let result = try await GoogleHealthService.shared.sync(daysBack: daysBack)
            appState.mergeHealthDays(result.days)
            appState.mergeSleepNights(result.nights)
            appState.mergeSteps(result.steps)
            appState.setHealthSettings {
                $0.hasBackfilled = true
                $0.lastSyncedAt = Date()
                $0.lastSyncSource = Source.fitbit.rawValue
                $0.lastSyncFailures = result.failures
            }

            var message: String?
            if result.days.isEmpty && result.steps.isEmpty {
                message = "Fitbit returned no data. If you've only just set the device up, it may not have synced to Fitbit's servers yet."
            } else if !result.failures.isEmpty {
                message = "Synced, but these didn't come through: \(result.failures.joined(separator: ", "))."
            }
            return Outcome(source: .fitbit, dayCount: result.days.count, message: message)
        } catch {
            let text = (error as? GoogleHealthError)?.errorDescription ?? error.localizedDescription
            return Outcome(source: .fitbit, dayCount: 0, message: text)
        }
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
