import SwiftUI

struct ProjectsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var projects: ProjectListStore
    @ObservedObject var sections: CollapsedSections
    @State private var isCreating = false
    let languageModel: any OnDeviceLanguageModel
    let voiceRecording: VoiceRecordingSession?
    let onCaptureSurfaceChange: (QuickCaptureRouter.Surface?) -> Void

    init(
        projects: ProjectListStore,
        sections: CollapsedSections,
        startCreating: Bool = false,
        languageModel: any OnDeviceLanguageModel = NoLanguageModel(),
        voiceRecording: VoiceRecordingSession? = nil,
        onCaptureSurfaceChange: @escaping (QuickCaptureRouter.Surface?) -> Void = { _ in }
    ) {
        self.projects = projects
        self.sections = sections
        self.languageModel = languageModel
        self.voiceRecording = voiceRecording
        self.onCaptureSurfaceChange = onCaptureSurfaceChange
        _isCreating = State(initialValue: startCreating)
    }

    var body: some View {
        NavigationStack {
            List {
                ThemedListGroup("Active") {
                    ForEach(projects.activeProjects) { project in
                        projectLink(project)
                    }
                    Button("New project") { isCreating = true }
                        .accessibilityIdentifier("project-new")
                }
                if !projects.archivedProjects.isEmpty {
                    ThemedListGroup("Archived") {
                        ForEach(projects.archivedProjects) { project in
                            projectLink(project)
                        }
                    }
                }
            }
            .themedListBackground()
            .themedNavigationTitle("All projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("projects-done")
                }
            }
            .sheet(isPresented: $isCreating) {
                ProjectTextForm(title: "New project", field: "Project name", identifier: "project-name") {
                    projects.createProject(name: $0) != nil
                }
            }
        }
    }

    private func projectLink(_ project: Project) -> some View {
        NavigationLink {
            ProjectDetailView(projectID: project.id, projects: projects, taskList: projects.taskList,
                languageModel: languageModel, voiceRecording: voiceRecording,
                onCaptureSurfaceChange: onCaptureSurfaceChange, sections: sections, onDone: { dismiss() })
        } label: {
            Text(project.name)
        }
        .accessibilityIdentifier("project-open-\(project.id.uuidString)")
    }
}

struct ProjectDetailView: View {
    @Environment(\.theme) private var theme
    let projectID: UUID
    @ObservedObject var projects: ProjectListStore
    @ObservedObject var taskList: TaskListStore
    let languageModel: any OnDeviceLanguageModel
    let voiceRecording: VoiceRecordingSession?
    let onCaptureSurfaceChange: (QuickCaptureRouter.Surface?) -> Void
    @ObservedObject var sections: CollapsedSections
    let onDone: () -> Void
    @State private var isWritingMemo = false
    @State private var isRecordingMemo = false
    @State private var openMemoID: UUID?
    @State private var isRenaming = false
    @State private var isAddingTask = false
    @State private var schedulingTask: DailyTask?

    private var isArchived: Bool { projects.projects.first { $0.id == projectID }?.isArchived == true }

    private var name: String { projects.projects.first { $0.id == projectID }?.name ?? "Project" }

