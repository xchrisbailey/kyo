import SwiftUI
import UIKit

struct TodayView: View {
    @StateObject private var taskList: TaskListStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeSheet: TodayPreviewSheet?
    @State private var isShowingTaskDraft = false
    @State private var taskDraft = ""
    @State private var dayBoundaryRefreshToken = 0
    @FocusState private var isTaskDraftFocused: Bool

    init() {
        let env = ProcessInfo.processInfo.environment
        let key = env["HOY_TASK_STORAGE_KEY"]
        let storageKey = key ?? TaskListStore.storageKey
        // Isolated UI-test stores never publish, so tests don't race real WatchConnectivity delivery.
        let sync: TaskListSync? = key == nil ? .publish(to: WatchConnectivityTaskTransport.shared) : nil
        _taskList = StateObject(wrappedValue: TaskListStore(storageKey: storageKey, sync: sync))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        summaryStats
                        TodaySection(title: "Tasks", note: "For today") {
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
                                }
                            }
                        }
                        TodaySection(title: "Habits", note: "Small steps, daily") {
                            VStack(spacing: 0) {
                                CheckRow(title: "Morning walk", trailing: "20 min", isComplete: true)
                                rowDivider
                                CheckRow(title: "Read a little", trailing: "10 pages", isComplete: false)
                            }
                        }
                        TodaySection(title: "Memos", note: "Notes & voice") {
                            VStack(spacing: 0) {
                                MemoRow(icon: "text.alignleft", title: "An idea for the weekend", detail: "Try the trail by the lake. Bring coffee.")
                                rowDivider
                                VoiceMemoRow()
                            }
                        }
                        TodaySection(title: "Meals", note: "2 logged") {
                            VStack(spacing: 0) {
                                MealSummary()
                                    .padding(.horizontal, 16)
                                rowDivider
                                    .padding(.horizontal, 16)
                                MealRow(title: "Yogurt, oats & berries", detail: "Breakfast · 8:15 AM", calories: "420 kcal")
                                rowDivider
                                MealRow(title: "Chicken & rice bowl", detail: "Lunch · 12:30 PM", calories: "820 kcal")
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
                        openAdd: beginTaskDraft,
                        openCalendar: { activeSheet = .calendar }
                    )
                }
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case .calendar:
                        CalendarPreviewSheet()
                    }
                }
                .onDisappear(perform: abandonTaskDraft)
                .onChange(of: isShowingTaskDraft) { _, isShowing in
                    if isShowing {
                        withAnimation {
                            scrollProxy.scrollTo("task-draft", anchor: .center)
                        }
                    }
                }
            }
        }
        .task(id: dayBoundaryRefreshToken) {
            await taskList.refreshAtEachDayBoundary()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                taskList.refreshForCurrentDay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            taskList.refreshForCurrentDay()
            dayBoundaryRefreshToken += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            taskList.refreshForCurrentDay()
            dayBoundaryRefreshToken += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            taskList.refreshForCurrentDay()
            dayBoundaryRefreshToken += 1
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("hoy")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(.secondary)
                .padding(.bottom, 17)
                .accessibilityLabel("Hoy")

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
            SummaryStat(value: "1 / 2", label: "Habits done")
            statDivider
            SummaryStat(value: "1,240", label: "kcal logged")
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

    private func beginTaskDraft() {
        if !isShowingTaskDraft {
            taskDraft = ""
            isShowingTaskDraft = true
        }
        isTaskDraftFocused = true
    }

    private func saveTaskDraft() {
        taskList.addTask(text: taskDraft)
        abandonTaskDraft()
    }

    private func abandonTaskDraft() {
        isTaskDraftFocused = false
        isShowingTaskDraft = false
        taskDraft = ""
    }
}

private enum TodayPreviewSheet: String, Identifiable {
    case calendar

    var id: String { rawValue }
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
    let openAdd: () -> Void
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

            Button(action: openAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(accentColor, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an item")
            .accessibilityHint("Adds a task to today's list")

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
        HoyPalette.accent
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
                .tint(HoyPalette.accent)
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

private enum HoyPalette {
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

private struct TodaySection<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: 51)
            .accessibilityElement(children: .combine)

            content
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .contain)
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

private struct MemoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Written memo. \(title). \(detail)")
    }

    private var accentColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.57, green: 0.79, blue: 0.68, alpha: 1)
                : UIColor(red: 0.22, green: 0.43, blue: 0.34, alpha: 1)
        })
    }
}

private struct VoiceMemoRow: View {
    private let bars: [CGFloat] = [5, 11, 18, 9, 22, 15, 8, 13, 20, 11, 5, 16, 9, 5]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Thoughts on my walk")
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
                        Capsule()
                            .fill(accentColor.opacity(0.65))
                            .frame(width: 3, height: height)
                    }
                }
                .frame(height: 22, alignment: .center)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("0:42")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice memo, Thoughts on my walk, 42 seconds")
    }

    private var accentColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.57, green: 0.79, blue: 0.68, alpha: 1)
                : UIColor(red: 0.22, green: 0.43, blue: 0.34, alpha: 1)
        })
    }
}

private struct MealSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("1,240")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("/ 2,000 kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("760 left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)

            HStack(alignment: .top, spacing: 12) {
                MacroProgress(label: "Protein", amount: "86 / 130 g", progress: 0.66, opacity: 1)
                MacroProgress(label: "Carbs", amount: "134 / 220 g", progress: 0.61, opacity: 0.75)
                MacroProgress(label: "Fat", amount: "40 / 67 g", progress: 0.60, opacity: 0.5)
            }
            .padding(.top, 13)
            .padding(.bottom, 15)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meal nutrition summary")
    }
}

private struct MacroProgress: View {
    let label: String
    let amount: String
    let progress: CGFloat
    let opacity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(amount)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .separator).opacity(0.45))
                    Capsule()
                        .fill(accentColor.opacity(opacity))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(amount)")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    private var accentColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.57, green: 0.79, blue: 0.68, alpha: 1)
                : UIColor(red: 0.22, green: 0.43, blue: 0.34, alpha: 1)
        })
    }
}

private struct MealRow: View {
    let title: String
    let detail: String
    let calories: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(calories)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 55)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TodayView()
}
