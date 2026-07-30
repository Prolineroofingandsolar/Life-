import SwiftUI

// MARK: - More View

struct MoreView: View {

    @Environment(AppState.self) private var appState
    @EnvironmentObject private var authManager: AuthManager
    @State private var showSettings = false
    @State private var showProgressPhotos = false
    @State private var showHabits = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Tracking
                Section("Tracking") {
                    // Habits moved here when Health took the fourth tab slot.
                    // Presented rather than pushed: HabitsView carries its own
                    // NavigationStack from its days as a tab root, and pushing
                    // it into this one would nest two stacks. Same reason
                    // Progress Photos below is a sheet.
                    Button {
                        showHabits = true
                    } label: {
                        MoreRowLabel(
                            icon: "chart.bar.fill",
                            color: AppTheme.primary,
                            title: "Habits",
                            subtitle: "Daily habits & streaks",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    MoreRow(
                        icon: "scalemass.fill",
                        color: .green,
                        title: "Body",
                        subtitle: "Weight & body composition"
                    ) {
                        BodyView()
                    }
                    Button {
                        showProgressPhotos = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color.pink.opacity(0.15))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "photo.stack.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.pink)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Progress Photos")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("Track your visual progress")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    MoreRow(
                        icon: "dollarsign.circle.fill",
                        color: .orange,
                        title: "Money",
                        subtitle: "Bills & monthly outgoings"
                    ) {
                        MoneyView()
                    }
                    MoreRow(
                        icon: "trophy.fill",
                        color: Color(hex: "#FFD700"),
                        title: "Achievements",
                        subtitle: "Milestones & badges"
                    ) {
                        AchievementsView()
                    }
                    MoreRow(
                        icon: "chart.line.uptrend.xyaxis",
                        color: AppTheme.primary,
                        title: "Habit Analytics",
                        subtitle: "Trends & streaks deep dive"
                    ) {
                        HabitAnalyticsView()
                    }
                }

                // MARK: - Explore
                Section("Explore") {
                    MoreRow(
                        icon: "map.fill",
                        color: .blue,
                        title: "Travel",
                        subtitle: "Fog-of-war world map"
                    ) {
                        WorldMapView()
                    }

                    MoreRow(
                        icon: "function",
                        color: .purple,
                        title: "Calculators",
                        subtitle: "1RM, BMI, macros & more"
                    ) {
                        CalculatorsView()
                    }
                }

                // MARK: - Account
                Section("Account") {
                    if let user = authManager.user {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.primary.opacity(0.15))
                                    .frame(width: 38, height: 38)
                                Text(String(user.email?.prefix(1).uppercased() ?? "?"))
                                    .font(.headline)
                                    .foregroundColor(AppTheme.primary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.userName.isEmpty ? "Your Account" : appState.userName)
                                    .font(.subheadline.weight(.semibold))
                                Text(user.email ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showProgressPhotos) {
                ProgressPhotosView()
            }
            .sheet(isPresented: $showHabits) {
                HabitsView()
            }
        }
    }
}

// MARK: - More Row

private struct MoreRow<Destination: View>: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            MoreRowLabel(icon: icon, color: color, title: title, subtitle: subtitle)
        }
    }
}

/// The icon + title + subtitle content of a More row, split out so rows that
/// present a sheet instead of pushing a destination look identical to those
/// that push.
private struct MoreRowLabel: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    /// `NavigationLink` draws its own disclosure chevron in a `List`; rows that
    /// present a sheet have to draw their own.
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if showsChevron {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 4)
    }
}
