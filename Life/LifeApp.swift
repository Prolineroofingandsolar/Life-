import SwiftUI
import FirebaseCore

@main
struct LifeApp: App {

    @State private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
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