    var body: some View {
        List {
            ThemedListGroup("Today") {
                ForEach(projects.todayTasks(in: projectID).filter { !$0.isComplete }) { task in
                    taskRow(task)
                }
            }
            ThemedListGroup("Later") {
                ForEach(projects.laterTasks(in: projectID)) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        taskRow(task)
                        if let date = task.plannedOn?.date(in: .autoupdatingCurrent) {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                                .padding(.horizontal, 14)
                                .accessibilityIdentifier("project-task-planned-day-\(task.id.uuidString)")
                        }
                    }
                    .padding(.bottom, 12)
                    .listRowInsets(EdgeInsets())
                }
            }
            ThemedListGroup("Unscheduled") {
                ForEach(projects.unscheduledTasks(in: projectID)) { task in
                    taskRow(task)
                }
                if !isArchived {
                    Button("Add task") { isAddingTask = true }
                        .accessibilityIdentifier("project-add-task")
                }
            }
            ThemedListGroup {
                Button {
                    sections.toggleCompleted(projectID)
                } label: {
                    Label("Completed", systemImage: sections.isCompletedCollapsed(projectID) ? "chevron.right" : "chevron.down")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityValue(sections.isCompletedCollapsed(projectID) ? "collapsed" : "expanded")
                .accessibilityIdentifier("project-completed-collapse-\(projectID.uuidString)")
                if !sections.isCompletedCollapsed(projectID) {
                    ForEach(projects.completedTasks(in: projectID)) { task in
                        taskRow(task)
                    }
                }
            }
            if let memoStore = projects.memoStore {
                ProjectMemosSection(projectID: projectID, projects: projects, store: memoStore,
                    onOpen: { openMemoID = $0 }, onWrite: { isWritingMemo = true },
                    onRecord: { isRecordingMemo = true })
            }
        }
        .themedListBackground()
        .themedNavigationTitle(LocalizedStringKey(name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .accessibilityIdentifier("projects-done")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if isArchived {
                    Button("Restore") { projects.restoreProject(id: projectID) }
                        .accessibilityLabel("Restore project")
                        .accessibilityIdentifier("project-restore")
                } else {
                    Button("Rename") { isRenaming = true }
                        .accessibilityIdentifier("project-rename")
                    Button("Archive") { projects.archiveProject(id: projectID) }
                        .accessibilityLabel("Archive project")
                        .accessibilityIdentifier("project-archive")
                }
            }
        }
        .onChange(of: isWritingMemo) { _, showing in
            onCaptureSurfaceChange(showing ? .compose(hasUnsavedDraft: false) : nil)
        }
        .onChange(of: isRecordingMemo) { _, showing in
            onCaptureSurfaceChange(showing ? .recorder : nil)
        }
        .onDisappear {
            if !isWritingMemo && !isRecordingMemo { onCaptureSurfaceChange(nil) }
        }
        .sheet(isPresented: $isWritingMemo) {
            if let memoStore = projects.memoStore {
                WrittenMemoComposeSheet(projects: projects.projects, initialProjectID: projectID,
                    onSave: { text, photos, selected in
                        memoStore.addWrittenMemo(text: text, photos: photos, projectID: selected)
                    },
                    onDraftChange: { onCaptureSurfaceChange(.compose(hasUnsavedDraft: $0)) })
            }
        }
        .fullScreenCover(isPresented: $isRecordingMemo) {
            if let voiceRecording {
                VoiceRecorderView(session: voiceRecording, projects: projects.projects, initialProjectID: projectID,
                    onFinish: { isRecordingMemo = false })
            }
        }
        .sheet(isPresented: Binding(get: { openMemoID != nil }, set: { if !$0 { openMemoID = nil } })) {
            if let id = openMemoID, let memoStore = projects.memoStore {
                ProjectMemoDetail(id: id, projectID: projectID, store: memoStore, projects: projects, languageModel: languageModel)
            }
        }
        .sheet(isPresented: $isRenaming) {
            ProjectTextForm(title: "Rename project", field: "Project name", identifier: "project-name", text: name) {
                projects.renameProject(id: projectID, name: $0) != nil
            }
        }
        .sheet(item: $schedulingTask) { task in
            TaskSchedulingSheet(date: task.plannedOn?.date(in: .autoupdatingCurrent), languageModel: languageModel) {
                taskList.deferTask(id: task.id, to: $0) != nil
            }
        }
        .sheet(isPresented: $isAddingTask) {
            ProjectTaskCaptureSheet(languageModel: languageModel) { text, plannedFor in
                if let plannedFor {
                    return projects.addTask(text: text, to: projectID, plannedFor: plannedFor) != nil
                }
                return projects.addTask(text: text, to: projectID) != nil
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: DailyTask) -> some View {
        if isArchived {
            HStack {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(task.text)
            }
            .foregroundStyle(task.isComplete ? theme.secondaryText : theme.primaryText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(task.isComplete ? "\(task.text), completed" : task.text)
            .accessibilityIdentifier("project-task-reference-\(task.id.uuidString)")
        } else {
            TaskRow(task: task,
                    onToggle: {
                        if task.isUnscheduled && !task.isComplete { projects.doToday(taskID: task.id) }
                        else { taskList.toggleTask(id: task.id) }
                    },
                    onEdit: { taskList.editTask(id: task.id, text: $0) != nil },
                    onDelete: { taskList.deleteTask(id: task.id) },
                    onDoLater: { schedulingTask = task },
                    onReturnToProject: task.isUnscheduled ? nil : { projects.returnToProject(taskID: task.id) },
                    projects: projects.projects,
                    onAssignProject: { taskList.assignTask(id: task.id, to: $0) })
                .listRowInsets(EdgeInsets())
        }
    }
}

private struct ProjectTaskCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var plannedFor: Date?
    @State private var isScheduling = false
    let languageModel: any OnDeviceLanguageModel
    let onSave: (String, Date?) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                ThemedListGroup {
                    TextField("Task", text: $text)
                        .accessibilityIdentifier("project-task-editor")
                }
                ThemedListGroup("Availability") {
                    Group {
                        if let plannedFor {
                            Text(plannedFor, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        } else {
                            Text("Unscheduled")
                        }
                    }
                    .accessibilityIdentifier("project-task-availability")
                    Button("Unscheduled") { plannedFor = nil }
                        .accessibilityIdentifier("project-task-unscheduled")
                    Button("Today") { plannedFor = Calendar.autoupdatingCurrent.startOfDay(for: .now) }
                        .accessibilityIdentifier("project-task-today")
                    Button("Planned day") { isScheduling = true }
                        .accessibilityIdentifier("project-task-schedule")
                }
            }
            .themedListBackground()
            .themedNavigationTitle("Add task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("project-task-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if onSave(text, plannedFor) { dismiss() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("project-task-save")
                }
            }
            .sheet(isPresented: $isScheduling) {
                TaskSchedulingSheet(date: plannedFor, languageModel: languageModel) {
                    plannedFor = $0
                    return true
                }
            }
        }
    }
}

