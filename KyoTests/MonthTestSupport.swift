import Combine
import Foundation

/// The setup every Month behavior test shares: a fixed UTC Gregorian calendar and locale, and a
/// clock fixed at a chosen moment. The task, habit, memo and Schedule tickets add their real stores and the
/// fake calendar service here as each one wires its kind into Month.
@MainActor
final class MonthHarness {
    let calendar: Calendar
    let locale = Locale(identifier: "en_US")
    private(set) var now: Date

    /// A harness whose clock starts at the given moment, noon unless said otherwise.
    init(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, firstWeekday: Int = 1) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
        self.calendar = calendar
        self.now = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Noon on the given day, so tests never sit on a day boundary.
    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Moves the clock to `moment`, as the passing of time does.
    func setNow(_ moment: Date) { now = moment }

    func makeModel(
        sources: [any MonthContentSource] = [],
        sleep: @escaping MonthModel.Sleep = { seconds in try await Task.sleep(for: .seconds(seconds)) }
    ) -> MonthModel {
        MonthModel(now: { self.now }, calendar: calendar, locale: locale, sources: sources, sleep: sleep)
    }
}

/// Stands in for `Task.sleep`: records each requested duration and waits until the test wakes it.
@MainActor
final class MonthSleepRecorder {
    private(set) var durations: [TimeInterval] = []
    private let wakeStream: AsyncStream<Void>
    private let wakeContinuation: AsyncStream<Void>.Continuation

    init() {
        (wakeStream, wakeContinuation) = AsyncStream.makeStream()
    }

    func sleep(_ seconds: TimeInterval) async throws {
        durations.append(seconds)
        for await _ in wakeStream { return }
        throw CancellationError()
    }

    func wake() { wakeContinuation.yield() }
}

/// Stands in for one kind's real content, which later tickets supply from the stores. Tests set
/// what it holds on each day and say when it changes.
@MainActor
final class StandInMonthContent: MonthContentSource {
    let kind: MonthKind
    var content: [Date: MonthKindDay] = [:] {
        didSet { changeSubject.send() }
    }
    /// Every set of days the model asked about.
    private(set) var requests: [[Date]] = []
    private let changeSubject = PassthroughSubject<Void, Never>()

    init(_ kind: MonthKind) { self.kind = kind }

    var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    func content(on days: [Date]) -> [Date: MonthKindDay] {
        requests.append(days)
        return content.filter { days.contains($0.key) }
    }
}
