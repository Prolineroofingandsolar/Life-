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
        NotificationsManager.shared.registerHabitCategories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environmentObject(authManager)
                .tint(Color(hex: "#30d158"))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.applyPendingWidgetCompletions()
                HabitReminderManager.shared.syncReminders(for: appState.habits)
            }
        }
    }
}
