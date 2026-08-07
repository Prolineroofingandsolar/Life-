import SwiftUI
import Charts
import PhotosUI

// MARK: - TrainView

struct TrainView: View {

    @Environment(AppState.self) private var appState
    /// Captured when the workout sheet opens so it survives `finishSession`
    /// nulling `activeSession` (otherwise Finish → blank white page).
    @State private var presentedWorkout: PresentedWorkout?
    @State private var showExerciseLibrary = false
    @State private var showAddRoutine = false
    @State private var showBrowsePrograms = false
    @State private var showPrograms = false
    @State private var hubTab: TrainProgressHubView.HubTab? = nil
    @State private var pulseResume = false
    @State private var planDate: Date? = nil
    @State private var sessionForDetail: WorkoutSession? = nil
    @State private var detailRoutine: Routine? = nil
    @State private var showImportRoutine = false
    @State private var showQuickStartPicker = false
    /// The AI builder. Nil when closed; the value carries what kind of thing to
    /// build, so the sheet opens straight into the right form.
    @State private var builderKind: WorkoutPreviewSheet.Kind?
    /// Carried into the builder when it is opened from the weekly review, so
    /// the conversation starts from what the review was about.
    @State private var pendingBrief = WorkoutBrief()
    /// Progression proposals awaiting review. Non-empty presents the sheet.
    @State private var reviewingProposals: [ProgressionEngine.Proposal] = []
    @State private var showSettings = false
    @State private var showScanner = false
    @State private var showWeeklyReview = false
    /// Drift signals being reviewed. Empty dismisses the sheet.
    @State private var driftSignals: [DriftEngine.Signal] = []
    @State private var showAutomations = false
    @State private var deloadProposal: DeloadEngine.Proposal?
    @State private var plateauFinding: PlateauEngine.Finding?
    @State private var adjustingRoutineId: String?
    /// The missed session being rescheduled, if any. Nil dismisses the sheet.
    @State private var reschedulingSession: PlannedSession?

