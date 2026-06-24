import SwiftUI
import FirebaseCore

@main
struct LifeApp: App {

    @State private var appState = AppState()
    @StateObject private var authManager = AuthManager()

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        UITabBar.appearance().isHidden = true
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environmentObject(authManager)
                .tint(Color(hex: "#30d158"))
        }
    }
}
