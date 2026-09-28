import Combine
import Foundation

struct TaskCompletionDay: Codable, Equatable, Sendable {
    let era: Int?
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        self.era = components.era
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
    }
}

struct DailyTask: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let creationOrder: Int64
    let isComplete: Bool
    let completedOn: TaskCompletionDay?

    init(
        id: UUID = UUID(),
        text: String,
        creationOrder: Int64,
        isComplete: Bool = false,
        completedOn: TaskCompletionDay? = nil
    ) {
        self.id = id
        self.text = text
        self.creationOrder = creationOrder
        self.isComplete = isComplete
        self.completedOn = completedOn
    }
}

@MainActor
protocol TaskListBehavior: AnyObject {
    var tasks: [DailyTask] { get }
    var taskCount: Int { get }
    var completedCount: Int { get }
    var incompleteCount: Int { get }
    @discardableResult func addTask(text: String) -> DailyTask?
    @discardableResult func editTask(id: UUID, text: String) -> DailyTask?
    @discardableResult func deleteTask(id: UUID) -> DailyTask?
    @discardableResult func toggleTask(id: UUID) -> DailyTask?
}

@MainActor
final class TaskListStore: ObservableObject, TaskListBehavior {
    static let storageKey = "hoy.dailyTasks.v1"

    @Published private(set) var tasks: [DailyTask] = []
    @Published private(set) var currentDate: Date

    private var savedTasks: [DailyTask]
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let now: () -> Date
    private let calendar: Calendar
    private let sync: TaskListSync?
    private let revisionKey: String
    private var revision: Int64?

    var taskCount: Int { tasks.count }
    var completedCount: Int { tasks.filter(\.isComplete).count }
    var incompleteCount: Int { taskCount - completedCount }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = TaskListStore.storageKey,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        sync: TaskListSync? = nil
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.now = now
        self.calendar = calendar
        self.sync = sync
        self.revisionKey = storageKey + ".revision"
        self.currentDate = calendar.startOfDay(for: now())

        if let data = userDefaults.data(forKey: storageKey),
           let savedTasks = try? JSONDecoder().decode([DailyTask].self, from: data) {
            self.savedTasks = Self.ordered(savedTasks)
        } else {
            self.savedTasks = []
        }
        if sync != nil {
            self.revision = (userDefaults.object(forKey: revisionKey) as? NSNumber)?.int64Value
        } else {
            self.revision = nil
        }
        refreshForCurrentDay()

        switch sync {
        case .publish(let transport):
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
            transport.publish(TaskListSnapshot(revision: revision ?? 0, tasks: tasks))
        case .mirror(let transport):
            // Registered last: the transport may call the handler synchronously,
            // and everything it touches (savedTasks, revision, tasks) must already exist.
            transport.setSnapshotHandler { [weak self] snapshot in
                self?.apply(snapshot)
            }
        case nil:
            break
        }
    }

    @discardableResult
    func addTask(text: String) -> DailyTask? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let creationOrder = (savedTasks.map(\.creationOrder).max() ?? -1) + 1
        let task = DailyTask(text: trimmedText, creationOrder: creationOrder)
        savedTasks.append(task)
        refreshForCurrentDay()
        persist()
        publishChange()
        return task
    }

    @discardableResult
    func editTask(id: UUID, text: String) -> DailyTask? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let index = savedTasks.firstIndex(where: { $0.id == id }) else { return nil }

        let task = savedTasks[index]
        let updatedTask = DailyTask(
            id: task.id,
            text: trimmedText,
            creationOrder: task.creationOrder,
            isComplete: task.isComplete,
            completedOn: task.completedOn
        )
        savedTasks[index] = updatedTask
        refreshForCurrentDay()
        persist()
        publishChange()
        return updatedTask
    }

    @discardableResult
    func deleteTask(id: UUID) -> DailyTask? {
        guard let index = savedTasks.firstIndex(where: { $0.id == id }) else { return nil }
        let removedTask = savedTasks.remove(at: index)
        refreshForCurrentDay()
        persist()
        publishChange()
        return removedTask
    }

    @discardableResult
    func toggleTask(id: UUID) -> DailyTask? {
        guard let index = savedTasks.firstIndex(where: { $0.id == id }) else { return nil }

        let task = savedTasks[index]
        let updatedTask = DailyTask(
            id: task.id,
            text: task.text,
            creationOrder: task.creationOrder,
            isComplete: !task.isComplete,
            completedOn: task.isComplete ? nil : TaskCompletionDay(date: now(), calendar: calendar)
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
        tasks = Self.ordered(savedTasks.filter { task in
            !task.isComplete || task.completedOn == day
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

    /// Publishes the current task list to the counterpart device if this store is the
    /// publishing (phone) side of a sync pair. Does nothing for `.mirror` or no sync role.
    /// Bumps the revision with a hybrid clock: strictly increasing even across restarts and
    /// reinstalls, since it is floored by the device's wall clock in milliseconds.
    private func publishChange() {
        guard case .publish(let transport) = sync else { return }
        let candidate = max((revision ?? 0) + 1, Int64(now().timeIntervalSince1970 * 1000))
        revision = candidate
        userDefaults.set(NSNumber(value: candidate), forKey: revisionKey)
        transport.publish(TaskListSnapshot(revision: candidate, tasks: tasks))
    }

    /// Applies an incoming snapshot from the publishing (phone) side, per the reconciliation
    /// rule in docs/adr/0001-phone-authoritative-task-snapshots.md: a snapshot is applied only
    /// if its revision is strictly greater than the last one applied, or none has been applied
    /// yet. Applying replaces the stored task list outright; older or repeated snapshots are
    /// ignored, so redelivery and out-of-order delivery cannot duplicate or resurrect tasks.
    private func apply(_ snapshot: TaskListSnapshot) {
        if let revision, snapshot.revision <= revision { return }
        savedTasks = Self.ordered(snapshot.tasks)
        persist()
        revision = snapshot.revision
        userDefaults.set(NSNumber(value: snapshot.revision), forKey: revisionKey)
        refreshForCurrentDay()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedTasks) else { return }
        userDefaults.set(data, forKey: storageKey)
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
