import SwiftUI
import WatchKit

struct WatchTodayView: View {
    // Owned by `WatchAppModel`, so a background launch can apply snapshots without this view.
    @ObservedObject private var taskList = WatchAppModel.shared.taskList
    @ObservedObject private var habitList = WatchAppModel.shared.habitList
    @ObservedObject private var memoList = WatchAppModel.shared.memoList
    /// Which sections are collapsed, kept on the watch and separate from the phone's.
    @StateObject private var sections = CollapsedSectionsSelection.make()
    @State private var activeSheet: WatchPreviewSheet?
    /// Made once the memo list exists, which is where the outbox a recording is saved to lives.
    @State private var recordingSession: VoiceRecordingSession?
    @State private var isRecording = false
    // Quick capture (the Record memo control and complications) asks this router to open the recorder.
    @ObservedObject private var quickCapture = QuickCaptureRouter.shared
    /// Set while a sheet that has to close first is dismissing, so the recorder opens once it's gone.
    @State private var recordAfterSheetDismissal = false
    @State private var dayBoundaryRefreshToken = 0
    @Environment(\.watchPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // A `List` rather than a `ScrollView` because `.swipeActions` only works on list
                // rows. Everything except the task rows is a single plain row, styled to look
                // the same as the old `VStack`. watchOS has no `listRowSpacing` or separator
                // control, so the minimum row height is dropped and `WatchTaskRowBackground`
                // bleeds into the small gap between rows to keep the section one joined card.
                List {
                    header
                        .listRow(top: 8, bottom: 8)
                    summary
                        .listRow()

                    taskRows

                    habitRows
                    memoRows
                    // The memo rows end flush, so this keeps the list's bottom margin.
                    Color.clear
                        .frame(height: 12)
                        .accessibilityHidden(true)
                        .listRow()
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 1)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .frame(height: max(0, geometry.size.height - 54), alignment: .top)

                WatchActionBar(openAdd: { activeSheet = .add })
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .ignoresSafeArea(edges: .top)
        .sheet(item: $activeSheet, onDismiss: openRecorderAfterSheetDismissal) { sheet in
            switch sheet {
            case .add:
                WatchTaskTextSheet(
                    title: "Add a task",
                    placeholder: "New task",
                    initialText: "",
                    buttonLabel: "Add",
                    buttonHint: "Saves this task to today's list",
                    save: { text in _ = taskList.addTask(text: text) }
                )
            case .edit(let task):
                WatchTaskTextSheet(
                    title: "Edit task",
                    placeholder: "Task",
                    initialText: task.text,
                    buttonLabel: "Save",
                    buttonHint: "Saves your changes to this task",
                    save: { text in _ = taskList.editTask(id: task.id, text: text) }
                )
            }
        }
        .sheet(isPresented: $isRecording) {
            if let recordingSession {
                WatchRecorderView(session: recordingSession) { isRecording = false }
            }
        }
        .task {
            // Once per launch: a recording a quit or crash cut short goes into the outbox.
            guard recordingSession == nil, let outbox = memoList.outbox else { return }
            let session = VoiceRecordingSession(recorder: WatchAudioRecorder(), memos: outbox)
            session.recoverInterruptedRecordings()
            recordingSession = session
        }
        .onChange(of: captureSurface, initial: true) { _, surface in
            quickCapture.report(surface: surface)
        }
        .onChange(of: quickCapture.pending, initial: true) { _, _ in applyPendingCapture() }
        // A request from a cold launch waits for the recording session, made in the task above.
        .onChange(of: recordingSession == nil) { _, _ in applyPendingCapture() }
        .task(id: dayBoundaryRefreshToken) {
            await taskList.refreshAtEachDayBoundary()
        }
        .task(id: dayBoundaryRefreshToken) {
            await habitList.refreshAtEachDayBoundary()
        }
        .task(id: dayBoundaryRefreshToken) {
            await memoList.refreshAtEachDayBoundary()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                taskList.refreshForCurrentDay()
                habitList.refreshForCurrentDay()
                memoList.refreshForCurrentDay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            taskList.refreshForCurrentDay()
            habitList.refreshForCurrentDay()
            memoList.refreshForCurrentDay()
            dayBoundaryRefreshToken += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            taskList.refreshForCurrentDay()
            habitList.refreshForCurrentDay()
            memoList.refreshForCurrentDay()
            dayBoundaryRefreshToken += 1
        }
    }

