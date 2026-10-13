import SwiftUI

struct ProjectsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var projects: ProjectListStore
    @State private var isCreating = false
    let languageModel: any OnDeviceLanguageModel
    let voiceRecording: VoiceRecordingSession?

    init(projects: ProjectListStore, startCreating: Bool = false, languageModel: any OnDeviceLanguageModel = NoLanguageModel(), voiceRecording: VoiceRecordingSession? = nil) {
        self.projects = projects
        self.languageModel = languageModel
        self.voiceRecording = voiceRecording
        _isCreating = State(initialValue: startCreating)
    }

    var body: some View {
        NavigationStack {
            List {
                ThemedListGroup {
                    ForEach(projects.projects) { project in
                        NavigationLink {
                            ProjectDetailView(projectID: project.id, projects: projects, taskList: projects.taskList, languageModel: languageModel, voiceRecording: voiceRecording, onDone: { dismiss() })
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

private struct ProjectDetailView: View {
    @Environment(\.theme) private var theme
    let projectID: UUID
    @ObservedObject var projects: ProjectListStore
    @ObservedObject var taskList: TaskListStore
    let languageModel: any OnDeviceLanguageModel
    let voiceRecording: VoiceRecordingSession?
    let onDone: () -> Void
    @State private var isWritingMemo = false
    @State private var isRecordingMemo = false
    @State private var openMemoID: UUID?
    @State private var isRenaming = false
    @State private var isAddingTask = false
    @State private var editingTask: DailyTask?
    @State private var shareItems: ShareItems?

    private var name: String { projects.projects.first { $0.id == projectID }?.name ?? "Project" }

    var body: some View {
        List {
            ThemedListGroup("Unscheduled") {
                ForEach(projects.unscheduledTasks(in: projectID)) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.text)
                            .accessibilityIdentifier("project-task-text-\(task.id.uuidString)")
                        HStack {
                            Button("Edit") { editingTask = task }
                                .accessibilityIdentifier("project-task-edit-\(task.id.uuidString)")
                            Button("Share") { shareItems = ShareItems(.make(for: task)) }
                                .accessibilityIdentifier("project-task-share-\(task.id.uuidString)")
                            Button("Delete", role: .destructive) { taskList.deleteTask(id: task.id) }
                                .foregroundStyle(theme.destructive)
                                .accessibilityIdentifier("project-task-delete-\(task.id.uuidString)")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add task") { isAddingTask = true }
                    .accessibilityIdentifier("project-add-task")
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
        .sheet(isPresented: $isWritingMemo) {
            if let memoStore = projects.memoStore {
                WrittenMemoComposeSheet(projects: projects.projects, initialProjectID: projectID,
                    onSave: { text, photos, selected in
                        memoStore.addWrittenMemo(text: text, photos: photos, projectID: selected)
                    })
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
        .sheet(item: $editingTask) { task in
            ProjectTextForm(title: "Edit task", field: "Task", identifier: "project-task", text: task.text) {
                taskList.editTask(id: task.id, text: $0) != nil
            }
        }
        .popover(item: $shareItems) { items in
            ShareSheet(items: items) { shareItems = nil }
                .presentationDetents([.medium, .large])
                .presentationCompactAdaptation(.sheet)
        }
    }
}

private struct ProjectTextForm: View {
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
            Menu("Add memo") {
                Button("Written memo", action: onWrite)
                    .accessibilityIdentifier("project-add-written-memo")
                Button("Voice memo", action: onRecord)
                    .accessibilityIdentifier("project-add-voice-memo")
            }
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
