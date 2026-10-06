import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @StateObject private var taskList: TaskListStore
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
    /// Created when Today first appears, once the memo store exists.
    @State private var voiceRecording: VoiceRecordingSession?
    @State private var isShowingRecorder = false
    /// Whether the compose sheet holds text or a photo, which quick capture mustn't throw away.
    @State private var composeHasDraft = false
    /// The capture quick capture opens once the sheet it closed has finished dismissing.
    @State private var captureAfterSheetDismissal: QuickCaptureRouter.Target?
    @State private var voiceMemoPendingDelete: UUID?
    @State private var isShowingTaskDraft = false
    @State private var taskDraft = ""
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
        _taskList = StateObject(wrappedValue: TaskListStore(modelContainer: modelContainer, sync: sync))
        let habitSync: HabitListSync? = isInMemory ? nil : .publish(to: WatchConnectivityTaskTransport.shared)
        _habitList = StateObject(wrappedValue: HabitListStore(modelContainer: modelContainer, sync: habitSync))
        // The Simulator can't transcribe, and UI tests shouldn't touch the speech model.
        let transcriber: any VoiceTranscriber = isInMemory ? NoTranscriber() : SpeechVoiceTranscriber(support: .shared)
        // UI tests have no Apple Intelligence, so Memo → Task takes its manual path and a Voice
        // memo keeps its "Voice memo" title.
        let languageModel: any OnDeviceLanguageModel = isInMemory ? NoLanguageModel() : FoundationOnDeviceLanguageModel()
        _memoStore = StateObject(
            wrappedValue: MemoStore(
                modelContainer: modelContainer, transcriber: transcriber, languageModel: languageModel,
                memoSync: isInMemory ? nil : WatchConnectivityTaskTransport.shared,
                watchRecordings: isInMemory ? nil : WatchConnectivityTaskTransport.shared
            )
        )
        // UI tests pick a fake calendar service; the live one never prompts until Connect is tapped.
        _schedule = StateObject(wrappedValue: CalendarServiceSelection.makeScheduleStore())
        _sections = StateObject(wrappedValue: CollapsedSectionsSelection.make())
        self.languageModel = languageModel
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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
                            collapsedSummary: taskList.collapsedSummary,
                            section: .tasks,
                            sections: sections
                        ) {
                            VStack(spacing: 0) {
                                if taskList.tasks.isEmpty && !isShowingTaskDraft {
                                    Text("No tasks yet")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                                        .padding(.horizontal, 14)
                                }
                                ForEach(Array(taskList.tasks.enumerated()), id: \.element.id) { index, task in
                                    if index > 0 { rowDivider }
                                    TaskRow(
                                        task: task,
                                        onToggle: { taskList.toggleTask(id: task.id) },
                                        onEdit: { text in taskList.editTask(id: task.id, text: text) != nil },
                                        onDelete: { _ = taskList.deleteTask(id: task.id) }
                                    )
                                }
                                if isShowingTaskDraft {
                                    if !taskList.tasks.isEmpty { rowDivider }
                                    TaskDraftRow(text: $taskDraft, isFocused: $isTaskDraftFocused, submit: saveTaskDraft)
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
                            title: "Habits",
                            note: "Small steps, daily",
                            collapsedSummary: habitList.collapsedSummary,
                            section: .habits,
                            sections: sections
                        ) {
                            VStack(spacing: 0) {
                                if habitList.habits.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("No habits yet")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                        Text("Tap + to add one")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .accessibilityElement(children: .combine)
                                } else if habitList.todayHabits.isEmpty {
                                    Text("Nothing due today")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
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
                                        .foregroundStyle(.secondary)
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
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalPadding(for: geometry.size.width))
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    TodayBottomBar(
                        addTask: beginTaskDraft,
                        addHabit: { activeSheet = .habitForm },
                        addWrittenMemo: { activeSheet = .composeMemo },
                        addVoiceMemo: { isShowingRecorder = true },
                        openCalendar: { activeSheet = .calendar }
                    )
                }
                .sheet(item: $activeSheet, onDismiss: openCaptureAfterSheetDismissal) { sheet in
                    switch sheet {
                    case .calendar:
                        CalendarPreviewSheet()
                    case .settings:
                        SettingsSheet(habitList: habitList, schedule: schedule)
                    case .habitForm:
                        HabitFormSheet(onSave: { name, schedule in habitList.addHabit(name: name, schedule: schedule) != nil })
                    case .composeMemo:
                        WrittenMemoComposeSheet(
                            onSave: { text, photos in memoStore.addWrittenMemo(text: text, photos: photos) },
                            onDraftChange: { composeHasDraft = $0 }
                        )
                    case .memo(let id):
                        if let memo = memoStore.memo(id: id) {
                            MemoCardSheet(memo: memo, store: memoStore, languageModel: languageModel, taskList: taskList)
                        }
                    case .allMemos:
                        MemosSheet(memoStore: memoStore, languageModel: languageModel, taskList: taskList)
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
                        VoiceRecorderView(session: voiceRecording, onFinish: { isShowingRecorder = false })
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
            let session = VoiceRecordingSession(recorder: recorder, memos: memoStore, live: live)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("kyo")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Kyo")
                Spacer()
                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The 44pt tap target overhangs the wordmark's line and the edge, not the layout.
                .padding(.vertical, -13)
                .padding(.trailing, -12)
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens Settings")
            }
            .padding(.bottom, 17)

            Text("Today")
                .font(.largeTitle.weight(.bold))
                .tracking(-1.2)
                .foregroundStyle(.primary)

            Text(taskList.currentDate, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.body)
                .foregroundStyle(.secondary)
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
                .fill(Color(uiColor: .separator).opacity(0.6))
                .frame(height: 0.5)
        }
        .padding(.bottom, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's summary")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.6))
            .frame(width: 0.5, height: 39)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.55))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        width > 680 ? 28 : (width < 360 ? 15 : 20)
    }

    /// What quick capture needs to know is showing over Today.
    private var captureSurface: QuickCaptureRouter.Surface {
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
        composeHasDraft = false
        guard let target = captureAfterSheetDismissal else { return }
        captureAfterSheetDismissal = nil
        open(target)
    }

    private func beginTaskDraft() {
        let draftWasHidden = isShowingTaskDraft && sections.isCollapsed(.tasks)
        sections.startTaskDraft()
        if !isShowingTaskDraft {
            taskDraft = ""
            isShowingTaskDraft = true
        } else if draftWasHidden {
            revealTaskDraftWhenShown = true
        }
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
        taskList.addTask(text: taskDraft)
        abandonTaskDraft()
    }

    private func abandonTaskDraft() {
        isTaskDraftFocused = false
        isShowingTaskDraft = false
        revealTaskDraftWhenShown = false
        taskDraft = ""
    }
}

