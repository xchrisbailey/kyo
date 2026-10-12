import Combine
import Foundation

/// Calendar intent resolved against local Today. Weekdays use Calendar's 1...7 numbering;
/// nextWeekday selects that weekday in the following calendar week, rather than its next occurrence.
enum TaskSchedulingIntent: Equatable, Sendable {
    case weekday(Int)
    case nextWeekday(Int)
    case days(Int)
    case weeks(Int)
    case months(Int)
    case date(year: Int, month: Int, day: Int)
}

/// A scheduling draft: preview and correction never change a saved task. Every entry point
/// confirms through this workflow, including a fresh clock check when a picker spans midnight.
@MainActor
final class TaskSchedulingWorkflow: ObservableObject {
    @Published var proposedDate: Date {
        didSet {
            hasValidChoice = true
            message = nil
        }
    }
    @Published private(set) var message: String?
    private var hasValidChoice = true
    private let now: () -> Date
    private let calendarProvider: () -> Calendar
    var calendar: Calendar { calendarProvider() }

    init(date: Date? = nil, now: @escaping () -> Date = Date.init,
         calendar: Calendar = .autoupdatingCurrent, calendarProvider: (() -> Calendar)? = nil) {
        self.now = now
        self.calendarProvider = calendarProvider ?? { calendar }
        proposedDate = (calendarProvider?() ?? calendar).startOfDay(for: date ?? now())
    }

    var today: Date { calendar.startOfDay(for: now()) }
    var preview: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        return formatter.string(from: proposedDate)
    }

    @discardableResult
    func choose(_ intent: TaskSchedulingIntent) -> Bool {
        guard let date = resolve(intent) else {
            hasValidChoice = false
            message = "Choose another planned day. This date is not valid."
            return false
        }
        proposedDate = calendar.startOfDay(for: date)
        return true
    }

    private func resolve(_ intent: TaskSchedulingIntent) -> Date? {
        let calendar = calendar
        let today = today
        switch intent {
        case .weekday(let weekday):
            guard (1...7).contains(weekday) else { return nil }
            let offset = (weekday - calendar.component(.weekday, from: today) + 7) % 7
            return calendar.date(byAdding: .day, value: offset, to: today)
        case .nextWeekday(let weekday):
            guard (1...7).contains(weekday) else { return nil }
            let elapsed = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
            let offset = (weekday - calendar.firstWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: 7 - elapsed + offset, to: today)
        case .days(let amount):
            return calendar.date(byAdding: .day, value: amount, to: today)
        case .weeks(let amount):
            let days = amount.multipliedReportingOverflow(by: 7)
            guard !days.overflow else { return nil }
            return calendar.date(byAdding: .day, value: days.partialValue, to: today)
        case .months(let amount):
            guard let start = calendar.dateInterval(of: .month, for: today)?.start,
                  let month = calendar.date(byAdding: .month, value: amount, to: start),
                  let days = calendar.range(of: .day, in: .month, for: month) else { return nil }
            return calendar.date(byAdding: .day,
                                 value: min(calendar.component(.day, from: today), days.count) - 1,
                                 to: month)
        case .date(let year, let month, let day):
            guard year > 0, month > 0, day > 0,
                  let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard components.year == year, components.month == month, components.day == day else { return nil }
            return date
        }
    }

    func chooseToday() {
        proposedDate = today
        message = nil
    }

    @discardableResult
    func confirm(_ save: (Date) -> Bool) -> Bool {
        guard hasValidChoice else { return false }
        let date = calendar.startOfDay(for: proposedDate)
        guard date >= today else {
            message = "Choose Today or another date. This day has passed."
            return false
        }
        guard save(date) else {
            message = "This task can no longer be scheduled."
            return false
        }
        message = nil
        return true
    }
}
