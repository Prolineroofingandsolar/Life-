import SwiftUI

// MARK: - App Tab

/// Habits used to hold the fourth slot. It moved into More ▸ Tracking when
/// Health took its place — five tabs is the comfortable maximum, and health
/// data is checked far more often than the habits list. The `life://habits`
/// widget link still works; it opens Habits as a sheet (see `ContentView`).
enum AppTab: String, CaseIterable {
    case today, tasks, train, health, more

    var label: String {
        switch self {
        case .today:   return "Today"
        case .tasks:   return "Tasks"
        case .train:   return "Train"
        case .health:  return "Health"
        case .more:    return "More"
        }
    }

    var icon: String {
        switch self {
        case .today:   return "sun.max.fill"
        case .tasks:   return "checkmark.circle.fill"
        case .train:   return "dumbbell.fill"
        case .health:  return "heart.fill"
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
        // `onChange` fires on a *change*, and the auth listener can resolve a
        // restored session before this view is on screen — at which point there
        // is no change left to observe. Cloud sync then never started: uploads
        // were skipped for want of a `cloudUserId`, and everything the user did
        // stayed on the phone while the app showed them as signed in. This
        // covers the already-signed-in case; `loadFromCloud` is safe to call
        // more than once for the same account.
        .task(id: authManager.user?.uid) {
            guard let uid = authManager.user?.uid else { return }
            await appState.loadFromCloud(userId: uid)
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
                    .background {
                        Circle()
                            .fill(AppTheme.brandGradient)
                            .frame(width: 168, height: 168)
                            .blur(radius: 44)
                            .opacity(0.35)
                    }
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(AppTheme.primary)
            }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: AppTab = .today
    /// Captured when the workout sheet opens so it survives `finishSession`
    /// nulling `activeSession` (otherwise the sheet goes blank white on Finish).
    @State private var presentedWorkout: PresentedWorkout?

    /// Habits lost its tab to Health; the habit widget's `life://habits` link
    /// presents it instead.
    @State private var showHabits = false

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tag(AppTab.today)
                .tabItem { tabLabel(.today) }
            TasksView()
                .tag(AppTab.tasks)
                .tabItem { tabLabel(.tasks) }
            TrainView()
                .tag(AppTab.train)
                .tabItem { tabLabel(.train) }
            HealthView()
                .tag(AppTab.health)
                .tabItem { tabLabel(.health) }
            MoreView()
                .tag(AppTab.more)
                .tabItem { tabLabel(.more) }
        }
        .tint(AppTheme.primary)
        // Global active workout banner shown on non-Train tabs.
        //
        // A `safeAreaInset` rather than a `ZStack` overlay. As an overlay the
        // banner sat on top of whatever was beneath it — in landscape, where
        // there is barely any vertical room to begin with, that was the first
        // row of content on every tab, permanently hidden behind it. An inset
        // shortens the scroll area instead, so the content moves down rather
        // than disappearing, and it scrolls to a position that can be reached.
        .safeAreaInset(edge: .top, spacing: 0) {
            if selectedTab != .train, let session = appState.activeSession {
                ActiveWorkoutBanner(sessionName: session.name) {
                    presentedWorkout = PresentedWorkout(id: session.id)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: appState.activeSession?.id)

        .sheet(item: $presentedWorkout) { workout in
            ActiveWorkoutView(
                isPresented: Binding(
                    get: { presentedWorkout != nil },
                    set: { if !$0 { presentedWorkout = nil } }
                ),
                sessionId: workout.id
            )
        }
        // Not wrapped in a NavigationStack — HabitsView brings its own.
        .sheet(isPresented: $showHabits) {
            HabitsView()
        }
        .onOpenURL { url in
            guard url.scheme == "life" else { return }
            switch url.host {
            case "tasks":  selectedTab = .tasks
            // Habits no longer has a tab, but the habit widget still links here,
            // so present it rather than dropping the tap on the floor.
            case "habits": showHabits = true
            // The coach widget links here. It shows a suggestion and nothing
            // else — the card on Today is where it can be acted on.
            case "coach":  selectedTab = .today
            default:       break
            }
        }
    }

    /// A tab item that names itself, says it is a tab, and says whether it is
    /// the current one.
    ///
    /// The symbol carries `accessibilityHidden` so VoiceOver never reads the SF
    /// Symbol name — "sun max fill" is an asset identifier, not a word anyone
    /// chose to say aloud. The label is set explicitly rather than left to be
    /// inferred, and the selected state goes on `accessibilityValue`, which is
    /// what makes the announcement "Today, tab, selected" instead of the bare
    /// "Selected" the tab bar was producing.
    private func tabLabel(_ tab: AppTab) -> some View {
        Label {
            Text(tab.label)
        } icon: {
            Image(systemName: tab.icon)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(tab.label)
        .accessibilityValue(selectedTab == tab ? "Selected" : "")
        .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint("Opens the \(tab.label) tab")
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
                    .fill(AppTheme.primary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                Text(sessionName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("Resume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout in progress: \(sessionName)")
        .accessibilityHint("Opens the active workout")
        .onAppear { pulse = true }
    }
}
