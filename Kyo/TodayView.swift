import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.theme) private var theme
    @StateObject private var taskList: TaskListStore
    @StateObject private var projects: ProjectListStore
    @StateObject private var habitList: HabitListStore
    @StateObject private var memoStore: MemoStore
    @StateObject private var schedule: ScheduleStore
    /// Which sections are collapsed, kept on this device.
    @StateObject private var sections: CollapsedSections
    private let languageModel: any OnDeviceLanguageModel
    /// Where **Record memo** and **Write memo** (controls, Siri, Shortcuts) land.
    @ObservedObject private var quickCapture: QuickCaptureRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeSheet: TodayPreviewSheet?
    /// Which main view the bottom bar has selected. Kyo always launches into Today.
    @State private var mainView: MainView = .today
    @StateObject private var month: MonthModel
    /// Created when Today first appears, once the memo store exists.
    @State private var voiceRecording: VoiceRecordingSession?
    @State private var isShowingRecorder = false
    /// Whether the compose sheet holds text or a photo, which quick capture mustn't throw away.
    @State private var composeHasDraft = false
    @State private var projectCaptureSurface: QuickCaptureRouter.Surface?
    /// The capture quick capture opens once the sheet it closed has finished dismissing.
    @State private var captureAfterSheetDismissal: QuickCaptureRouter.Target?
    @State private var voiceMemoPendingDelete: UUID?
    @State private var isShowingTaskDraft = false
    @State private var taskDraft = ""
    @State private var taskDraftProjectID: UUID?
    /// Set when + → Task brings back a draft that was hidden by collapsing Tasks, so the row scrolls
    /// into view and takes focus once it's on screen again.
    @State private var revealTaskDraftWhenShown = false
    @State private var dayBoundaryRefreshToken = 0
    @FocusState private var isTaskDraftFocused: Bool

    init(modelContainer: ModelContainer, quickCapture: QuickCaptureRouter = .shared) {
        self.quickCapture = quickCapture
        // UI tests launch with an in-memory store, which also means no sync, so they don't race
        // real WatchConnectivity delivery.
        let isInMemory = KyoModelContainer.isInMemoryRequested
        let sync: TaskListSync? = isInMemory ? nil : .publish(to: WatchConnectivityTaskTransport.shared)
        // Built on first use, once, so a new TodayView value made while the view is on screen builds nothing.
        lazy var taskList = TaskListStore(modelContainer: modelContainer, sync: sync)
        _taskList = StateObject(wrappedValue: taskList)
        let habitSync: HabitListSync? = isInMemory ? nil : .publish(to: WatchConnectivityTaskTransport.shared)
        // Built on first use, once, so a new TodayView value made while the view is on screen builds nothing.
        lazy var habits = HabitListStore(modelContainer: modelContainer, sync: habitSync)
        _habitList = StateObject(wrappedValue: habits)
        // The Simulator can't transcribe, and UI tests shouldn't touch the speech model.
        let transcriber: any VoiceTranscriber = isInMemory ? NoTranscriber() : SpeechVoiceTranscriber(support: .shared)
        // UI tests have no Apple Intelligence, so Memo → Task takes its manual path and a Voice
        // memo keeps its "Voice memo" title.
        let languageModel: any OnDeviceLanguageModel = isInMemory ? NoLanguageModel() : FoundationOnDeviceLanguageModel()
        // Built on first use, once, so a new TodayView value made while the view is on screen builds nothing.
        lazy var memoStore = MemoStore(
            modelContainer: modelContainer, transcriber: transcriber, languageModel: languageModel,
            memoSync: isInMemory ? nil : WatchConnectivityTaskTransport.shared,
            watchRecordings: isInMemory ? nil : WatchConnectivityTaskTransport.shared
        )
        _memoStore = StateObject(wrappedValue: memoStore)
        _projects = StateObject(wrappedValue: ProjectListStore(modelContainer: modelContainer, taskList: taskList, memoStore: memoStore))
        // UI tests pick a fake calendar service; the live one never prompts until Connect is tapped.
        // Built on first use, once, because Month reads events through it as well.
        lazy var schedule = CalendarServiceSelection.makeScheduleStore()
        _schedule = StateObject(wrappedValue: schedule)
        _sections = StateObject(wrappedValue: CollapsedSectionsSelection.make())
        _month = StateObject(wrappedValue: MonthModel(sources: [
            TaskMonthContent(taskList: taskList),
            MemoMonthContent(store: memoStore),
            HabitMonthContent(habits: habits),
            EventMonthContent(schedule: schedule, calendar: .current),
        ]))
        self.languageModel = languageModel
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch mainView {
                        case .today:
                            todaySections(scrollProxy: scrollProxy)
                        case .month:
                            topBar
                                .padding(.bottom, 17)
                            MonthView(model: month, onOpen: { target in
                                switch target {
                                case .memo(let id): activeSheet = .memo(id)
                                case .event(let id): schedule.open(id)
                                }
                            })
                            // The Schedule section, which shows these on Today, isn't on screen under Month.
                            .sheet(item: Binding(
                                get: { schedule.presentedDetail },
                                set: { if $0 == nil { schedule.dismissDetail() } }
                            )) { detail in
                                EventDetailSheet(detail: detail)
                            }
                        }
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalPadding(for: geometry.size.width))
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .id("main-top")
                }
                .themedText()
                .background(theme.screenBackground)
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MainBottomBar(
                        selected: mainView,
                        select: select,
                        addTask: beginTaskDraft,
                        addHabit: { activeSheet = .habitForm },
                        addWrittenMemo: { activeSheet = .composeMemo },
                        addVoiceMemo: { isShowingRecorder = true }
                    )
                }
                .sheet(item: $activeSheet, onDismiss: openCaptureAfterSheetDismissal) { sheet in
                    switch sheet {
                    case .settings:
                        SettingsSheet(schedule: schedule, themes: .shared, palette: .shared)
                    case .habitForm:
                        HabitFormSheet(onSave: { name, schedule in habitList.addHabit(name: name, schedule: schedule) != nil })
                    case .composeMemo:
                        WrittenMemoComposeSheet(
                            projects: projects.projects,
                            onSave: { text, photos, projectID in memoStore.addWrittenMemo(text: text, photos: photos, projectID: projectID) },
                            onDraftChange: { composeHasDraft = $0 }
                        )
                    case .memo(let id):
                        if let memo = memoStore.memo(id: id) {
                            MemoCardSheet(memo: memo, store: memoStore, languageModel: languageModel, taskList: taskList, projects: projects.projects)
                        }
                    case .later:
                        LaterSheet(taskList: taskList, languageModel: languageModel)
                    case .scheduleTaskDraft:
                        TaskSchedulingSheet(languageModel: languageModel, onConfirm: { date in
                            guard createTaskDraft(plannedFor: date) else { return false }
                            abandonTaskDraft()
                            return true
                        })
                    case .scheduleTask(let id):
                        TaskSchedulingSheet(languageModel: languageModel, onConfirm: { taskList.deferTask(id: id, to: $0) != nil })
                    case .allProjects:
                        ProjectsSheet(projects: projects, sections: sections, languageModel: languageModel,
                            voiceRecording: voiceRecording, onCaptureSurfaceChange: { projectCaptureSurface = $0 })
                    case .project(let id):
                        NavigationStack {
                            ProjectDetailView(projectID: id, projects: projects, taskList: taskList,
                                languageModel: languageModel, voiceRecording: voiceRecording,
                                onCaptureSurfaceChange: { projectCaptureSurface = $0 }, sections: sections,
                                onDone: { activeSheet = nil })
                        }
                    case .addProjectTask(let id):
                        ProjectTextForm(title: "Add task", field: "Task", identifier: "project-task") {
                            projects.addTaskForToday(text: $0, to: id) != nil
                        }
                    case .newProject:
                        ProjectsSheet(projects: projects, sections: sections, startCreating: true,
                            languageModel: languageModel, voiceRecording: voiceRecording,
                            onCaptureSurfaceChange: { projectCaptureSurface = $0 })
                    case .allHabits:
                        HabitsSheet(habitList: habitList)
                    case .allMemos:
                        MemosSheet(memoStore: memoStore, languageModel: languageModel, taskList: taskList, projects: projects.projects)
                    case .editHabit(let id):
                        if let habit = habitList.habits.first(where: { $0.id == id }) {
                            HabitFormSheet(
                                habit: habit,
                                onSave: { name, schedule in habitList.editHabit(id: id, name: name, schedule: schedule) != nil },
                                onDelete: { habitList.deleteHabit(id: id) }
                            )
                        }
                    }
                }
                .fullScreenCover(isPresented: $isShowingRecorder) {
                    if let voiceRecording {
                        VoiceRecorderView(session: voiceRecording, projects: projects.projects, onFinish: { isShowingRecorder = false })
                    }
                }
                .confirmationDialog(
                    "Delete this voice memo?",
                    isPresented: Binding(
                        get: { voiceMemoPendingDelete != nil },
                        set: { if !$0 { voiceMemoPendingDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if let id = voiceMemoPendingDelete { _ = memoStore.deleteMemo(id: id) }
                        voiceMemoPendingDelete = nil
                    }
                } message: {
                    Text("Its audio and transcript are removed. This can't be undone.")
                }
                .onDisappear(perform: abandonTaskDraft)
                .onChange(of: sections.isCollapsed(.tasks)) { _, isCollapsed in
                    // A hidden field mustn't keep the keyboard up. The draft text stays.
                    if isCollapsed { isTaskDraftFocused = false }
                }
                // Today and Month share this scroll view, so each opens at its top, not where the other was left.
                .onChange(of: mainView) {
                    scrollProxy.scrollTo("main-top", anchor: .top)
                }
                .onChange(of: isShowingTaskDraft) { _, isShowing in
                    if isShowing {
                        withAnimation {
                            scrollProxy.scrollTo("task-draft", anchor: .center)
                        }
                    }
                }
            }
        }
        .task {
            // Once per launch: a recording a quit or crash cut short becomes a Voice memo.
            guard voiceRecording == nil else { return }
            let live: any LiveTranscribing = KyoModelContainer.isInMemoryRequested ? NoLiveTranscriber() : LiveSpeechTranscriber(support: .shared)
            let recorder = DeviceAudioRecorder()
            recorder.beforeDeactivation = { await live.waitUntilStopped() }
            let session = VoiceRecordingSession(recorder: recorder, memos: memoStore, live: live,
                userDefaults: RecordingMemoContextSelection.defaults())
            session.recoverInterruptedRecordings()
            voiceRecording = session
        }
        .onChange(of: captureSurface, initial: true) { _, surface in
            quickCapture.report(surface: surface)
        }
        // A request can wait for the recorder's session, which is made as Today first appears.
        .onChange(of: quickCapture.pending, initial: true) { _, _ in applyPendingCapture() }
        .onChange(of: voiceRecording != nil) { _, _ in applyPendingCapture() }
        .task(id: dayBoundaryRefreshToken) {
            await taskList.refreshAtEachDayBoundary()
        }
        .task(id: dayBoundaryRefreshToken) {
            await habitList.refreshAtEachDayBoundary()
        }
        .task(id: dayBoundaryRefreshToken) {
            await memoStore.refreshAtEachDayBoundary()
        }
        // Also covers a day rollover, a time zone change and a clock change, which bump the token.
        .task(id: dayBoundaryRefreshToken) {
            await schedule.refreshAtEachDayBoundary()
        }
        .task(id: dayBoundaryRefreshToken) {
            await month.refreshAtEachDayBoundary()
        }
        .task {
            await schedule.observeChanges()
        }
        // Now and the compact set move at each event's start and end; a changed event list reschedules.
        .task(id: schedule.events) {
            await schedule.advanceAtEventBoundaries()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                taskList.refreshForCurrentDay()
                habitList.refreshForCurrentDay()
                memoStore.refreshForCurrentDay()
                month.refresh()
                Task { await schedule.refresh() }
                // The speech model may have been installed while Kyo was in the background.
                memoStore.retryTranscriptionsWaitingForModel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            taskList.refreshForCurrentDay()
            habitList.refreshForCurrentDay()
            memoStore.refreshForCurrentDay()
            dayBoundaryRefreshToken += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            taskList.refreshForCurrentDay()
            habitList.refreshForCurrentDay()
            memoStore.refreshForCurrentDay()
            dayBoundaryRefreshToken += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            taskList.refreshForCurrentDay()
            habitList.refreshForCurrentDay()
            memoStore.refreshForCurrentDay()
            dayBoundaryRefreshToken += 1
        }
    }

    /// Everything Today shows in the scroll view. It stays a view of the same stores whether or not Month has
    /// taken its place for a while, so nothing here is recreated by switching.
    @ViewBuilder
    private func todaySections(scrollProxy: ScrollViewProxy) -> some View {
        header
        summaryStats
        if schedule.showsSection {
            TodaySection(title: "Schedule", note: schedule.sectionNote, section: .schedule, sections: sections) {
                ScheduleSectionContent(schedule: schedule)
            }
        }
        TodaySection(
            title: "Tasks",
            note: "For today",
            collapsedSummary: taskList.everydayTasks.isEmpty ? "No tasks" : "\(taskList.everydayTasks.filter(\.isComplete).count) of \(taskList.everydayTasks.count) done",
            section: .tasks,
            sections: sections,
            linkTitle: "Later",
            linkHint: "Opens deferred tasks",
            linkAction: { activeSheet = .later }
        ) {
            VStack(spacing: 0) {
                if taskList.everydayTasks.isEmpty && !isShowingTaskDraft {
                    Text("No tasks yet")
                        .font(.body)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                        .padding(.horizontal, 14)
                }
                ForEach(Array(taskList.everydayTasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 { rowDivider }
                    TaskRow(
                        task: task,
                        onToggle: { taskList.toggleTask(id: task.id) },
                        onEdit: { text in taskList.editTask(id: task.id, text: text) != nil },
                        onDelete: { _ = taskList.deleteTask(id: task.id) },
                        onDoLater: { activeSheet = .scheduleTask(task.id) },
                        projects: projects.projects,
                        onAssignProject: { taskList.assignTask(id: task.id, to: $0) }
                    )
                }
                if isShowingTaskDraft {
                    if !taskList.everydayTasks.isEmpty { rowDivider }
                    TaskDraftRow(
                        text: $taskDraft, projectID: $taskDraftProjectID, projects: projects.projects, isFocused: $isTaskDraftFocused, submit: saveTaskDraft,
                        schedule: {
                            isTaskDraftFocused = false
                            activeSheet = .scheduleTaskDraft
                        },
                        cancel: abandonTaskDraft
                    )
                        .id("task-draft")
                        .onAppear {
                            guard revealTaskDraftWhenShown else { return }
                            revealTaskDraftWhenShown = false
                            isTaskDraftFocused = true
                            withAnimation { scrollProxy.scrollTo("task-draft", anchor: .center) }
                        }
                }
            }
        }
        TodaySection(
            title: "Projects",
            note: "For today",
            collapsedSummary: projects.todayProjects.isEmpty ? "No project tasks for today" : "\(projects.todayProjects.count) projects",
            section: .projects,
            sections: sections,
            linkTitle: "All projects",
            linkHint: "Opens all projects",
            linkAction: { activeSheet = .allProjects }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if projects.todayProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No project tasks for today")
                            .foregroundStyle(theme.secondaryText)
                            .accessibilityIdentifier("projects-empty")
                        if projects.projects.isEmpty {
                            Button("New project") { activeSheet = .newProject }
                                .foregroundStyle(theme.accent)
                                .accessibilityIdentifier("projects-new")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                    .padding(14)
                }
                ForEach(projects.todayProjects) { project in
                    projectGroup(project)
                }
            }
        }
        TodaySection(
            title: "Habits",
            note: "Small steps, daily",
            collapsedSummary: habitList.collapsedSummary,
            section: .habits,
            sections: sections,
            linkTitle: habitList.hasHabits ? "See all" : nil,
            linkHint: "Opens the Habits sheet",
            linkAction: { activeSheet = .allHabits }
        ) {
            VStack(spacing: 0) {
                if habitList.habits.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No habits yet")
                            .font(.body)
                            .foregroundStyle(theme.secondaryText)
                        Text("Tap + to add one")
                            .font(.caption)
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                    .padding(.horizontal, 14)
                    .accessibilityElement(children: .combine)
                } else if habitList.todayHabits.isEmpty {
                    Text("Nothing due today")
                        .font(.body)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                        .padding(.horizontal, 14)
                }
                ForEach(Array(habitList.todayHabits.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { rowDivider }
                    HabitRow(
                        entry: entry,
                        onToggle: { habitList.toggleCheckOff(id: entry.id) },
                        onEdit: { activeSheet = .editHabit(entry.id) }
                    )
                }
            }
        }
        TodaySection(
            title: "Memos",
            note: memoStore.sectionSubtitle,
            section: .memos,
            sections: sections,
            linkTitle: memoStore.hasMemos ? "See all" : nil,
            linkAction: { activeSheet = .allMemos }
        ) {
            VStack(spacing: 0) {
                if memoStore.memos.isEmpty {
                    Text("Tap + to add a memo")
                        .font(.body)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                        .padding(.horizontal, 14)
                }
                ForEach(Array(memoStore.memos.enumerated()), id: \.element.id) { index, memo in
                    if index > 0 { rowDivider }
                    MemoRow(
                        memo: memo,
                        loadThumbnail: { memoStore.thumbnailData(forPhotoID: $0) },
                        loadPhoto: { memoStore.photoData(forPhotoID: $0) },
                        onOpen: { activeSheet = .memo(memo.id) },
                        onDelete: { requestDelete(of: memo) }
                    )
                }
            }
        }
    }

    /// The wordmark and Settings, which sit above both Today and Month.
    private var topBar: some View {
        HStack {
            Text("kyo")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(theme.secondaryText)
                .accessibilityLabel("Kyo")
            Spacer()
            Button {
                activeSheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The 44pt tap target overhangs the wordmark's line and the edge, not the layout.
            .padding(.vertical, -13)
            .padding(.trailing, -12)
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens Settings")
            .accessibilityIdentifier("settings-button")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.bottom, 17)

            Text("Today")
                .headerStyle(.largeTitle)
                .foregroundStyle(theme.primaryText)

            Text(taskList.currentDate, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.body)
                .foregroundStyle(theme.secondaryText)
                .padding(.top, 5)
                .accessibilityLabel(taskList.currentDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }

    private var summaryStats: some View {
        HStack(alignment: .top, spacing: 0) {
            SummaryStat(value: "\(taskList.completedCount) / \(taskList.taskCount)", label: "Tasks done")
            statDivider
            SummaryStat(value: "\(habitList.doneCount) / \(habitList.todayCount)", label: "Habits done")
        }
        .padding(.vertical, 17)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.separator.opacity(0.6))
                .frame(height: 0.5)
        }
        .padding(.bottom, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's summary")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(theme.separator.opacity(0.6))
            .frame(width: 0.5, height: 39)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.separator.opacity(0.55))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        width > 680 ? 28 : (width < 360 ? 15 : 20)
    }

    /// What quick capture needs to know is showing over Today.
    private var captureSurface: QuickCaptureRouter.Surface {
        if let projectCaptureSurface { return projectCaptureSurface }
        if isShowingRecorder { return .recorder }
        switch activeSheet {
        case nil: return .none
        case .composeMemo: return .compose(hasUnsavedDraft: composeHasDraft)
        default: return .otherSheet
        }
    }

    /// Applies **Record memo** or **Write memo**: opens the capture, or brings forward the one in
    /// progress. Any open sheet closes first (a memo card's player stops as it goes), and the
    /// capture opens once it has finished dismissing, because a second modal can't present over it.
    private func applyPendingCapture() {
        guard let request = quickCapture.pending, voiceRecording != nil else { return }
        quickCapture.markApplied(request)
        let command = request.command
        guard command.startsNew else { return }
        if command.closesOpenSheets, activeSheet != nil {
            captureAfterSheetDismissal = command.target
            activeSheet = nil
        } else {
            open(command.target)
        }
    }

    private func open(_ target: QuickCaptureRouter.Target) {
        switch target {
        case .recorder: isShowingRecorder = true
        case .compose: activeSheet = .composeMemo
        }
    }

    private func openCaptureAfterSheetDismissal() {
        projectCaptureSurface = nil
        composeHasDraft = false
        guard let target = captureAfterSheetDismissal else { return }
        captureAfterSheetDismissal = nil
        open(target)
    }

    /// Switches the main content. Month opens on the current month with Today selected every time.
    private func select(_ view: MainView) {
        guard view != mainView else { return }
        if view == .month { month.showCurrentMonth() }
        mainView = view
    }

    private func projectGroup(_ project: Project) -> some View {
        let tasks = projects.todayTasks(in: project.id)
        let collapsed = sections.isProjectCollapsed(project.id)
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button { sections.toggleProject(project.id) } label: {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(project.name) tasks")
                .accessibilityValue(collapsed ? "collapsed" : "expanded")
                .accessibilityIdentifier("project-group-collapse-\(project.id.uuidString)")
                VStack(alignment: .leading, spacing: 4) {
                    Button { activeSheet = .project(project.id) } label: {
                        Text(project.name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("project-group-open-\(project.id.uuidString)")
                    Text("\(tasks.filter(\.isComplete).count) of \(tasks.count) done")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityIdentifier("project-group-summary-\(project.id.uuidString)")
                }
                .padding(.vertical, 10)
            }
            .padding(.horizontal, 8)
            if !collapsed {
                ForEach(tasks) { task in
                    rowDivider
                    TaskRow(task: task,
                            onToggle: { taskList.toggleTask(id: task.id) },
                            onEdit: { taskList.editTask(id: task.id, text: $0) != nil },
                            onDelete: { taskList.deleteTask(id: task.id) },
                            onDoLater: { activeSheet = .scheduleTask(task.id) },
                            onReturnToProject: { projects.returnToProject(taskID: task.id) },
                            projects: projects.projects,
                            onAssignProject: { taskList.assignTask(id: task.id, to: $0) })
                }
                Button("Add task") { activeSheet = .addProjectTask(project.id) }
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 14)
                    .accessibilityIdentifier("project-group-add-\(project.id.uuidString)")
            }
            rowDivider
        }
    }

    private func beginTaskDraft() {
        let draftWasHidden = isShowingTaskDraft && sections.isCollapsed(.tasks)
        // Today's field is built again as it comes back from Month, so it takes focus once it's on screen.
        let comingFromMonth = mainView == .month
        mainView = .today
        sections.startTaskDraft()
        if !isShowingTaskDraft {
            taskDraft = ""
            taskDraftProjectID = nil
            isShowingTaskDraft = true
        } else if draftWasHidden {
            revealTaskDraftWhenShown = true
        }
        if comingFromMonth { revealTaskDraftWhenShown = true }
        isTaskDraftFocused = true
    }

    /// Voice memos confirm before they're deleted; Written memos go straight away.
    private func requestDelete(of memo: Memo) {
        if memo.kind == .voice {
            voiceMemoPendingDelete = memo.id
        } else {
            _ = memoStore.deleteMemo(id: memo.id)
        }
    }

    private func saveTaskDraft() {
        guard createTaskDraft() else { return }
        abandonTaskDraft()
    }

    private func createTaskDraft(plannedFor date: Date? = nil) -> Bool {
        if let taskDraftProjectID {
            return taskList.addTask(text: taskDraft, projectID: taskDraftProjectID, plannedFor: date ?? .now) != nil
        }
        if let date { return taskList.addTask(text: taskDraft, plannedFor: date) != nil }
        return taskList.addTask(text: taskDraft) != nil
    }

    private func abandonTaskDraft() {
        isTaskDraftFocused = false
        isShowingTaskDraft = false
        revealTaskDraftWhenShown = false
        taskDraft = ""
        taskDraftProjectID = nil
    }
}

