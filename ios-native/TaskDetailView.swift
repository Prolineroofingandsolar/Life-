import SwiftUI

// MARK: - Task Detail View

struct TaskDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let taskId: String

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var listId: String = "personal"
    @State private var dueDate: DueDate? = .today
    @State private var useCustomDate: Bool = false
    @State private var customDate: Date = Date()
    @State private var priority: TaskPriority = .none
    @State private var reminderEnabled: Bool = false
    @State private var reminderDate: Date = Date()
    @State private var newSubtaskText: String = ""
    @State private var showDeleteConfirm: Bool = false
    @FocusState private var titleFocused: Bool

    private var task: AppTask? { appState.tasks.first { $0.id == taskId } }
    private var list: TaskList? { task.flatMap { appState.taskList(for: $0) } }

    private var subtasks: [Subtask] { task?.subtasks ?? [] }

    var body: some View {
        Group {
            if task != nil {
                content
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48)).foregroundColor(.green)
                    Text("Task completed").font(.headline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(AppTheme.danger)
                }
            }
        }
        .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                appState.deleteTask(id: taskId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { populateFromTask() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                TextField("Task title", text: $title, axis: .vertical)
                    .font(.title3.bold())
                    .focused($titleFocused)
                    .padding(20)
                    .onChange(of: title) { _, v in
                        appState.updateTask(id: taskId, title: v)
                    }

                Divider().padding(.horizontal, 20)

                // Notes
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Add notes...")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notes)
                        .font(.subheadline)
                        .frame(minHeight: 80)
                        .scrollDisabled(true)
                        .onChange(of: notes) { _, v in
                            appState.updateTask(id: taskId, notes: v)
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider().padding(.horizontal, 20)

                // Detail rows
                VStack(spacing: 0) {
                    // List picker
                    detailRow(icon: "list.bullet", iconColor: list?.color ?? .secondary, label: "List") {
                        Picker("List", selection: $listId) {
                            ForEach(appState.taskLists) { l in
                                Label(l.name, systemImage: "circle.fill")
                                    .tag(l.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: listId) { _, v in
                            appState.updateTask(id: taskId, listId: v)
                        }
                    }

                    Divider().padding(.leading, 56)

                    // Due date
                    detailRow(icon: "calendar", iconColor: .orange, label: "Due Date") {
                        Menu {
                            Button("No Date") {
                                dueDate = nil
                                useCustomDate = false
                                appState.updateTask(id: taskId, dueDate: .some(nil), dueDateOverride: .some(nil))
                            }
                            Button("Today") {
                                dueDate = .today
                                useCustomDate = false
                                appState.updateTask(id: taskId, dueDate: .some(.today), dueDateOverride: .some(nil))
                            }
                            Button("Tomorrow") {
                                dueDate = .tomorrow
                                useCustomDate = false
                                appState.updateTask(id: taskId, dueDate: .some(.tomorrow), dueDateOverride: .some(nil))
                            }
                            Button("This Week") {
                                dueDate = .thisWeek
                                useCustomDate = false
                                appState.updateTask(id: taskId, dueDate: .some(.thisWeek), dueDateOverride: .some(nil))
                            }
                        } label: {
                            Text(useCustomDate
                                 ? customDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                 : (dueDate?.label ?? "No Date"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Custom date picker (shown inline when useCustomDate)
                    if useCustomDate {
                        DatePicker("", selection: $customDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding(.horizontal, 16)
                            .onChange(of: customDate) { _, v in
                                appState.updateTask(id: taskId, dueDateOverride: .some(v))
                            }
                    }

                    Divider().padding(.leading, 56)

                    // Priority
                    detailRow(icon: "flag.fill", iconColor: priority == .none ? .secondary : priority.color, label: "Priority") {
                        HStack(spacing: 6) {
                            ForEach(TaskPriority.allCases.filter { $0 != .none }) { p in
                                Button {
                                    priority = priority == p ? .none : p
                                    appState.updateTask(id: taskId, priority: priority)
                                    HapticManager.selection()
                                } label: {
                                    Text(p.label)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(priority == p ? p.color : Color(.tertiarySystemFill))
                                        .foregroundColor(priority == p ? .white : .secondary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider().padding(.leading, 56)

                    // Reminder
                    detailRow(icon: "bell.fill", iconColor: reminderEnabled ? AppTheme.primary : .secondary, label: "Reminder") {
                        Toggle("", isOn: $reminderEnabled)
                            .onChange(of: reminderEnabled) { _, v in
                                appState.updateTask(id: taskId, reminderDate: .some(v ? reminderDate : nil))
                            }
                    }
                    if reminderEnabled {
                        DatePicker("", selection: $reminderDate)
                            .datePickerStyle(.compact)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .onChange(of: reminderDate) { _, v in
                                appState.updateTask(id: taskId, reminderDate: .some(v))
                            }
                    }
                }
                .padding(.vertical, 4)
                .background(AppTheme.cardBg)
                .cornerRadius(AppTheme.chipRadius)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Subtasks
                VStack(alignment: .leading, spacing: 0) {
                    Text("Subtasks")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 10)

                    VStack(spacing: 0) {
                        ForEach(subtasks) { sub in
                            HStack(spacing: 12) {
                                Button {
                                    appState.toggleSubtask(taskId: taskId, subtaskId: sub.id)
                                    HapticManager.impact(.light)
                                } label: {
                                    Image(systemName: sub.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(sub.done ? .green : .secondary)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)

                                Text(sub.title)
                                    .font(.subheadline)
                                    .strikethrough(sub.done)
                                    .foregroundColor(sub.done ? .secondary : .primary)
                                Spacer()
                                Button {
                                    appState.deleteSubtask(taskId: taskId, subtaskId: sub.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if sub.id != subtasks.last?.id {
                                Divider().padding(.leading, 48)
                            }
                        }

                        // Add subtask row
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(AppTheme.primary)
                                .font(.title3)
                            TextField("Add subtask...", text: $newSubtaskText)
                                .font(.subheadline)
                                .submitLabel(.done)
                                .onSubmit {
                                    let t = newSubtaskText.trimmingCharacters(in: .whitespaces)
                                    guard !t.isEmpty else { return }
                                    appState.addSubtask(taskId: taskId, title: t)
                                    newSubtaskText = ""
                                }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(AppTheme.cardBg)
                    .cornerRadius(AppTheme.chipRadius)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func detailRow<Content: View>(icon: String, iconColor: Color, label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 28)
            Text(label)
                .font(.subheadline)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func populateFromTask() {
        guard let task = task else { return }
        title        = task.title
        notes        = task.notes
        listId       = task.listId
        priority     = task.priority
        if let override = task.dueDateOverride {
            useCustomDate = true
            customDate    = override
        } else {
            useCustomDate = false
            dueDate       = task.dueDate
        }
        if let reminder = task.reminderDate {
            reminderEnabled = true
            reminderDate    = reminder
        } else {
            reminderEnabled = false
        }
    }
}
