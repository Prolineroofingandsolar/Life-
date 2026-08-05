import BackgroundTasks
import Foundation

// MARK: - Health Background Refresh

/// Keeps health data arriving while Life isn't open.
///
/// Two mechanisms, because the two sources are nothing alike.
///
/// **Apple Health** pushes. `HealthKitManager.startObservingHealthChanges`
/// registers observer queries and asks iOS to wake Life when new samples land —
/// including relaunching it if it has been terminated. This is the fast path,
/// and on a setup where the tracker writes into Apple Health it is the one that
/// matters.
///
/// **Google Health (Fitbit)** has to be polled: it's an HTTP API, nothing
/// notifies us. That's a `BGAppRefreshTask`, which iOS runs when it judges the
/// moment right rather than on a schedule we choose.
///
/// What that means in practice, stated plainly because the alternative is
/// disappointment: `earliestBeginDate` is a floor, not an appointment. iOS
/// decides the actual cadence from how often the app is used, battery level,
/// Low Power Mode, and whether Background App Refresh is switched on at all in
/// Settings. A regularly used app typically gets several runs a day. It will
/// not be every fifteen minutes, and no amount of asking changes that.
///
/// Fitbit's own lag sits on top of this and is usually the larger of the two.
/// Life reads from Google's servers, not from the band, so a reading only
/// exists to be fetched once the band has synced to the Fitbit app and the
/// Fitbit app has pushed it onward. Polling more often than that changes
/// nothing.
enum HealthBackgroundRefresh {

    /// Must match an entry in `BGTaskSchedulerPermittedIdentifiers` in
    /// Info.plist, or `register` traps at launch.
    static let taskIdentifier = "uk.co.prolineroofingandsolar.life.health-refresh"

    /// The earliest iOS is asked to consider running the task again.
    ///
    /// Fifteen minutes is the shortest interval the system entertains. Treat it
    /// as "as soon as you reasonably can", not as a period.
    private static let earliestInterval: TimeInterval = 15 * 60

    private static var isRegistered = false

    // MARK: Registration

    /// Registers the background task handler, then starts the observers.
    ///
    /// Called from `LifeApp.init()`, which is not main-actor isolated — so this
    /// isn't either, and the registration below runs synchronously. That matters:
    /// `BGTaskScheduler.register` throws if it happens after the app has
    /// finished launching, and iOS relaunches Life straight into the background
    /// to deliver a HealthKit change, at which point no view has appeared and
    /// anything wired up in `onAppear` doesn't exist yet.
    ///
    /// Starting the observers needs `AppState`, so it hops to the main actor and
    /// lands a moment later. Harmless — nothing can be delivered in that gap.
    static func register(appState: AppState) {
        guard !isRegistered else { return }
        isRegistered = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await handle(refreshTask, appState: appState)
            }
        }

        Task { @MainActor in
            applySettings(appState: appState)
        }
    }

    /// Brings the observers and the queued task into line with the user's
    /// setting. Called at launch and whenever the switch moves, so turning it
    /// off takes effect immediately rather than at the next launch.
    @MainActor
    static func applySettings(appState: AppState) {
        guard appState.healthSettings.backgroundRefreshEnabled else {
            HealthKitManager.shared.disableBackgroundDelivery()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }

        HealthKitManager.shared.startObservingHealthChanges {
            await runSync(appState: appState)
        }
        schedule(appState: appState)
    }

    // MARK: Scheduling

    /// Queues the next background refresh.
    ///
    /// Called when the app leaves the foreground and again at the start of each
    /// background run — a `BGAppRefreshTask` is one-shot, so a run that doesn't
    /// reschedule is the last one that ever happens.
    @MainActor
    static func schedule(appState: AppState) {
        guard appState.healthSettings.backgroundRefreshEnabled else { return }
        // Nothing to fetch on a Fitbit-less setup; Apple Health arrives through
        // the observers instead, and an empty wake-up still spends the budget.
        guard GoogleHealthService.shared.isConnected else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected in the simulator, which has no scheduler, and when the
            // user has switched Background App Refresh off system-wide. Neither
            // is a fault: the foreground sync still runs.
            print("[HealthBackgroundRefresh] couldn't schedule: \(error.localizedDescription)")
        }
    }

    // MARK: Running

    @MainActor
    private static func handle(_ task: BGAppRefreshTask, appState: AppState) async {
        // Queued first. If the work below overruns and iOS kills the task, the
        // next run is already booked — rescheduling only on success is how a
        // background refresh quietly stops forever.
        schedule(appState: appState)

        let work = Task { @MainActor in
            await runSync(appState: appState)
        }

        task.expirationHandler = { work.cancel() }

        await work.value
        task.setTaskCompleted(success: !work.isCancelled)
    }

    /// One sync, from whichever source is active, plus a flush so the result
    /// reaches the account rather than sitting in a debounce the app won't live
    /// long enough to serve.
    ///
    /// A short window on purpose. Background time is measured in seconds, and
    /// the incremental sync only asks each metric for what it hasn't already
    /// got, so a week is plenty to catch up on and cheap when there's nothing
    /// new. The full backfill stays a foreground job.
    @MainActor
    static func runSync(appState: AppState) async {
        guard appState.healthSettings.backgroundRefreshEnabled else { return }

        // Rate-limited by Google until a known time — waking to be refused
        // spends the wake-up and gets nothing.
        if let until = appState.healthSettings.rateLimitedUntil, until > Date() { return }

        // Guards against the observers firing for several types at once and
        // starting a pile of overlapping syncs, each re-requesting the same
        // window.
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        await HealthSync.run(
            appState: appState,
            healthKit: HealthKitManager.shared,
            daysBack: appState.healthSettings.hasBackfilled ? 7 : 30
        )

        // The upload is debounced by two seconds and the process may not exist
        // in two seconds.
        appState.flushPendingWrites()
    }

    @MainActor
    private static var isSyncing = false
}
