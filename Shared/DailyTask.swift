import Combine
import Foundation
import SwiftData

struct TaskCompletionDay: Codable, Hashable, Sendable {
    let era: Int?
    let year: Int
    let month: Int
    let day: Int

    init(era: Int?, year: Int, month: Int, day: Int) {
        self.era = era
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        self.era = components.era
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
    }
}

typealias TaskPlannedDay = TaskCompletionDay

extension TaskCompletionDay {
    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(era: era, year: year, month: month, day: day))
    }
}

struct DailyTask: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let creationOrder: Int64
    let isComplete: Bool
    let completedOn: TaskCompletionDay?
    let plannedOn: TaskPlannedDay?
    let projectID: UUID?
    let isUnscheduled: Bool

    init(
        id: UUID = UUID(),
        text: String,
        creationOrder: Int64,
        isComplete: Bool = false,
        completedOn: TaskCompletionDay? = nil,
        plannedOn: TaskPlannedDay? = nil,
        projectID: UUID? = nil,
        isUnscheduled: Bool = false
    ) {
        self.id = id
        self.text = text
        self.creationOrder = creationOrder
        self.isComplete = isComplete
        self.completedOn = completedOn
        self.plannedOn = plannedOn
        self.projectID = projectID
        self.isUnscheduled = isUnscheduled
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, creationOrder, isComplete, completedOn, plannedOn, projectID, isUnscheduled
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        creationOrder = try values.decode(Int64.self, forKey: .creationOrder)
        isComplete = try values.decode(Bool.self, forKey: .isComplete)
        completedOn = try values.decodeIfPresent(TaskCompletionDay.self, forKey: .completedOn)
        plannedOn = try values.decodeIfPresent(TaskPlannedDay.self, forKey: .plannedOn)
        projectID = try values.decodeIfPresent(UUID.self, forKey: .projectID)
        isUnscheduled = try values.decodeIfPresent(Bool.self, forKey: .isUnscheduled) ?? false
    }

}

@MainActor
protocol TaskListBehavior: AnyObject {
    var tasks: [DailyTask] { get }
    var laterTasks: [DailyTask] { get }
    var everydayTasks: [DailyTask] { get }
    var projectCatalog: [Project] { get }
    @discardableResult func returnTaskToProject(id: UUID) -> DailyTask?
    func tasks(in projectID: UUID) -> [DailyTask]
    @discardableResult func addUnscheduledTask(text: String, projectID: UUID) -> DailyTask?
    @discardableResult func deferTask(id: UUID, to date: Date) -> DailyTask?
    @discardableResult func bringTaskToToday(id: UUID) -> DailyTask?
    var taskCount: Int { get }
    var completedCount: Int { get }
    var incompleteCount: Int { get }
    /// What a collapsed Tasks header shows: "2 of 5 done" for Today's tasks (carried-forward
    /// ones included), "No tasks" when Today has none.
    var collapsedSummary: String { get }
    @discardableResult func addTask(text: String) -> DailyTask?
    @discardableResult func addTask(text: String, plannedFor date: Date) -> DailyTask?
    @discardableResult func editTask(id: UUID, text: String) -> DailyTask?
    @discardableResult func deleteTask(id: UUID) -> DailyTask?
    @discardableResult func toggleTask(id: UUID) -> DailyTask?
}

@MainActor
final class TaskListStore: ObservableObject, TaskListBehavior {
    static let storageKey = "kyo.dailyTasks.v1"
    static let projectStorageKey = "kyo.taskProjectCatalog.v1"

    @Published private(set) var tasks: [DailyTask] = []
    @Published private(set) var projectCatalog: [Project] = []
    private let projectCatalogKey: String
    @Published private(set) var laterTasks: [DailyTask] = []
    @Published private(set) var currentDate: Date