    private var finishedSessions: [WorkoutSession] {
        appState.sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    /// Gaps between conceptual sections. Everything inside a section is
    /// tighter than this; nothing else is looser. Matches Today, so the two
    /// tabs read as one app.
    private static let sectionSpacing: CGFloat = 22

    /// Today's routine, from a planned entry first and the programme second —
    /// the same precedence `TodaysWorkoutCard` uses, so "View plan" always opens
    /// what the card is describing.
    private var todaysRoutine: Routine? {
        if let planned = appState.plannedSessions.first(where: {
            Calendar.current.isDateInToday($0.date) && !$0.completed
        }), let id = planned.routineId {
            return appState.routines.first { $0.id == id }
        }
        return appState.todaysSuggestedRoutine()
    }

    /// Routes an automation's finding to the screen that can act on it.
    ///
    /// Every branch presents something with its own confirm button. The
    /// automation found the thing; the sheet is where anything happens, and
    /// there is no case here that writes.
    private func open(_ destination: AutomationOutcome.Destination) {
        switch destination {
        case .weeklyReview:
            showWeeklyReview = true
        case .reschedule(let session):
            reschedulingSession = session
        case .progression:
            // The most recent finished session — the one the automation fired
            // about.
            let latest = appState.completedWorkouts
                .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
                .first
            if let latest {
                reviewingProposals = ProgressionEngine.proposals(
                    forSessionId: latest.id, appState: appState
                )
            }
        case .plateau(let finding):
            plateauFinding = finding
        case .adjustRoutine(let routineId):
            adjustingRoutineId = routineId
        case .drift(let signals):
            driftSignals = signals
        }
    }

    private func startTodaysWorkout() {
        if let active = appState.activeSession {
            presentedWorkout = PresentedWorkout(id: active.id)
            return
        }
        if let planned = appState.plannedSessions.first(where: {
            Calendar.current.isDateInToday($0.date) && !$0.completed && !$0.isRestDay
        }) {
            appState.startSession(name: planned.routineName, routineId: planned.routineId)
        } else if let suggested = appState.todaysSuggestedRoutine() {
            appState.startSession(name: suggested.name, routineId: suggested.id)
        } else {
            // Nothing planned, so there is nothing to put in a workout yet.
            // Same rule as Quick Start: pick the exercise first.
            showQuickStartPicker = true
            return
        }
        presentedWorkout = appState.activeSession.map { PresentedWorkout(id: $0.id) }
    }

    private func circularToolbarButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(AppTheme.cardBg))
        }
        .accessibilityLabel(label)
    }

    /// One heading style for the page.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// Routines, kept below the new sections rather than removed.
    ///
    /// The four-glyph header row is gone: browse and programmes moved into the
    /// grid above, and building moved with them. Only "new routine" is left,
    /// because that is the one thing this section is actually about.
    private var routinesSection: some View {
        section("My routines") {
            VStack(spacing: 12) {
                QuickStartCard { showQuickStartPicker = true }
                    .padding(.horizontal, 16)

                if appState.routines.isEmpty {
                    EmptyStateView(
                        icon: "dumbbell",
                        title: "No routines yet",
                        actionLabel: "Create your first routine",
                        action: { showAddRoutine = true }
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(appState.routines) { routine in
                            RoutineTile(
                                routine: routine,
                                onStart: {
                                    appState.startSession(name: routine.name, routineId: routine.id)
                                    presentedWorkout = appState.activeSession.map { PresentedWorkout(id: $0.id) }
                                },
                                onTap: { detailRoutine = routine }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Self.sectionSpacing) {

                    WeekStripView(
                        onPlanDate: { date in planDate = date },
                        onTapSession: { session in sessionForDetail = session }
                    )
                    .padding(.horizontal, 16)

                    // A live session outranks everything, including today's
                    // plan — you are already doing the thing.
                    if let active = appState.activeSession {
                        ResumeCard(session: active, pulse: pulseResume) {
                            presentedWorkout = PresentedWorkout(id: active.id)
                        }
                        .padding(.horizontal, 16)
                        .onAppear { pulseResume = true }
                    } else {
                        TodaysWorkoutCard(
                            onStart: startTodaysWorkout,
                            onViewPlan: { detailRoutine = todaysRoutine }
                        )
                        .padding(.horizontal, 16)
                    }

                    // Hides itself entirely when there is nothing to say. A card
                    // permanently present and usually empty teaches people to
                    // stop looking at it.
                    CoachSuggestionCard { proposals in
                        reviewingProposals = proposals
                    }
                    .padding(.horizontal, 16)

                    // Both of these hide themselves when there is nothing to
                    // say. A prompt that is permanently present and usually
                    // empty teaches people to stop reading it.
                    MissedSessionCard { session in
                        reschedulingSession = session
                    }
                    .padding(.horizontal, 16)

                    WeeklyReviewCard { showWeeklyReview = true }
                        .padding(.horizontal, 16)

                    DriftCard { signals in
                        driftSignals = signals
                    }
                    .padding(.horizontal, 16)

                    DeloadCard { proposal in
                        deloadProposal = proposal
                    }
                    .padding(.horizontal, 16)

                    section("Train your way") {
                        TrainYourWayGrid(
                            onBuildProgramme: { builderKind = .plan },
                            onBuildWorkout: { builderKind = .workout },
                            onScanMachine: { showScanner = true },
                            onExerciseLibrary: { showExerciseLibrary = true }
                        )
                        .padding(.horizontal, 16)
                    }

                    section("Your programme") {
                        ProgrammeProgressCard { showPrograms = true }
                            .padding(.horizontal, 16)
                    }

                    section("Progress") {
                        TrainingProgressCard { hubTab = .progress }
                            .padding(.horizontal, 16)
                    }

                    routinesSection

                    MuscleVolumeSection()

                    Color.clear
                        .frame(height: 24)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
            }
            .background(AppTheme.trainBg)
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Circular, so they read as controls rather than as
                    // decoration sitting next to the title. The exercise library
                    // moved into the grid below, where it has a name; settings
                    // takes its place because Train had no way into them at all.
                    circularToolbarButton("chart.bar.fill", label: "Training progress") {
                        hubTab = .activity
                    }
                    circularToolbarButton("wand.and.stars", label: "Automations") {
                        showAutomations = true
                    }
                    circularToolbarButton("gearshape.fill", label: "Settings") {
                        showSettings = true
                    }
                }
            }
            .sheet(item: $sessionForDetail) { session in
                NavigationStack { SessionDetailView(session: session) }
            }

            .sheet(item: $presentedWorkout) { workout in
                ActiveWorkoutView(
                    isPresented: Binding(
                        get: { presentedWorkout != nil },
                        set: { if !$0 { presentedWorkout = nil } }
                    ),
                    sessionId: workout.id
                )
            }
            // Quick Start used to create the workout on the tap and then show
            // an empty session, so the timer was already running, the banner was
            // already on every other tab, and backing out left a live workout
            // with nothing in it that had to be found and discarded. Nothing is
            // created until an exercise is picked; cancelling the picker leaves
            // no trace.
            .sheet(isPresented: $showQuickStartPicker) {
                ExercisePickerSheet(title: "Choose an Exercise") { exerciseId in
                    startQuickWorkout(with: exerciseId)
                }
            }
            .sheet(isPresented: $showExerciseLibrary) { ExerciseLibraryView() }
            .sheet(isPresented: $showAddRoutine) { AddRoutineSheet() }
            .sheet(isPresented: $showImportRoutine) { ImportRoutineSheet() }
            .sheet(item: $builderKind, onDismiss: { pendingBrief = WorkoutBrief() }) { kind in
                WorkoutPreviewSheet(initialBrief: pendingBrief, initialKind: kind)
            }
            .sheet(
                isPresented: Binding(
                    get: { !reviewingProposals.isEmpty },
                    set: { if !$0 { reviewingProposals = [] } }
                )
            ) {
                ProgressionReviewSheet(proposals: reviewingProposals)
            }
            .sheet(item: $detailRoutine) { routine in
                RoutineDetailSheet(routine: routine) {
                    appState.startSession(name: routine.name, routineId: routine.id)
                    detailRoutine = nil
                    presentedWorkout = appState.activeSession.map { PresentedWorkout(id: $0.id) }
                }
            }
            .sheet(isPresented: $showBrowsePrograms) { BrowseProgramsSheet() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showScanner) { MachineScanSheet() }
            .sheet(isPresented: $showWeeklyReview) {
                WeeklyReviewSheet(
                    onOpenBuilder: { brief in
                        // The review opens the builder; the builder still asks
                        // its own questions and still needs confirming.
                        pendingBrief = brief
                        builderKind = .plan
                    },
                    onOpenSchedule: { showPrograms = true }
                )
            }
            .sheet(item: $reschedulingSession) { session in
                RescheduleSheet(missed: session)
            }
            .sheet(
                isPresented: Binding(
                    get: { !driftSignals.isEmpty },
                    set: { if !$0 { driftSignals = [] } }
                )
            ) {
                DriftReviewSheet(signals: driftSignals) { brief in
                    pendingBrief = brief
                    builderKind = .plan
                }
            }
            .sheet(isPresented: $showAutomations) {
                AutomationsView { destination in
                    open(destination)
                }
            }
            .sheet(item: $plateauFinding) { finding in
                PlateauSheet(finding: finding)
            }
            .sheet(
                isPresented: Binding(
                    get: { deloadProposal != nil },
                    set: { if !$0 { deloadProposal = nil } }
                )
            ) {
                if let deloadProposal {
                    DeloadSheet(proposal: deloadProposal)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { adjustingRoutineId != nil },
                    set: { if !$0 { adjustingRoutineId = nil } }
                )
            ) {
                if let id = adjustingRoutineId,
                   let routine = appState.routines.first(where: { $0.id == id }) {
                    AdjustWorkoutSheet(exercises: routine.exercises) { adjusted in
                        appState.updateRoutine(id: id, exercises: adjusted)
                    }
                }
            }
            .sheet(isPresented: $showPrograms) { ProgramsView() }
            .sheet(item: $hubTab) { tab in
                TrainProgressHubView(initialTab: tab)
            }
            .sheet(isPresented: Binding(get: { planDate != nil }, set: { if !$0 { planDate = nil } })) {
                if let date = planDate {
                    PlanSessionSheet(date: date) { planDate = nil }
                }
            }
        }
    }

    /// Creates the Quick Start session around the exercise the user chose, then
    /// opens it. Resuming an existing workout takes priority: `startSession`
    /// refuses to replace one, so without this the picked exercise would be
    /// dropped silently.
    private func startQuickWorkout(with exerciseId: String) {
        if let active = appState.activeSession {
            appState.addExerciseToSession(sessionId: active.id, exerciseId: exerciseId)
            presentedWorkout = PresentedWorkout(id: active.id)
        } else {
            appState.startSession(name: "Quick Workout")
            guard let session = appState.activeSession else { return }
            appState.addExerciseToSession(sessionId: session.id, exerciseId: exerciseId)
            presentedWorkout = PresentedWorkout(id: session.id)
        }
    }
}

// MARK: - Stats Row

private struct StatsRow: View {
    @Environment(AppState.self) private var appState

    private var workoutsThisWeek: Int {
        appState.sessionsThisWeek().values.flatMap { $0 }.count
    }

    private var kgThisWeek: Int {
        Int(appState.volumeThisWeekByMuscle().map(\.volumeKg).reduce(0, +))
    }

    var body: some View {
        HStack(spacing: 12) {
            StatChip(
                icon: "figure.strengthtraining.traditional",
                value: "\(workoutsThisWeek)",
                label: "WORKOUTS",
                accent: AppTheme.trainAccent
            )
            StatChip(
                icon: "scalemass.fill",
                value: kgThisWeek > 0 ? "\(kgThisWeek)kg" : "0kg",
                label: "VOLUME",
                accent: Color(hex: "#FF9F0A")
            )
            StatChip(
                icon: "flame.fill",
                value: "\(appState.workoutStreak)",
                label: "STREAK",
                accent: Color(hex: "#FF453A")
            )
        }
    }
}

private struct StatChip: View {
    let icon: String
    let value: String
    let label: String
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(accent)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(hex: "#A0A0B0"))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.trainCard)
        .cornerRadius(14)
    }
}

// MARK: - Workout Calendar Card

struct WorkoutCalendarCard: View {
    @Environment(AppState.self) private var appState
    let onPlanDate: (Date) -> Void
    let onTapSession: (WorkoutSession) -> Void

    @State private var showMonth = false
    private let cal = Calendar.current

