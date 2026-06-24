import SwiftUI

// MARK: - Tasks Filter

private enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case work = "Work"
    case gym = "Gym"
    case personal = "Personal"
    var id: String { rawValue }
}

// MARK: - TasksView

struct TasksView: View {

    @Environment(AppState.self) private var appState
    @State private var filter: TaskFilter = .all
    @State private var searchText = ""
    @State private var showAddTask = false
    @State private var showCalendar = false
    @State private var showStats = false
    @State private var undoTask: AppTask? = nil
    @State private var undoTimer: Timer? = nil
    @State private var showUndo = false
    @State private var expandedTaskId: String? = nil
    @State private var crm = CRMService()

    private var filteredTasks: [AppTask] {
        var base: [AppTask]
        if !searchText.isEmpty {
            base = appState.tasks.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText)
            }
        } else {
            switch filter {
            case .all:      base = appState.tasks
            case .today:    base = appState.tasks.filter { $0.dueDate == .today }
            case .work:     base = appState.tasks.filter { $0.category == .work }
            case .gym:      base = appState.tasks.filter { $0.category == .gym }
            case .personal: base = appState.tasks.filter { $0.category == .personal }
            }
        }
        return base
    }

    private var pendingTasks: [AppTask] {
        filteredTasks.filter { !$0.done }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    private var doneTasks: [AppTask] {
        filteredTasks.filter { $0.done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if filter == .work {
                        WorkView(
                            pendingTasks: pendingTasks,
                            doneTasks: doneTasks,
                            expandedTaskId: $expandedTaskId,
                            crm: crm,
                            onDelete: { deleteTask($0) }
                        )
                    } else if filteredTasks.isEmpty {
                        EmptyTasksView(isSearching: !searchText.isEmpty)
                    } else {
                        List {
                            if !pendingTasks.isEmpty {
                                Section {
                                    ForEach(pendingTasks) { task in
                                        TaskRow(
                                            task: task,
                                            isExpanded: expandedTaskId == task.id,
                                            onExpand: {
                                                withAnimation(.spring(response: 0.35)) {
                                                    expandedTaskId = expandedTaskId == task.id ? nil : task.id
                                                }
                                            },
                                            onDelete: { deleteTask(task) }
                                        )
                                    }
                                } header: {
                                    Text("Pending (\(pendingTasks.count))")
                                }
                            }

                            if !doneTasks.isEmpty {
                                Section {
                                    ForEach(doneTasks) { task in
                                        TaskRow(
                                            task: task,
                                            isExpanded: expandedTaskId == task.id,
                                            onExpand: {
                                                withAnimation(.spring(response: 0.35)) {
                                                    expandedTaskId = expandedTaskId == task.id ? nil : task.id
                                                }
                                            },
                                            onDelete: { deleteTask(task) }
                                        )
                                    }
                                } header: {
                                    Text("Done (\(doneTasks.count))")
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }

                if showUndo, let task = undoTask {
                    UndoToast(message: "Task deleted") {
                        appState.tasks.append(task)
                        appState.save()
                        dismissUndo()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search tasks")
            .safeAreaInset(edge: .top) {
                if searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TaskFilter.allCases) { f in
                                FilterChip(label: f.rawValue, isSelected: filter == f) {
                                    filter = f
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showStats = true } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                    Button { showCalendar = true } label: {
                        Image(systemName: "calendar")
                    }
                    Button { showAddTask = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddTask) { AddTaskSheet() }
            .sheet(isPresented: $showCalendar) { TaskCalendarView() }
            .sheet(isPresented: $showStats) { TaskStatsView() }
            .task {
                await crm.fetchAll()
            }
            .onChange(of: filter) { _, newFilter in
                if newFilter == .work {
                    Task { await crm.fetchAll() }
                }
            }
        }
        .animation(.spring(response: 0.3), value: showUndo)
    }

    private func deleteTask(_ task: AppTask) {
        undoTask = task
        expandedTaskId = nil
        appState.deleteTask(id: task.id)
        showUndo = true
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            dismissUndo()
        }
    }

    private func dismissUndo() {
        showUndo = false
        undoTask = nil
        undoTimer?.invalidate()
        undoTimer = nil
    }
}

// MARK: - Task Row

private struct TaskRow: View {
    @Environment(AppState.self) private var appState
    let task: AppTask
    let isExpanded: Bool
    let onExpand: () -> Void
    let onDelete: () -> Void

    @State private var draftTitle: String = ""
    @State private var draftNotes: String = ""
    @State private var newSubtaskText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 0) {
                // Priority bar
                if task.priority != .none {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(task.priority.color)
                        .frame(width: 3)
                        .padding(.trailing, 10)
                }

                Button {
                    HapticManager.impact(.light)
                    appState.toggleTask(id: task.id)
                } label: {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.done ? .green : task.category.color)
                        .font(.title3)
                        .scaleEffect(task.done ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: task.done)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)

                Button(action: onExpand) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .strikethrough(task.done)
                            .foregroundColor(task.done ? .secondary : .primary)

                        HStack(spacing: 6) {
                            Circle().fill(task.category.color).frame(width: 6, height: 6)
                            Text(task.category.label).font(.caption).foregroundColor(.secondary)
                            Text("·").foregroundColor(.secondary).font(.caption)
                            Text(task.dueDate?.label ?? "")
                                .font(.caption)
                                .foregroundColor(task.dueDate == .today ? .orange : .secondary)
                            if !task.notes.isEmpty {
                                Image(systemName: "note.text").font(.caption2).foregroundColor(.secondary)
                            }
                            if !task.subtasks.isEmpty {
                                Text("\(task.subtasks.filter(\.done).count)/\(task.subtasks.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .onTapGesture(perform: onExpand)
            }
            .padding(.vertical, 4)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().padding(.top, 4)

                    // Edit title
                    TextField("Task title", text: $draftTitle)
                        .font(.subheadline)
                        .padding(8)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(8)
                        .onSubmit { appState.updateTask(id: task.id, title: draftTitle) }
                        .onChange(of: draftTitle) { _, v in appState.updateTask(id: task.id, title: v) }

                    // Category picker
                    HStack(spacing: 8) {
                        Text("Category").font(.caption).foregroundColor(.secondary)
                        ForEach(TaskCategory.allCases) { cat in
                            Button {
                                appState.updateTask(id: task.id, category: cat)
                                HapticManager.selection()
                            } label: {
                                Circle()
                                    .fill(cat.color)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        task.category == cat ?
                                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white) : nil
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Priority picker
                    HStack(spacing: 8) {
                        Text("Priority").font(.caption).foregroundColor(.secondary)
                        ForEach(TaskPriority.allCases.filter { $0 != .none }) { p in
                            Button {
                                appState.updateTask(id: task.id, priority: task.priority == p ? .none : p)
                                HapticManager.selection()
                            } label: {
                                Text(p.label)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(task.priority == p ? p.color : Color(.tertiarySystemFill))
                                    .foregroundColor(task.priority == p ? .white : .secondary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Due date picker
                    HStack(spacing: 8) {
                        Text("Due").font(.caption).foregroundColor(.secondary)
                        ForEach(DueDate.allCases) { d in
                            Button {
                                appState.updateTask(id: task.id, dueDate: d)
                                HapticManager.selection()
                            } label: {
                                Text(d.label)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(task.dueDate == d ? Color(hex: "#30d158") : Color(.tertiarySystemFill))
                                    .foregroundColor(task.dueDate == d ? .white : .secondary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Notes
                    TextField("Add a note...", text: $draftNotes, axis: .vertical)
                        .font(.caption)
                        .padding(8)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(8)
                        .lineLimit(2...4)
                        .onChange(of: draftNotes) { _, v in appState.updateTask(id: task.id, notes: v) }

                    // Subtasks
                    if !task.subtasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(task.subtasks) { sub in
                                HStack(spacing: 8) {
                                    Button {
                                        appState.toggleSubtask(taskId: task.id, subtaskId: sub.id)
                                        HapticManager.impact(.light)
                                    } label: {
                                        Image(systemName: sub.done ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(sub.done ? .green : .secondary)
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.plain)
                                    Text(sub.title)
                                        .font(.caption)
                                        .strikethrough(sub.done)
                                        .foregroundColor(sub.done ? .secondary : .primary)
                                    Spacer()
                                    Button {
                                        appState.deleteSubtask(taskId: task.id, subtaskId: sub.id)
                                    } label: {
                                        Image(systemName: "xmark").font(.caption2).foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Add subtask
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle").font(.caption).foregroundColor(Color(hex: "#30d158"))
                        TextField("Add subtask...", text: $newSubtaskText)
                            .font(.caption)
                            .onSubmit {
                                let t = newSubtaskText.trimmingCharacters(in: .whitespaces)
                                guard !t.isEmpty else { return }
                                appState.addSubtask(taskId: task.id, title: t)
                                newSubtaskText = ""
                            }
                    }
                    .padding(.bottom, 4)
                }
                .padding(.leading, task.priority != .none ? 13 : 0)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .onAppear {
            draftTitle = task.title
            draftNotes = task.notes
        }
        .onChange(of: task.title) { _, v in draftTitle = v }
        .onChange(of: task.notes) { _, v in draftNotes = v }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color(hex: "#30d158") : Color(.secondarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.95))
    }
}

// MARK: - Empty State

private struct EmptyTasksView: View {
    var isSearching: Bool = false
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: isSearching ? "magnifyingglass" : "tray")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(isSearching ? "No Results" : "No Tasks")
                .font(.title2.bold())
            Text(isSearching ? "Try a different search." : "Tap + to add your first task.")
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Undo Toast

struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message).font(.subheadline).foregroundColor(.white)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
                .foregroundColor(Color(hex: "#30d158"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.darkGray))
        .cornerRadius(12)
        .padding(.horizontal, 24)
        .shadow(radius: 8)
    }
}

// MARK: - Work View (local work tasks + CRM job & general tasks)

private struct WorkView: View {
    let pendingTasks: [AppTask]
    let doneTasks: [AppTask]
    @Binding var expandedTaskId: String?
    var crm: CRMService
    let onDelete: (AppTask) -> Void

    @State private var showCRMCompleted = false

    private var incompleteJobTasks: [CRMJobTask] { crm.jobTasks.filter { !$0.completed } }

    private var jobGroups: [(key: String, ref: String, title: String, tasks: [CRMJobTask])] {
        let filtered = showCRMCompleted ? crm.jobTasks : incompleteJobTasks
        let grouped = Dictionary(grouping: filtered) { $0.leadId }
        return grouped.compactMap { (leadId, tasks) -> (key: String, ref: String, title: String, tasks: [CRMJobTask])? in
            guard let first = tasks.first else { return nil }
            return (key: leadId, ref: first.jobRef, title: first.jobTitle, tasks: tasks.sorted { $0.title < $1.title })
        }
        .sorted { $0.ref < $1.ref }
    }

    private var visibleGeneralTasks: [CRMGeneralTask] {
        crm.generalTasks.filter { showCRMCompleted || !$0.completed }
    }

    var body: some View {
        List {
            // Local work tasks
            if !pendingTasks.isEmpty {
                Section {
                    ForEach(pendingTasks) { task in
                        TaskRow(
                            task: task,
                            isExpanded: expandedTaskId == task.id,
                            onExpand: {
                                withAnimation(.spring(response: 0.35)) {
                                    expandedTaskId = expandedTaskId == task.id ? nil : task.id
                                }
                            },
                            onDelete: { onDelete(task) }
                        )
                    }
                } header: { Text("Pending (\(pendingTasks.count))") }
            }

            if !doneTasks.isEmpty {
                Section {
                    ForEach(doneTasks) { task in
                        TaskRow(
                            task: task,
                            isExpanded: expandedTaskId == task.id,
                            onExpand: {
                                withAnimation(.spring(response: 0.35)) {
                                    expandedTaskId = expandedTaskId == task.id ? nil : task.id
                                }
                            },
                            onDelete: { onDelete(task) }
                        )
                    }
                } header: { Text("Done (\(doneTasks.count))") }
            }

            // CRM divider
            if crm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if crm.error != nil {
                Text("Could not load CRM tasks")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                // CRM General Tasks
                if !visibleGeneralTasks.isEmpty {
                    Section {
                        ForEach(visibleGeneralTasks) { task in
                            CRMGeneralTaskRow(task: task) {
                                Task { await crm.completeGeneralTask(task) }
                            }
                        }
                    } header: {
                        Label("CRM — General Tasks", systemImage: "checklist")
                    }
                }

                // CRM Job Tasks grouped by job
                ForEach(jobGroups, id: \.key) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            CRMJobTaskRow(task: task) {
                                Task { await crm.completeJobTask(task) }
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.ref)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange)
                                .clipShape(Capsule())
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { Task { await crm.fetchAll() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCRMCompleted.toggle() } label: {
                    Image(systemName: showCRMCompleted ? "eye.slash" : "eye")
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct CRMJobTaskRow: View {
    let task: CRMJobTask
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.completed ? .green : .orange)
            }
            .buttonStyle(.plain)
            .disabled(task.completed)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .strikethrough(task.completed)
                    .foregroundColor(task.completed ? .secondary : .primary)
                if let due = task.dueDateParsed {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundColor(due < Date() && !task.completed ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CRMGeneralTaskRow: View {
    let task: CRMGeneralTask
    let onComplete: () -> Void

    private var priorityColor: Color {
        switch task.priority {
        case "high": return .red
        case "medium": return .orange
        default: return Color(hex: "#5E9BF0")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(task.completed ? .green : priorityColor)
            }
            .buttonStyle(.plain)
            .disabled(task.completed)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .strikethrough(task.completed)
                    .foregroundColor(task.completed ? .secondary : .primary)
                HStack(spacing: 6) {
                    if task.priority != "low" {
                        Text(task.priority.capitalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(priorityColor)
                    }
                    if let due = task.dueDateParsed {
                        Text(due, style: .date)
                            .font(.caption)
                            .foregroundColor(due < Date() && !task.completed ? .red : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Task Sheet

struct AddTaskSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: TaskCategory = .personal
    @State private var dueDate: DueDate = .today
    @State private var priority: TaskPriority = .none
    @State private var notes = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs to be done?", text: $title)
                        .focused($isTitleFocused)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(TaskCategory.allCases) { cat in
                            Label(cat.label, systemImage: "circle.fill")
                                .foregroundColor(cat.color)
                                .tag(cat)
                        }
                    }

                    Picker("Due Date", selection: $dueDate) {
                        ForEach(DueDate.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }

                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { p in
                            HStack {
                                if p != .none {
                                    Image(systemName: p.icon).foregroundColor(p.color)
                                }
                                Text(p.label)
                            }
                            .tag(p)
                        }
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        appState.addTask(
                            title: title.trimmingCharacters(in: .whitespaces),
                            category: category,
                            dueDate: dueDate,
                            priority: priority,
                            notes: notes
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isTitleFocused = true }
        }
    }
}