    /// The phone's (and any standalone store's) authoritative persisted list. Unused by a
    /// `.mirror` store, which keeps `baseTasks` + `outbox` instead. See
    /// docs/adr/0002-watch-commands-and-phone-reconciliation.md.
    private var savedTasks: [DailyTask]
    /// A `.mirror` (Watch) store's tasks as of the last applied snapshot, before replaying
    /// its own unacknowledged commands on top.
    private var baseTasks: [DailyTask]
    /// A `.mirror` store's ordered, unacknowledged commands. Replayed over `baseTasks` to
    /// produce the Watch's visible/saved list; cleared as the phone acknowledges them.
    private var outbox: [TaskCommand]
    /// A `.publish` (phone) store's ids of tasks it has deleted. Prevents a late or
    /// duplicated Watch command from resurrecting a task the phone has since deleted.
    private var tombstonedTaskIDs: [UUID]
    /// A `.publish` store's ids of commands it has already applied, for idempotency under
    /// retry and duplicate delivery.
    private var processedCommandIDs: [UUID]

    private let userDefaults: UserDefaults
    /// Where task content lives: SwiftData for a `.publish` or standalone store, the
    /// `storageKey` UserDefaults entry for a `.mirror` (Watch) store.
    private let content: any TaskContentPersistence
    private let modelContainer: ModelContainer?
    private let now: () -> Date
    private let calendarProvider: () -> Calendar
    private var calendar: Calendar { calendarProvider() }
    private let sync: TaskListSync?
    private let revisionKey: String
    private let outboxKey: String
    private let tombstonesKey: String
    private let processedCommandIDsKey: String
    private var revision: Int64?

    /// Persisted sets are bounded to this many most-recent entries (insertion order) so they
    /// cannot grow without bound over the life of an install.
    private static let maxBoundedSetSize = 500

    var everydayTasks: [DailyTask] { tasks.filter { $0.projectID == nil } }

    var taskCount: Int { tasks.count }
    var completedCount: Int { tasks.filter(\.isComplete).count }
    var incompleteCount: Int { taskCount - completedCount }

    var collapsedSummary: String {
        taskCount == 0 ? "No tasks" : "\(completedCount) of \(taskCount) done"
    }