    private static let monthTitleFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()

    private var monthTitle: String {
        Self.monthTitleFmt.string(from: Date())
    }

    private var weekDays: [(date: Date, shortDay: String)] {
        Self.weekDays(containing: Date(), calendar: cal)
    }

    /// The seven days of the week `date` falls in, always Monday first.
    ///
    /// Monday is computed from the weekday component rather than taken from
    /// `Calendar.weekOfYear`, and that is the fix rather than a preference.
    /// `dateComponents([.yearForWeekOfYear, .weekOfYear])` starts the week on
    /// `calendar.firstWeekday`, which is Monday in en_GB but *Sunday* in en_US
    /// — the simulator's default locale. The column labels below are the fixed
    /// string "M T W T F S S", so on a Sunday-first device every day sat one
    /// column off its own name: Thursday 6 August 2026 drew under Friday, and
    /// tapping the cell under "Wed" planned a session for Tuesday.
    ///
    /// The month grid alongside this already derives its offset from the
    /// weekday number and so was always Monday-based. Two calendars in one card
    /// disagreeing about which column a date belongs in is the bug; this makes
    /// both of them agree with the labels.
    static func weekDays(
        containing date: Date,
        calendar: Calendar
    ) -> [(date: Date, shortDay: String)] {
        let startOfDay = calendar.startOfDay(for: date)
        // weekday is 1=Sunday … 7=Saturday in the Gregorian calendar,
        // independent of firstWeekday. Monday is 2, so this is how many days
        // back Monday sits, with Sunday counting as six days *after* Monday
        // rather than the day before it.
        let daysSinceMonday = (calendar.component(.weekday, from: startOfDay) + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay) ?? startOfDay

        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (0..<7).map { offset in
            // Added as calendar days, not as 86,400-second multiples: on the
            // day the clocks change, one of these seven is 23 or 25 hours long.
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            return (date: day, shortDay: labels[offset])
        }
    }

    private var monthDays: [Date?] {
        let comps = cal.dateComponents([.year, .month], from: Date())
        guard let firstOfMonth = cal.date(from: comps) else { return [] }
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let firstWeekday = cal.component(.weekday, from: firstOfMonth) // 1=Sun
        let offset = (firstWeekday + 5) % 7 // Mon-based offset 0-6
        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in 1...daysInMonth {
            days.append(cal.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    // Bucketed by startedAt (not finishedAt) so this agrees with the week
    // strip on the main Train page, which matches sessions by their start
    // day — a workout that finishes after midnight would otherwise show as
    // "done" on a different day between the two calendars.
    private var sessionDayMap: [Date: [WorkoutSession]] {
        var map: [Date: [WorkoutSession]] = [:]
        for s in appState.sessions.filter({ $0.finishedAt != nil }) {
            let day = cal.startOfDay(for: s.startedAt)
            map[day, default: []].append(s)
        }
        return map
    }

    private var plannedDaySet: Set<Date> {
        Set(appState.plannedSessions
            .filter { !$0.completed }
            .map { cal.startOfDay(for: $0.date) })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(monthTitle.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#A0A0B0"))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35)) { showMonth.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showMonth ? "WEEK" : "MONTH")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: showMonth ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(AppTheme.trainAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Day-of-week labels
            HStack(spacing: 0) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#A0A0B0"))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            if showMonth {
                // Month grid
                let rows = monthDays.chunked(into: 7)
                VStack(spacing: 2) {
                    ForEach(rows.indices, id: \.self) { rowIdx in
                        HStack(spacing: 2) {
                            ForEach(0..<7) { colIdx in
                                if let date = rows[rowIdx][colIdx] {
                                    calDayCell(date: date)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Week strip
                HStack(spacing: 2) {
                    ForEach(weekDays, id: \.date) { entry in
                        calDayCell(date: entry.date)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            // Legend
            HStack(spacing: 14) {
                legendDot(color: AppTheme.primary, label: "Done")
                legendDot(color: AppTheme.trainAccent, label: "Planned", isRing: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppTheme.trainCard)
        .cornerRadius(16)
    }

    @ViewBuilder
    private func calDayCell(date: Date) -> some View {
        let startOfDay = cal.startOfDay(for: date)
        let isToday = cal.isDateInToday(date)
        let isFuture = startOfDay > cal.startOfDay(for: Date())
        let sessions = sessionDayMap[startOfDay] ?? []
        let hasDone = !sessions.isEmpty
        let hasPlanned = plannedDaySet.contains(startOfDay)
        let dayNum = cal.component(.day, from: date)

        Button {
            HapticManager.selection()
            if let session = sessions.first {
                onTapSession(session)
            } else if isFuture || isToday {
                onPlanDate(date)
            }
        } label: {
            ZStack {
                // Background fill
                if hasDone {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 34, height: 34)
                } else if hasPlanned {
                    Circle()
                        .stroke(AppTheme.trainAccent, lineWidth: 2)
                        .frame(width: 34, height: 34)
                } else if isToday {
                    Circle()
                        .stroke(Color.primary.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }

                Text("\(dayNum)")
                    .font(.system(size: 13, weight: hasDone || isToday ? .bold : .regular))
                    .foregroundColor(
                        hasDone ? .white
                        : isToday ? AppTheme.trainAccent
                        : isFuture ? Color(hex: "#A0A0B0")
                        : .primary
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
        }
        .buttonStyle(.plain)
    }

    private func legendDot(color: Color, label: String, isRing: Bool = false) -> some View {
        HStack(spacing: 5) {
            ZStack {
                if isRing {
                    Circle().stroke(color, lineWidth: 2).frame(width: 9, height: 9)
                } else {
                    Circle().fill(color).frame(width: 9, height: 9)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(Color(hex: "#A0A0B0"))
        }
    }
}

// MARK: - Week Strip View (compact main-page calendar)

/// The week, bare, as seven columns.
///
/// No card, no month header, no paging chevrons. The previous version wrapped
/// all three in a container that took as much vertical room as the workout card
/// underneath it — on a screen whose job is "what am I doing today", the
/// calendar was competing with the answer.
///
/// Days with a completed workout carry a filled dot; planned ones a hollow
/// dot. Today is the filled pill.
private struct WeekStripView: View {

    @Environment(AppState.self) private var appState

    let onPlanDate: (Date) -> Void
    let onTapSession: (WorkoutSession) -> Void

    /// Monday-first, derived from the weekday component rather than
    /// `Calendar.weekOfYear` — which starts on Sunday under en_US and would put
    /// every date one column from its own name.
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) else {
            return [today]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private static let labels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                dayColumn(date: date, label: Self.labels[min(index, 6)])
            }
        }
    }

    @ViewBuilder
    private func dayColumn(date: Date, label: String) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        let session = appState.completedWorkouts.first {
            calendar.isDate($0.startedAt, inSameDayAs: date)
        }
        let isPlanned = appState.plannedSessions.contains {
            !$0.completed && calendar.isDate($0.date, inSameDayAs: date)
        }

        Button {
            HapticManager.selection()
            if let session {
                onTapSession(session)
            } else if date >= calendar.startOfDay(for: Date()) {
                onPlanDate(date)
            }
        } label: {
            VStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 20, weight: isToday ? .semibold : .regular))
                    .foregroundColor(isToday ? .white : .primary)
                    .frame(width: 40, height: 40)
                    .background {
                        if isToday {
                            Circle().fill(AppTheme.trainAccent)
                        }
                    }

                Circle()
                    .fill(session != nil ? AppTheme.trainAccent : Color.clear)
                    .frame(width: 5, height: 5)
                    .overlay {
                        if session == nil && isPlanned {
                            Circle().strokeBorder(AppTheme.trainAccent.opacity(0.6), lineWidth: 1.2)
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(date: date, hasSession: session != nil, isPlanned: isPlanned))
        .accessibilityAddTraits(isToday ? [.isButton, .isSelected] : [.isButton])
    }

    private func accessibilityLabel(date: Date, hasSession: Bool, isPlanned: Bool) -> String {
        var parts = [date.formatted(.dateTime.weekday(.wide).day().month(.wide))]
        if hasSession { parts.append("workout completed") }
        else if isPlanned { parts.append("workout planned") }
        return parts.joined(separator: ", ")
    }
}

struct PlanSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let onDone: () -> Void

    @State private var selectedRoutineId: String? = nil
    @State private var notes = ""

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(Self.dateFmt.string(from: date))
                        .foregroundColor(.secondary)
                } header: { Text("Date") }

                Section {
                    Picker("Routine", selection: $selectedRoutineId) {
                        Text("Free Workout").tag(String?.none)
                        ForEach(appState.routines) { routine in
                            Text(routine.name).tag(Optional(routine.id))
                        }
                    }
                } header: { Text("Routine") }

                Section {
                    TextField("Optional notes…", text: $notes)
                } header: { Text("Notes") }
            }
            .navigationTitle("Plan Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss(); onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name: String
                        if let id = selectedRoutineId,
                           let r = appState.routines.first(where: { $0.id == id }) {
                            name = r.name
                        } else {
                            name = "Free Workout"
                        }
                        appState.planSession(date: date, routineId: selectedRoutineId, name: name)
                        HapticManager.success()
                        dismiss()
                        onDone()
                    }
                }
            }
        }
    }
}

// MARK: - Resume Card

private struct ResumeCard: View {
    let session: WorkoutSession
    let pulse: Bool
    let onTap: () -> Void

    @State private var now = Date()

    private var elapsed: String {
        let secs = Int(now.timeIntervalSince(session.startedAt))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.trainAccent.opacity(pulse ? 0.25 : 0.12))
                        .frame(width: 44, height: 44)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                    Image(systemName: "play.fill")
                        .foregroundColor(AppTheme.trainAccent)
                        .font(.system(size: 16))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Resume Workout")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(session.name)
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#A0A0B0"))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(elapsed)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundColor(AppTheme.trainAccent)
                    Image(systemName: "chevron.right")
                        .foregroundColor(AppTheme.trainAccent)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(16)
            .background(AppTheme.trainAccent.opacity(0.1))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.trainAccent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { t in now = t }
    }
}

// MARK: - Today Planned Card (from PlannedSession)

// MARK: - Quick Start Card

private struct QuickStartCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.trainAccent)
                Text("Quick Start")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppTheme.trainAccent.opacity(0.7))
            }
            .padding(14)
            .background(AppTheme.trainCard)
            .cornerRadius(12)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - PR Section

private struct PRSection: View {
    @Environment(AppState.self) private var appState