private enum TodayPreviewSheet: Identifiable {
    case settings
    case habitForm
    case editHabit(UUID)
    case composeMemo
    case memo(UUID)
    case allMemos
    case allHabits
    case allProjects
    case newProject
    case project(UUID)
    case addProjectTask(UUID)
    case later
    case scheduleTask(UUID)
    case scheduleTaskDraft

    var id: String {
        switch self {
        case .settings: "settings"
        case .habitForm: "habitForm"
        case .editHabit(let id): "editHabit:\(id.uuidString)"
        case .composeMemo: "composeMemo"
        case .memo(let id): "memo:\(id.uuidString)"
        case .allMemos: "allMemos"
        case .allHabits: "allHabits"
        case .allProjects: "allProjects"
        case .newProject: "newProject"
        case .project(let id): "project:\(id.uuidString)"
        case .addProjectTask(let id): "addProjectTask:\(id.uuidString)"
        case .later: "later"
        case .scheduleTaskDraft: "scheduleTaskDraft"
        case .scheduleTask(let id): "scheduleTask:\(id.uuidString)"
        }
    }
}

private struct TaskDraftRow: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    @Binding var projectID: UUID?
    let projects: [Project]
    var isFocused: FocusState<Bool>.Binding
    let submit: () -> Void
    let schedule: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !projects.isEmpty {
                TaskCaptureProjectPicker(projects: projects, projectID: $projectID)
                    .foregroundStyle(theme.accent)
            }
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(theme.tertiaryText, lineWidth: 1.5)
                    .frame(width: 23, height: 23)
                    .accessibilityHidden(true)

                TextField("New task", text: $text)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .accessibilityLabel("New task")
                    .accessibilityIdentifier("new-task")

                Button("Planned day", systemImage: "calendar", action: schedule)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("new-task-schedule")

                Button("Cancel task", systemImage: "xmark", action: cancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("new-task-cancel")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
    }
}

