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
    @State private var showAddTask = false
    @State private var undoTask: AppTask? = nil
    @State private var undoTimer: Timer? = nil
    @State private var showUndo = false

    private var filteredTasks: [AppTask] {
        let base: [AppTask]
        switch filter {
        case .all:      base = appState.tasks
        case .today:    base = appState.tasks.filter { $0.dueDate == .today }
        case .work:     base = appState.tasks.filter { $0.category == .work }
        case .gym:      base = appState.tasks.filter { $0.category == .gym }
        case .personal: base = appState.tasks.filter { $0.category == .personal }
        }
        return base
    }

    private var pendingTasks: [AppTask] {
        filteredTasks.filter { !$0.done }
    }

    private var doneTasks: [AppTask] {
        filteredTasks.filter { $0.done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if filteredTasks.isEmpty {
                        EmptyTasksView()
                    } else {
                        List {
                            if !pendingTasks.isEmpty {
                                Section {
                                    ForEach(pendingTasks) { task in
                                        TaskRow(task: task, onDelete: { deleteTask(task) })
                                    }
                                } header: {
                                    Text("Pending (\(pendingTasks.count))")
                                }
                            }

                            if !doneTasks.isEmpty {
                                Section {
                                    ForEach(doneTasks) { task in
                                        TaskRow(task: task, onDelete: { deleteTask(task) })
                                    }
                                } header: {
                                    Text("Done (\(doneTasks.count))")
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }

                // Undo toast
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
            .safeAreaInset(edge: .top) {
                // Filter chips
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddTask) {
                AddTaskSheet()
            }
        }
        .animation(.spring(response: 0.3), value: showUndo)
    }

    private func deleteTask(_ task: AppTask) {
        undoTask = task
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
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.done)
                    .foregroundColor(task.done ? .secondary : .primary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(task.category.color)
                        .frame(width: 6, height: 6)
                    Text(task.category.label)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Text(task.dueDate.label)
                        .font(.caption)
                        .foregroundColor(task.dueDate == .today ? .orange : .secondary)
                }
            }

            Spacer()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
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
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("No Tasks")
                .font(.title2.bold())
            Text("Tap + to add your first task.")
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
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
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

// MARK: - Add Task Sheet

struct AddTaskSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: TaskCategory = .personal
    @State private var dueDate: DueDate = .today
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs to be done?", text: $title)
                        .focused($isTitleFocused)
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
                        appState.addTask(title: title.trimmingCharacters(in: .whitespaces), category: category, dueDate: dueDate)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isTitleFocused = true }
        }
    }
}
