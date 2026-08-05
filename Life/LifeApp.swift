import SwiftUI

@main
struct LifeApp: App {

    @State private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Belt and braces. By the time this body runs the `@State`/`@StateObject`
        // defaults above have already been constructed and one of them will have
        // configured Firebase via `FirebaseBootstrap`. This call covers the case
        // where neither of them touches Firebase, and is a no-op otherwise.
        FirebaseBootstrap.configureIfNeeded()
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
                    case .inactive, .background:
                        // Saves are debounced by 0.4s and uploads by a further
                        // 2s. Leaving the foreground is exactly when that
                        // window gets cut short, so it's forced closed here.
                        appState.flushPendingWrites()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