    private var exercisesWithData: [(Exercise, AppState.PRResult)] {
        appState.exercises
            .compactMap { ex -> (Exercise, AppState.PRResult)? in
                let prs = appState.computePRs(for: ex.id)
                guard prs.bestWeight > 0 else { return nil }
                return (ex, prs)
            }
            .sorted { $0.1.best1RM > $1.1.best1RM }
    }

    var body: some View {
        if !exercisesWithData.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PERSONAL RECORDS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#A0A0B0"))
                    Spacer()
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(exercisesWithData.prefix(15), id: \.0.id) { ex, prs in
                            PRCardView(exercise: ex, prs: prs)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct PRCardView: View {
    @Environment(AppState.self) private var appState
    let exercise: Exercise
    let prs: AppState.PRResult
    @State private var showDetail = false

    private var unit: WeightUnit { appState.workoutSettings.weightUnit }
    private var bestWeightDisplay: Double { WeightUnit.kg.convert(prs.bestWeight, to: unit) }
    private var best1RMDisplay: Double { WeightUnit.kg.convert(prs.best1RM, to: unit) }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundColor(AppTheme.trainAccent)
                    Text(exercise.muscle)
                        .font(.caption2)
                        .foregroundColor(exercise.muscle.muscleColor)
                }

                Text(exercise.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 130, alignment: .leading)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("\(bestWeightDisplay.formatted1)\(unit.label.lowercased())")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.trainAccent)
                        Text("×\(prs.bestReps)")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#A0A0B0"))
                    }
                    Text("Est. 1RM: \(best1RMDisplay.formatted1)\(unit.label.lowercased())")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#A0A0B0"))
                }
            }
            .padding(14)
            .frame(width: 150, height: 140)
            .background(AppTheme.trainCard)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.trainAccent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .sheet(isPresented: $showDetail) {
            ExerciseDetailSheet(exerciseId: exercise.id)
        }
    }
}

// MARK: - Muscle Volume Section

private struct MuscleVolumeSection: View {
    @Environment(AppState.self) private var appState

    private struct MuscleWeek {
        let muscle: String
        let sets: Int
        let volumeKg: Double
        let target: (min: Int, max: Int)
    }

    private var weeklyData: [MuscleWeek] {
        let setsMap = Dictionary(uniqueKeysWithValues: appState.setsThisWeekByMuscle().map { ($0.muscle, $0.sets) })
        let volMap = Dictionary(uniqueKeysWithValues: appState.volumeThisWeekByMuscle().map { ($0.muscle, $0.volumeKg) })
        return setsMap.keys.map { m in
            MuscleWeek(muscle: m, sets: setsMap[m] ?? 0, volumeKg: volMap[m] ?? 0, target: appState.weeklySetTarget(forMuscle: m))
        }.sorted { $0.sets > $1.sets }
    }

    /// Muted while under the minimum effective volume, the muscle's own
    /// color once inside its research-backed weekly range, amber past the
    /// top of that range.
    private func barColor(_ item: MuscleWeek) -> Color {
        if item.sets < item.target.min { return item.muscle.muscleColor.opacity(0.4) }
        if item.sets > item.target.max { return .orange }
        return item.muscle.muscleColor
    }

    var body: some View {
        if !weeklyData.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("THIS WEEK'S SETS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#A0A0B0"))
                    .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    ForEach(weeklyData.prefix(9), id: \.muscle) { item in
                        HStack(spacing: 10) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(item.muscle.muscleColor)
                                    .frame(width: 7, height: 7)
                                Text(item.muscle)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 80, alignment: .leading)

                            GeometryReader { geo in
                                let ratio = item.target.max > 0 ? Double(item.sets) / Double(item.target.max) : 0
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.07))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(barColor(item))
                                        .frame(width: item.sets > 0 ? max(4, geo.size.width * min(1.2, ratio)) : 0)
                                }
                            }
                            .frame(height: 14)

                            Text("\(item.sets)/\(item.target.max)")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(Color(hex: "#A0A0B0"))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .background(AppTheme.trainCard)
                .cornerRadius(14)
                .padding(.horizontal, 16)

                Text("Target range shown is per-muscle weekly sets (min–max) for hypertrophy.")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#A0A0B0"))
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Routine Card

