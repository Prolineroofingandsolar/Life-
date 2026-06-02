import SwiftUI

// MARK: - Workout Summary View

struct WorkoutSummaryView: View {
    @Environment(AppState.self) private var appState
    let sessionId: String
    let onDone: () -> Void

    @State private var rating: Int = 0
    @State private var appeared = false

    private var session: WorkoutSession? {
        appState.sessions.first { $0.id == sessionId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Celebration header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#30d158").opacity(0.15))
                                .frame(width: 100, height: 100)
                                .scaleEffect(appeared ? 1 : 0.5)
                                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: appeared)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 44))
                                .foregroundColor(Color(hex: "#30d158"))
                                .scaleEffect(appeared ? 1 : 0.3)
                                .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.2), value: appeared)
                        }

                        Text("Workout Complete!")
                            .font(.title.bold())
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut.delay(0.35), value: appeared)

                        if let session = session {
                            Text(session.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .opacity(appeared ? 1 : 0)
                                .animation(.easeOut.delay(0.45), value: appeared)
                        }
                    }
                    .padding(.top, 24)

                    if let session = session {
                        // Stats grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            StatCard(icon: "clock.fill", color: .blue, label: "Duration", value: session.durationSeconds.formattedDuration)
                            StatCard(icon: "checkmark.circle.fill", color: Color(hex: "#30d158"), label: "Sets", value: "\(session.totalSets)")
                            StatCard(icon: "scalemass.fill", color: .orange, label: "Volume", value: formatVolume(session.totalVolumeKg))
                        }
                        .padding(.horizontal, 16)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut.delay(0.5), value: appeared)

                        // Muscle breakdown
                        if !session.exercises.isEmpty {
                            muscleBreakdown(session: session)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.easeOut.delay(0.6), value: appeared)
                        }

                        // New achievements
                        let newAchievements = appState.achievements.filter {
                            guard let fin = session.finishedAt else { return false }
                            return abs($0.unlockedAt.timeIntervalSince(fin)) < 60
                        }
                        if !newAchievements.isEmpty {
                            achievementsSection(newAchievements)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.easeOut.delay(0.7), value: appeared)
                        }

                        // Rating
                        ratingSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.easeOut.delay(0.75), value: appeared)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if rating > 0 {
                            appState.rateSession(sessionId: sessionId, rating: rating)
                        }
                        HapticManager.success()
                        onDone()
                    }
                    .bold()
                    .foregroundColor(Color(hex: "#30d158"))
                }
            }
            .onAppear {
                HapticManager.success()
                withAnimation { appeared = true }
                if let r = session?.rating { rating = r }
            }
        }
    }

    // MARK: - Muscle Breakdown

    @ViewBuilder
    private func muscleBreakdown(session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Muscles Trained")
                .font(.headline)
                .padding(.horizontal, 16)

            let muscles = uniqueMuscles(session: session)
            FlowLayout(spacing: 8) {
                ForEach(muscles, id: \.self) { muscle in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(muscle.muscleColor)
                            .frame(width: 8, height: 8)
                        Text(muscle)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Achievements

    @ViewBuilder
    private func achievementsSection(_ achievements: [Achievement]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements Unlocked!")
                .font(.headline)
                .padding(.horizontal, 16)

            ForEach(achievements) { ach in
                HStack(spacing: 12) {
                    Image(systemName: ach.kind.icon)
                        .font(.title2)
                        .foregroundColor(Color(hex: ach.kind.color))
                        .frame(width: 44, height: 44)
                        .background(Color(hex: ach.kind.color).opacity(0.15))
                        .cornerRadius(10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ach.kind.title)
                            .font(.subheadline.bold())
                        if !ach.detail.isEmpty {
                            Text(ach.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Rating

    private var ratingSection: some View {
        VStack(spacing: 10) {
            Text("How was this workout?")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        HapticManager.selection()
                        rating = star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundColor(star <= rating ? .yellow : .secondary)
                            .scaleEffect(star <= rating ? 1.15 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: rating)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func uniqueMuscles(session: WorkoutSession) -> [String] {
        var seen = Set<String>()
        return session.exercises.compactMap { ex -> String? in
            guard let exercise = appState.exercises.first(where: { $0.id == ex.exerciseId }) else { return nil }
            return seen.insert(exercise.muscle).inserted ? exercise.muscle : nil
        }
    }

    private func formatVolume(_ kg: Double) -> String {
        if kg >= 1000 {
            return String(format: "%.1ft", kg / 1000)
        }
        return "\(Int(kg))kg"
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
