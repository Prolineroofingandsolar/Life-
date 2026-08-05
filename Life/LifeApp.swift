import SwiftUI

@main
struct LifeApp: App {

    /// The shared instance rather than a fresh one, so the background refresh
    /// registered below reads and writes the same state the UI shows.
    @State private var appState = AppState.shared
    @StateObject private var authManager = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Belt and braces. By the time this body runs the `@State`/`@StateObject`
        // defaults above have already been constructed and one of them will have
        // configured Firebase via `FirebaseBootstrap`. This call covers the case
        // where neither of them touches Firebase, and is a no-op otherwise.
        FirebaseBootstrap.configureIfNeeded()

        // Has to happen here. `BGTaskScheduler.register` throws if called after
        // launch finishes, and iOS relaunches the app straight into the
        // background to deliver a HealthKit change — at which point no view has
        // appeared and anything wired up in `onAppear` doesn't exist yet.
        HealthBackgroundRefresh.register(appState: .shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environmentObject(authManager)
                .tint(AppTheme.primary)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Apply any habit completions queued by the widget.
                        appState.drainPendingHabitCompletions()
                        // Coming back to the app is the moment stale figures are
                        // most obvious, and nothing else triggered a sync here:
                        // the five-minute timer only starts once Today is on
                        // screen, so returning to any other tab showed whatever
                        // was last fetched.
                        Task { await HealthSync.runIfStale(appState: appState) }
                    case .inactive, .background:
                        // Saves are debounced by 0.4s and uploads by a further
                        // 2s. Leaving the foreground is exactly when that
                        // window gets cut short, so it's forced closed here.
                        appState.flushPendingWrites()
                        // A `BGAppRefreshTask` is one-shot. Leaving the
                        // foreground is the natural point to book the next one.
                        HealthBackgroundRefresh.schedule(appState: appState)
                    @unknown default:
                        break
                    }
                }
        }
    }
}