private struct RoutineTile: View {
    @Environment(AppState.self) private var appState
    let routine: Routine
    let onStart: () -> Void
    let onTap: () -> Void

    @State private var showEdit = false

    private var muscleGroups: [String] {
        Array(Set(routine.exercises.compactMap { re in
            appState.exercises.first(where: { $0.id == re.exerciseId })?.muscle
        })).sorted()
    }
    private var totalSets: Int { routine.exercises.reduce(0) { $0 + $1.defaultSets } }
    private var estimatedMinutes: Int { max(10, totalSets * 2) }
    private var accentColor: Color { Color(hex: routine.colorHex) }

    var body: some View {
        Button {
            HapticManager.selection()
            onTap()
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Background: photo or gradient
                Group {
                    if let data = routine.photoData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [accentColor.opacity(0.85), accentColor.opacity(0.4), Color.black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .clipped()

                // Dark scrim so text is always readable
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Big emoji top-right
                Text(routine.emoji)
                    .font(.system(size: 52))
                    .opacity(routine.photoData == nil ? 0.35 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(16)

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Label("~\(estimatedMinutes)m", systemImage: "clock")
                        Label("\(routine.exercises.count) ex", systemImage: "dumbbell")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                    Button {
                        HapticManager.impact(.medium)
                        onStart()
                    } label: {
                        Text("START")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.trainAccent)
                            .cornerRadius(10)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .padding(14)
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: accentColor.opacity(0.35), radius: 12, x: 0, y: 6)
        .buttonStyle(.plain)
        .contextMenu {
            Button { showEdit = true } label: { Label("Edit Routine", systemImage: "pencil") }
            Button(role: .destructive) { appState.deleteRoutine(id: routine.id) } label: { Label("Delete", systemImage: "trash") }
        }
        .sheet(isPresented: $showEdit) { EditRoutineSheet(routine: routine) }
    }
}

// MARK: - Routine Detail Sheet

private struct RoutineDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let routine: Routine
    let onStart: () -> Void

    @State private var showEdit = false
    @State private var showAdjust = false

    private var muscleGroups: [String] {
        Array(Set(routine.exercises.compactMap { re in
            appState.exercises.first(where: { $0.id == re.exerciseId })?.muscle
        })).sorted()
    }

    private var totalSets: Int { routine.exercises.reduce(0) { $0 + $1.defaultSets } }
    private var estimatedMinutes: Int { max(10, totalSets * 2) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Summary header
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 5) {
                                ForEach(muscleGroups, id: \.self) { muscle in
                                    Text(muscle)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(muscle.muscleColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(muscle.muscleColor.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "dumbbell").font(.caption2)
                                Text("\(routine.exercises.count) exercises")
                                Text("·")
                                Image(systemName: "square.stack").font(.caption2)
                                Text("\(totalSets) sets")
                                Text("·")
                                Image(systemName: "clock").font(.caption2)
                                Text("~\(estimatedMinutes)m")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Exercise list
                        VStack(spacing: 0) {
                            ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { idx, re in
                                if let ex = appState.exercises.first(where: { $0.id == re.exerciseId }) {
                                    HStack(spacing: 10) {
                                        Circle().fill(ex.muscle.muscleColor).frame(width: 8, height: 8)
                                        Text(ex.name)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text("\(re.defaultSets)×\(re.defaultReps)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.secondary)
                                        if re.defaultWeight > 0 {
                                            Text("\(re.defaultWeight.formatted1)kg")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    if idx < routine.exercises.count - 1 {
                                        Divider().padding(.leading, 34)
                                    }
                                }
                            }
                        }
                        .background(AppTheme.cardBg)
                        .cornerRadius(16)
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 16)
                }

                // Start, and the one thing worth doing before starting.
                //
                // "Adjust" sits beside it rather than behind the Edit button
                // because they are different intents: Edit changes the routine
                // for good, Adjust changes it for the shape of today. The
                // adjuster shows a diff and writes nothing until it is applied.
                VStack(spacing: 10) {
                    Button {
                        HapticManager.impact(.medium)
                        onStart()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Workout")
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.trainAccent)
                        .cornerRadius(AppTheme.buttonRadius)
                    }
                    .buttonStyle(PressableButtonStyle())

                    Button {
                        showAdjust = true
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("Adjust for today")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.trainAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.trainAccent.opacity(0.12))
                        .cornerRadius(AppTheme.buttonRadius)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(routine.exercises.isEmpty)
                    .accessibilityHint("Shorter, lighter, or with different equipment. Shows what changes before anything is saved.")
                }
                .padding(16)
            }
            .background(AppTheme.trainBg)
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }
                }
            }
            .sheet(isPresented: $showEdit) { EditRoutineSheet(routine: routine) }
            .sheet(isPresented: $showAdjust) {
                AdjustWorkoutSheet(exercises: routine.exercises) { adjusted in
                    // The one write. `updateRoutine` already saves, and the
                    // sheet has shown every change that produced this list.
                    appState.updateRoutine(id: routine.id, exercises: adjusted)
                }
            }
        }
    }
}

// MARK: - Session History Card

private struct SessionHistoryCard: View {
    @Environment(AppState.self) private var appState
    let session: WorkoutSession

    private var muscles: [String] {
        Array(Set(session.exercises.compactMap { se in
            appState.exercises.first(where: { $0.id == se.exerciseId })?.muscle
        })).sorted()
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill((muscles.first ?? "Other").muscleColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18))
                    .foregroundColor((muscles.first ?? "Other").muscleColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                HStack(spacing: 10) {
                    if let finished = session.finishedAt {
                        Label(finished.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    Label(session.durationSeconds.formattedDurationShort, systemImage: "clock")
                    Label("\(session.exercises.count) ex", systemImage: "dumbbell")
                }
                .font(.caption)
                .foregroundColor(Color(hex: "#A0A0B0"))
            }

            Spacer()

            if session.totalVolumeKg > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(session.totalVolumeKg))")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundColor(AppTheme.trainAccent)
                    Text("kg vol")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#A0A0B0"))
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(hex: "#A0A0B0").opacity(0.5))
        }
        .padding(14)
        .background(AppTheme.trainCard)
        .cornerRadius(14)
    }
}

// MARK: - Add Routine Sheet

