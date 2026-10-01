import Combine
import Foundation

/// The rule that decides which days a habit is due. Only `everyDay` exists so far; the
/// enum is the seam where specific weekdays and weekly targets are added later.
enum HabitSchedule: Codable, Equatable, Sendable {
    case everyDay
}

struct Habit: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// Position in the manager's order; Today follows it. New habits go to the end.
    let creationOrder: Int64
    let schedule: HabitSchedule
    /// The habit's log: one entry per calendar day it was checked off. A missed day is the
    /// absence of an entry.
    let checkOffs: [TaskCompletionDay]

    init(
        id: UUID = UUID(),
        name: String,
        creationOrder: Int64,
        schedule: HabitSchedule = .everyDay,
        checkOffs: [TaskCompletionDay] = []
    ) {
        self.id = id
        self.name = name
        self.creationOrder = creationOrder
        self.schedule = schedule
        self.checkOffs = checkOffs
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, creationOrder, schedule, checkOffs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        creationOrder = try container.decode(Int64.self, forKey: .creationOrder)
        // Missing fields decode to defaults so later schema additions need no migration.
        schedule = try container.decodeIfPresent(HabitSchedule.self, forKey: .schedule) ?? .everyDay
        checkOffs = try container.decodeIfPresent([TaskCompletionDay].self, forKey: .checkOffs) ?? []
    }

    func withCheckOffs(_ checkOffs: [TaskCompletionDay]) -> Habit {
        Habit(id: id, name: name, creationOrder: creationOrder, schedule: schedule, checkOffs: checkOffs)
    }
}

/// A habit on Today's list, with whether it sits in the done group.
struct TodayHabit: Identifiable, Equatable, Sendable {
    let habit: Habit
    let isDone: Bool

    var id: UUID { habit.id }
}

@MainActor
protocol HabitListBehavior: AnyObject {
    /// Every habit, in manager order.
    var habits: [Habit] { get }
    /// Habits on Today's list: still to do first, then the done group; each keeps manager order.
    var todayHabits: [TodayHabit] { get }
    /// Habits on Today's list (the denominator of the "Habits done" summary).
    var todayCount: Int { get }
    /// Habits in the done group (the numerator of the "Habits done" summary).
    var doneCount: Int { get }
    @discardableResult func addHabit(name: String) -> Habit?
    /// Checks the habit off for Today, or removes Today's check-off.
    @discardableResult func toggleCheckOff(id: UUID) -> Habit?
}

@MainActor
final class HabitListStore: ObservableObject, HabitListBehavior {
    static let storageKey = "kyo.habits.v1"

    @Published private(set) var habits: [Habit] = []
    @Published private(set) var todayHabits: [TodayHabit] = []

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let now: () -> Date
    private let calendar: Calendar

    var todayCount: Int { todayHabits.count }
    var doneCount: Int { todayHabits.filter(\.isDone).count }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = HabitListStore.storageKey,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.now = now
        self.calendar = calendar

        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Habit].self, from: data) {
            habits = Self.ordered(decoded)
        }
        refreshForCurrentDay()
    }

    @discardableResult
    func addHabit(name: String) -> Habit? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let creationOrder = (habits.map(\.creationOrder).max() ?? -1) + 1
        let habit = Habit(name: trimmedName, creationOrder: creationOrder)
        habits = Self.ordered(habits + [habit])
        refreshForCurrentDay()
        persist()
        return habit
    }

    @discardableResult
    func toggleCheckOff(id: UUID) -> Habit? {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return nil }

        let today = TaskCompletionDay(date: now(), calendar: calendar)
        let habit = habits[index]
        let updated: Habit
        if habit.checkOffs.contains(today) {
            updated = habit.withCheckOffs(habit.checkOffs.filter { $0 != today })
        } else {
            updated = habit.withCheckOffs(habit.checkOffs + [today])
        }
        habits[index] = updated
        refreshForCurrentDay()
        persist()
        return updated
    }

    /// Re-evaluates Today's list against the clock. Check-offs are keyed to calendar days, so
    /// after midnight yesterday's check-offs no longer put a habit in the done group.
    func refreshForCurrentDay() {
        let today = TaskCompletionDay(date: now(), calendar: calendar)
        let entries = habits.map { TodayHabit(habit: $0, isDone: $0.checkOffs.contains(today)) }
        todayHabits = entries.filter { !$0.isDone } + entries.filter(\.isDone)
    }

    /// Refreshes now, then again at every local midnight until cancelled.
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

    private func persist() {
        guard let data = try? JSONEncoder().encode(habits) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private static func ordered(_ habits: [Habit]) -> [Habit] {
        habits.sorted {
            if $0.creationOrder == $1.creationOrder {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.creationOrder < $1.creationOrder
        }
    }
}
