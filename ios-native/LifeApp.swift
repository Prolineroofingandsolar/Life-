import SwiftUI

@main
struct LifeApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .tint(Color(hex: "#30d158"))
        }
    }
}