struct AddRoutineSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "💪"
    @State private var colorHex = "#2FD4C0"
    @State private var exercises: [DraftRoutineExercise] = []
    @State private var showExercisePicker = false
    @FocusState private var isNameFocused: Bool

    private let colorOptions = ["#2FD4C0","#0a84ff","#ff375f","#ff9f0a","#bf5af2","#64d2ff","#ff6961","#ffffff"]
    private let emojiOptions = ["💪","🏋️","🔥","⚡️","🦵","🫀","🏃","🤸","🥊","🧘","🎯","🏆"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Push A, Leg Day", text: $name)
                        .focused($isNameFocused)
                }

                Section("Card Appearance") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon").font(.caption).foregroundColor(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                            ForEach(emojiOptions, id: \.self) { e in
                                Text(e)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(emoji == e ? Color(hex: colorHex).opacity(0.25) : Color(.tertiarySystemFill))
                                    .cornerRadius(8)
                                    .onTapGesture { emoji = e }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Colour").font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 10) {
                            ForEach(colorOptions, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.white, lineWidth: colorHex == hex ? 3 : 0))
                                    .shadow(color: Color(hex: hex).opacity(0.5), radius: colorHex == hex ? 4 : 0)
                                    .onTapGesture { colorHex = hex }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    ForEach($exercises) { $ex in
                        DraftExerciseRow(draft: $ex, allExercises: appState.exercises)
                    }
                    .onDelete { offsets in exercises.remove(atOffsets: offsets) }
                    .onMove { from, to in exercises.move(fromOffsets: from, toOffset: to) }

                    Button {
                        showExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .foregroundColor(AppTheme.primary)
                    }
                } header: { Text("Exercises") }
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let routineExercises = exercises.map { d in
                            RoutineExercise(exerciseId: d.exerciseId, defaultSets: d.sets,
                                           defaultReps: d.reps, defaultWeight: d.weight, restSeconds: d.restSeconds)
                        }
                        var routine = Routine(name: trimmed, exercises: routineExercises)
                        routine.emoji = emoji
                        routine.colorHex = colorHex
                        appState.routines.append(routine)
                        appState.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
            }
            .onAppear { isNameFocused = true }
            .sheet(isPresented: $showExercisePicker) {
                ExerciseSelectSheet { exerciseId in
                    if !exercises.contains(where: { $0.exerciseId == exerciseId }) {
                        exercises.append(DraftRoutineExercise(exerciseId: exerciseId))
                    }
                }
            }
        }
    }
}

// MARK: - Edit Routine Sheet

struct EditRoutineSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let routine: Routine
    @State private var name: String
    @State private var emoji: String
    @State private var colorHex: String
    @State private var photoData: Data?
    @State private var exercises: [DraftRoutineExercise]
    @State private var showExercisePicker = false
    @State private var showPhotoPicker = false

    private let colorOptions = ["#2FD4C0","#0a84ff","#ff375f","#ff9f0a","#bf5af2","#64d2ff","#ff6961","#ffffff"]
    private let emojiOptions = ["💪","🏋️","🔥","⚡️","🦵","🫀","🏃","🤸","🥊","🧘","🎯","🏆"]

    init(routine: Routine) {
        self.routine = routine
        _name      = State(initialValue: routine.name)
        _emoji     = State(initialValue: routine.emoji)
        _colorHex  = State(initialValue: routine.colorHex)
        _photoData = State(initialValue: routine.photoData)
        _exercises = State(initialValue: routine.exercises.map { re in
            DraftRoutineExercise(exerciseId: re.exerciseId, sets: re.defaultSets,
                                 reps: re.defaultReps, weight: re.defaultWeight, restSeconds: re.restSeconds)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Routine name", text: $name)
                }

                Section("Card Appearance") {
                    // Photo picker
                    Button {
                        showPhotoPicker = true
                    } label: {
                        HStack {
                            if let data = photoData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 60, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: colorHex).opacity(0.3))
                                    .frame(width: 60, height: 40)
                                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                            }
                            Text(photoData != nil ? "Change Photo" : "Add Photo")
                            Spacer()
                            if photoData != nil {
                                Button("Remove") { photoData = nil }
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .foregroundColor(.primary)

                    // Emoji
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon").font(.caption).foregroundColor(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                            ForEach(emojiOptions, id: \.self) { e in
                                Text(e)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(emoji == e ? Color(hex: colorHex).opacity(0.25) : Color(.tertiarySystemFill))
                                    .cornerRadius(8)
                                    .onTapGesture { emoji = e }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    // Colour
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Colour").font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 10) {
                            ForEach(colorOptions, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.white, lineWidth: colorHex == hex ? 3 : 0))
                                    .shadow(color: Color(hex: hex).opacity(0.5), radius: colorHex == hex ? 4 : 0)
                                    .onTapGesture { colorHex = hex }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    ForEach($exercises) { $ex in
                        DraftExerciseRow(draft: $ex, allExercises: appState.exercises)
                    }
                    .onDelete { offsets in exercises.remove(atOffsets: offsets) }
                    .onMove { from, to in exercises.move(fromOffsets: from, toOffset: to) }

                    Button {
                        showExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .foregroundColor(AppTheme.primary)
                    }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        EditButton().font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let routineExercises = exercises.map { d in
                            RoutineExercise(exerciseId: d.exerciseId, defaultSets: d.sets,
                                           defaultReps: d.reps, defaultWeight: d.weight, restSeconds: d.restSeconds)
                        }
                        appState.updateRoutine(
                            id: routine.id, name: trimmed, exercises: routineExercises,
                            colorHex: colorHex, emoji: emoji,
                            photoData: photoData, clearPhoto: photoData == nil && routine.photoData != nil
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExerciseSelectSheet { exerciseId in
                    if !exercises.contains(where: { $0.exerciseId == exerciseId }) {
                        exercises.append(DraftRoutineExercise(exerciseId: exerciseId))
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: Binding(
                get: { nil },
                set: { item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            photoData = data
                        }
                    }
                }
            ), matching: .images)
        }
    }
}

// MARK: - Draft Routine Exercise helpers

struct DraftRoutineExercise: Identifiable {
    let id = UUID()
    var exerciseId: String
    var sets: Int = 3
    var reps: Int = 10
    var weight: Double = 0
    var restSeconds: Int = 90
}

private struct DraftExerciseRow: View {
    @Binding var draft: DraftRoutineExercise
    let allExercises: [Exercise]

    private var exercise: Exercise? { allExercises.first { $0.id == draft.exerciseId } }

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var setsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let ex = exercise {
                    Circle().fill(ex.muscle.muscleColor).frame(width: 8, height: 8)
                    Text(ex.name).font(.subheadline.bold())
                } else {
                    Text("Unknown exercise").font(.subheadline).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    TextField("3", text: $setsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: setsText) { _, v in if let n = Int(v) { draft.sets = max(1, n) } }
                    Text("sets").font(.caption2).foregroundColor(.secondary)
                }
                VStack(spacing: 2) {
                    TextField("10", text: $repsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: repsText) { _, v in if let n = Int(v) { draft.reps = max(1, n) } }
                    Text("reps").font(.caption2).foregroundColor(.secondary)
                }
                if exercise?.kind == .weight {
                    VStack(spacing: 2) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: weightText) { _, v in if let n = Double(v) { draft.weight = n } }
                        Text("kg").font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            Stepper("Rest: \(draft.restSeconds)s", value: $draft.restSeconds, in: 15...300, step: 15)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .onAppear {
            setsText = "\(draft.sets)"
            repsText = "\(draft.reps)"
            weightText = draft.weight == 0 ? "" : draft.weight.formatted1
        }
    }
}

// MARK: - Exercise Select Sheet

