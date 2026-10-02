import Foundation
import SwiftData

/// The one-time move of the phone's tasks and habits from their UserDefaults content keys into
/// SwiftData (see docs/specs/swiftdata-storage.md). It runs on the first launch after the move,
/// before the list stores are created, and is invisible to the user.
///
/// The import only reads. The content keys stay as a frozen backup, and the Watch-link records
/// (`.revision`, `.tombstones`, `.processedCommands`, `.outbox`) are never touched, so a
/// `.publish` store built afterwards carries on from the same revision. Everything is inserted in
/// a single save and the done flag is set only after that save succeeds, so a failure rolls back
/// and the next launch retries. Items whose id is already stored are skipped, so a retry (or a
/// crash between the save and the flag) never duplicates.
@MainActor
struct UserDefaultsImport {
    /// Set once an import has succeeded. Never removed by the app.
    static let doneKey = "kyo.swiftDataImport.v1.done"

    enum Outcome: Equatable {
        /// The flag was already set; nothing was read or written.
        case alreadyDone
        /// Everything found was stored (a missing or undecodable key counts as nothing found)
        /// and the flag is now set.
        case imported
        /// The save failed and was rolled back. The flag is unset, so the next launch retries.
        case failed
    }

    let userDefaults: UserDefaults
    let modelContainer: ModelContainer
    let taskKey: String
    let habitKey: String
    let doneKey: String
    private let save: (ModelContext) throws -> Void

    /// `save` is the single save of the whole import; tests replace it to force a failure.
    init(
        userDefaults: UserDefaults = .standard,
        modelContainer: ModelContainer,
        taskKey: String = TaskListStore.storageKey,
        habitKey: String = HabitListStore.storageKey,
        doneKey: String = UserDefaultsImport.doneKey,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.userDefaults = userDefaults
        self.modelContainer = modelContainer
        self.taskKey = taskKey
        self.habitKey = habitKey
        self.doneKey = doneKey
        self.save = save
    }

    /// Imports if the flag is absent. Never throws: a failed import is reported as `.failed`.
    @discardableResult
    func run() -> Outcome {
        guard !userDefaults.bool(forKey: doneKey) else { return .alreadyDone }
        let context = modelContainer.mainContext

        var storedTaskIDs = Set(((try? context.fetch(FetchDescriptor<TaskRecord>())) ?? []).map(\.id))
        for task in decode([DailyTask].self, forKey: taskKey) where storedTaskIDs.insert(task.id).inserted {
            SwiftDataTaskContent.insert(task, into: context)
        }
        var storedHabitIDs = Set(((try? context.fetch(FetchDescriptor<HabitRecord>())) ?? []).map(\.id))
        for habit in decode([Habit].self, forKey: habitKey) where storedHabitIDs.insert(habit.id).inserted {
            SwiftDataHabitContent.insert(habit, into: context)
        }

        do {
            try save(context)
        } catch {
            context.rollback()
            return .failed
        }
        userDefaults.set(true, forKey: doneKey)
        return .imported
    }

    /// The values under `key`, or none if the key is missing or can't be decoded, the same as
    /// the stores did before SwiftData.
    private func decode<Value: Decodable>(_ type: [Value].Type, forKey key: String) -> [Value] {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(type, from: data) else { return [] }
        return decoded
    }
}