private enum TodayPreviewSheet: Identifiable {
    case calendar
    case settings
    case habitForm
    case editHabit(UUID)
    case composeMemo
    case memo(UUID)
    case allMemos

    var id: String {
        switch self {
        case .calendar: "calendar"
        case .settings: "settings"
        case .habitForm: "habitForm"
        case .editHabit(let id): "editHabit:\(id.uuidString)"
        case .composeMemo: "composeMemo"
        case .memo(let id): "memo:\(id.uuidString)"
        case .allMemos: "allMemos"
        }
    }
}

private struct TaskDraftRow: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color(uiColor: .tertiaryLabel), lineWidth: 1.5)
                .frame(width: 23, height: 23)
                .accessibilityHidden(true)

            TextField("New task", text: $text)
                .font(.body)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
                .accessibilityLabel("New task")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
    }
}

private struct TodayBottomBar: View {
    let addTask: () -> Void
    let addHabit: () -> Void
    let addWrittenMemo: () -> Void
    let addVoiceMemo: () -> Void
    let openCalendar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {}) {
                VStack(spacing: 3) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 22, weight: .medium))
                    Text("Today")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(accentColor.opacity(0.09), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Today")
            .accessibilityAddTraits(.isSelected)

            Menu {
                Button("Task", systemImage: "checkmark.circle", action: addTask)
                Button("Habit", systemImage: "repeat", action: addHabit)
                Button("Written memo", systemImage: "text.alignleft", action: addWrittenMemo)
                Button("Voice memo", systemImage: "waveform", action: addVoiceMemo)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(accentColor, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an item")
            .accessibilityHint("Adds a task, a habit or a memo")

            Button(action: openCalendar) {
                VStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .font(.system(size: 22, weight: .medium))
                    Text("Calendar")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calendar")
            .accessibilityHint("Opens the past days preview")
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

    private var accentColor: Color {
        KyoPalette.accent
    }
}

private struct CalendarPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 23)
    ) ?? .now

    private let latestDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 24)
    ) ?? .now

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Past days")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close calendar preview")
            }

            DatePicker("Choose a day", selection: $selectedDate, in: ...latestDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(.body)
                .tint(KyoPalette.accent)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.headline)
                    .accessibilityLabel(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                Text("No entries in this sketch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .frame(maxWidth: 520, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar preview")
    }
}