    @ViewBuilder
    private var taskRows: some View {
        WatchSectionHeader(
            title: "Tasks",
            section: .tasks,
            sections: sections,
            count: WatchCollapsedCount.progress(done: taskList.completedCount, total: taskList.taskCount)
        )
        .listRow(top: 8, bottom: 5)

        if !sections.isCollapsed(.tasks) {
            if taskList.tasks.isEmpty {
                Text("No tasks yet")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText.style)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRow(background: WatchTaskRowBackground(position: .only))
            } else {
                ForEach(Array(taskList.tasks.enumerated()), id: \.element.id) { index, task in
                    WatchCheckRow(
                        title: task.text,
                        completed: task.isComplete,
                        task: true,
                        onToggle: { taskList.toggleTask(id: task.id) },
                        onEdit: { activeSheet = .edit(task) },
                        onDelete: { taskList.deleteTask(id: task.id) }
                    )
                    .padding(.horizontal, 9)
                    .overlay(alignment: .top) {
                        if index > 0 { rowDivider.padding(.horizontal, 9) }
                    }
                    .listRow(background: WatchTaskRowBackground(position: .position(index: index, count: taskList.tasks.count)))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            taskList.deleteTask(id: task.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            activeSheet = .edit(task)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(palette.editTint.color)
                    }
                }
            }
        }
    }

    /// Today's habits: to-do first, then the done group (gray, no strikethrough). Tapping a row
    /// checks the habit off or unchecks it; there are no swipe actions or editing.
    @ViewBuilder
    private var habitRows: some View {
        WatchSectionHeader(
            title: "Habits",
            section: .habits,
            sections: sections,
            count: WatchCollapsedCount.progress(done: habitList.doneCount, total: habitList.todayCount)
        )
        .listRow(top: 8, bottom: 5)

        if !sections.isCollapsed(.habits) {
            if habitList.todayHabits.isEmpty {
                Text(habitEmptyMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText.style)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRow(background: WatchTaskRowBackground(position: .only))
            } else {
                ForEach(Array(habitList.todayHabits.enumerated()), id: \.element.id) { index, entry in
                    WatchHabitRow(entry: entry, onToggle: { toggleHabit(entry) })
                        .padding(.horizontal, 9)
                        .overlay(alignment: .top) {
                            if index > 0 { rowDivider.padding(.horizontal, 9) }
                        }
                        .listRow(background: WatchTaskRowBackground(position: .position(index: index, count: habitList.todayHabits.count)))
                }
            }
        }
    }

    /// Checks the habit off or unchecks it, with a success haptic only on checking off.
    private func toggleHabit(_ entry: TodayHabit) {
        let wasCheckedOff = entry.isCheckedOffToday
        guard habitList.toggleCheckOff(id: entry.habit.id) != nil, !wasCheckedOff else { return }
        WKInterfaceDevice.current().play(.success)
    }

    /// What quick capture needs to know is showing over Today.
    private var captureSurface: QuickCaptureRouter.Surface {
        if isRecording { return .recorder }
        return activeSheet == nil ? .none : .otherSheet
    }

    /// Applies **Record memo**: opens the recorder and starts recording, or brings forward the
    /// recording in progress. An open sheet closes first, and the recorder opens once it has
    /// finished dismissing, because a second modal can't present over it.
    private func applyPendingCapture() {
        guard let request = quickCapture.pending, recordingSession != nil else { return }
        quickCapture.markApplied(request)
        let command = request.command
        // The Watch only records, so the target is always the recorder.
        guard command.target == .recorder, command.startsNew else { return }
        if command.closesOpenSheets, activeSheet != nil {
            recordAfterSheetDismissal = true
            activeSheet = nil
        } else {
            isRecording = true
        }
    }

    private func openRecorderAfterSheetDismissal() {
        guard recordAfterSheetDismissal else { return }
        recordAfterSheetDismissal = false
        isRecording = true
    }

    /// The **Record** button, then today's memos newest first, with recordings the phone hasn't
    /// confirmed shown as waiting. Rows aren't tappable: the Watch has no memo detail, playback,
    /// editing or deleting.
    @ViewBuilder
    private var memoRows: some View {
        WatchSectionHeader(
            title: "Memos",
            section: .memos,
            sections: sections,
            count: WatchCollapsedCount.memos(memoList.listedMemos.count)
        )
        .listRow(top: 8, bottom: 5)

        if !sections.isCollapsed(.memos) {
                Button {
                    isRecording = true
                } label: {
                    Label("Record", systemImage: "mic.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .solidFill(.destructive)
                .disabled(recordingSession == nil)
                .accessibilityHint("Records a voice memo")
                .listRow(top: 0, bottom: 5)

            if memoList.listedMemos.isEmpty {
                Text(memoList.hasSynced ? "No memos today" : "Open Kyo on iPhone to sync memos")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryText.style)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRow(background: WatchTaskRowBackground(position: .only))
            } else {
                ForEach(Array(memoList.listedMemos.enumerated()), id: \.element.id) { index, memo in
                    WatchMemoRow(memo: memo)
                        .padding(.horizontal, 9)
                        .overlay(alignment: .top) {
                            if index > 0 { rowDivider.padding(.horizontal, 9) }
                        }
                        .listRow(background: WatchTaskRowBackground(position: .position(index: index, count: memoList.listedMemos.count)))
                }
                if !memoList.hasSynced {
                    Text("Open Kyo on iPhone to sync memos")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText.style)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRow(top: 5, bottom: 0)
                }
            }
        }
    }

    private var habitEmptyMessage: String {
        if !habitList.hasSynced { return "Open Kyo on iPhone to sync habits" }
        if habitList.habits.isEmpty { return "No habits yet. Add them on iPhone." }
        return "Nothing due today"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("kyo")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.secondaryText.style)
                .accessibilityLabel("Kyo")
            Text("Today")
                .font(.headline.weight(.bold))
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(taskList.currentDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.style)
                .accessibilityLabel(taskList.currentDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        HStack(spacing: 5) {
            WatchSummaryStat(value: "\(taskList.completedCount) / \(taskList.taskCount)", label: "Tasks")
            WatchSummaryStat(value: "\(habitList.doneCount) / \(habitList.todayCount)", label: "Habits")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(palette.card.style, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's summary")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(palette.divider.style)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

private enum WatchPreviewSheet: Identifiable {
    case add
    case edit(DailyTask)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let task): "edit-\(task.id.uuidString)"
        }
    }
}

