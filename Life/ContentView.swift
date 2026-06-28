import SwiftUI

// MARK: - App Tab

enum AppTab: String, CaseIterable {
    case today, tasks, train, habits, more

    var label: String {
        switch self {
        case .today:   return "Today"
        case .tasks:   return "Tasks"
        case .train:   return "Train"
        case .habits:  return "Habits"
        case .more:    return "More"
        }
    }

    var icon: String {
        switch self {
        case .today:   return "sun.max.fill"
        case .tasks:   return "checkmark.circle.fill"
        case .train:   return "dumbbell.fill"
        case .habits:  return "chart.bar.fill"
        case .more:    return "ellipsis"
        }
    }
}

// MARK: - Root View (auth gate)

struct RootView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var authManager: AuthManager

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
            VStack(spacing: 24) {
                Image("life_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                ProgressView()
                    .scaleEffect(1.2)
            }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: AppTab = .today
    @State private var showActiveWorkout = false

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tag(AppTab.today)
                    .tabItem { Label(AppTab.today.label, systemImage: AppTab.today.icon) }
                TasksView()
                    .tag(AppTab.tasks)
                    .tabItem { Label(AppTab.tasks.label, systemImage: AppTab.tasks.icon) }
                TrainView()
                    .tag(AppTab.train)
                    .tabItem { Label(AppTab.train.label, systemImage: AppTab.train.icon) }
                HabitsView()
                    .tag(AppTab.habits)
                    .tabItem { Label(AppTab.habits.label, systemImage: AppTab.habits.icon) }
                MoreView()
                    .tag(AppTab.more)
                    .tabItem { Label(AppTab.more.label, systemImage: AppTab.more.icon) }
            }
            .tint(Color(hex: "#30d158"))

            // Global active workout banner shown on non-Train tabs
            if selectedTab != .train, let session = appState.activeSession {
                ActiveWorkoutBanner(sessionName: session.name) {
                    showActiveWorkout = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: appState.activeSession?.id)
        .sheet(isPresented: $showActiveWorkout) {
            if let session = appState.activeSession {
                ActiveWorkoutView(isPresented: $showActiveWorkout, sessionId: session.id)
            }
        }
        .onOpenURL { url in
            guard url.scheme == "life" else { return }
            switch url.host {
            case "tasks":  selectedTab = .tasks
            case "habits": selectedTab = .habits
            default:       break
            }
        }
    }
}

// MARK: - Active Workout Banner (shown on non-Train tabs)

private struct ActiveWorkoutBanner: View {
    let sessionName: String
    let onTap: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: "#30d158"))
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                Text(sessionName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("Resume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color(hex: "#30d158"))
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(hex: "#30d158"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .onAppear { pulse = true }
    }
}
