import SwiftUI

// MARK: - Health Carousel

/// The swipeable health header at the top of Today.
///
/// Two pages of tiles rather than one tall grid. The grid version was the
/// tallest thing on the screen and pushed the day's actual work — the next
/// action, the tasks — below the fold; the collapsed summary that replaced it
/// went too far the other way and hid figures people open the app to check.
/// Paging keeps the six or seven that matter at the top and costs one swipe for
/// the rest.
///
/// **Every tile reads `AppState.healthSnapshot` and renders its `MetricState`,
/// not just its value.** That is the point of the thing, and the reason this
/// isn't a copy of the layout it's modelled on. A tracker that hasn't synced
/// shows "—" and "not synced", never "0"; a resting heart rate with four nights
/// behind it shows the number *and* "4/10 nights", never a trend it can't
/// justify. The snapshot already knows the difference between missing, stale,
/// no-baseline-yet and ready, so the tile can say which.
struct HealthCarousel: View {

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0

    private var snapshot: HealthSnapshot { appState.healthSnapshot }
    private var care: CareDay { appState.today }
    private var careSettings: CareSettings { appState.careSettings }
    private var healthSettings: HealthSettings { appState.healthSettings }

    /// Fixed, and deliberately so.
    ///
    /// A `TabView` in page style sizes itself to its tallest page, so pages of
    /// different heights make the content below jump as you swipe. Pinning the
    /// height means both pages are laid out to the same box and the page dots
    /// stay put.
    private static let pageHeight: CGFloat = 214

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $page) {
                primaryPage
                    .padding(.horizontal, 16)
                    .tag(0)
                secondaryPage
                    .padding(.horizontal, 16)
                    .tag(1)
            }
            .frame(height: Self.pageHeight)
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Reduce Motion turns the swipe into a cut rather than a slide.
            // The gesture still works; it just stops animating.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)

            pageDots
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Page dots

    /// Drawn rather than left to `indexDisplayMode: .always`.
    ///
    /// The built-in dots inherit the page control's own tint and sit inside the
    /// paged area, which eats vertical space on every page. These sit below it,
    /// and — more usefully — each is a real button, so the second page is
    /// reachable without a swipe gesture. That matters for Switch Control and
    /// for anyone who finds horizontal swiping awkward.
    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { index in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        page = index
                    }
                } label: {
                    Circle()
                        .fill(page == index ? AppTheme.primary : Color(.tertiaryLabel))
                        .frame(width: 7, height: 7)
                        .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(index == 0 ? "Today's activity" : "Heart and body")
                .accessibilityValue(page == index ? "Selected" : "")
                .accessibilityAddTraits(page == index ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Health pages")
    }

    // MARK: Page 1 — today's activity

    private var primaryPage: some View {
        HStack(spacing: 12) {
            stepsRing
            VStack(spacing: 10) {
                sleepTile
                readinessTile
                activeMinutesTile
            }
        }
    }

    /// Steps against the goal, as the one large figure.
    ///
    /// Steps rather than readiness, because it is the number that moves during
    /// the day and the one a ring is actually informative about. Readiness is a
    /// morning verdict — a ring implies progress towards something.
    private var stepsRing: some View {
        let goal = careSettings.stepGoal
        let steps = snapshot.steps.value
        let progress = (goal > 0 && steps != nil) ? Double(steps!) / Double(goal) : 0

        return ZStack {
            Circle()
                .stroke(AppTheme.primary.opacity(0.14), lineWidth: 14)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(
                    AppTheme.primary,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: progress)

            VStack(spacing: 1) {
                Text(steps.map { $0.formatted() } ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("steps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(stepsCaption)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
            }
        }
        .frame(width: 150, height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stepsAccessibilityLabel)
    }

    /// "of 10,000" when there's a figure, the reason there isn't when there
    /// isn't. Never "0 of 10,000" for a tracker that simply hasn't reported.
    private var stepsCaption: String {
        guard snapshot.steps.value != nil else {
            return snapshot.hasConnectedSource ? "not synced yet" : "no tracker"
        }
        return careSettings.stepGoal > 0 ? "of \(careSettings.stepGoal.formatted())" : ""
    }

    private var stepsAccessibilityLabel: String {
        guard let steps = snapshot.steps.value else {
            return snapshot.hasConnectedSource
                ? "Steps, not synced yet"
                : "Steps, no tracker connected"
        }
        if careSettings.stepGoal > 0 {
            return "Steps, \(steps.formatted()) of \(careSettings.stepGoal.formatted())"
        }
        return "Steps, \(steps.formatted())"
    }

    private var sleepTile: some View {
        CarouselTile(
            icon: "bed.double.fill",
            tint: .indigo,
            title: "Sleep",
            value: snapshot.sleepMinutes.value.map { HealthInsights.formatDuration($0) },
            caption: sleepCaption,
            state: snapshot.sleepMinutes.state
        )
    }

    private var sleepCaption: String {
        switch snapshot.sleepMinutes.state {
        case .missing:
            return snapshot.hasConnectedSource ? "not recorded" : "no tracker"
        case .stale:
            return "not last night"
        default:
            if let score = snapshot.sleepScore.value { return "score \(score)" }
            let goal = healthSettings.sleepGoalMinutes
            return "goal \(goal / 60)h"
        }
    }

    /// Readiness, including the case that used to read as no data at all.
    private var readinessTile: some View {
        CarouselTile(
            icon: "figure.mind.and.body",
            tint: .teal,
            title: "Readiness",
            value: snapshot.readiness.value.map(String.init),
            caption: readinessCaption,
            state: snapshot.readiness.state
        )
    }

    private var readinessCaption: String {
        switch snapshot.readiness.state {
        case .insufficientHistory:
            // The measurement exists; the baseline doesn't. Saying "no data"
            // here is the contradiction this whole snapshot exists to stop.
            let recorded = max(snapshot.hrvMs.sampleCount, snapshot.restingHeartRate.sampleCount)
            return "\(recorded)/\(HealthSnapshot.baselineSampleRequirement) nights"
        case .missing:
            return snapshot.hasConnectedSource ? "not recorded" : "no tracker"
        case .stale:
            return "not today"
        default:
            return "out of 100"
        }
    }

    private var activeMinutesTile: some View {
        CarouselTile(
            icon: "flame.fill",
            tint: .orange,
            title: "Active",
            value: snapshot.activeMinutes.value.map { "\($0)m" },
            caption: snapshot.activeMinutes.state.hasValue
                ? "goal \(healthSettings.exerciseGoalMinutes)m"
                : (snapshot.hasConnectedSource ? "not recorded" : "no tracker"),
            state: snapshot.activeMinutes.state
        )
    }

    // MARK: Page 2 — heart and body

    private var secondaryPage: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            restingHeartRateTile
            hrvTile
            distanceTile
            energyTile
            waterTile
            workoutTile
        }
    }

    private var restingHeartRateTile: some View {
        CarouselTile(
            icon: "heart.fill",
            tint: .pink,
            title: "Resting HR",
            value: snapshot.restingHeartRate.value.map { "\(Int($0))" },
            caption: baselineCaption(
                for: snapshot.restingHeartRate,
                comparison: snapshot.restingHeartRateBaseline,
                unit: "bpm"
            ),
            state: snapshot.restingHeartRate.state
        )
    }

    private var hrvTile: some View {
        CarouselTile(
            icon: "waveform.path.ecg",
            tint: AppTheme.primary,
            title: "HRV",
            value: snapshot.hrvMs.value.map { "\(Int($0))" },
            caption: baselineCaption(
                for: snapshot.hrvMs,
                comparison: snapshot.hrvBaseline,
                unit: "ms"
            ),
            state: snapshot.hrvMs.state
        )
    }

    /// The caption that distinguishes the four recovery situations.
    ///
    /// A reading with a baseline gets a direction; a reading without one says
    /// how far off having one it is; a stale reading says it isn't today's; an
    /// absent one says whether that's the tracker or the connection.
    private func baselineCaption(
        for metric: HealthMetric<Double>,
        comparison: BaselineComparison?,
        unit: String
    ) -> String {
        switch metric.state {
        case .missing:
            return snapshot.hasConnectedSource ? "not recorded" : "no tracker"
        case .stale:
            return "not today"
        case .insufficientHistory:
            return "\(metric.sampleCount)/\(metric.requiredSamples) nights"
        case .partial, .ready:
            guard let comparison, comparison.isMeaningful else { return unit }
            return comparison.direction == .above ? "above usual" : "below usual"
        }
    }

    private var distanceTile: some View {
        CarouselTile(
            icon: "location.fill",
            tint: .blue,
            title: "Distance",
            value: snapshot.distanceKm.value.map { String(format: "%.1f", $0) },
            caption: snapshot.distanceKm.state.hasValue
                ? "km"
                : (snapshot.hasConnectedSource ? "not recorded" : "no tracker"),
            state: snapshot.distanceKm.state
        )
    }

    private var energyTile: some View {
        CarouselTile(
            icon: "bolt.fill",
            tint: .yellow,
            title: "Energy",
            value: snapshot.activeEnergyKcal.value.map { "\(Int($0))" },
            caption: snapshot.activeEnergyKcal.state.hasValue
                ? "kcal"
                : (snapshot.hasConnectedSource ? "not recorded" : "no tracker"),
            state: snapshot.activeEnergyKcal.state
        )
    }

    /// Water is logged in the app, not synced from a device, so it is always
    /// `.ready` — there is no such thing as an unsynced glass of water.
    private var waterTile: some View {
        CarouselTile(
            icon: "drop.fill",
            tint: .cyan,
            title: "Water",
            value: "\(care.waterGlasses)",
            caption: "of \(careSettings.waterGoal)",
            state: .ready,
            action: { appState.addWater() }
        )
    }

    private var workoutTile: some View {
        let done = appState.completedWorkouts.contains { $0.startedAt.dayKey == snapshot.dayKey }
        let planned = appState.plannedSessions.contains {
            !$0.completed && $0.date.dayKey == snapshot.dayKey && !$0.isRestDay
        }
        let rest = appState.plannedSessions.contains {
            !$0.completed && $0.date.dayKey == snapshot.dayKey && $0.isRestDay
        }

        // Three different days, three different words. "Rest" used to appear
        // whenever nothing had been *completed*, which said the same thing
        // about a planned rest day and a hard session still ahead of it.
        return CarouselTile(
            icon: done ? "checkmark.circle.fill" : (rest ? "moon.zzz.fill" : "dumbbell.fill"),
            tint: done ? .green : (rest ? .indigo : AppTheme.primary),
            title: "Workout",
            value: done ? "Done" : (rest ? "Rest" : (planned ? "Planned" : "—")),
            caption: done ? "logged today" : (rest ? "scheduled" : (planned ? "for today" : "none planned")),
            state: .ready
        )
    }
}

// MARK: - Tile

/// One figure, its label, and — when it matters — why the figure isn't what you
/// might expect.
///
/// The `state` parameter is what separates this from an ordinary stat tile. A
/// missing or stale reading is drawn muted with the dash in place of a number,
/// so a tile that can't tell you something looks different from one that can,
/// at a glance and without reading the caption.
private struct CarouselTile: View {

    let icon: String
    let tint: Color
    let title: String
    /// Nil renders as an em dash. Never as zero — "0 steps" and "your tracker
    /// hasn't synced" look identical as a number and need opposite responses.
    let value: String?
    let caption: String
    let state: MetricState
    var action: (() -> Void)? = nil

    private var isDimmed: Bool { !state.hasValue || state == .stale }

    private var spokenLabel: String {
        guard let value else { return "\(title), \(caption)" }
        return "\(title), \(value), \(caption)"
    }

    var body: some View {
        if let action {
            Button {
                HapticManager.impact(.light)
                action()
            } label: { content }
                .buttonStyle(PressableButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((isDimmed ? Color.secondary : tint).opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDimmed ? .secondary : tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value ?? "—")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(isDimmed ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 43, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}