private extension View {
    /// Makes a view a bare `List` row: no background, or default insets, with only
    /// the 10 pt screen margin and the given vertical spacing the old `VStack` layout used.
    func listRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 10, bottom: bottom, trailing: 10))
            .listRowBackground(Color.clear)
    }

    /// Like `listRow`, with a per-row slice of the rounded section background.
    func listRow(background: some View) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            .listRowBackground(background)
    }
}

/// One task row's slice of the rounded section background, so consecutive rows join into the
/// same rounded shape.
private struct WatchTaskRowBackground: View {
    enum Position {
        case only, first, middle, last

        static func position(index: Int, count: Int) -> Position {
            switch (index == 0, index == count - 1) {
            case (true, true): .only
            case (true, false): .first
            case (false, true): .last
            case (false, false): .middle
            }
        }
    }

    let position: Position
    @Environment(\.watchPalette) private var palette

    var body: some View {
        let radius: CGFloat = 13
        let top = (position == .only || position == .first) ? radius : 0
        let bottom = (position == .only || position == .last) ? radius : 0
        UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
        .fill(palette.listRow.style)
        .padding(.horizontal, 10)
        .padding(.vertical, -2.5)  // covers the ~5 pt gap watchOS leaves between list rows
    }
}

private struct WatchActionBar: View {
    let openAdd: () -> Void
    @Environment(\.watchPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Button(action: openAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.accent.style)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an item")
            .accessibilityHint("Opens the add preview")
        }
        .padding(2)
        .background(.regularMaterial, in: Capsule())
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: 106)
        .frame(maxWidth: .infinity)
        .padding(.top, 3)
    }
}

/// A section's header. Tapping it collapses or expands the section. While collapsed it shows the
/// section's count, if there is one, at the right.
private struct WatchSectionHeader: View {
    let title: String
    let section: TodaySectionID
    @ObservedObject var sections: CollapsedSections
    /// What the section holds, such as "2/5". Only shown while the section is collapsed.
    let count: WatchCollapsedCount?
    @Environment(\.watchPalette) private var palette

    private var isCollapsed: Bool { sections.isCollapsed(section) }
    private var shownCount: WatchCollapsedCount? { isCollapsed ? count : nil }

    var body: some View {
        Button {
            withAnimation { sections.toggle(section) }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.secondaryText.style)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                Spacer(minLength: 4)
                if let shownCount {
                    Text(shownCount.text)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondaryText.style)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shownCount.map { "\(title), \($0.spoken)" } ?? title)
        .accessibilityValue(isCollapsed ? "collapsed" : "expanded")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("section-header-\(section.rawValue)")
    }
}

