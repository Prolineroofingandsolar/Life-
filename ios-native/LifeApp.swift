import SwiftUI
import FirebaseCore

@main
struct LifeApp: App {

    @State private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboarding_complete")

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
                .tint(AppTheme.primary)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                        .environment(appState)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.applyPendingWidgetCompletions()
                HabitReminderManager.shared.syncReminders(for: appState.habits)
            }
        }
    }
}