    /// A `.publish` or standalone (nil sync) store keeps its content in `modelContainer`, which
    /// it requires; a `.mirror` store ignores the container and keeps UserDefaults. Revision,
    /// tombstones and processed command ids stay in `userDefaults` under keys derived from
    /// `storageKey` in every case; the content key itself is never read or written by a
    /// non-mirror store.
    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = TaskListStore.storageKey,
        modelContainer: ModelContainer? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        calendarProvider: (() -> Calendar)? = nil,
        sync: TaskListSync? = nil
    ) {
        self.modelContainer = modelContainer
        self.userDefaults = userDefaults
        self.now = now
        self.calendarProvider = calendarProvider ?? { calendar }
        self.sync = sync
        self.revisionKey = storageKey + ".revision"
        self.outboxKey = storageKey + ".outbox"
        self.tombstonesKey = storageKey + ".tombstones"
        self.processedCommandIDsKey = storageKey + ".processedCommands"
        self.projectCatalogKey = storageKey + "." + Self.projectStorageKey
        self.currentDate = (calendarProvider?() ?? calendar).startOfDay(for: now())

        if case .mirror = sync {
            // The Watch's existing storage key holds its mirrored task list, which is
            // `baseTasks` under the outbox model.
            let content = UserDefaultsTaskContent(userDefaults: userDefaults, key: storageKey)
            self.content = content
            self.baseTasks = Self.ordered(content.load())
            self.savedTasks = []
        } else {
            guard let modelContainer else {
                preconditionFailure("A phone or standalone TaskListStore needs a ModelContainer")
            }
            let content = SwiftDataTaskContent(modelContainer: modelContainer)
            self.content = content
            self.savedTasks = Self.ordered(content.load())
            self.baseTasks = []
        }

        if case .mirror = sync,
           let data = userDefaults.data(forKey: outboxKey),
           let decoded = try? JSONDecoder().decode([TaskCommand].self, from: data) {
            self.outbox = decoded
        } else {
            self.outbox = []
        }

        if case .publish = sync,
           let data = userDefaults.data(forKey: tombstonesKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            self.tombstonedTaskIDs = decoded
        } else {
            self.tombstonedTaskIDs = []
        }

        if case .publish = sync,
           let data = userDefaults.data(forKey: processedCommandIDsKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            self.processedCommandIDs = decoded
        } else {
            self.processedCommandIDs = []
        }

        if sync != nil {
            self.revision = (userDefaults.object(forKey: revisionKey) as? NSNumber)?.int64Value
        } else {
            self.revision = nil
        }
        if case .mirror = sync,
           let data = userDefaults.data(forKey: projectCatalogKey),
           let decoded = try? JSONDecoder().decode([Project].self, from: data) {
            projectCatalog = decoded
        } else {
            loadProjectCatalog()
        }
        refreshForCurrentDay()

        switch sync {
        case .publish(let transport):
            // Registering the command handler before the initial publish means any command
            // the transport already queued before this store existed gets applied and
            // acknowledged as part of this store's first snapshot.
            transport.setCommandHandler { [weak self] command in
                self?.applyCommand(command)
            }
            // A fresh install or a reset UserDefaults suite has no stored revision yet. Seed
            // one from the wall clock now, rather than publishing at revision 0 forever: a
            // Watch that already applied a higher revision from a previous install would
            // otherwise ignore this device's snapshots indefinitely. See the ADR's
            // reinstalled-phone consequence.
            if revision == nil {
                let seeded = Int64(now().timeIntervalSince1970 * 1000)
                revision = seeded
                userDefaults.set(NSNumber(value: seeded), forKey: revisionKey)
            }
            transport.publish(TaskListSnapshot(revision: revision ?? 0, tasks: tasks + laterTasks, acknowledgedCommandIDs: processedCommandIDs, projects: projectCatalog))
        case .mirror(let transport):
            // Registered last: the transport may call the handler synchronously,
            // and everything it touches (baseTasks, outbox, revision, tasks) must already exist.
            transport.setSnapshotHandler { [weak self] snapshot in
                self?.apply(snapshot)
            }
            // Retry: resend every still-unacknowledged command. Duplicates are harmless; the
            // phone dedupes by command id.
            for command in outbox {
                transport.send(command)
            }
        case nil:
            break
        }
    }

    @discardableResult
    func addTask(text: String) -> DailyTask? {
        createTask(text: text, plannedOn: nil)
    }

    @discardableResult
    func addTask(text: String, plannedFor date: Date) -> DailyTask? {
        if case .mirror = sync { return nil }
        guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: now()) else { return nil }
        return createTask(text: text, plannedOn: TaskPlannedDay(date: date, calendar: calendar))
    }

    func tasks(in projectID: UUID) -> [DailyTask] {
        currentFullTaskList.filter { $0.projectID == projectID }.sorted {
            if $0.creationOrder != $1.creationOrder { return $0.creationOrder < $1.creationOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    @discardableResult
    func addUnscheduledTask(text: String, projectID: UUID) -> DailyTask? {
        if case .mirror = sync { return nil }
        guard let modelContainer,
              let projects = try? modelContainer.mainContext.fetch(FetchDescriptor<ProjectRecord>()),
              projects.contains(where: { $0.id == projectID }) else { return nil }
        return createTask(text: text, plannedOn: nil, projectID: projectID, isUnscheduled: true)
    }

    private func createTask(text: String, plannedOn: TaskPlannedDay?, projectID: UUID? = nil, isUnscheduled: Bool = false) -> DailyTask? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        if case .mirror(let transport) = sync {
            let taskID = UUID()
            let command = TaskCommand(id: UUID(), action: .add(taskID: taskID, text: trimmedText))
            outbox.append(command)
            persistOutbox()
            refreshForCurrentDay()
            transport.send(command)
            return tasks.first { $0.id == taskID }
        }

        let creationOrder = (savedTasks.map(\.creationOrder).max() ?? -1) + 1
        let task = DailyTask(text: trimmedText, creationOrder: creationOrder, plannedOn: plannedOn, projectID: projectID, isUnscheduled: isUnscheduled)
        savedTasks.append(task)
        refreshForCurrentDay()
        persist()
        publishChange()
        return task
    }

    @discardableResult
    func editTask(id: UUID, text: String) -> DailyTask? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if case .mirror(let transport) = sync {
            guard !trimmedText.isEmpty,
                  effectiveMirrorTasks.contains(where: { $0.id == id }) else { return nil }
            let command = TaskCommand(id: UUID(), action: .rename(taskID: id, text: trimmedText))
            outbox.append(command)
            persistOutbox()
            refreshForCurrentDay()
            transport.send(command)
            return effectiveMirrorTasks.first { $0.id == id }
        }

        guard !trimmedText.isEmpty,
              let index = savedTasks.firstIndex(where: { $0.id == id }) else { return nil }

        let task = savedTasks[index]
        let updatedTask = DailyTask(
            id: task.id,
            text: trimmedText,
            creationOrder: task.creationOrder,
            isComplete: task.isComplete,
            completedOn: task.completedOn,
            plannedOn: task.plannedOn,
            projectID: task.projectID,
            isUnscheduled: task.isUnscheduled
        )
        savedTasks[index] = updatedTask
        refreshForCurrentDay()
        persist()
        publishChange()
        return updatedTask
    }

    @discardableResult
    func deleteTask(id: UUID) -> DailyTask? {
        if case .mirror(let transport) = sync {
            guard let removed = effectiveMirrorTasks.first(where: { $0.id == id }) else { return nil }
            let command = TaskCommand(id: UUID(), action: .delete(taskID: id))
            outbox.append(command)
            persistOutbox()
            refreshForCurrentDay()
            transport.send(command)
            return removed
        }

        guard let index = savedTasks.firstIndex(where: { $0.id == id }) else { return nil }
        let removedTask = savedTasks.remove(at: index)
        if case .publish = sync {
            recordTombstone(id)
        }
        refreshForCurrentDay()
        persist()
        publishChange()
        return removedTask
    }

    @discardableResult
    func toggleTask(id: UUID) -> DailyTask? {
        if case .mirror(let transport) = sync {
            guard let current = effectiveMirrorTasks.first(where: { $0.id == id }) else { return nil }
            let isComplete = !current.isComplete
            let completedOn = isComplete ? TaskCompletionDay(date: now(), calendar: calendar) : nil
            let command = TaskCommand(id: UUID(), action: .setCompletion(taskID: id, isComplete: isComplete, completedOn: completedOn))
            outbox.append(command)
            persistOutbox()
            refreshForCurrentDay()
            transport.send(command)
            return effectiveMirrorTasks.first { $0.id == id }
        }

        guard let index = savedTasks.firstIndex(where: { $0.id == id }) else { return nil }

        let task = savedTasks[index]
        let updatedTask = DailyTask(
            id: task.id,
            text: task.text,
            creationOrder: task.creationOrder,
            isComplete: !task.isComplete,
            completedOn: task.isComplete ? nil : TaskCompletionDay(date: now(), calendar: calendar),
            plannedOn: task.isComplete && task.projectID != nil ? nil : task.plannedOn,
            projectID: task.projectID,
            isUnscheduled: task.isComplete && task.projectID != nil ? false : task.isUnscheduled
        )
        savedTasks[index] = updatedTask
        refreshForCurrentDay()
        persist()
        publishChange()
        return updatedTask
    }

    /// Re-evaluates which saved tasks belong to the local current day.
    /// Incomplete tasks remain visible; completed tasks stay visible only on
    /// their completion day and remain saved for future history/sync work.
    func refreshForCurrentDay() {
        let now = now()
        currentDate = calendar.startOfDay(for: now)
        let day = TaskCompletionDay(date: now, calendar: calendar)
        tasks = Self.ordered(currentFullTaskList.filter { task in
            !task.isUnscheduled && (task.isComplete ? task.completedOn == day : !isDeferred(task))
        })
        laterTasks = currentFullTaskList.filter { !$0.isUnscheduled && !$0.isComplete && isDeferred($0) }.sorted {
            let lhs = $0.plannedOn?.date(in: calendar) ?? currentDate
            let rhs = $1.plannedOn?.date(in: calendar) ?? currentDate
            if lhs != rhs { return lhs < rhs }
            if $0.creationOrder != $1.creationOrder { return $0.creationOrder < $1.creationOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func isDeferred(_ task: DailyTask) -> Bool {
        guard let planned = task.plannedOn?.date(in: calendar) else { return false }
        return planned > currentDate
    }

    @discardableResult
    func deferTask(id: UUID, to date: Date) -> DailyTask? {
        guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: now()) else { return nil }
        return setPlannedDay(id: id, day: TaskPlannedDay(date: date, calendar: calendar))
    }

    @discardableResult
    func bringTaskToToday(id: UUID) -> DailyTask? {
        setPlannedDay(id: id, day: nil, isUnscheduled: false)
    }

    @discardableResult
    func returnTaskToProject(id: UUID) -> DailyTask? {
        guard currentFullTaskList.contains(where: { $0.id == id && $0.projectID != nil }) else { return nil }
        return setPlannedDay(id: id, day: nil, isUnscheduled: true)
    }

    private func setPlannedDay(id: UUID, day: TaskPlannedDay?, isUnscheduled: Bool? = nil) -> DailyTask? {
        if case .mirror = sync { return nil }
        guard let index = savedTasks.firstIndex(where: { $0.id == id }),
              !savedTasks[index].isComplete else { return nil }
        let task = savedTasks[index]
        let updated = DailyTask(id: task.id, text: task.text, creationOrder: task.creationOrder,
                                isComplete: task.isComplete, completedOn: task.completedOn, plannedOn: day,
                                projectID: task.projectID, isUnscheduled: isUnscheduled ?? task.isUnscheduled)
        savedTasks[index] = updated
        refreshForCurrentDay()
        persist()
        publishChange()
        return updated
    }

    /// The tasks completed on the day containing `day`, in creation order. Reads the full list, not
    /// Today's, so it answers for any past day.
    func tasksCompleted(on day: Date, calendar: Calendar? = nil) -> [DailyTask] {
        let calendar = calendar ?? self.calendar
        let completionDay = TaskCompletionDay(date: day, calendar: calendar)
        return Self.ordered(currentFullTaskList.filter { !$0.isUnscheduled && $0.isComplete && $0.completedOn == completionDay })
    }

    /// Incomplete tasks with this planned day, including ones already available on Today.
    func tasksPlanned(on day: Date, calendar: Calendar? = nil) -> [DailyTask] {
        let calendar = calendar ?? self.calendar
        let plannedDay = TaskPlannedDay(date: day, calendar: calendar)
        return Self.ordered(currentFullTaskList.filter { !$0.isUnscheduled && !$0.isComplete && $0.plannedOn == plannedDay })
    }

    /// The start of each day in `days` on which at least one task was completed.
    func daysWithCompletedTask(in days: [Date]) -> Set<Date> {
        let completionDays = Set(currentFullTaskList.compactMap { !$0.isUnscheduled && $0.isComplete ? $0.completedOn : nil })
        return Set(days.map { calendar.startOfDay(for: $0) }.filter {
            completionDays.contains(TaskCompletionDay(date: $0, calendar: calendar))
        })
    }

    /// Refreshes for the current day now, then again at every local midnight until cancelled.
    /// Both `TodayView` and `WatchTodayView` drive their day rollover from this.
    func refreshAtEachDayBoundary() async {
        while !Task.isCancelled {
            refreshForCurrentDay()
            let today = calendar.startOfDay(for: now())
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
            let delay = max(1, tomorrow.timeIntervalSince(now()))
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    /// The full (not day-filtered) task list this store currently shows: `savedTasks` for a
    /// phone or standalone store, or the outbox replayed over `baseTasks` for a Watch mirror.
    private var currentFullTaskList: [DailyTask] {
        if case .mirror = sync {
            return effectiveMirrorTasks
        }
        return savedTasks
    }

    /// A Watch mirror's `baseTasks` with every outbox command replayed on top, using the same
    /// rules the phone applies: `add` appends with the current max creation order + 1 if the
    /// task id is absent; `setCompletion` sets the given state and `rename` sets the text if
    /// the task is present; `delete` removes it if present.
    private var effectiveMirrorTasks: [DailyTask] {
        Self.replaying(outbox, over: baseTasks)
    }

    private static func replaying(_ commands: [TaskCommand], over base: [DailyTask]) -> [DailyTask] {
        var result = base
        // Ids deleted earlier in this replay, mirroring the phone's tombstones: a later replayed
        // `add` for one is a no-op, so an add-then-delete pair stays deleted even when a
        // snapshot that still contains the task acknowledges only the add.
        var deletedTaskIDs: Set<UUID> = []
        for command in commands {
            switch command.action {
            case .add(let taskID, let text):
                guard !deletedTaskIDs.contains(taskID),
                      !result.contains(where: { $0.id == taskID }) else { continue }
                let creationOrder = (result.map(\.creationOrder).max() ?? -1) + 1
                result.append(DailyTask(id: taskID, text: text, creationOrder: creationOrder))
            case .setCompletion(let taskID, let isComplete, let completedOn):
                guard let index = result.firstIndex(where: { $0.id == taskID }) else { continue }
                let task = result[index]
                result[index] = DailyTask(
                    id: task.id,
                    text: task.text,
                    creationOrder: task.creationOrder,
                    isComplete: isComplete,
                    completedOn: completedOn,
                    plannedOn: !isComplete && task.projectID != nil ? nil : task.plannedOn,
                    projectID: task.projectID,
                    isUnscheduled: !isComplete && task.projectID != nil ? false : task.isUnscheduled
                )
            case .rename(let taskID, let text):
                guard let index = result.firstIndex(where: { $0.id == taskID }) else { continue }
                let task = result[index]
                result[index] = DailyTask(
                    id: task.id,
                    text: text,
                    creationOrder: task.creationOrder,
                    isComplete: task.isComplete,
                    completedOn: task.completedOn,
                    plannedOn: task.plannedOn,
                    projectID: task.projectID,
                    isUnscheduled: task.isUnscheduled
                )
            case .delete(let taskID):
                deletedTaskIDs.insert(taskID)
                result.removeAll { $0.id == taskID }
            }
        }
        return result
    }

    func refreshProjectCatalog() {
        loadProjectCatalog()
        publishChange()
    }

    private func loadProjectCatalog() {
        guard let modelContainer else { return }
        projectCatalog = ((try? modelContainer.mainContext.fetch(FetchDescriptor<ProjectRecord>())) ?? [])
            .map(\.project).sorted {
                if $0.creationOrder != $1.creationOrder { return $0.creationOrder < $1.creationOrder }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// Publishes the current task list to the counterpart device if this store is the
    /// publishing (phone) side of a sync pair. Does nothing for `.mirror` or no sync role.
    /// Bumps the revision with a hybrid clock: strictly increasing even across restarts and
    /// reinstalls, since it is floored by the device's wall clock in milliseconds.
    private func publishChange() {
        guard case .publish(let transport) = sync else { return }
        let candidate = max((revision ?? 0) + 1, Int64(now().timeIntervalSince1970 * 1000))
        revision = candidate
        userDefaults.set(NSNumber(value: candidate), forKey: revisionKey)
        transport.publish(TaskListSnapshot(revision: candidate, tasks: tasks + laterTasks, acknowledgedCommandIDs: processedCommandIDs, projects: projectCatalog))
    }

    /// Applies a Watch-originated command on the phone (`.publish` side), per
    /// docs/adr/0002-watch-commands-and-phone-reconciliation.md: the phone applies its own
    /// changes and Watch commands in the order it receives/performs them, last applied wins
    /// per task, and deletion is final (tombstones). Every command is acknowledged — recorded
    /// in `processedCommandIDs` and reflected in the next published snapshot — even one that
    /// is ignored below, so the Watch can retire it from its outbox.
    private func applyCommand(_ command: TaskCommand) {
        guard !processedCommandIDs.contains(command.id) else { return }

        switch command.action {
        case .add(let taskID, let text):
            let alreadyExists = savedTasks.contains { $0.id == taskID }
            let tombstoned = tombstonedTaskIDs.contains(taskID)
            if !alreadyExists && !tombstoned {
                let creationOrder = (savedTasks.map(\.creationOrder).max() ?? -1) + 1
                savedTasks.append(DailyTask(id: taskID, text: text, creationOrder: creationOrder))
            }
        case .setCompletion(let taskID, let isComplete, let completedOn):
            if let index = savedTasks.firstIndex(where: { $0.id == taskID }) {
                let task = savedTasks[index]
                savedTasks[index] = DailyTask(
                    id: task.id,
                    text: task.text,
                    creationOrder: task.creationOrder,
                    isComplete: isComplete,
                    completedOn: completedOn,
                    plannedOn: !isComplete && task.projectID != nil ? nil : task.plannedOn,
                    projectID: task.projectID,
                    isUnscheduled: !isComplete && task.projectID != nil ? false : task.isUnscheduled
                )
            }
        case .rename(let taskID, let text):
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty, let index = savedTasks.firstIndex(where: { $0.id == taskID }) {
                let task = savedTasks[index]
                savedTasks[index] = DailyTask(
                    id: task.id,
                    text: trimmedText,
                    creationOrder: task.creationOrder,
                    isComplete: task.isComplete,
                    completedOn: task.completedOn,
                    plannedOn: task.plannedOn,
                    projectID: task.projectID,
                    isUnscheduled: task.isUnscheduled
                )
            }
        case .delete(let taskID):
            savedTasks.removeAll { $0.id == taskID }
            recordTombstone(taskID)
        }

        // Content is saved before the command id is recorded as processed, so a command is never
        // marked done while its effect is missing from storage.
        refreshForCurrentDay()
        persist()
        recordProcessedCommand(command.id)
        publishChange()
    }

    /// Applies an incoming snapshot from the publishing (phone) side, per the reconciliation
    /// rule in docs/adr/0001-phone-authoritative-task-snapshots.md: a snapshot replaces
    /// `baseTasks` outright only if its revision is strictly greater than the last one applied,
    /// or none has been applied yet; older or repeated snapshots leave `baseTasks` untouched.
    /// Independent of that check, any outbox commands the snapshot acknowledges are always
    /// dropped, since the phone has already applied (or intentionally ignored, e.g. a
    /// tombstoned add) them.
    private func apply(_ snapshot: TaskListSnapshot) {
        let acknowledged = Set(snapshot.acknowledgedCommandIDs)
        let outboxChanged = !acknowledged.isEmpty && outbox.contains { acknowledged.contains($0.id) }
        if outboxChanged {
            outbox.removeAll { acknowledged.contains($0.id) }
            persistOutbox()
        }

        let isNewer = revision.map { snapshot.revision > $0 } ?? true
        if isNewer {
            projectCatalog = snapshot.projects
            if let data = try? JSONEncoder().encode(projectCatalog) {
                userDefaults.set(data, forKey: projectCatalogKey)
            }
            baseTasks = Self.ordered(snapshot.tasks)
            persistBaseTasks()
            revision = snapshot.revision
            userDefaults.set(NSNumber(value: snapshot.revision), forKey: revisionKey)
        }

        if isNewer || outboxChanged {
            refreshForCurrentDay()
        }
    }

    private func recordProcessedCommand(_ id: UUID) {
        processedCommandIDs.append(id)
        if processedCommandIDs.count > Self.maxBoundedSetSize {
            processedCommandIDs.removeFirst(processedCommandIDs.count - Self.maxBoundedSetSize)
        }
        persistProcessedCommandIDs()
    }

    private func recordTombstone(_ id: UUID) {
        tombstonedTaskIDs.append(id)
        if tombstonedTaskIDs.count > Self.maxBoundedSetSize {
            tombstonedTaskIDs.removeFirst(tombstonedTaskIDs.count - Self.maxBoundedSetSize)
        }
        persistTombstones()
    }

    private func persist() {
        content.save(savedTasks)
    }

    private func persistBaseTasks() {
        content.save(baseTasks)
    }

    private func persistOutbox() {
        guard let data = try? JSONEncoder().encode(outbox) else { return }
        userDefaults.set(data, forKey: outboxKey)
    }

    private func persistTombstones() {
        guard let data = try? JSONEncoder().encode(tombstonedTaskIDs) else { return }
        userDefaults.set(data, forKey: tombstonesKey)
    }

    private func persistProcessedCommandIDs() {
        guard let data = try? JSONEncoder().encode(processedCommandIDs) else { return }
        userDefaults.set(data, forKey: processedCommandIDsKey)
    }

    private static func ordered(_ tasks: [DailyTask]) -> [DailyTask] {
        tasks.sorted {
            if $0.isComplete != $1.isComplete {
                return !$0.isComplete
            }
            if $0.creationOrder == $1.creationOrder {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.creationOrder < $1.creationOrder
        }
    }
}
