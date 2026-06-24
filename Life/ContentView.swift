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

// MARK: - Content View

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: AppTab = .today
    @State private var isCompact = false
    @State private var expandWorkItem: DispatchWorkItem?
    @State private var showActiveWorkout = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tag(AppTab.today)
                    .toolbar(.hidden, for: .tabBar)
                TasksView()
                    .tag(AppTab.tasks)
                    .toolbar(.hidden, for: .tabBar)
                TrainView()
                    .tag(AppTab.train)
                    .toolbar(.hidden, for: .tabBar)
                HabitsView()
                    .tag(AppTab.habits)
                    .toolbar(.hidden, for: .tabBar)
                MoreView()
                    .tag(AppTab.more)
                    .toolbar(.hidden, for: .tabBar)
            }
            .toolbar(.hidden, for: .tabBar)
            .onAppear { UITabBar.appearance().isHidden = true }
            // Reserve space so screen content scrolls above the pill
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 84)
            }
            .sheet(isPresented: $showActiveWorkout) {
                if let session = appState.activeSession {
                    ActiveWorkoutView(isPresented: $showActiveWorkout, sessionId: session.id)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .global)
                    .onChanged { value in
                        let dy = value.translation.height
                        let dx = abs(value.translation.width)
                        guard abs(dy) > dx else { return }
                        if dy < -18 {
                            expandWorkItem?.cancel()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCompact = true }
                        } else if dy > 18 {
                            expandWorkItem?.cancel()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCompact = false }
                        }
                    }
                    .onEnded { _ in scheduleExpand() }
            )

            FloatingTabBar(selectedTab: $selectedTab, isCompact: isCompact, hasActiveWorkout: appState.activeSession != nil)
                .padding(.bottom, 10)
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

    private func scheduleExpand() {
        expandWorkItem?.cancel()
        let item = DispatchWorkItem {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isCompact = false }
        }
        expandWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    let isCompact: Bool
    var hasActiveWorkout: Bool = false
    @Namespace private var pillAnimation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    isCompact: isCompact,
                    badge: tab == .train && hasActiveWorkout,
                    namespace: pillAnimation
                ) {
                    HapticManager.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 6)
        .padding(.horizontal, 18)
    }
}

// MARK: - Active Session Banner

private struct ActiveSessionBanner: View {
    let session: WorkoutSession
    let onTap: () -> Void
    @State private var elapsed: Int = 0
    @State private var bannerTimer: Timer? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#FFD700").opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#FFD700"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text(elapsed.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Resume")
                    .font(.subheadline.bold())
                    .foregroundColor(Color(hex: "#FFD700"))
                Image(systemName: "chevron.up")
                    .font(.caption.bold())
                    .foregroundColor(Color(hex: "#FFD700"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "#FFD700").opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onAppear {
            elapsed = Int(Date().timeIntervalSince(session.startedAt))
            bannerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in elapsed += 1 }
        }
        .onDisappear { bannerTimer?.invalidate(); bannerTimer = nil }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let isCompact: Bool
    var badge: Bool = false
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var pulseBadge = false
    private var showLabel: Bool { isSelected && !isCompact }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(Color(hex: "#30d158").opacity(0.18))
                                .frame(height: 30)
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color(hex: "#30d158") : Color.secondary)
                            .frame(minWidth: 32, minHeight: 30)
                            .padding(.horizontal, showLabel ? 5 : 0)
                    }
                    if badge {
                        Circle()
                            .fill(Color(hex: "#30d158"))
                            .frame(width: 8, height: 8)
                            .scaleEffect(pulseBadge ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulseBadge)
                            .offset(x: -2, y: 2)
                            .onAppear { pulseBadge = true }
                    }
                }
                if showLabel {
                    Text(tab.label)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(hex: "#30d158"))
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isCompact)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }
}
