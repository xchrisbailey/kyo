import Combine
import Foundation

struct DailyTask: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let creationOrder: Int64
    let isComplete: Bool

    init(id: UUID = UUID(), text: String, creationOrder: Int64, isComplete: Bool = false) {
        self.id = id
        self.text = text
        self.creationOrder = creationOrder
        self.isComplete = isComplete
    }
}

@MainActor
protocol TaskListBehavior: AnyObject {
    var tasks: [DailyTask] { get }
    var taskCount: Int { get }
    var incompleteCount: Int { get }
    @discardableResult func addTask(text: String) -> DailyTask?
}

@MainActor
final class TaskListStore: ObservableObject, TaskListBehavior {
    static let storageKey = "hoy.dailyTasks.v1"

    @Published private(set) var tasks: [DailyTask]

    private let userDefaults: UserDefaults
    private let storageKey: String

    var taskCount: Int { tasks.count }
    var incompleteCount: Int { tasks.filter { !$0.isComplete }.count }

    init(userDefaults: UserDefaults = .standard, storageKey: String = TaskListStore.storageKey) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey

        if let data = userDefaults.data(forKey: storageKey),
           let savedTasks = try? JSONDecoder().decode([DailyTask].self, from: data) {
            self.tasks = Self.ordered(savedTasks)
        } else {
            self.tasks = []
        }
    }

    @discardableResult
    func addTask(text: String) -> DailyTask? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let creationOrder = (tasks.map(\.creationOrder).max() ?? -1) + 1
        let task = DailyTask(text: trimmedText, creationOrder: creationOrder)
        tasks.append(task)
        tasks = Self.ordered(tasks)
        persist()
        return task
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private static func ordered(_ tasks: [DailyTask]) -> [DailyTask] {
        tasks.sorted {
            if $0.creationOrder == $1.creationOrder {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.creationOrder < $1.creationOrder
        }
    }
}
