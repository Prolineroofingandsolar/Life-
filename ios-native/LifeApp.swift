import SwiftUI
import FirebaseCore

@main
struct LifeApp: App {

    @State private var appState = AppState()
    @State private var authManager = AuthManager()

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(authManager)
                .tint(Color(hex: "#30d158"))
        }
    }
}