struct ExerciseSelectSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedMuscle: String? = nil

    private let muscleOrder = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Legs", "Core", "Other"]

    private var availableMuscles: [String] {
        muscleOrder.filter { m in appState.exercises.contains { $0.muscle == m } }
    }

    private var filtered: [Exercise] {
        appState.exercises.filter { ex in
            let matchesMuscle = selectedMuscle == nil || ex.muscle == selectedMuscle
            let matchesSearch = searchText.isEmpty ||
                ex.name.localizedCaseInsensitiveContains(searchText) ||
                ex.muscle.localizedCaseInsensitiveContains(searchText)
            return matchesMuscle && matchesSearch
        }
        .sorted { $0.name < $1.name }
    }

    private var grouped: [(String, [Exercise])] {
        if selectedMuscle != nil { return [(selectedMuscle!, filtered)] }
        return availableMuscles.compactMap { muscle in
            let exs = filtered.filter { $0.muscle == muscle }
            return exs.isEmpty ? nil : (muscle, exs)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChipSmall(label: "All", isSelected: selectedMuscle == nil) { selectedMuscle = nil }
                        ForEach(availableMuscles, id: \.self) { muscle in
                            FilterChipSmall(label: muscle, isSelected: selectedMuscle == muscle,
                                           color: muscle.muscleColor) {
                                selectedMuscle = selectedMuscle == muscle ? nil : muscle
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))

                List {
                    ForEach(grouped, id: \.0) { muscle, exs in
                        Section(muscle) {
                            ForEach(exs) { ex in
                                Button {
                                    onSelect(ex.id)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Circle().fill(muscle.muscleColor).frame(width: 8, height: 8)
                                        Text(ex.name).foregroundColor(.primary)
                                        Spacer()
                                        Text(ex.equipment.label).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Filter Chip Small

private struct FilterChipSmall: View {
    let label: String
    let isSelected: Bool
    var color: Color = AppTheme.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                .foregroundColor(isSelected ? color : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession

    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var showShareSheet = false

    var body: some View {
        List {
            SessionSummarySection(session: session)
            ForEach(session.exercises) { ex in
                SessionExerciseSection(ex: ex)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [session.shareText(exercises: appState.exercises, unit: appState.workoutSettings.weightUnit)])
        }
        .fullScreenCover(isPresented: $showEditSheet) {
            ActiveWorkoutView(isPresented: $showEditSheet, sessionId: session.id, mode: .editFinished)
        }
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                appState.deleteFinishedSession(sessionId: session.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

private struct SessionSummarySection: View {
    let session: WorkoutSession
    var body: some View {
        Section {
            InfoRow(label: "Date", value: session.finishedAt.map {
                $0.formatted(date: .long, time: .shortened)
            } ?? "In progress")
            InfoRow(label: "Duration", value: session.durationSeconds.formattedDurationShort)
            InfoRow(label: "Sets completed", value: "\(session.totalSets)")
            InfoRow(label: "Volume", value: session.totalVolumeKg > 0 ? "\(Int(session.totalVolumeKg)) kg" : "—")
        } header: { Text("Summary") }
    }
}

private struct SessionExerciseSection: View {
    @Environment(AppState.self) private var appState
    let ex: SessionExercise
    var body: some View {
        if let exercise = appState.exercises.first(where: { $0.id == ex.exerciseId }) {
            Section {
                ForEach(Array(ex.sets.enumerated()), id: \.element.id) { idx, set in
                    SessionSetRow(set: set, index: idx, kind: exercise.kind)
                }
            } header: {
                HStack {
                    Circle().fill(exercise.muscle.muscleColor).frame(width: 8, height: 8)
                    Text(exercise.name)
                }
            }
        }
    }
}

private struct SessionSetRow: View {
    @Environment(AppState.self) private var appState
    let set: LoggedSet
    let index: Int
    let kind: ExerciseKind
    private var unit: WeightUnit { appState.workoutSettings.weightUnit }
    private var weightDisplay: Double { WeightUnit.kg.convert(set.weight, to: unit) }
    var body: some View {
        HStack {
            Group {
                // Same badge as the live workout row, off the same property, so
                // a set doesn't change type between logging it and reading it
                // back in the session history.
                if set.kind == .normal {
                    Text("\(index + 1)").font(.caption).foregroundColor(.secondary)
                } else {
                    Text(set.kind.badge)
                        .font(.caption.bold())
                        .foregroundColor(set.kind.badgeColour)
                }
            }
            .frame(width: 20)
            .accessibilityLabel(set.kind == .normal ? "Set \(index + 1)" : set.kind.label)
            if kind == .cardio {
                Text(set.durationSec > 0
                     ? "\(set.durationSec / 60):\(String(format: "%02d", set.durationSec % 60))"
                     : "—")
                if set.distanceKm > 0 { Text("· \(set.distanceKm.formatted1) km").foregroundColor(.secondary) }
            } else {
                Text(set.weight > 0 ? "\(weightDisplay.formatted1) \(unit.label.lowercased())" : "BW")
                Text("×")
                Text(set.reps > 0 ? "\(set.reps)" : "—")
            }
            Spacer()
            if set.done {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Muscle Recovery Section

struct MuscleRecoverySection: View {
    @Environment(AppState.self) private var appState
    @State private var showMap = false

    private var muscles: [String] {
        Array(Set(appState.exercises.filter { $0.kind != .cardio }.map(\.muscle))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showMap = true
            } label: {
                HStack {
                    Text("MUSCLE RECOVERY")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#A0A0B0"))
                    Spacer()
                    HStack(spacing: 3) {
                        Text("Body map")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.primary)
                }
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(muscles, id: \.self) { muscle in
                        let status = appState.recoveryStatus(muscle: muscle)
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(status.color.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Circle()
                                    .stroke(status.color, lineWidth: 2)
                                    .frame(width: 48, height: 48)
                                Text(String(muscle.prefix(2)))
                                    .font(.caption2.bold())
                                    .foregroundColor(status.color)
                            }
                            Text(muscle)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#A0A0B0"))
                                .lineLimit(1)
                        }
                        .frame(width: 56)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            HStack(spacing: 14) {
                ForEach([AppState.RecoveryStatus.fatigued, .recovering, .recovered, .fresh], id: \.label) { s in
                    HStack(spacing: 4) {
                        Circle().fill(s.color).frame(width: 7, height: 7)
                        Text(s.label).font(.caption2).foregroundColor(Color(hex: "#A0A0B0"))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showMap) {
            MuscleRecoveryMapView()
        }
    }
}

// MARK: - Weekly Consistency Chart

struct WeeklyConsistencyChart: View {
    @Environment(AppState.self) private var appState
    private var data: [(weekLabel: String, count: Int)] { appState.weeklyWorkoutCounts(weeks: 8) }

    var body: some View {
        Chart {
            ForEach(data.indices, id: \.self) { i in
                BarMark(
                    x: .value("Week", data[i].weekLabel),
                    y: .value("Sessions", data[i].count)
                )
                .foregroundStyle(AppTheme.trainAccent.gradient)
                .cornerRadius(4)
            }
        }
        .frame(height: 110)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let s = value.as(String.self) {
                        Text(s.components(separatedBy: " ").last ?? s)
                            .font(.caption2)
                            .foregroundColor(Color(hex: "#A0A0B0"))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .stride(by: 1)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.primary.opacity(0.1))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)").font(.caption2).foregroundColor(Color(hex: "#A0A0B0"))
                    }
                }
            }
        }
    }
}

// MARK: - Browse Programs Sheet

struct BrowseProgramsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmProgram: WorkoutSeed.WorkoutProgram? = nil

    private let programs = WorkoutSeed.programTemplates

    var body: some View {
        NavigationStack {
            List(programs) { program in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: program.icon)
                                .font(.title2)
                                .foregroundColor(AppTheme.primary)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(program.name).font(.headline)
                                Text(program.description)
                                    .font(.caption).foregroundColor(.secondary).lineLimit(2)
                            }
                        }
                        HStack(spacing: 12) {
                            Label("\(program.daysPerWeek)×/week", systemImage: "calendar")
                            Label(program.difficulty, systemImage: "chart.bar")
                            Label("\(program.routines.count) routines", systemImage: "list.bullet")
                        }
                        .font(.caption2).foregroundColor(.secondary)

                        Button { confirmProgram = program } label: {
                            Text("Add Program")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(AppTheme.primary)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Browse Programs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .alert("Add Program?", isPresented: Binding(
                get: { confirmProgram != nil },
                set: { if !$0 { confirmProgram = nil } }
            )) {
                Button("Add Routines") {
                    if let prog = confirmProgram {
                        for routine in prog.routines {
                            appState.addRoutine(name: routine.name, exercises: routine.exercises)
                        }
                        HapticManager.success()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { confirmProgram = nil }
            } message: {
                if let prog = confirmProgram {
                    Text("Add \(prog.routines.count) routines from \"\(prog.name)\" to your routines list?")
                }
            }
        }
    }
}

// MARK: - Array chunked helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}


// MARK: - Import Routine Sheet

/// Imports a routine from a CSV file or pasted text.
///
/// **Was called `AIRoutineSheet`, and is not an AI feature.** Its "AI" is a
/// *Copy AI Prompt* button that tells you to paste a prompt into a chatbot
/// elsewhere and bring the CSV back by hand. The name is now taken by nothing —
/// the real generator lives in `WorkoutBuilderService` and resolves exercises by
/// id, never by name.
///
/// The distinction matters because `importFromText` below resolves exercises by
/// *name* and manufactures a custom `Exercise` when the name doesn't match
/// anything in the library. That is acceptable for a file the user chose to
/// import — they typed those names, and an import that silently dropped half the
/// rows would be worse. It is emphatically **not** acceptable for model output,
/// which is why the generator never reuses this path and why nothing new should
/// call it.
struct ImportRoutineSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var routineName = ""
    @State private var pastedText = ""
    @State private var importMode: ImportMode = .file
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    enum ImportMode: String, CaseIterable {
        case file  = "CSV File"
        case paste = "Paste Text"
    }

    private let exampleCSV = """
Exercise,Sets,Reps,Rest
Bench Press,4,8,120
Overhead Press,3,10,90
Tricep Pushdown,3,12,60
Lateral Raise,3,15,45
"""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.trainAccent)
                        Text("Import Routine")
                            .font(.title2.bold())
                        Text("Import from a CSV file or paste workout text directly.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Routine name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Routine Name")
                            .font(.subheadline.weight(.semibold))
                        TextField("e.g. Push Day A", text: $routineName)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }

                    // Mode picker
                    Picker("Mode", selection: $importMode) {
                        ForEach(ImportMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if importMode == .file {
                        // File import
                        VStack(spacing: 12) {
                            Button {
                                showFilePicker = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 18))
                                    Text("Choose CSV File")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppTheme.trainAccent)
                                .cornerRadius(16)
                            }
                            .buttonStyle(.plain)

                            // Format guide
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Expected format")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(exampleCSV)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .cornerRadius(10)
                                Text("Columns: Exercise (required), Sets, Reps, Rest (seconds), Muscle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // Paste mode
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste your workout")
                                .font(.subheadline.weight(.semibold))
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                if pastedText.isEmpty {
                                    Text(exampleCSV)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(Color(.tertiaryLabel))
                                        .padding(12)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $pastedText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minHeight: 160)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                            }
                            .frame(minHeight: 180)

                            Button {
                                importFromText(pastedText)
                            } label: {
                                Text("Import")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : AppTheme.trainAccent)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    if let ok = successMessage {
                        Label(ok, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppTheme.trainAccent)
                    }

                    // Copy prompt for ChatGPT/Claude
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Generate with ChatGPT or Claude", systemImage: "lightbulb")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text("Copy the prompt below, paste it into ChatGPT or Claude, describe your workout, then paste the response above.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        let aiPrompt = """
Create a workout routine for me in CSV format with exactly these columns:
Exercise,Sets,Reps,Rest

Rules:
- No header row needed (or include it, both work)
- Rest is in seconds
- 4-8 exercises
- No extra text, just the CSV

My workout: [DESCRIBE YOUR WORKOUT HERE]
"""
                        HStack {
                            Text("Copy AI Prompt")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.trainAccent)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = aiPrompt
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.trainAccent)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(AppTheme.trainAccent.opacity(0.08))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.trainAccent.opacity(0.2), lineWidth: 1))
                    }

                    // CSV tip
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Or create your own CSV", systemImage: "tablecells")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text("In Google Sheets or Excel, list your exercises with columns for Sets, Reps and Rest, then File → Download → CSV.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let gotAccess = url.startAccessingSecurityScopedResource()
                    defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        // Use filename as routine name if field is empty
                        if routineName.trimmingCharacters(in: .whitespaces).isEmpty {
                            routineName = url.deletingPathExtension().lastPathComponent
                        }
                        importFromText(text)
                    } else {
                        errorMessage = "Couldn't read file."
                    }
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }

    private func importFromText(_ text: String) {
        errorMessage = nil
        successMessage = nil

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            errorMessage = "No data found."
            return
        }

        // Detect header row
        let firstLine = lines[0].lowercased()
        let hasHeader = firstLine.contains("exercise") || firstLine.contains("name")
        let dataLines = hasHeader ? Array(lines.dropFirst()) : lines

        guard !dataLines.isEmpty else {
            errorMessage = "No exercises found after header."
            return
        }

        var routine = Routine(name: routineName.trimmingCharacters(in: .whitespaces).isEmpty ? "Imported Routine" : routineName)
        var count = 0

        for line in dataLines {
            let cols = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let exName = cols.first, !exName.isEmpty else { continue }

            let sets   = cols.count > 1 ? Int(cols[1]) ?? 3 : 3
            let reps   = cols.count > 2 ? Int(cols[2]) ?? 10 : 10
            let rest   = cols.count > 3 ? Int(cols[3]) ?? 90 : 90
            let muscle = cols.count > 4 ? cols[4] : "Full Body"

            let existing = appState.exercises.first {
                $0.name.lowercased() == exName.lowercased()
            }
            let exerciseId: String
            if let ex = existing {
                exerciseId = ex.id
            } else {
                var newEx = Exercise(name: exName, muscle: muscle, kind: .weight)
                newEx.isCustom = true
                appState.exercises.append(newEx)
                exerciseId = newEx.id
            }

            var re = RoutineExercise(exerciseId: exerciseId)
            re.defaultSets = sets
            re.defaultReps = reps
            re.repRangeMin = max(reps - 2, 1)
            re.repRangeMax = reps + 2
            re.restSeconds = rest
            routine.exercises.append(re)
            count += 1
        }

        guard count > 0 else {
            errorMessage = "No valid exercises found. Check your CSV format."
            return
        }

        appState.routines.append(routine)
        appState.save()
        successMessage = "Imported \"\(routine.name)\" with \(count) exercise\(count == 1 ? "" : "s")!"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}
