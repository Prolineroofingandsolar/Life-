import SwiftUI

// MARK: - Root View (auth gate)

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if authManager.isLoading {
                SplashView()
            } else if !AuthManager.isFirebaseReady || authManager.isSignedIn {
                ContentView()
            } else {
                AuthView()
            }
        }
        .onChange(of: authManager.user) { _, user in
            if let user = user {
                Task { await appState.loadFromCloud(userId: user.uid) }
            } else {
                appState.disableCloudSync()
            }
        }
    }
}

// MARK: - Splash Screen

private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Color(hex: "#30d158"))
                ProgressView()
                    .scaleEffect(1.2)
            }
        }
    }
}

// MARK: - Main Tab View

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }

            TasksView()
                .tabItem {
                    Label("Tasks", systemImage: "checkmark.circle.fill")
                }

            TrainView()
                .tabItem {
                    Label("Train", systemImage: "dumbbell.fill")
                }

            HabitsView()
                .tabItem {
                    Label("Habits", systemImage: "chart.bar.fill")
                }

            BodyView()
                .tabItem {
                    Label("Body", systemImage: "figure.stand")
                }

            MoneyView()
                .tabItem {
                    Label("Money", systemImage: "dollarsign.circle.fill")
                }
        }
    }
}
