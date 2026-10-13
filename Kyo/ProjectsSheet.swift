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
                ThemedListGroup {
                    ForEach(projects.projects) { project in
                        NavigationLink {
                            ProjectDetailView(projectID: project.id, projects: projects, taskList: projects.taskList,
                                languageModel: languageModel, voiceRecording: voiceRecording,
                                onCaptureSurfaceChange: onCaptureSurfaceChange, sections: sections, onDone: { dismiss() })
                        } label: {
                            Text(project.name)
                        }
                        .accessibilityIdentifier("project-open-\(project.id.uuidString)")
                    }
                    Button("New project") { isCreating = true }
                        .accessibilityIdentifier("project-new")
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
}

struct ProjectDetailView: View {
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

    private var name: String { projects.projects.first { $0.id == projectID }?.name ?? "Project" }

    var body: some View {
        List {
            ThemedListGroup("Today") {
                ForEach(projects.todayTasks(in: projectID).filter { !$0.isComplete }) { task in
                    taskRow(task)
                }
            }
            ThemedListGroup("Unscheduled") {
                ForEach(projects.unscheduledTasks(in: projectID)) { task in
                    taskRow(task)
                }
                Button("Add task") { isAddingTask = true }
                    .accessibilityIdentifier("project-add-task")
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
            ToolbarItem(placement: .primaryAction) {
                Button("Rename") { isRenaming = true }
                    .accessibilityIdentifier("project-rename")
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
                ProjectMemoDetail(id: id, store: memoStore, projects: projects, languageModel: languageModel)
            }
        }
        .sheet(isPresented: $isRenaming) {
            ProjectTextForm(title: "Rename project", field: "Project name", identifier: "project-name", text: name) {
                projects.renameProject(id: projectID, name: $0) != nil
            }
        }
        .sheet(isPresented: $isAddingTask) {
            ProjectTextForm(title: "Add task", field: "Task", identifier: "project-task") {
                projects.addTask(text: $0, to: projectID) != nil
            }
        }
    }

    private func taskRow(_ task: DailyTask) -> some View {
        TaskRow(task: task,
                onToggle: {
                    if task.isUnscheduled && !task.isComplete { projects.doToday(taskID: task.id) }
                    else { taskList.toggleTask(id: task.id) }
                },
                onEdit: { taskList.editTask(id: task.id, text: $0) != nil },
                onDelete: { taskList.deleteTask(id: task.id) },
                onReturnToProject: task.isUnscheduled ? nil : { projects.returnToProject(taskID: task.id) })
            .listRowInsets(EdgeInsets())
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

private struct ProjectMemoDetail: View {
    let id: UUID
    @ObservedObject var store: MemoStore
    @ObservedObject var projects: ProjectListStore
    let languageModel: any OnDeviceLanguageModel

    var body: some View {
        if let memo = store.memo(id: id) {
            MemoCardSheet(memo: memo, store: store, languageModel: languageModel,
                taskList: projects.taskList, projects: projects.projects)
        }
    }
}
