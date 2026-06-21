import SwiftUI

// MARK: - More View

struct MoreView: View {

    @Environment(AppState.self) private var appState
    @EnvironmentObject private var authManager: AuthManager
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Tracking
                Section("Tracking") {
                    MoreRow(
                        icon: "scalemass.fill",
                        color: .green,
                        title: "Body",
                        subtitle: "Weight & body composition"
                    ) {
                        BodyView()
                    }
                    MoreRow(
                        icon: "dollarsign.circle.fill",
                        color: .orange,
                        title: "Money",
                        subtitle: "Bills & monthly outgoings"
                    ) {
                        MoneyView()
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
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
