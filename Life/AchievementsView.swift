import SwiftUI

// MARK: - AchievementsView

struct AchievementsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var unlockedKinds: Set<AchievementKind> {
        Set(appState.achievements.map(\.kind))
    }

    private func unlockedDate(for kind: AchievementKind) -> Date? {
        appState.achievements.first { $0.kind == kind }?.unlockedAt
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LevelCard(
                    xpLevel: appState.xpLevel,
                    xpPoints: appState.xpPoints,
                    xpProgress: appState.xpProgress
                )

                StreakCard(streak: appState.workoutStreak)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Achievements")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(AchievementKind.allCases, id: \.self) { kind in
                            AchievementCell(
                                kind: kind,
                                unlocked: unlockedKinds.contains(kind),
                                unlockedAt: unlockedDate(for: kind)
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Level Card

private struct LevelCard: View {
    let xpLevel: Int
    let xpPoints: Int
    let xpProgress: Double

    private var pointsToNext: Int {
        max(0, xpLevel * 500 - xpPoints)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(xpLevel)")
                        .font(.largeTitle.bold())
                    Text("\(xpPoints) XP total")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(AppTheme.brandGradient)
                        .frame(width: 56, height: 56)
                    Text("\(xpLevel)")
                        .font(.title.bold())
                        .foregroundColor(.white)
                }
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemFill))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.brandGradient)
                            .frame(width: max(0, geo.size.width * xpProgress), height: 12)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: xpProgress)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("\(Int(xpProgress * 100))% to Level \(xpLevel + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(pointsToNext) XP needed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Streak Card

private struct StreakCard: View {
    let streak: Int
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 44, height: 44)
                .background(Color.orange.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak) day streak")
                    .font(.headline)
                Text(streak == 0 ? "Start training to build your streak" : "Keep it going!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Achievement Cell

private struct AchievementCell: View {
    let kind: AchievementKind
    let unlocked: Bool
    let unlockedAt: Date?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(unlocked ? Color(hex: kind.color).opacity(0.15) : Color(.systemFill))
                    .frame(width: 52, height: 52)
                Image(systemName: kind.icon)
                    .font(.title3)
                    .foregroundColor(unlocked ? Color(hex: kind.color) : Color(.tertiaryLabel))
            }

            Text(kind.title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .foregroundColor(unlocked ? .primary : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if unlocked, let date = unlockedAt {
                Text(Self.dateFormatter.string(from: date))
                    .font(.caption2)
                    .foregroundColor(Color(hex: kind.color))
            } else if !unlocked {
                Text("Locked")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .opacity(unlocked ? 1 : 0.6)
    }
}