enum KyoPalette {
    static var accent: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.57, green: 0.79, blue: 0.68, alpha: 1)
                : UIColor(red: 0.22, green: 0.43, blue: 0.34, alpha: 1)
        })
    }
}

private struct SummaryStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(label == "Tasks done" ? "task-count-summary" : "summary-\(label)")
        .accessibilityValue("\(value) \(label.lowercased())")
    }
}

struct TodaySection<Content: View>: View {
    let title: String
    let note: String
    /// Shown in place of `note` while the section is collapsed, such as "2 of 5 done".
    var collapsedSummary: String?
    let section: TodaySectionID
    @ObservedObject var sections: CollapsedSections
    /// A link at the right of the header, such as **See all**. It stays when the section is collapsed.
    var linkTitle: String?
    var linkAction: () -> Void = {}
    @ViewBuilder let content: Content

    private var isCollapsed: Bool { sections.isCollapsed(section) }
    private var shownNote: String { isCollapsed ? (collapsedSummary ?? note) : note }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation { sections.toggle(section) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(spacing: 7) {
                            Text(title)
                                .font(.title3.weight(.semibold))
                                .tracking(-0.4)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        }
                        Spacer(minLength: 8)
                        Text(shownNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: .infinity, minHeight: 51)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(shownNote)")
                .accessibilityValue(isCollapsed ? "collapsed" : "expanded")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("section-header-\(section.rawValue)")
                if let linkTitle {
                    Button(action: linkAction) {
                        Text(linkTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KyoPalette.accent)
                            .padding(.leading, 6)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 51)

            if !isCollapsed {
                content
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .contain)
            }
        }
    }

    private var cardBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1)
                : .white
        })
    }
}

private struct CheckRow: View {
    let title: String
    var trailing: String? = nil
    let isComplete: Bool
    var isTask = false
    var onToggle: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

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
                .foregroundStyle(isComplete ? Color.secondary : Color.primary)
                .strikethrough(isComplete && isTask, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .strokeBorder(isComplete ? accentColor : Color(uiColor: .tertiaryLabel), lineWidth: 1.5)
                .background(Circle().fill(isComplete ? accentColor : .clear))
                .frame(width: 23, height: 23)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(uiColor: .secondarySystemBackground))
            }
        }
    }

    private var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 0.57, green: 0.79, blue: 0.68)
            : Color(red: 0.22, green: 0.43, blue: 0.34)
    }
}

private struct HabitRow: View {
    let entry: TodayHabit
    let onToggle: () -> Void
    let onEdit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

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
                    .foregroundStyle(entry.isDone ? Color.secondary : Color.primary)
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

