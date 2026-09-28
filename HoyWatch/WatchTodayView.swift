import SwiftUI

struct WatchTodayView: View {
    @StateObject private var taskList: TaskListStore
    @State private var activeSheet: WatchPreviewSheet?
    @State private var dayBoundaryRefreshToken = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _taskList = StateObject(wrappedValue: TaskListStore(sync: .mirror(from: WatchConnectivityTaskTransport.shared)))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        summary

                        WatchSection(title: "Tasks") {
                            VStack(spacing: 0) {
                                if taskList.tasks.isEmpty {
                                    Text("No tasks yet")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 7)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    ForEach(Array(taskList.tasks.enumerated()), id: \.element.id) { index, task in
                                        if index > 0 { rowDivider }
                                        WatchCheckRow(
                                            title: task.text,
                                            completed: task.isComplete,
                                            task: true,
                                            onToggle: { taskList.toggleTask(id: task.id) }
                                        )
                                    }
                                }
                            }
                        }
                        WatchSection(title: "Habits") {
                            VStack(spacing: 0) {
                                WatchCheckRow(title: "Morning walk", detail: "20 min", completed: true)
                                rowDivider
                                WatchCheckRow(title: "Read a little", detail: "10 pages", completed: false)
                            }
                        }
                        WatchSection(title: "Memos") {
                            VStack(spacing: 0) {
                                WatchMemoRow(
                                    icon: "text.alignleft",
                                    title: "An idea for the weekend",
                                    detail: "Try the trail by the lake. Bring coffee."
                                )
                                rowDivider
                                WatchMemoRow(icon: "waveform", title: "Thoughts on my walk", detail: "Voice memo · 0:42")
                            }
                        }
                        WatchSection(title: "Meals") {
                            VStack(alignment: .leading, spacing: 0) {
                                WatchMealSummary()
                                rowDivider
                                WatchMealRow(title: "Yogurt, oats & berries", detail: "Breakfast · 8:15 AM", calories: "420 kcal")
                                rowDivider
                                WatchMealRow(title: "Chicken & rice bowl", detail: "Lunch · 12:30 PM", calories: "820 kcal")
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(height: max(0, geometry.size.height - 54), alignment: .top)

                WatchActionBar(
                    openAdd: { activeSheet = .add },
                    openCalendar: { activeSheet = .calendar }
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .ignoresSafeArea(edges: .top)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                WatchAddTaskSheet(addTask: { text in taskList.addTask(text: text) })
            case .calendar:
                WatchCalendarPreviewSheet()
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
        VStack(alignment: .leading, spacing: 1) {
            Text("hoy")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Hoy")
            Text("Today")
                .font(.headline.weight(.bold))
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(taskList.currentDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(taskList.currentDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        HStack(spacing: 5) {
            WatchSummaryStat(value: "\(taskList.completedCount) / \(taskList.taskCount)", label: "Tasks")
            WatchSummaryStat(value: "1 / 2", label: "Habits")
            WatchSummaryStat(value: "1,240", label: "kcal")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(surface.opacity(colorScheme == .dark ? 0.72 : 0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's summary")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }

    private var surface: Color {
        colorScheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.15) : .white
    }
}

private enum WatchPreviewSheet: String, Identifiable {
    case add
    case calendar

    var id: String { rawValue }
}

private struct WatchActionBar: View {
    let openAdd: () -> Void
    let openCalendar: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: openAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an item")
            .accessibilityHint("Opens the add preview")

            Button(action: openCalendar) {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calendar")
            .accessibilityHint("Opens the past days preview")
        }
        .padding(2)
        .background(.regularMaterial, in: Capsule())
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: 106)
        .frame(maxWidth: .infinity)
        .padding(.top, 3)
    }
}

private struct WatchSection<Content: View>: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)

            content
                .padding(.horizontal, 9)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityElement(children: .contain)
        }
    }
}

private struct WatchSummaryStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(completed ? accentColor : Color.secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.footnote, weight: .regular))
                    .strikethrough(completed && task, color: .secondary)
                    .foregroundStyle(completed ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }

    private var accentColor: Color { .green }
}

private struct WatchMemoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 16)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.footnote, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(icon == "waveform" ? "Voice memo" : "Written memo"), \(title), \(detail)")
    }
}

private struct WatchMealSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("1,240")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("/ 2,000 kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("760 left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            WatchMacroRow(name: "Protein", amount: "86 / 130 g", progress: 0.66, opacity: 1)
            WatchMacroRow(name: "Carbs", amount: "134 / 220 g", progress: 0.61, opacity: 0.75)
            WatchMacroRow(name: "Fat", amount: "40 / 67 g", progress: 0.60, opacity: 0.5)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meal nutrition summary")
    }
}

private struct WatchMacroRow: View {
    let name: String
    let amount: String
    let progress: CGFloat
    let opacity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(amount)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.green.opacity(opacity))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(amount)")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private struct WatchMealRow: View {
    let title: String
    let detail: String
    let calories: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.footnote, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 2) {
                Text(detail)
                Spacer(minLength: 2)
                Text(calories)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// Adds a task to today's list using native text input (the watchOS `TextField` offers
/// dictation, Scribble, and the on-screen keyboard). Submitting or tapping Add with blank text
/// creates nothing; dismissing without submitting also creates nothing, matching the phone's
/// abandoned-draft behavior.
private struct WatchAddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    let addTask: (String) -> DailyTask?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add a task").font(.headline)

                TextField("New task", text: $draft)
                    .font(.footnote)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityLabel("New task")

                Button("Add") { save() }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .tint(.green)
                    .accessibilityHint("Saves this task to today's list")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add task")
    }

    private func save() {
        _ = addTask(draft)
        dismiss()
    }
}

private struct WatchCalendarPreviewSheet: View {
    @State private var selectedDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 23)
    ) ?? .now
    private let latestDate = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 24)
    ) ?? .now

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Past days").font(.headline)
                }

                DatePicker("Choose a day", selection: $selectedDate, in: ...latestDate, displayedComponents: .date)
                    .font(.footnote)
                    .tint(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.footnote.weight(.semibold))
                    Text("No entries in this sketch.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar preview")
    }
}

#Preview {
    WatchTodayView()
}
