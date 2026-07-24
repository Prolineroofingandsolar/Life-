import SwiftUI
import FirebaseCore

@main
struct LifeApp: App {

    @State private var appState: AppState
    @StateObject private var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Firebase MUST be configured before anything that touches it.
        // Stored-property default values are evaluated before the init body,
        // so AppState/AuthManager are constructed here *after* configure()
        // rather than as inline defaults — otherwise AuthManager's init sees
        // an unconfigured Firebase, skips attaching its auth-state listener,
        // and sign-in silently never works.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        _appState = State(initialValue: AppState())
        _authManager = StateObject(wrappedValue: AuthManager())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environmentObject(authManager)
                .tint(AppTheme.primary)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // Apply any habit completions queued by the widget.
                        appState.drainPendingHabitCompletions()
                    }
                }
        }
    }
}