/// The main content the bottom bar switches between.
private enum MainView: String {
    case today
    case month
}

private struct MainBottomBar: View {
    @Environment(\.theme) private var theme
    let selected: MainView
    let select: (MainView) -> Void
    let addTask: () -> Void
    let addHabit: () -> Void
    let addWrittenMemo: () -> Void
    let addVoiceMemo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switchButton(.today, title: "Today", systemImage: "sun.max")

            Menu {
                Button("Task", systemImage: "checkmark.circle", action: addTask)
                    .accessibilityIdentifier("add-item-task")
                Button("Habit", systemImage: "repeat", action: addHabit)
                    .accessibilityIdentifier("add-item-habit")
                Button("Written memo", systemImage: "text.alignleft", action: addWrittenMemo)
                    .accessibilityIdentifier("add-item-written-memo")
                Button("Voice memo", systemImage: "waveform", action: addVoiceMemo)
                    .accessibilityIdentifier("add-item-voice-memo")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(theme.onAccentText)
                    .frame(width: 52, height: 52)
                    .background(theme.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an item")
            .accessibilityHint("Adds a task, a habit or a memo")
            .accessibilityIdentifier("add-item")

            switchButton(.month, title: "Month", systemImage: "calendar")
        }
        .padding(6)
        .frame(maxWidth: 430)
        .background(.regularMaterial, in: Capsule())
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    /// A button that shows `view`. The selected one is drawn in the accent on a pill.
    private func switchButton(_ view: MainView, title: String, systemImage: String) -> some View {
        let isSelected = selected == view
        return Button { select(view) } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isSelected ? theme.accent.opacity(0.09) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("main-view-\(view.rawValue)")
    }

}

private struct SummaryStat: View {
    @Environment(\.theme) private var theme
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(label == "Tasks done" ? "task-count-summary" : "summary-\(label)")
        .accessibilityValue("\(value) \(label.lowercased())")
    }
}

