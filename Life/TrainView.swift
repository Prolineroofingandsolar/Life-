import SwiftUI
import Charts
import PhotosUI

// MARK: - TrainView

struct TrainView: View {

    @Environment(AppState.self) private var appState
    @State private var showActiveWorkout = false
    @State private var showExerciseLibrary = false
    @State private var showAddRoutine = false
    @State private var showBrowsePrograms = false
    @State private var showPrograms = false
    @State private var hubTab: TrainProgressHubView.HubTab? = nil
    @State private var pulseResume = false
    @State private var planDate: Date? = nil
    @State private var sessionForDetail: WorkoutSession? = nil
    @State private var showSessionDetail = false
    @State private var detailRoutine: Routine? = nil
    @State private var showAIRoutine = false

    private var finishedSessions: [WorkoutSession] {
        appState.sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Compact week strip
                    WeekStripView(
                        onPlanDate: { date in planDate = date },
                        onTapSession: { session in
                            sessionForDetail = session
                            showSessionDetail = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // Resume active workout
                    if let active = appState.activeSession {
                        ResumeCard(session: active, pulse: pulseResume) {
                            showActiveWorkout = true
                        }
                        .padding(.horizontal, 16)
                        .onAppear { pulseResume = true }
                    }

                    // Today's planned or suggested routine
                    if let planned = appState.plannedSessions.first(where: {
                        Calendar.current.isDateInToday($0.date) && !$0.completed
                    }) {
                        TodayPlannedCard(plan: planned) {
                            appState.startSession(
                                name: planned.routineName,
                                routineId: planned.routineId
                            )
                            showActiveWorkout = true
                        }
                        .padding(.horizontal, 16)
                    } else if let suggested = appState.todaysSuggestedRoutine() {
                        TodayRoutineCard(routine: suggested) {
                            appState.startSession(name: suggested.name, routineId: suggested.id)
                            showActiveWorkout = true
                        }
                        .padding(.horizontal, 16)
                    }

                    // Personal Records
                    PRSection()

                    // Routines section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("MY ROUTINES")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "#A0A0B0"))
                            Spacer()
                            HStack(spacing: 14) {
                                Button { showBrowsePrograms = true } label: {
                                    Image(systemName: "square.grid.2x2")
                                        .foregroundColor(AppTheme.trainAccent)
                                }
                                Button { showPrograms = true } label: {
                                    Image(systemName: "calendar")
                                        .foregroundColor(AppTheme.trainAccent)
                                }
                                Button { showAIRoutine = true } label: {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(AppTheme.trainAccent)
                                        .font(.system(size: 18))
                                }
                                Button { showAddRoutine = true } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(AppTheme.trainAccent)
                                        .font(.system(size: 20))
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        // Quick Start
                        QuickStartCard {
                            appState.startSession(name: "Quick Workout")
                            showActiveWorkout = true
                        }
                        .padding(.horizontal, 16)

                        if appState.routines.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "dumbbell")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("No routines yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Button { showAddRoutine = true } label: {
                                    Text("Create your first routine")
                                        .font(.subheadline.bold())
                                        .foregroundColor(AppTheme.trainAccent)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(appState.routines) { routine in
                                    RoutineTile(
                                        routine: routine,
                                        onStart: {
                                            appState.startSession(name: routine.name, routineId: routine.id)
                                            showActiveWorkout = true
                                        },
                                        onTap: { detailRoutine = routine }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Volume by muscle
                    MuscleVolumeSection()

                    Color.clear.frame(height: 80)
                }
                .padding(.top, 8)
            }
            .background(AppTheme.trainBg)
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { hubTab = .activity } label: {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundColor(AppTheme.trainAccent)
                    }
                    Button { showExerciseLibrary = true } label: {
                        Image(systemName: "books.vertical")
                    }
                }
            }
            .sheet(isPresented: $showSessionDetail) {
                if let session = sessionForDetail {
                    NavigationStack { SessionDetailView(session: session) }
                }
            }
            .sheet(isPresented: $showActiveWorkout) {
                if let session = appState.activeSession {
                    ActiveWorkoutView(isPresented: $showActiveWorkout, sessionId: session.id)
                }
            }
            .sheet(isPresented: $showExerciseLibrary) { ExerciseLibraryView() }
            .sheet(isPresented: $showAddRoutine) { AddRoutineSheet() }
            .sheet(isPresented: $showAIRoutine) { AIRoutineSheet() }
            .sheet(item: $detailRoutine) { routine in
                RoutineDetailSheet(routine: routine) {
                    appState.startSession(name: routine.name, routineId: routine.id)
                    detailRoutine = nil
                    showActiveWorkout = true
                }
            }
            .sheet(isPresented: $showBrowsePrograms) { BrowseProgramsSheet() }
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
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            return (date: date, shortDay: labels[offset])
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

    private var sessionDayMap: [Date: [WorkoutSession]] {
        var map: [Date: [WorkoutSession]] = [:]
        for s in appState.sessions.filter({ $0.finishedAt != nil }) {
            guard let fin = s.finishedAt else { continue }
            let day = cal.startOfDay(for: fin)
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
                legendDot(color: Color(hex: "#30d158"), label: "Done")
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
            if isFuture || isToday {
                onPlanDate(date)
            } else if let session = sessions.first {
                onTapSession(session)
            }
        } label: {
            ZStack {
                // Background fill
                if hasDone {
                    Circle()
                        .fill(Color(hex: "#30d158"))
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

private struct WeekStripView: View {
    @Environment(AppState.self) private var appState
    @State private var weekOffset: Int = 0
    let onPlanDate: (Date) -> Void
    let onTapSession: (WorkoutSession) -> Void

    private var finishedSessions: [WorkoutSession] {
        appState.sessions.filter { $0.finishedAt != nil }
    }

    private var weekDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysToMonday = (weekday == 1 ? -6 : 2 - weekday)
        let monday = cal.date(byAdding: .day, value: daysToMonday + weekOffset * 7, to: today)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }

    private static let monthLabelFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()

    private var monthLabel: String {
        Self.monthLabelFmt.string(from: weekDates[3])
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { weekOffset -= 1 } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                }
                Spacer()
                Text(monthLabel)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { weekOffset += 1 } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 4)

            HStack(spacing: 4) {
                ForEach(weekDates, id: \.self) { date in
                    let session = finishedSessions.first { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
                    WeekDayCell(
                        date: date,
                        isToday: Calendar.current.isDateInToday(date),
                        isCompleted: session != nil,
                        isPlanned: appState.plannedSessions.contains { !$0.completed && Calendar.current.isDate($0.date, inSameDayAs: date) },
                        sessionName: session?.name
                    ) {
                        let today = Calendar.current.startOfDay(for: Date())
                        if date >= today {
                            onPlanDate(date)
                        } else if let s = session {
                            onTapSession(s)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBg)
        .cornerRadius(AppTheme.cardRadius)
    }
}

private struct WeekDayCell: View {
    let date: Date
    let isToday: Bool
    let isCompleted: Bool
    let isPlanned: Bool
    let sessionName: String?
    let onTap: () -> Void

    private static let dayLetterFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private static let dayNumberFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d"; return f }()

    private var dayLetter: String { Self.dayLetterFmt.string(from: date).uppercased() }
    private var dayNumber: String { Self.dayNumberFmt.string(from: date) }
    private var isFuture: Bool { date > Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Text(dayLetter)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isToday ? AppTheme.trainAccent : Color(hex: "#A0A0B0"))

                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCompleted ? AppTheme.trainAccent :
                              isToday ? AppTheme.trainAccent.opacity(0.15) :
                              Color.white.opacity(0.06))
                        .frame(width: 36, height: 36)
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                    } else {
                        Text(dayNumber)
                            .font(.system(size: 15, weight: isToday ? .bold : .medium))
                            .foregroundColor(isToday ? AppTheme.trainAccent : isFuture ? Color(hex: "#606070") : .primary)
                    }
                }

                if isPlanned && !isCompleted {
                    Circle()
                        .fill(AppTheme.trainAccent)
                        .frame(width: 4, height: 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }
}

// MARK: - Plan Session Sheet

private struct PlanSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let onDone: () -> Void

    @State private var selectedRoutineId: String? = nil
    @State private var notes = ""

    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(dateFmt.string(from: date))
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

private struct TodayPlannedCard: View {
    let plan: PlannedSession
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Planned Today", systemImage: "calendar.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.trainAccent)
                Text(plan.routineName)
                    .font(.headline)
                if !plan.notes.isEmpty {
                    Text(plan.notes)
                        .font(.caption)
                        .foregroundColor(Color(hex: "#A0A0B0"))
                }
            }
            Spacer()
            Button(action: onStart) {
                Image(systemName: "play.fill")
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.trainAccent)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(16)
        .background(AppTheme.trainCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.trainAccent.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Today Routine Card (from program)

private struct TodayRoutineCard: View {
    let routine: Routine
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Today's Workout", systemImage: "calendar.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.trainAccent)
                Text(routine.name)
                    .font(.headline)
                Text("\(routine.exercises.count) exercises")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#A0A0B0"))
            }
            Spacer()
            Button(action: onStart) {
                Image(systemName: "play.fill")
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.trainAccent)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(16)
        .background(AppTheme.trainCard)
        .cornerRadius(14)
    }
}

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
                        Text("\(prs.bestWeight.formatted1)kg")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.trainAccent)
                        Text("×\(prs.bestReps)")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#A0A0B0"))
                    }
                    Text("Est. 1RM: \(prs.best1RM.formatted1)kg")
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

    private var volumeData: [(muscle: String, volumeKg: Double)] {
        appState.volumeThisWeekByMuscle()
    }

    var body: some View {
        if !volumeData.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("THIS WEEK'S VOLUME")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#A0A0B0"))
                    .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    ForEach(volumeData.prefix(7), id: \.muscle) { item in
                        let maxVol = volumeData.first?.volumeKg ?? 1
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
                                let ratio = maxVol > 0 ? item.volumeKg / maxVol : 0
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.07))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(item.muscle.muscleColor.opacity(0.75))
                                        .frame(width: max(4, geo.size.width * ratio))
                                }
                            }
                            .frame(height: 14)

                            Text("\(Int(item.volumeKg))kg")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(Color(hex: "#A0A0B0"))
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .background(AppTheme.trainCard)
                .cornerRadius(14)
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

                // Start button
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
    @State private var colorHex = "#30d158"
    @State private var exercises: [DraftRoutineExercise] = []
    @State private var showExercisePicker = false
    @FocusState private var isNameFocused: Bool

    private let colorOptions = ["#30d158","#0a84ff","#ff375f","#ff9f0a","#bf5af2","#64d2ff","#ff6961","#ffffff"]
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
                            .foregroundColor(Color(hex: "#30d158"))
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
                                           defaultReps: d.reps, defaultWeight: d.weight)
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

    private let colorOptions = ["#30d158","#0a84ff","#ff375f","#ff9f0a","#bf5af2","#64d2ff","#ff6961","#ffffff"]
    private let emojiOptions = ["💪","🏋️","🔥","⚡️","🦵","🫀","🏃","🤸","🥊","🧘","🎯","🏆"]

    init(routine: Routine) {
        self.routine = routine
        _name      = State(initialValue: routine.name)
        _emoji     = State(initialValue: routine.emoji)
        _colorHex  = State(initialValue: routine.colorHex)
        _photoData = State(initialValue: routine.photoData)
        _exercises = State(initialValue: routine.exercises.map { re in
            DraftRoutineExercise(exerciseId: re.exerciseId, sets: re.defaultSets,
                                 reps: re.defaultReps, weight: re.defaultWeight)
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
                            .foregroundColor(Color(hex: "#30d158"))
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
                                           defaultReps: d.reps, defaultWeight: d.weight)
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
    var color: Color = Color(hex: "#30d158")
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
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditSessionSheet(session: session)
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

struct EditSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession

    @State private var name: String
    @State private var notes: String

    init(session: WorkoutSession) {
        self.session = session
        _name  = State(initialValue: session.name)
        _notes = State(initialValue: session.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Name") {
                    TextField("Name", text: $name)
                }
                Section("Notes") {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(4...)
                }
                Section("Sets") {
                    ForEach(session.exercises) { ex in
                        if let exercise = appState.exercises.first(where: { $0.id == ex.exerciseId }) {
                            HStack {
                                Circle().fill(exercise.muscle.muscleColor).frame(width: 8, height: 8)
                                Text(exercise.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(ex.sets.filter(\.done).count) sets")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            appState.renameSession(sessionId: session.id, name: trimmed)
                        }
                        appState.updateSessionNotes(sessionId: session.id, notes: notes)
                        dismiss()
                    }
                }
            }
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
    let set: LoggedSet
    let index: Int
    let kind: ExerciseKind
    var body: some View {
        HStack {
            Group {
                if set.isWarmup { Text("W").font(.caption.bold()).foregroundColor(.orange) }
                else if set.isDropSet { Text("↓").font(.caption.bold()).foregroundColor(.purple) }
                else { Text("\(index + 1)").font(.caption).foregroundColor(.secondary) }
            }
            .frame(width: 20)
            if kind == .cardio {
                Text(set.durationSec > 0
                     ? "\(set.durationSec / 60):\(String(format: "%02d", set.durationSec % 60))"
                     : "—")
                if set.distanceKm > 0 { Text("· \(set.distanceKm.formatted1) km").foregroundColor(.secondary) }
            } else {
                Text(set.weight > 0 ? "\(set.weight.formatted1) kg" : "BW")
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

    private var muscles: [String] {
        Array(Set(appState.exercises.filter { $0.kind != .cardio }.map(\.muscle))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MUSCLE RECOVERY")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#A0A0B0"))
                .padding(.horizontal, 16)

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
                                .foregroundColor(Color(hex: "#30d158"))
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
                                .background(Color(hex: "#30d158"))
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

struct AIRoutineSheet: View {
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