    /// Week progress (weekly targets) then the streak flame, hidden at 0.
    @ViewBuilder
    private var trailingStatus: some View {
        let style = entry.isDone ? Color.secondary : Color.primary
        HStack(spacing: 6) {
            if let progress = entry.weekProgress {
                Text("\(progress.count)/\(progress.target)")
                    .font(.subheadline.monospacedDigit())
                if entry.streak >= 1 { Text("·") }
            }
            if entry.streak >= 1 {
                Label {
                    Text(entry.weekProgress == nil ? "\(entry.streak)" : "\(entry.streak)w")
                        .font(.subheadline.monospacedDigit())
                } icon: {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .foregroundStyle(style)
        .accessibilityHidden(true)
    }

    /// "Completed" only when Today has a check-off; week progress and the streak follow.
    private var accessibilityValue: String {
        var value = entry.isCheckedOffToday ? "Completed" : "Not completed"
        if let progress = entry.weekProgress {
            value += ", \(progress.count) of \(progress.target) this week"
            if progress.isTargetMet && !entry.isCheckedOffToday { value += ", target met" }
        }
        if entry.streak >= 1 {
            value += entry.weekProgress == nil ? ", \(entry.streak) day streak" : ", \(entry.streak) week streak"
        }
        return value
    }

    private var checkboxGlyph: some View {
        ZStack {
            Circle()
                .strokeBorder(entry.isCheckedOffToday ? accentColor : Color(uiColor: .tertiaryLabel), lineWidth: 1.5)
                .background(Circle().fill(entry.isCheckedOffToday ? accentColor : .clear))
                .frame(width: 23, height: 23)
            if entry.isCheckedOffToday {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(uiColor: .secondarySystemBackground))
            }
        }
        .accessibilityHidden(true)
    }

    private var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 0.57, green: 0.79, blue: 0.68)
            : Color(red: 0.22, green: 0.43, blue: 0.34)
    }
}

private struct TaskRow: View {
    let task: DailyTask
    let onToggle: () -> Void
    let onEdit: (String) -> Bool
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isDeleteRevealed = false
    @FocusState private var isEditorFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                        .foregroundStyle(.white)
                        .frame(width: deleteWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete task: \(task.text)")
                .accessibilityHint("Deletes this task")
                .transition(.identity)
            }
        }
        .clipped()
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
            Button(action: onToggle) {
                checkboxGlyph
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.text)
            .accessibilityValue(task.isComplete ? "Completed" : "Not completed")
            .accessibilityHint(task.isComplete ? "Reopens this task" : "Marks this task complete")

            if isEditing {
                TextField("Edit task", text: $draft)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .focused($isEditorFocused)
                    .submitLabel(.done)
                    .onSubmit(saveEdit)
                    .accessibilityLabel("Edit task")
                    .accessibilityIdentifier("task-editor:\(task.text)")
            } else {
                Button {
                    isEditing = true
                } label: {
                    Text(task.text)
                        .font(.body)
                        .foregroundStyle(task.isComplete ? Color.secondary : Color.primary)
                        .strikethrough(task.isComplete, color: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit task: \(task.text)")
                .accessibilityHint("Edits this task")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
        .background(Color(uiColor: .systemBackground))
    }

    private var checkboxGlyph: some View {
        ZStack {
            Circle()
                .strokeBorder(task.isComplete ? accentColor : Color(uiColor: .tertiaryLabel), lineWidth: 1.5)
                .background(Circle().fill(task.isComplete ? accentColor : .clear))
                .frame(width: 23, height: 23)
            if task.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(uiColor: .secondarySystemBackground))
            }
        }
        .accessibilityHidden(true)
    }

    private var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 0.57, green: 0.79, blue: 0.68)
            : Color(red: 0.22, green: 0.43, blue: 0.34)
    }

    private func saveEdit() {
        guard onEdit(draft) else { return }
        isEditing = false
    }
}

#Preview {
    if let container = try? KyoModelContainer.make(inMemory: true) {
        TodayView(modelContainer: container)
    }
}