struct TodaySection<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let note: String
    /// Shown in place of `note` while the section is collapsed, such as "2 of 5 done".
    var collapsedSummary: String?
    let section: TodaySectionID
    @ObservedObject var sections: CollapsedSections
    /// A link at the right of the header, such as **See all**. It stays when the section is collapsed.
    var linkTitle: String?
    /// What VoiceOver says about where the link leads.
    var linkHint: String?
    var linkAction: () -> Void = {}
    @ViewBuilder let content: Content

    private var isCollapsed: Bool { sections.isCollapsed(section) }
    private var shownNote: String { isCollapsed ? (collapsedSummary ?? note) : note }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    collapseButton
                    headerLink
                }
                .padding(.vertical, 8)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    collapseButton
                    headerLink
                }
                .frame(minHeight: 51)
            }

            if !isCollapsed {
                content
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .contain)
            }
        }
    }

    private var sectionTitle: some View {
        HStack(spacing: 7) {
            Text(title)
                .headerStyle(.section)
                .foregroundStyle(theme.primaryText)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
        }
    }

    private var collapseButton: some View {
        Button {
            withAnimation { sections.toggle(section) }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle
                        Text(shownNote)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 51, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        sectionTitle
                        Spacer(minLength: 8)
                        Text(shownNote)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: .infinity, minHeight: 51)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(shownNote)")
        .accessibilityValue(isCollapsed ? "collapsed" : "expanded")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("section-header-\(section.rawValue)")
    }

    @ViewBuilder
    private var headerLink: some View {
        if let linkTitle {
            Button(action: linkAction) {
                Text(linkTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 6)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(linkHint ?? "")
            .accessibilityIdentifier("section-link-\(section.rawValue)")
        }
    }

}

