import Combine
import Foundation

struct TaskCompletionDay: Codable, Equatable {
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

struct DailyTask: Identifiable, Codable, Equatable {
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

    var taskCount: Int { tasks.count }
    var completedCount: Int { tasks.filter(\.isComplete).count }
    var incompleteCount: Int { taskCount - completedCount }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = TaskListStore.storageKey,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.now = now
        self.calendar = calendar
        self.currentDate = calendar.startOfDay(for: now())

        if let data = userDefaults.data(forKey: storageKey),
           let savedTasks = try? JSONDecoder().decode([DailyTask].self, from: data) {
            self.savedTasks = Self.ordered(savedTasks)
        } else {
            self.savedTasks = []
        }
        refreshForCurrentDay()
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
        return updatedTask
    }

    @discardableResult
    func deleteTask(id: UUID) -> DailyTask? {
        guard let index = savedTasks.firstIndex(where: { $0.id == id }) else { return nil }
        let removedTask = savedTasks.remove(at: index)
        refreshForCurrentDay()
        persist()
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
