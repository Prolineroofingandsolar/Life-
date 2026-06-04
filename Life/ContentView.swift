import SwiftUI

// MARK: - App Tab

enum AppTab: String, CaseIterable {
    case today, tasks, train, habits, body, money, travel

    var label: String {
        switch self {
        case .today:   return "Today"
        case .tasks:   return "Tasks"
        case .train:   return "Train"
        case .habits:  return "Habits"
        case .body:    return "Body"
        case .money:   return "Money"
        case .travel:  return "Travel"
        }
    }

    var icon: String {
        switch self {
        case .today:   return "sun.max.fill"
        case .tasks:   return "checkmark.circle.fill"
        case .train:   return "dumbbell.fill"
        case .habits:  return "chart.bar.fill"
        case .body:    return "figure.stand"
        case .money:   return "dollarsign.circle.fill"
        case .travel:  return "map.fill"
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

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tag(AppTab.today)
                TasksView()
                    .tag(AppTab.tasks)
                TrainView()
                    .tag(AppTab.train)
                HabitsView()
                    .tag(AppTab.habits)
                BodyView()
                    .tag(AppTab.body)
                MoneyView()
                    .tag(AppTab.money)
                WorldMapView()
                    .tag(AppTab.travel)
            }
            .toolbar(.hidden, for: .tabBar)
            // Reserve space so screen content scrolls above the pill
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 84)
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

            FloatingTabBar(selectedTab: $selectedTab, isCompact: isCompact)
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
    @Namespace private var pillAnimation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    isCompact: isCompact,
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

// MARK: - Tab Button

private struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let isCompact: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    private var showLabel: Bool { isSelected && !isCompact }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
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