private struct CheckRow: View {
    @Environment(\.theme) private var theme
    let title: String
    var trailing: String? = nil
    let isComplete: Bool
    var isTask = false
    var onToggle: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if onToggle == nil {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(isComplete ? "Completed" : "Not completed")
                .accessibilityHint(trailing ?? "")
        } else {
            row
                .accessibilityElement(children: .contain)
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            checkbox

            Text(title)
                .font(.body)
                .foregroundStyle(isComplete ? theme.secondaryText : theme.primaryText)
                .strikethrough(isComplete && isTask, color: theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
    }

    @ViewBuilder
    private var checkbox: some View {
        if let onToggle {
            Button(action: onToggle) {
                checkboxGlyph
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isComplete ? "Completed" : "Not completed")
            .accessibilityHint(isComplete ? "Reopens this task" : "Marks this task complete")
        } else {
            checkboxGlyph
                .accessibilityHidden(true)
        }
    }

    private var checkboxGlyph: some View {
        ZStack {
            Circle()
                .strokeBorder(isComplete ? theme.accent : theme.tertiaryText, lineWidth: 1.5)
                .background(Circle().fill(isComplete ? theme.accent : .clear))
                .frame(width: 23, height: 23)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.onAccent)
            }
        }
    }
}

private struct HabitRow: View {
    @Environment(\.theme) private var theme
    let entry: TodayHabit
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                checkboxGlyph
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.habit.name)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(entry.isCheckedOffToday ? "Removes today's check-off" : "Checks this habit off for today")

            Button(action: onEdit) {
                Text(entry.habit.name)
                    .font(.body)
                    .foregroundStyle(entry.isDone ? theme.secondaryText : theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit habit: \(entry.habit.name)")
            .accessibilityHint("Edits this habit")

            trailingStatus
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
    }

    private var trailingStatus: some View {
        HabitStatusLabel(weekProgress: entry.weekProgress, streak: entry.streak)
            .foregroundStyle(entry.isDone ? theme.secondaryText : theme.primaryText)
            .accessibilityHidden(true)
    }

    /// "Checked off" only when Today has a check-off; week progress and the streak follow.
    private var accessibilityValue: String {
        var value = entry.isCheckedOffToday ? "Checked off" : "Not checked off"
        if let progress = entry.weekProgress {
            value += ", " + HabitStatusLabel.spokenWeekProgress(progress)
            if progress.isTargetMet && !entry.isCheckedOffToday { value += ", target met" }
        }
        if entry.streak >= 1 {
            value += ", " + HabitStatusLabel.spokenStreak(entry.streak, isWeekly: entry.weekProgress != nil)
        }
        return value
    }

    private var checkboxGlyph: some View {
        ZStack {
            Circle()
                .strokeBorder(entry.isCheckedOffToday ? theme.accent : theme.tertiaryText, lineWidth: 1.5)
                .background(Circle().fill(entry.isCheckedOffToday ? theme.accent : .clear))
                .frame(width: 23, height: 23)
            if entry.isCheckedOffToday {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.onAccent)
            }
        }
        .accessibilityHidden(true)
    }
}

