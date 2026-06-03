import SwiftUI

// MARK: - Task Section Model

private struct TaskSection: Identifiable {
    let id: String
    let title: String
    let color: Color
    let tasks: [AppTask]
}

// MARK: - TasksView

struct TasksView: View {

    @Environment(AppState.self) private var appState
    @State private var selectedListId: String = "all"
    @State private var searchText = ""
    @State private var showAddTask = false
    @State private var showManageLists = false
    @State private var quickTitle = ""
    @State private var collapsedSections: Set<String> = ["done"]
    @State private var undoTask: AppTask? = nil
    @State private var undoTimer: Timer? = nil
    @State private var showUndo = false

    // MARK: - Filtered tasks

    private var filteredTasks: [AppTask] {
        var base = appState.tasks
        if !searchText.isEmpty {
            base = base.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText)
            }
        } else if selectedListId != "all" {
            base = base.filter { $0.listId == selectedListId }
        }
        return base
    }

    // MARK: - Date-grouped sections

    private var taskSections: [TaskSection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let weekEnd  = cal.date(byAdding: .day, value: 7, to: today)!

        let pending = filteredTasks.filter { !$0.done }
        let done    = filteredTasks.filter { $0.done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        var overdue: [AppTask] = []
        var todayTasks: [AppTask] = []
        var tomorrowTasks: [AppTask] = []
        var thisWeekTasks: [AppTask] = []
        var laterTasks: [AppTask] = []
        var noDate: [AppTask] = []

        for task in pending.sorted(by: { $0.priority.sortOrder < $1.priority.sortOrder }) {
            guard let date = task.resolvedDate else { noDate.append(task); continue }
            let day = cal.startOfDay(for: date)
            if day < today           { overdue.append(task) }
            else if day == today     { todayTasks.append(task) }
            else if day == tomorrow  { tomorrowTasks.append(task) }
            else if day < weekEnd    { thisWeekTasks.append(task) }
            else                     { laterTasks.append(task) }
        }

        var sections: [TaskSection] = []
        if !overdue.isEmpty     { sections.append(.init(id: "overdue",   title: "Overdue",    color: .red,             tasks: overdue)) }
        if !todayTasks.isEmpty  { sections.append(.init(id: "today",     title: "Today",      color: AppTheme.primary, tasks: todayTasks)) }
        if !tomorrowTasks.isEmpty { sections.append(.init(id: "tomorrow", title: "Tomorrow",  color: .orange,          tasks: tomorrowTasks)) }
        if !thisWeekTasks.isEmpty { sections.append(.init(id: "thisWeek", title: "This Week", color: .blue,            tasks: thisWeekTasks)) }
        if !laterTasks.isEmpty  { sections.append(.init(id: "later",     title: "Later",      color: .secondary,       tasks: laterTasks)) }
        if !noDate.isEmpty      { sections.append(.init(id: "noDate",    title: "No Date",    color: .secondary,       tasks: noDate)) }
        if !done.isEmpty        { sections.append(.init(id: "done",      title: "Done",       color: .secondary,       tasks: done)) }
        return sections
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if taskSections.isEmpty && searchText.isEmpty {
                        EmptyTasksView(isSearching: false)
                    } else if taskSections.isEmpty {
                        EmptyTasksView(isSearching: true)
                    } else {
                        List {
                            ForEach(taskSections) { section in
                                Section {
                                    if !collapsedSections.contains(section.id) {
                                        ForEach(section.tasks) { task in
                                            NavigationLink(destination: TaskDetailView(taskId: task.id)) {
                                                TaskRow(task: task, listColor: appState.taskList(for: task)?.color)
                                            }
                                            .swipeActions(edge: .leading) {
                                                Button {
                                                    HapticManager.impact(.light)
                                                    appState.toggleTask(id: task.id)
                                                } label: {
                                                    Label("Done", systemImage: "checkmark.circle.fill")
                                                }
                                                .tint(.green)
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    deleteTask(task)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                } header: {
                                    TaskSectionHeader(
                                        section: section,
                                        isCollapsed: collapsedSections.contains(section.id),
                                        onClearDone: section.id == "done" ? {
                                            HapticManager.impact(.medium)
                                            section.tasks.forEach { appState.deleteTask(id: $0.id) }
                                        } : nil
                                    ) {
                                        withAnimation(.spring(response: 0.3)) {
                                            if collapsedSections.contains(section.id) {
                                                collapsedSections.remove(section.id)
                                            } else {
                                                collapsedSections.insert(section.id)
                                            }
                                        }
                                    }
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
                    .padding(.bottom, 8)
                    .zIndex(1)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search tasks")
            .safeAreaInset(edge: .top, spacing: 0) {
                if searchText.isEmpty {
                    ListPickerBar(
                        lists: appState.taskLists,
                        selectedId: $selectedListId,
                        onManage: { showManageLists = true }
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                QuickAddBar(text: $quickTitle, onSubmit: addQuickTask, onExpand: { showAddTask = true })
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddTask = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddTask) {
                AddTaskSheet(initialListId: selectedListId == "all" ? "personal" : selectedListId)
            }
            .sheet(isPresented: $showManageLists) {
                ManageListsSheet()
            }
        }
        .animation(.spring(response: 0.3), value: showUndo)
    }

    // MARK: - Actions

    private func addQuickTask() {
        let t = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let listId = selectedListId == "all" ? "personal" : selectedListId
        appState.addTask(title: t, listId: listId, dueDate: nil)
        HapticManager.impact(.light)
        quickTitle = ""
    }

    private func deleteTask(_ task: AppTask) {
        undoTask = task
        appState.deleteTask(id: task.id)
        showUndo = true
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async { dismissUndo() }
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
    var listColor: Color?

    private var overdue: Bool {
        guard !task.done, let date = task.resolvedDate else { return false }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

    private var checkboxColor: Color {
        task.done ? (listColor ?? AppTheme.primary) : (overdue ? .red : (listColor ?? Color(.systemFill)))
    }

    var body: some View {
        HStack(spacing: 12) {
            // Priority stripe
            if task.priority != .none {
                RoundedRectangle(cornerRadius: 2)
                    .fill(task.priority.color)
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }

            // Square checkbox
            Button {
                HapticManager.impact(.light)
                appState.toggleTask(id: task.id)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(task.done ? checkboxColor : .clear)
                        .frame(width: 22, height: 22)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(checkboxColor, lineWidth: task.done ? 0 : 1.5)
                        .frame(width: 22, height: 22)
                    if task.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: task.done)
            }
            .buttonStyle(.plain)

            // Title + list subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.done)
                    .foregroundColor(task.done ? .secondary : .primary)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 4) {
                    if let list = appState.taskList(for: task) {
                        Text(list.emoji + " " + list.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !task.subtasks.isEmpty {
                        Text("· \(task.subtasks.filter(\.done).count)/\(task.subtasks.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Right column: date label + bell
            VStack(alignment: .trailing, spacing: 2) {
                if task.dueDate != nil || task.dueDateOverride != nil {
                    Text(task.dueDateLabel)
                        .font(.caption)
                        .foregroundColor(overdue ? .red : .secondary)
                }
                if task.reminderDate != nil {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Section Header

private struct TaskSectionHeader: View {
    let section: TaskSection
    let isCollapsed: Bool
    var onClearDone: (() -> Void)?
    let onToggle: () -> Void

    private var titleColor: Color {
        switch section.id {
        case "overdue": return .red
        case "today":   return AppTheme.primary
        default:        return .secondary
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Text(section.title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundColor(titleColor)
                    .tracking(0.5)
                Spacer()
                if let clearDone = onClearDone {
                    Button("Clear") { clearDone() }
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppTheme.primary)
                }
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - List Picker Bar

private struct ListPickerBar: View {
    let lists: [TaskList]
    @Binding var selectedId: String
    let onManage: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                listChip(id: "all", emoji: nil, name: "All", color: AppTheme.primary)
                ForEach(lists) { list in
                    listChip(id: list.id, emoji: list.emoji, name: list.name, color: list.color)
                }
                Button(action: onManage) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundColor(.secondary)
                        .cornerRadius(20)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.95))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func listChip(id: String, emoji: String?, name: String, color: Color) -> some View {
        let isSelected = selectedId == id
        Button {
            HapticManager.selection()
            selectedId = id
        } label: {
            HStack(spacing: 4) {
                if let emoji = emoji {
                    Text(emoji).font(.caption)
                }
                Text(name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(isSelected ? color : Color(.secondarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.95))
    }
}

// MARK: - Quick Add Bar

private struct QuickAddBar: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Add task...", text: $text)
                .font(.subheadline)
                .submitLabel(.done)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppTheme.primary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            Button(action: onExpand) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: "mic")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
        .animation(.spring(response: 0.25), value: text.isEmpty)
    }
}

// MARK: - Empty State

private struct EmptyTasksView: View {
    var isSearching: Bool = false
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: isSearching ? "magnifyingglass" : "checkmark.circle")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text(isSearching ? "No Results" : "All Clear!")
                .font(.title2.bold())
            Text(isSearching ? "Try a different search." : "Add a task below or tap +")
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
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
                .foregroundColor(AppTheme.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }
}

// MARK: - Add Task Sheet

struct AddTaskSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var initialListId: String = "personal"

    @State private var title = ""
    @State private var listId: String = "personal"
    @State private var dueDate: DueDate? = .today
    @State private var useCustomDate = false
    @State private var customDate = Date()
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
                    Picker("List", selection: $listId) {
                        ForEach(appState.taskLists) { l in
                            Label(l.name, systemImage: "circle.fill")
                                .tag(l.id)
                        }
                    }

                    Toggle("Pick a specific date", isOn: $useCustomDate)
                    if useCustomDate {
                        DatePicker("Date", selection: $customDate, displayedComponents: .date)
                    } else {
                        Picker("Due Date", selection: Binding(
                            get: { dueDate ?? .today },
                            set: { dueDate = $0 }
                        )) {
                            Text("No Date").tag(Optional<DueDate>.none)
                            ForEach(DueDate.allCases) { d in
                                Text(d.label).tag(Optional(d))
                            }
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
                            listId: listId,
                            dueDate: useCustomDate ? .today : dueDate,
                            dueDateOverride: useCustomDate ? customDate : nil,
                            priority: priority,
                            notes: notes
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                listId = initialListId
                isTitleFocused = true
            }
        }
    }
}

// MARK: - Manage Lists Sheet

struct ManageListsSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showAddList = false
    @State private var editingList: TaskList? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.taskLists) { list in
                    HStack(spacing: 12) {
                        Text(list.emoji).font(.title3)
                        Text(list.name).font(.subheadline)
                        Spacer()
                        Circle()
                            .fill(list.color)
                            .frame(width: 12, height: 12)
                        if !list.isSystem {
                            Button {
                                editingList = list
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        let list = appState.taskLists[idx]
                        if !list.isSystem { appState.deleteTaskList(id: list.id) }
                    }
                }
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddList = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddList) {
                EditListSheet(existingList: nil)
            }
            .sheet(item: $editingList) { list in
                EditListSheet(existingList: list)
            }
        }
    }
}

// MARK: - Edit List Sheet

private struct EditListSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var existingList: TaskList?

    @State private var name: String = ""
    @State private var emoji: String = "📋"
    @State private var colorHex: String = "#5E9BF0"

    private let presetColors: [(String, String)] = [
        ("#5E9BF0", "Blue"), ("#30d158", "Green"), ("#FF9F0A", "Orange"),
        ("#FF375F", "Red"), ("#BF5AF2", "Purple"), ("#5E5CE6", "Indigo"),
        ("#64D2FF", "Cyan"), ("#FFD700", "Gold"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    HStack {
                        TextField("Emoji", text: $emoji)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                        TextField("List name", text: $name)
                    }
                }
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(presetColors, id: \.0) { hex, label in
                            Button {
                                colorHex = hex
                                HapticManager.selection()
                            } label: {
                                ZStack {
                                    Circle().fill(Color(hex: hex)).frame(width: 44, height: 44)
                                    if colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(existingList == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        let em = emoji.isEmpty ? "📋" : String(emoji.prefix(2))
                        if let existing = existingList {
                            appState.updateTaskList(id: existing.id, name: n, emoji: em, colorHex: colorHex)
                        } else {
                            appState.addTaskList(name: n, emoji: em, colorHex: colorHex)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let list = existingList {
                    name     = list.name
                    emoji    = list.emoji
                    colorHex = list.colorHex
                }
            }
        }
    }
}
