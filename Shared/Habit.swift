import Combine
import Foundation

/// The rule that decides which days a habit is due.
enum HabitSchedule: Codable, Equatable, Sendable {
    case everyDay
    /// Due only on these days, as `Calendar` weekday numbers (1 = Sunday). At least one.
    case weekdays(Set<Int>)
    /// Due every day until checked off on this many days (1...6) in the calendar week.
    case weeklyTarget(Int)

    static let weeklyTargetRange = 1...6

    /// Whether the schedule can be saved: weekdays need at least one valid day and a weekly
    /// target must be within `weeklyTargetRange`.
    var isValid: Bool {
        switch self {
        case .everyDay: true
        case .weekdays(let days): !days.isEmpty && days.allSatisfy { (1...7).contains($0) }
        case .weeklyTarget(let target): Self.weeklyTargetRange.contains(target)
        }
    }

    /// Weekday numbers in the calendar's week order, starting at its `firstWeekday`.
    static func weekdaysInWeekOrder(calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

/// A weekly-target habit's check-offs so far this calendar week against its target.
struct HabitWeekProgress: Equatable, Sendable {
    /// Days checked off this week; at most one per day, and it can exceed `target`.
    let count: Int
    let target: Int

    var isTargetMet: Bool { count >= target }
}

struct Habit: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// Position in the manager's order; Today follows it. New habits go to the end.
    let order: Int64
    let schedule: HabitSchedule
    /// The habit's log: one entry per calendar day it was checked off. A missed day is the
    /// absence of an entry.
    let checkOffs: [TaskCompletionDay]

    init(
        id: UUID = UUID(),
        name: String,
        order: Int64,
        schedule: HabitSchedule = .everyDay,
        checkOffs: [TaskCompletionDay] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.schedule = schedule
        self.checkOffs = checkOffs
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, order, schedule, checkOffs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decode(Int64.self, forKey: .order)
        // Missing fields decode to defaults so later schema additions need no migration.
        schedule = try container.decodeIfPresent(HabitSchedule.self, forKey: .schedule) ?? .everyDay
        checkOffs = try container.decodeIfPresent([TaskCompletionDay].self, forKey: .checkOffs) ?? []
    }

    func withCheckOffs(_ checkOffs: [TaskCompletionDay]) -> Habit {
        Habit(id: id, name: name, order: order, schedule: schedule, checkOffs: checkOffs)
    }

    /// Whether the schedule makes the habit due on `date`. Weekly-target habits are due every day.
    func isDue(on date: Date, calendar: Calendar) -> Bool {
        switch schedule {
        case .everyDay, .weeklyTarget: true
        case .weekdays(let days): days.contains(calendar.component(.weekday, from: date))
        }
    }

    /// Week progress for the calendar week containing `date` (the week starts on the calendar's
    /// `firstWeekday`). `nil` unless the habit has a weekly target. The target is never prorated.
    func weekProgress(on date: Date, calendar: Calendar) -> HabitWeekProgress? {
        guard case .weeklyTarget(let target) = schedule,
              let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        let days = Set(checkOffs.compactMap { checkOff -> Date? in
            let components = DateComponents(
                era: checkOff.era, year: checkOff.year, month: checkOff.month, day: checkOff.day
            )
            return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
        })
        return HabitWeekProgress(count: days.filter { week.contains($0) }.count, target: target)
    }
}

/// A habit on Today's list, with whether it sits in the done group.
struct TodayHabit: Identifiable, Equatable, Sendable {
    let habit: Habit
    /// Whether the habit is in the done group: checked off today, or a weekly-target habit
    /// whose target is already met this week.
    let isDone: Bool
    /// Whether Today has a check-off. A habit can be done without it (target met earlier in
    /// the week); its circle then stays empty and tapping adds Today's check-off.
    let isCheckedOffToday: Bool
    /// This week's progress; `nil` unless the habit has a weekly target.
    let weekProgress: HabitWeekProgress?

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
    /// Adds a habit at the end of the manager's order. Returns `nil` for a blank name or an
    /// invalid schedule (no weekdays, or a weekly target outside 1...6).
    @discardableResult func addHabit(name: String, schedule: HabitSchedule) -> Habit?
    /// Checks the habit off for Today, or removes Today's check-off. Only habits on Today's
    /// list can be toggled.
    @discardableResult func toggleCheckOff(id: UUID) -> Habit?
}

extension HabitListBehavior {
    @discardableResult func addHabit(name: String) -> Habit? {
        addHabit(name: name, schedule: .everyDay)
    }
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
    func addHabit(name: String, schedule: HabitSchedule) -> Habit? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, schedule.isValid else { return nil }

        let order = (habits.map(\.order).max() ?? -1) + 1
        let habit = Habit(name: trimmedName, order: order, schedule: schedule)
        habits = Self.ordered(habits + [habit])
        refreshForCurrentDay()
        persist()
        return habit
    }

    @discardableResult
    func toggleCheckOff(id: UUID) -> Habit? {
        guard let index = habits.firstIndex(where: { $0.id == id }),
              habits[index].isDue(on: now(), calendar: calendar) else { return nil }

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
        let date = now()
        let entries = habits.filter { $0.isDue(on: date, calendar: calendar) }.map { habit -> TodayHabit in
            let isCheckedOffToday = habit.checkOffs.contains(today)
            let progress = habit.weekProgress(on: date, calendar: calendar)
            return TodayHabit(
                habit: habit,
                isDone: isCheckedOffToday || progress?.isTargetMet == true,
                isCheckedOffToday: isCheckedOffToday,
                weekProgress: progress
            )
        }
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
            if $0.order == $1.order {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.order < $1.order
        }
    }
}