private struct WatchSummaryStat: View {
    let value: String
    let label: String
    @Environment(\.watchPalette) private var palette

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText.style)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct WatchCheckRow: View {
    let title: String
    var detail: String? = nil
    let completed: Bool
    var task = false
    var onToggle: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @Environment(\.watchPalette) private var palette

    var body: some View {
        if let onToggle {
            Button(action: onToggle) {
                rowContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(completed ? "Completed" : "Not completed")
            .accessibilityHint(completed ? "Reopens this task" : "Marks this task complete")
            .accessibilityAction(named: "Edit") { onEdit?() }
            .accessibilityAction(named: "Delete") { onDelete?() }
        } else {
            rowContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(completed ? "Completed" : "Not completed")
                .accessibilityHint(detail ?? "")
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(completed ? palette.accent.color : palette.secondaryText.color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.footnote, weight: .regular))
                    .strikethrough(completed && task, color: palette.secondaryText.color)
                    .foregroundStyle(completed ? palette.secondaryText.color : palette.primaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText.style)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }
}

/// A habit row; tapping anywhere on it toggles the check-off. Day-based habits show the flame
/// streak (hidden at 0); weekly targets show only week progress, with no week streak on the Watch.
private struct WatchHabitRow: View {
    let entry: TodayHabit
    let onToggle: () -> Void
    @Environment(\.watchPalette) private var palette

    var body: some View {
        Button(action: onToggle) {
            rowContent
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.habit.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(entry.isCheckedOffToday ? "Removes today's check-off" : "Checks this habit off for today")
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: entry.isCheckedOffToday ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(entry.isCheckedOffToday ? palette.accent.color : palette.secondaryText.color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(entry.habit.name)
                .font(.system(.footnote, weight: .regular))
                .foregroundStyle(entry.isDone ? palette.secondaryText.color : palette.primaryText.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingStatus
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        let style = entry.isDone ? palette.secondaryText.color : palette.primaryText.color
        if let progress = entry.weekProgress {
            Text("\(progress.count)/\(progress.target)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(style)
                .padding(.top, 2)
                .accessibilityHidden(true)
        } else if entry.streak >= 1 {
            Label {
                Text("\(entry.streak)")
                    .font(.caption2.monospacedDigit())
            } icon: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(style)
            .padding(.top, 2)
            .accessibilityHidden(true)
        }
    }

    private var accessibilityValue: String {
        var value = entry.isCheckedOffToday ? "Checked off" : "Not checked off"
        if let progress = entry.weekProgress {
            value += ", \(progress.count) of \(progress.target) this week"
        } else if entry.streak >= 1 {
            value += ", \(entry.streak) day streak"
        }
        return value
    }
}

private struct WatchMemoRow: View {
    let memo: WatchListedMemo
    @Environment(\.watchPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: memo.isPhotoOnly ? "photo" : (memo.isVoice ? "waveform" : "text.alignleft"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.accent.style)
                .frame(width: 16)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.title)
                    .font(.system(.footnote, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(memo.detailLine())
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.style)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(memo.accessibilityLabel())
    }
}

/// Collects a task's text using native text input (the watchOS `TextField` offers dictation,
/// Scribble, and the on-screen keyboard), for both adding a task and editing one. Submitting or
/// tapping the button with blank text changes nothing (the store ignores it); dismissing without
/// submitting also changes nothing, matching the phone's abandoned-draft behavior.
private struct WatchTaskTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    let title: String
    let placeholder: String
    let buttonLabel: String
    let buttonHint: String
    let save: (String) -> Void
    @Environment(\.watchPalette) private var palette

    init(
        title: String,
        placeholder: String,
        initialText: String,
        buttonLabel: String,
        buttonHint: String,
        save: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.buttonLabel = buttonLabel
        self.buttonHint = buttonHint
        self.save = save
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)

                TextField(placeholder, text: $draft)
                    .font(.footnote)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .accessibilityLabel(placeholder)

                Button(buttonLabel) { commit() }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    // A bordered button's label is the tint, which the root text style would override.
                    .foregroundStyle(.tint)
                    .tint(palette.accent.color)
                    .accessibilityHint(buttonHint)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func commit() {
        save(draft)
        dismiss()
    }
}

#Preview {
    WatchTodayView()
}
