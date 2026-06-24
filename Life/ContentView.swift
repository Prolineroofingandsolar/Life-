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
    @State private var dragProgress: CGFloat = 0  // -1...1 fraction toward prev/next tab

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
            // Reserve space so content scrolls above the pill
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
                        let dx = value.translation.width
                        if abs(dy) > abs(dx) {
                            // Vertical — compact/expand pill
                            if dy < -18 {
                                expandWorkItem?.cancel()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCompact = true }
                            } else if dy > 18 {
                                expandWorkItem?.cancel()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCompact = false }
                            }
                        } else {
                            // Horizontal — animate pill drag progress (-1 = left, +1 = right)
                            let tabs = AppTab.allCases
                            let currentIdx = tabs.firstIndex(of: selectedTab) ?? 0
                            let screenWidth = UIScreen.main.bounds.width
                            let raw = -dx / screenWidth
                            // Clamp so we don't go past first/last tab
                            let clamped = currentIdx == 0 ? max(raw, 0) :
                                          currentIdx == tabs.count - 1 ? min(raw, 0) : raw
                            dragProgress = clamped
                        }
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        let tabs = AppTab.allCases
                        let currentIdx = tabs.firstIndex(of: selectedTab) ?? 0
                        // Snap tab if drag exceeded threshold
                        if dx < -60 && currentIdx < tabs.count - 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = tabs[currentIdx + 1]
                            }
                        } else if dx > 60 && currentIdx > 0 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = tabs[currentIdx - 1]
                            }
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragProgress = 0 }
                        scheduleExpand()
                    }
            )

            FloatingTabBar(
                selectedTab: $selectedTab,
                isCompact: isCompact,
                hasActiveWorkout: appState.activeSession != nil,
                dragProgress: dragProgress
            )
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

private struct GlassTabBarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45))
                        Capsule().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.3 : 0.7), lineWidth: 1)
                    }
                }
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    let isCompact: Bool
    var hasActiveWorkout: Bool = false
    var dragProgress: CGFloat = 0
    @Namespace private var pillAnimation

    private var tabs: [AppTab] { AppTab.allCases }

    private var currentIdx: Int { tabs.firstIndex(of: selectedTab) ?? 0 }

    // Which tab index the indicator should visually sit at (fractional during drag)
    private var indicatorPosition: CGFloat {
        CGFloat(currentIdx) + dragProgress
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    dragProgress: dragProgress,
                    currentIdx: currentIdx,
                    tabIdx: tabs.firstIndex(of: tab) ?? 0,
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
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .modifier(GlassTabBarModifier())
        .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 10)
        .padding(.horizontal, 20)
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
    var dragProgress: CGFloat = 0
    var currentIdx: Int = 0
    var tabIdx: Int = 0
    let isCompact: Bool
    var badge: Bool = false
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var pulseBadge = false
    private var showLabel: Bool { isSelected && !isCompact }
    private let green = Color(hex: "#30d158")

    // 0...1 how "lit up" this tab icon is during a drag
    private var activation: CGFloat {
        max(0, 1 - abs(CGFloat(tabIdx) - (CGFloat(currentIdx) + dragProgress)))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.white.opacity(0.15))
                                .frame(width: 44, height: 30)
                                .matchedGeometryEffect(id: "selectionPill", in: namespace)
                        }
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: activation > 0.5 ? .semibold : .regular))
                            .foregroundStyle(
                                activation > 0.01
                                ? green.opacity(0.4 + activation * 0.6)
                                : Color(UIColor.secondaryLabel)
                            )
                            .frame(width: 44, height: 30)
                            .scaleEffect(1.0 + activation * 0.05)
                    }
                    if badge {
                        Circle()
                            .fill(green)
                            .frame(width: 7, height: 7)
                            .scaleEffect(pulseBadge ? 1.35 : 1.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseBadge)
                            .offset(x: 4, y: -2)
                            .onAppear { pulseBadge = true }
                    }
                }
                if showLabel {
                    Text(tab.label)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(green)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isCompact)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isSelected)
    }
}
