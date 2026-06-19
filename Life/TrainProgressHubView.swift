import SwiftUI

// MARK: - Train Progress Hub
// A single page inside Train that combines Progress Photos, Body, and
// Achievements behind a segmented control. Each embedded view keeps its
// own navigation bar, so this uses a lightweight custom header instead of
// another NavigationStack to avoid a doubled-up bar.

struct TrainProgressHubView: View {

    enum HubTab: String, CaseIterable, Identifiable {
        case progress = "Progress"
        case body = "Body"
        case achievements = "Achievements"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: HubTab

    init(initialTab: HubTab = .progress) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header: Done + segmented control
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.trainAccent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Picker("Section", selection: $selectedTab) {
                ForEach(HubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Embedded views (each provides its own NavigationStack/title)
            Group {
                switch selectedTab {
                case .progress:     ProgressPhotosView()
                case .body:         BodyView()
                case .achievements: AchievementsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.trainBg)
        .preferredColorScheme(.dark)
    }
}