struct TaskRow: View {
    @Environment(\.theme) private var theme
    let task: DailyTask
    let onToggle: () -> Void
    let onEdit: (String) -> Bool
    let onDelete: () -> Void
    var onDoLater: (() -> Void)? = nil
    var onReturnToProject: (() -> Void)? = nil
    var projects: [Project] = []
    var onAssignProject: ((UUID?) -> Void)? = nil

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isDeleteRevealed = false
    @State private var shareItems: ShareItems?
    @FocusState private var isEditorFocused: Bool

    private let deleteWidth: CGFloat = 84

    var body: some View {
        ZStack(alignment: .trailing) {
            rowContents
                .offset(x: isDeleteRevealed ? -deleteWidth : 0)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if value.translation.width < -40 {
                                withAnimation(.easeOut(duration: 0.2)) { isDeleteRevealed = true }
                            } else if value.translation.width > 40 {
                                withAnimation(.easeOut(duration: 0.2)) { isDeleteRevealed = false }
                            }
                        }
                )

            if isDeleteRevealed {
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.onDestructive)
                        .frame(width: deleteWidth)
                        .frame(maxHeight: .infinity)
                        .background(theme.destructive)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("task-delete-\(task.id.uuidString)")
                .accessibilityLabel("Delete task: \(task.text)")
                .accessibilityHint("Deletes this task")
                .transition(.identity)
            }
        }
        .clipped()
        .contextMenu {
            if let onAssignProject {
                TaskProjectAssignmentMenu(task: task, projects: projects, assign: onAssignProject)
            }
            if !task.isComplete, let onDoLater {
                Button("Do later", systemImage: "calendar", action: onDoLater)
                    .accessibilityIdentifier("task-do-later-\(task.id.uuidString)")
            }
            if !task.isComplete, let onReturnToProject {
                Button("Return to project", systemImage: "arrow.uturn.backward", action: onReturnToProject)
                    .accessibilityIdentifier("task-return-to-project-\(task.id.uuidString)")
            }
            Button("Share", systemImage: "square.and.arrow.up", action: share)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        // A popover anchored to the row on iPad; a sheet on iPhone.
        .popover(item: $shareItems) { items in
            ShareSheet(items: items) { shareItems = nil }
                .presentationDetents([.medium, .large])
                .presentationCompactAdaptation(.sheet)
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draft = task.text
                isEditorFocused = true
            } else {
                isEditorFocused = false
            }
        }
        .onChange(of: task.text) { _, newText in
            if !isEditing { draft = newText }
        }
    }

    private var rowContents: some View {
        HStack(spacing: 10) {
            // Tap gestures rather than `Button`s on this row: the swipe is a simultaneous gesture, which
            // doesn't cancel a button, so a `Button` would also fire when a swipe ends on it.
            Group {
                if task.isUnscheduled && !task.isComplete {
                    Image(systemName: "sun.max")
                        .foregroundStyle(theme.accent)
                } else {
                    checkboxGlyph
                }
            }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(task.isUnscheduled && !task.isComplete ? "Do today: \(task.text)" : task.text)
                .accessibilityValue(task.isUnscheduled && !task.isComplete ? "Unscheduled" : task.isComplete ? "Completed" : "Not completed")
                .accessibilityHint(task.isUnscheduled && !task.isComplete ? "Chooses this project task for Today" : task.isComplete ? "Reopens this task" : "Marks this task complete")
                .accessibilityIdentifier("\(task.isUnscheduled && !task.isComplete ? "task-do-today" : "task-checkbox")-\(task.id.uuidString)")
                .accessibilityAction { onToggle() }
                .accessibilityAction(named: "Share", share)

            if isEditing {
                TextField("Edit task", text: $draft)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .focused($isEditorFocused)
                    .submitLabel(.done)
                    .onSubmit(saveEdit)
                    .accessibilityLabel("Edit task")
                    .accessibilityIdentifier("task-editor-\(task.id.uuidString)")
                    .accessibilityAction(named: "Share", share)
            } else {
                Text(task.text)
                    .font(.body)
                    .foregroundStyle(task.isComplete ? theme.secondaryText : theme.primaryText)
                    .strikethrough(task.isComplete, color: theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { isEditing = true }
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("task-edit-\(task.id.uuidString)")
                    .accessibilityLabel("Edit task: \(task.text)")
                    .accessibilityHint("Edits this task")
                    .accessibilityAction { isEditing = true }
                    .accessibilityAction(named: "Share", share)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
        .background(theme.card)
    }

    private var checkboxGlyph: some View {
        ZStack {
            Circle()
                .strokeBorder(task.isComplete ? theme.accent : theme.tertiaryText, lineWidth: 1.5)
                .background(Circle().fill(task.isComplete ? theme.accent : .clear))
                .frame(width: 23, height: 23)
            if task.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.onAccent)
            }
        }
        .accessibilityHidden(true)
    }

    private func saveEdit() {
        guard onEdit(draft) else { return }
        isEditing = false
    }

    /// Opens the share sheet with the Task's saved text, leaving any inline edit as it is.
    private func share() {
        shareItems = ShareItems(TaskSharePayload.make(for: task))
    }
}

#Preview {
    if let container = try? KyoModelContainer.make(inMemory: true) {
        TodayView(modelContainer: container)
    }
}
