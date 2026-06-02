import SwiftUI
import FirebaseCore

@main
struct LifeApp: App {

    @State private var appState = AppState()
    @State private var authManager = AuthManager()

    init() {
        FirebaseApp.configure()
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