struct ProjectTextForm: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let field: String
    let identifier: String
    @State var text: String = ""
    let onSave: (String) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                ThemedListGroup {
                    TextField(field, text: $text)
                        .accessibilityIdentifier("\(identifier)-editor")
                }
            }
            .themedListBackground()
            .themedNavigationTitle(LocalizedStringKey(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("\(identifier)-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if onSave(text) { dismiss() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("\(identifier)-save")
                }
            }
        }
    }
}

private struct ProjectMemosSection: View {
    let projectID: UUID
    @ObservedObject var projects: ProjectListStore
    @ObservedObject var store: MemoStore
    let onOpen: (UUID) -> Void
    let onWrite: () -> Void
    let onRecord: () -> Void

    var body: some View {
        ThemedListGroup("Memos") {
            ForEach(projects.memos(in: projectID)) { memo in
                Button { onOpen(memo.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(memo.title)
                        if let detail = memo.detail { Text(detail).font(.caption).lineLimit(2) }
                    }
                }
                .accessibilityIdentifier("project-memo-open-\(memo.id.uuidString)")
            }
            if projects.activeProjects.contains(where: { $0.id == projectID }) {
                Menu {
                    Button("Written memo", action: onWrite)
                        .accessibilityIdentifier("project-add-written-memo")
                    Button("Voice memo", action: onRecord)
                        .accessibilityIdentifier("project-add-voice-memo")
                } label: {
                    Text("Add memo")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("project-add-memo")
            }
        }
    }
}

private struct ProjectMemoDetail: View {
    let id: UUID
    let projectID: UUID
    @ObservedObject var store: MemoStore
    @ObservedObject var projects: ProjectListStore
    let languageModel: any OnDeviceLanguageModel

    var body: some View {
        if let memo = store.memo(id: id) {
            MemoCardSheet(memo: memo, store: store, languageModel: languageModel,
                taskList: projects.taskList, projects: projects.projects,
                isReadOnly: projects.archivedProjects.contains { $0.id == projectID })
        }
    }
}

struct TaskProjectAssignmentMenu: View {
    let task: DailyTask
    let projects: [Project]
    let assign: (UUID?) -> Void

    var body: some View {
        if projects.contains(where: { !$0.isArchived }) {
            Menu("Move to project", systemImage: "folder") {
                ForEach(projects.filter { !$0.isArchived }) { project in
                    Button(project.name) { assign(project.id) }
                        .accessibilityIdentifier("task-project-option-\(project.id.uuidString)")
                }
            }
            .accessibilityIdentifier("task-move-project-\(task.id.uuidString)")
        }
        if task.projectID != nil {
            Button("Remove from project", systemImage: "folder.badge.minus") { assign(nil) }
                .accessibilityIdentifier("task-remove-project-\(task.id.uuidString)")
        }
    }
}

struct TaskCaptureProjectPicker: View {
    let projects: [Project]
    @Binding var projectID: UUID?

    private var selectionName: String {
        projectID.flatMap { id in projects.first { $0.id == id }?.name } ?? "No project"
    }

    var body: some View {
        Menu {
            Button("No project") { projectID = nil }
                .accessibilityIdentifier("new-task-project-none")
            ForEach(projects.filter { !$0.isArchived }) { project in
                Button(project.name) { projectID = project.id }
                    .accessibilityIdentifier("new-task-project-option-\(project.id.uuidString)")
            }
        } label: {
            Label(selectionName, systemImage: "folder")
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Project")
        .accessibilityValue(selectionName)
        .accessibilityIdentifier("new-task-project-picker")
    }
}
