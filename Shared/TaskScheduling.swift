import Combine
import Foundation

/// A scheduling draft: preview and correction never change a saved task. Every entry point
/// confirms through this workflow, including a fresh clock check when a picker spans midnight.
@MainActor
final class TaskSchedulingWorkflow: ObservableObject {
    @Published var proposedDate: Date
    @Published private(set) var message: String?
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

    func chooseToday() {
        proposedDate = today
        message = nil
    }

    @discardableResult
    func confirm(_ save: (Date) -> Bool) -> Bool {
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
