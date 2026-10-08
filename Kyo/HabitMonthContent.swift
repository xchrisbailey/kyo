import Combine
import Foundation

/// Month's habits: the habit slot's mark, its spoken phrase, and the habit rows of the Day summary,
/// worked out from the habit list's log and the schedule each habit had on each day.
@MainActor
final class HabitMonthContent: MonthContentSource {
    let kind = MonthKind.habits
    let changes: AnyPublisher<Void, Never>

    private let calendar: Calendar
    /// The habits as of the last change, since the list publishes before it has stored them.
    private var habits: [Habit]
    private var subscriptions = Set<AnyCancellable>()

    init(habits list: HabitListStore, calendar: Calendar = .current) {
        self.calendar = calendar
        self.habits = list.habits
        let subject = PassthroughSubject<Void, Never>()
        self.changes = subject.eraseToAnyPublisher()
        list.$habits
            .dropFirst()
            .sink { [weak self] habits in
                self?.habits = habits
                subject.send()
            }
            .store(in: &subscriptions)
    }

    func content(on days: [Date]) -> [Date: MonthKindDay] {
        var result: [Date: MonthKindDay] = [:]
        for day in days {
            let checkOffDay = TaskCompletionDay(date: day, calendar: calendar)
            // A habit has a row when it was due or was checked off, and a check-off counts wherever it falls.
            let entries = habits.compactMap { habit -> (habit: Habit, isDue: Bool, isChecked: Bool)? in
                let isDue = habit.countedAsDue(on: day, calendar: calendar)
                let isChecked = habit.checkOffs.contains(checkOffDay)
                return isDue || isChecked ? (habit, isDue, isChecked) : nil
            }
            guard !entries.isEmpty else { continue }
            let rows = entries.map { MonthSummaryRow(id: "habit-\($0.habit.id)", text: $0.habit.name, isChecked: $0.isChecked) }
            if entries.contains(where: \.isChecked) {
                let isComplete = entries.allSatisfy { $0.isChecked || !$0.isDue }
                result[day] = MonthKindDay(
                    mark: isComplete ? .filled : .hollow,
                    phrase: isComplete ? "all habits done" : "some habits done",
                    rows: rows
                )
            } else {
                result[day] = MonthKindDay(rows: rows)
            }
        }
        return result
    }
}
