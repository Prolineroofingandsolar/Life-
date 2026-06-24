import SwiftUI

// MARK: - Task Calendar View

struct TaskCalendarView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var weekOffset: Int = 0

    private var weekDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: today) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var tasksForSelected: [AppTask] {
        let cal = Calendar.current
        return appState.tasks
            .filter { task in
                guard !task.done, let resolved = task.resolvedDate else { return false }
                return cal.startOfDay(for: resolved) == selectedDate
            }
            .sorted {
                if let ta = $0.scheduledTime, let tb = $1.scheduledTime { return ta < tb }
                if $0.scheduledTime != nil { return true }
                if $1.scheduledTime != nil { return false }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private var scheduledTasks: [AppTask] { tasksForSelected.filter { $0.scheduledTime != nil } }
    private var unscheduledTasks: [AppTask] { tasksForSelected.filter { $0.scheduledTime == nil } }

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            weekStrip
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if tasksForSelected.isEmpty {
                        emptyState
                    } else {
                        if !scheduledTasks.isEmpty {
                            ForEach(Array(scheduledTasks.enumerated()), id: \.element.id) { idx, task in
                                TimelineRow(task: task, isLast: idx == scheduledTasks.count - 1 && unscheduledTasks.isEmpty)
                            }
                        }
                        if !unscheduledTasks.isEmpty {
                            Text("NO TIME")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                                .padding(.bottom, 8)
                            VStack(spacing: 0) {
                                ForEach(Array(unscheduledTasks.enumerated()), id: \.element.id) { idx, task in
                                    NoTimeRow(task: task)
                                    if idx < unscheduledTasks.count - 1 {
                                        Divider().padding(.leading, 20)
                                    }
                                }
                            }
                            .background(AppTheme.cardBg)
                            .cornerRadius(AppTheme.chipRadius)
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                            .padding(.horizontal, 16)
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        } // NavigationStack
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 36)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(weekDates, id: \.self) { date in
                        DayChip(date: date, isSelected: date == selectedDate) {
                            withAnimation(.spring(response: 0.25)) { selectedDate = date }
                            HapticManager.selection()
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Button {
                withAnimation(.spring(response: 0.3)) { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Nothing scheduled")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Tap + to add a task for this day")
                .font(.subheadline)
                .foregroundColor(Color(.tertiaryLabel))
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Day Chip

private struct DayChip: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(isSelected ? .white : (isToday ? AppTheme.primary : .secondary))
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isSelected ? .white : (isToday ? AppTheme.primary : .primary))
            }
            .frame(width: 44, height: 52)
            .background(isSelected ? AppTheme.primary : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }
}

// MARK: - Timeline Row

private struct TimelineRow: View {
    @Environment(AppState.self) private var appState
    let task: AppTask
    let isLast: Bool

    private var list: TaskList? { appState.taskList(for: task) }
    private var timeLabel: String {
        guard let t = task.scheduledTime else { return "" }
        return t.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        NavigationLink(destination: TaskDetailView(taskId: task.id)) {
            HStack(alignment: .top, spacing: 12) {
                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
                    .padding(.top, 14)

                VStack(spacing: 0) {
                    Circle()
                        .fill(list?.color ?? AppTheme.primary)
                        .frame(width: 10, height: 10)
                        .padding(.top, 15)
                    if !isLast {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        if let list = list {
                            Text(list.emoji + " " + list.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let mins = task.estimatedMinutes {
                            Text("· \(mins < 60 ? "\(mins)m" : "\(mins / 60)h\(mins % 60 > 0 ? " \(mins % 60)m" : "")")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if task.isRecurring {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 10)
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - No Time Row

private struct NoTimeRow: View {
    @Environment(AppState.self) private var appState
    let task: AppTask

    private var list: TaskList? { appState.taskList(for: task) }

    var body: some View {
        NavigationLink(destination: TaskDetailView(taskId: task.id)) {
            HStack(spacing: 12) {
                Circle()
                    .fill(list?.color ?? AppTheme.primary)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    if let list = list {
                        Text(list.emoji + " " + list.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}
