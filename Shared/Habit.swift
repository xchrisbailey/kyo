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

extension HabitSchedule {
    /// A short description for lists: "Every day", "Mon Wed Fri" (weekdays in the calendar's
    /// week order, short symbols) or "3× a week".
    func summary(calendar: Calendar) -> String {
        switch self {
        case .everyDay:
            return "Every day"
        case .weekdays(let days):
            return Self.weekdaysInWeekOrder(calendar: calendar)
                .filter(days.contains)
                .map { calendar.shortWeekdaySymbols[$0 - 1] }
                .joined(separator: " ")
        case .weeklyTarget(let target):
            return "\(target)× a week"
        }
    }

    /// Whether the schedule counts days or weeks. A streak carries across edits within a unit
    /// and restarts when the unit changes.
    var isWeekly: Bool {
        if case .weeklyTarget = self { true } else { false }
    }
}

/// A schedule and the calendar day it took effect. Every day from then until the next entry
/// is judged by it.
struct HabitScheduleEntry: Codable, Equatable, Sendable {
    let schedule: HabitSchedule
    let from: TaskCompletionDay
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
    /// Every schedule the habit has had, oldest first, each with the day it took effect. Never
    /// empty; the first entry starts at the creation day. An edit appends an entry for Today
    /// (or replaces Today's entry), so past days keep the schedule they had.
    let scheduleHistory: [HabitScheduleEntry]
    /// The habit's log: one entry per calendar day it was checked off. A missed day is the
    /// absence of an entry.
    let checkOffs: [TaskCompletionDay]
    /// The calendar day the habit was added. `nil` only for habits saved before it was recorded;
    /// the store fills it in on load (earliest check-off, else that day).
    let createdOn: TaskCompletionDay?

    /// The schedule in effect now: the latest entry.
    var schedule: HabitSchedule { scheduleHistory[scheduleHistory.count - 1].schedule }

    /// Stands in for the creation day of a habit saved before it was recorded, until the store
    /// backfills it.
    private static let unknownStart = TaskCompletionDay(era: 1, year: 1, month: 1, day: 1)

    /// With no `scheduleHistory`, the habit starts with `schedule` from its creation day.
    init(
        id: UUID = UUID(),
        name: String,
        order: Int64,
        schedule: HabitSchedule = .everyDay,
        checkOffs: [TaskCompletionDay] = [],
        createdOn: TaskCompletionDay? = nil,
        scheduleHistory: [HabitScheduleEntry]? = nil
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.scheduleHistory = scheduleHistory?.isEmpty == false
            ? scheduleHistory!
            : [HabitScheduleEntry(schedule: schedule, from: createdOn ?? Self.unknownStart)]
        self.checkOffs = checkOffs
        self.createdOn = createdOn
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, order, schedule, scheduleHistory, checkOffs, createdOn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdOn = try container.decodeIfPresent(TaskCompletionDay.self, forKey: .createdOn)
        let history = try container.decodeIfPresent([HabitScheduleEntry].self, forKey: .scheduleHistory)
        // Habits saved before schedule history have one schedule: it starts at the creation day.
        let schedule = try container.decodeIfPresent(HabitSchedule.self, forKey: .schedule) ?? .everyDay
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            order: try container.decode(Int64.self, forKey: .order),
            schedule: schedule,
            // Missing fields decode to defaults so later schema additions need no migration.
            checkOffs: try container.decodeIfPresent([TaskCompletionDay].self, forKey: .checkOffs) ?? [],
            createdOn: createdOn,
            scheduleHistory: history
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(order, forKey: .order)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(scheduleHistory, forKey: .scheduleHistory)
        try container.encode(checkOffs, forKey: .checkOffs)
        try container.encodeIfPresent(createdOn, forKey: .createdOn)
    }

    func withCheckOffs(_ checkOffs: [TaskCompletionDay]) -> Habit {
        Habit(id: id, name: name, order: order, checkOffs: checkOffs, createdOn: createdOn, scheduleHistory: scheduleHistory)
    }

    /// A single-entry history starts at the creation day, so it moves with it.
    func withCreatedOn(_ createdOn: TaskCompletionDay) -> Habit {
        let history = scheduleHistory.count == 1
            ? [HabitScheduleEntry(schedule: schedule, from: createdOn)] : scheduleHistory
        return Habit(id: id, name: name, order: order, checkOffs: checkOffs, createdOn: createdOn, scheduleHistory: history)
    }

    func withOrder(_ order: Int64) -> Habit {
        Habit(id: id, name: name, order: order, checkOffs: checkOffs, createdOn: createdOn, scheduleHistory: scheduleHistory)
    }

    /// The habit with `day` in its log (if `isCheckedOff`) or removed from it, never twice.
    func settingCheckOff(on day: TaskCompletionDay, to isCheckedOff: Bool) -> Habit {
        let others = checkOffs.filter { $0 != day }
        return withCheckOffs(isCheckedOff ? others + [day] : others)
    }

    func withName(_ name: String) -> Habit {
        Habit(id: id, name: name, order: order, checkOffs: checkOffs, createdOn: createdOn, scheduleHistory: scheduleHistory)
    }

    /// The habit with `schedule` in effect from `day`: replaces the entry for `day` if there is
    /// one, else appends. Unchanged if `schedule` is already the current one.
    func withSchedule(_ schedule: HabitSchedule, from day: TaskCompletionDay) -> Habit {
        guard schedule != self.schedule else { return self }
        var history = scheduleHistory
        if history.last?.from == day {
            history[history.count - 1] = HabitScheduleEntry(schedule: schedule, from: day)
        } else {
            history.append(HabitScheduleEntry(schedule: schedule, from: day))
        }
        return Habit(id: id, name: name, order: order, checkOffs: checkOffs, createdOn: createdOn, scheduleHistory: history)
    }

    /// The creation day for habits saved before it was recorded: the earliest check-off, else
    /// `fallback`.
    func resolvedCreatedOn(fallback: TaskCompletionDay) -> TaskCompletionDay {
        createdOn ?? checkOffs.min(by: { Self.isEarlier($0, $1) }) ?? fallback
    }

    private static func isEarlier(_ a: TaskCompletionDay, _ b: TaskCompletionDay) -> Bool {
        (a.era ?? 1, a.year, a.month, a.day) < (b.era ?? 1, b.year, b.month, b.day)
    }

    /// The schedule in effect on `date`: the latest entry that took effect on or before that
    /// day (the first entry for days before it).
    func schedule(on date: Date, calendar: Calendar) -> HabitSchedule {
        let day = TaskCompletionDay(date: date, calendar: calendar)
        return (scheduleHistory.last { !Self.isEarlier(day, $0.from) } ?? scheduleHistory[0]).schedule
    }

    /// Whether the schedule makes the habit due on `date`. Weekly-target habits are due every day.
    func isDue(on date: Date, calendar: Calendar) -> Bool {
        switch schedule(on: date, calendar: calendar) {
        case .everyDay, .weeklyTarget: true
        case .weekdays(let days): days.contains(calendar.component(.weekday, from: date))
        }
    }

    /// The target that judges the calendar week containing `date`: the one in effect on the
    /// week's last day (for the current week, the one in effect Today). `nil` if that
    /// schedule isn't a weekly target.
    private func weeklyTarget(inWeek week: DateInterval, calendar: Calendar) -> Int? {
        guard let lastDay = calendar.date(byAdding: .day, value: -1, to: week.end),
              case .weeklyTarget(let target) = schedule(on: lastDay, calendar: calendar) else { return nil }
        return target
    }

    /// The distinct calendar days with a check-off, as start-of-day dates.
    private func checkOffDays(calendar: Calendar) -> Set<Date> {
        Set(checkOffs.compactMap { checkOff -> Date? in
            let components = DateComponents(
                era: checkOff.era, year: checkOff.year, month: checkOff.month, day: checkOff.day
            )
            return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
        })
    }

    /// Week progress for the calendar week containing `date` (the week starts on the calendar's
    /// `firstWeekday`). `nil` unless the habit has a weekly target. The target is never prorated.
    func weekProgress(on date: Date, calendar: Calendar) -> HabitWeekProgress? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date),
              let target = weeklyTarget(inWeek: week, calendar: calendar) else { return nil }
        return HabitWeekProgress(count: checkOffDays(calendar: calendar).filter { week.contains($0) }.count, target: target)
    }

    /// The day the current streak unit began: the creation day, or the day of the latest edit
    /// between day-based and weekly-target schedules. A streak can't reach back before it.
    private func streakFloor(created: Date, calendar: Calendar) -> Date {
        var floor = created
        var index = scheduleHistory.count - 1
        while index > 0, scheduleHistory[index - 1].schedule.isWeekly == scheduleHistory[index].schedule.isWeekly {
            index -= 1
        }
        if index > 0 {
            let from = scheduleHistory[index].from
            let day = calendar.date(from: DateComponents(era: from.era, year: from.year, month: from.month, day: from.day))
            if let day { floor = max(floor, calendar.startOfDay(for: day)) }
        }
        return floor
    }

    /// The habit's streak as of `date` (Today): consecutive due days with a check-off for
    /// day-based habits, consecutive calendar weeks with the target met for weekly-target
    /// habits. Each day is judged by the schedule in effect that day, and each week by the
    /// target in effect at its end. Days that aren't due never break it and a check-off on one
    /// doesn't count; an unchecked Today or an in-progress week never breaks it either, and
    /// adds one once checked off or the target is met. It stops at the creation day, or at the
    /// day of the latest switch between day-based and weekly-target schedules (a weekly habit's
    /// first partial week counts only if met). Cost is linear in the log plus the streak's
    /// length.
    func streak(on date: Date, calendar: Calendar) -> Int {
        streakRun(on: date, calendar: calendar).length
    }

    /// The streak's length and the start of its oldest counted unit (the day, or the week's
    /// first day); `nil` when the streak is 0. Log entries before that start can't change the
    /// streak: the unit just before it was missed, or the streak had reached its floor.
    private func streakRun(on date: Date, calendar: Calendar) -> (length: Int, start: Date?) {
        let today = calendar.startOfDay(for: date)
        let creation = resolvedCreatedOn(fallback: TaskCompletionDay(date: date, calendar: calendar))
        let created = calendar.date(from: DateComponents(
            era: creation.era, year: creation.year, month: creation.month, day: creation.day
        )).map { calendar.startOfDay(for: $0) } ?? today
        let floor = streakFloor(created: created, calendar: calendar)
        let checked = checkOffDays(calendar: calendar)

        if !schedule(on: date, calendar: calendar).isWeekly {
            var streak = 0
            var start: Date?
            var day = today
            while day >= floor {
                if isDue(on: day, calendar: calendar) {
                    if checked.contains(day) {
                        streak += 1
                        start = day
                    } else if day != today {
                        break
                    }
                }
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = previous
            }
            return (streak, start)
        } else {
            var perWeek: [Date: Int] = [:]
            for day in checked {
                guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else { continue }
                perWeek[week.start, default: 0] += 1
            }
            guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today),
                  let firstWeek = calendar.dateInterval(of: .weekOfYear, for: floor) else { return (0, nil) }
            var streak = 0
            var start: Date?
            var week = currentWeek
            while week.start >= firstWeek.start {
                let isMet = weeklyTarget(inWeek: week, calendar: calendar).map { perWeek[week.start, default: 0] >= $0 } ?? false
                if isMet {
                    streak += 1
                    start = week.start
                } else if week.start != currentWeek.start && week.start != firstWeek.start {
                    break
                }
                guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start),
                      let previousWeek = calendar.dateInterval(of: .weekOfYear, for: previous) else { break }
                week = previousWeek
            }
            return (streak, start)
        }
    }

    /// The habit with its log cut to what `date` (Today) needs: the current streak and, for
    /// weekly targets, this week's progress. Check-offs before the streak's oldest counted unit
    /// and before the current week are dropped; streak, week progress and Today's check-off are
    /// unchanged, and stay right on later days until a new snapshot arrives. Falls back to the
    /// full log if the cut would ever change the streak or week progress.
    func trimmedLog(on date: Date, calendar: Calendar) -> Habit {
        let run = streakRun(on: date, calendar: calendar)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let cutoff = min(run.start ?? weekStart, weekStart)
        let kept = checkOffs.filter { checkOff in
            let components = DateComponents(era: checkOff.era, year: checkOff.year, month: checkOff.month, day: checkOff.day)
            guard let day = calendar.date(from: components) else { return true }
            return calendar.startOfDay(for: day) >= cutoff
        }
        let trimmed = withCheckOffs(kept)
        guard trimmed.streak(on: date, calendar: calendar) == run.length,
              trimmed.weekProgress(on: date, calendar: calendar) == weekProgress(on: date, calendar: calendar)
        else { return self }
        return trimmed
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
    /// The habit's streak: days for day-based habits, weeks for weekly-target habits.
    let streak: Int

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
    /// Renames the habit and/or replaces its schedule, from Today on (past days keep the schedule
    /// they had). Log, order and creation day are kept. Returns `nil` for an unknown habit, a
    /// blank name or an invalid schedule, with the same validation as `addHabit`.
    @discardableResult func editHabit(id: UUID, name: String, schedule: HabitSchedule) -> Habit?
    /// Permanently removes the habit and its log. Returns the removed habit, or `nil` if unknown.
    @discardableResult func deleteHabit(id: UUID) -> Habit?
    /// Checks the habit off for Today, or removes Today's check-off. Only habits on Today's
    /// list can be toggled. On the Watch the change shows immediately and reaches the phone as
    /// a set check-off command.
    @discardableResult func toggleCheckOff(id: UUID) -> Habit?
    /// Reorders the manager's list with the same offset semantics as SwiftUI's `onMove`: the
    /// habits at `source` end up before the habit that was at `destination`. Rewrites every
    /// habit's `order` and saves; Today follows. Out-of-range offsets are ignored.
    func moveHabits(fromOffsets source: IndexSet, toOffset destination: Int)
}

extension HabitListBehavior {
    @discardableResult func addHabit(name: String) -> Habit? {
        addHabit(name: name, schedule: .everyDay)
    }
}

@MainActor
final class HabitListStore: ObservableObject, HabitListBehavior {
    static let storageKey = "kyo.habits.v1"

    /// Every habit, in manager order. For a Watch mirror, `baseHabits` with the outbox replayed.
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var todayHabits: [TodayHabit] = []

    /// A `.mirror` (Watch) store's habits as of the last applied snapshot, before replaying its
    /// own unacknowledged commands. Stored under `storageKey`. Unused by other stores.
    private var baseHabits: [Habit] = []
    /// A `.mirror` store's ordered, unacknowledged commands (ADR 0002).
    private var outbox: [HabitCommand] = []
    /// A `.publish` (phone) store's ids of deleted habits, so a late command can't touch or
    /// recreate one. Bounded to the most recent `maxBoundedSetSize`.
    private var tombstonedHabitIDs: [UUID] = []
    /// A `.publish` store's ids of commands already processed, for idempotency under retry and
    /// duplicate delivery. Bounded to the most recent `maxBoundedSetSize`.
    private var processedCommandIDs: [UUID] = []

    /// Persisted sets keep this many most-recent entries (insertion order), as in ADR 0002.
    private static let maxBoundedSetSize = 500

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let now: () -> Date
    private let calendar: Calendar
    private let sync: HabitListSync?
    private let revisionKey: String
    private let outboxKey: String
    private let tombstonesKey: String
    private let processedCommandIDsKey: String
    private var revision: Int64?

    var todayCount: Int { todayHabits.count }
    var doneCount: Int { todayHabits.filter(\.isDone).count }

    /// Whether this store has habits to show. Always true unless it mirrors the phone (Watch)
    /// and no habit snapshot was ever applied.
    var hasSynced: Bool {
        if case .mirror = sync { return revision != nil }
        return true
    }

    private var isMirror: Bool {
        if case .mirror = sync { return true }
        return false
    }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = HabitListStore.storageKey,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        sync: HabitListSync? = nil
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.now = now
        self.calendar = calendar
        self.sync = sync
        self.revisionKey = storageKey + ".revision"
        self.outboxKey = storageKey + ".outbox"
        self.tombstonesKey = storageKey + ".tombstones"
        self.processedCommandIDsKey = storageKey + ".processedCommands"
        self.revision = sync == nil ? nil : (userDefaults.object(forKey: revisionKey) as? NSNumber)?.int64Value

        var stored: [Habit] = []
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Habit].self, from: data) {
            stored = Self.ordered(decoded)
        }
        if isMirror {
            baseHabits = stored
            outbox = Self.decode([HabitCommand].self, forKey: outboxKey, in: userDefaults) ?? []
        } else {
            habits = stored
            tombstonedHabitIDs = Self.decode([UUID].self, forKey: tombstonesKey, in: userDefaults) ?? []
            processedCommandIDs = Self.decode([UUID].self, forKey: processedCommandIDsKey, in: userDefaults) ?? []
        }
        backfillCreationDays()
        recomputeHabits()
        refreshForCurrentDay()

        switch sync {
        case .publish(let transport):
            // Registered before the first publish, so a command the transport queued before
            // this store existed is applied and acknowledged in that first snapshot.
            transport.setHabitCommandHandler { [weak self] command in
                self?.applyCommand(command)
            }
            // Seed a revision from the wall clock on a fresh install, as the task store does
            // (ADR 0001), rather than publishing at revision 0 forever.
            if revision == nil {
                let seeded = Int64(now().timeIntervalSince1970 * 1000)
                revision = seeded
                userDefaults.set(NSNumber(value: seeded), forKey: revisionKey)
            }
            transport.publish(snapshot(revision: revision ?? 0))
        case .mirror(let transport):
            // Registered last: the transport may call the handler synchronously.
            transport.setHabitSnapshotHandler { [weak self] snapshot in
                self?.apply(snapshot)
            }
            // Retry: resend every unacknowledged command. The phone dedupes by command id.
            for command in outbox {
                transport.send(command)
            }
        case nil:
            break
        }
    }

    /// Applies an incoming snapshot. Commands it acknowledges leave the outbox whatever its
    /// revision (ADR 0002). Per ADR 0001's rule, only a revision strictly greater than the last
    /// one applied (or any, if none was) replaces `baseHabits`. The habits are saved before the
    /// revision, so a crash between the two re-applies the same snapshot.
    private func apply(_ snapshot: HabitListSnapshot) {
        guard isMirror else { return }
        let acknowledged = Set(snapshot.acknowledgedCommandIDs)
        let outboxChanged = outbox.contains { acknowledged.contains($0.id) }
        if outboxChanged {
            outbox.removeAll { acknowledged.contains($0.id) }
            persistOutbox()
        }

        let isNewer = revision.map { snapshot.revision > $0 } ?? true
        if isNewer {
            baseHabits = Self.ordered(snapshot.habits)
            persist()
            revision = snapshot.revision
            userDefaults.set(NSNumber(value: snapshot.revision), forKey: revisionKey)
        }

        if isNewer || outboxChanged {
            recomputeHabits()
            refreshForCurrentDay()
            objectWillChange.send()
        }
    }

    /// The Watch's visible habits: `baseHabits` with every outbox command replayed on top using
    /// the phone's rules. A phone or standalone store's `habits` are authoritative as they are.
    private func recomputeHabits() {
        guard isMirror else { return }
        habits = Self.replaying(outbox, over: baseHabits)
    }

    /// Replays commands in order: a set check-off sets the habit's state for that day if the
    /// habit exists, and does nothing otherwise (the phone's rule for a deleted habit).
    private static func replaying(_ commands: [HabitCommand], over base: [Habit]) -> [Habit] {
        var result = base
        for command in commands {
            switch command.action {
            case .setCheckOff(let habitID, let day, let isCheckedOff):
                guard let index = result.firstIndex(where: { $0.id == habitID }) else { continue }
                result[index] = result[index].settingCheckOff(on: day, to: isCheckedOff)
            }
        }
        return result
    }

    private func snapshot(revision: Int64) -> HabitListSnapshot {
        HabitListSnapshot(
            revision: revision, habits: habits, acknowledgedCommandIDs: processedCommandIDs,
            trimmedOn: now(), calendar: calendar
        )
    }

    /// Bumps the revision with ADR 0001's hybrid clock and publishes. Phone side only.
    private func publishChange() {
        guard case .publish(let transport) = sync else { return }
        let candidate = max((revision ?? 0) + 1, Int64(now().timeIntervalSince1970 * 1000))
        revision = candidate
        userDefaults.set(NSNumber(value: candidate), forKey: revisionKey)
        transport.publish(snapshot(revision: candidate))
    }

    @discardableResult
    func addHabit(name: String, schedule: HabitSchedule) -> Habit? {
        guard !isMirror else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, schedule.isValid else { return nil }

        let order = (habits.map(\.order).max() ?? -1) + 1
        let habit = Habit(
            name: trimmedName, order: order, schedule: schedule,
            createdOn: TaskCompletionDay(date: now(), calendar: calendar)
        )
        habits = Self.ordered(habits + [habit])
        refreshForCurrentDay()
        persist()
        publishChange()
        return habit
    }

    @discardableResult
    func editHabit(id: UUID, name: String, schedule: HabitSchedule) -> Habit? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isMirror, let index = habits.firstIndex(where: { $0.id == id }),
              !trimmedName.isEmpty, schedule.isValid else { return nil }

        let updated = habits[index].withName(trimmedName)
            .withSchedule(schedule, from: TaskCompletionDay(date: now(), calendar: calendar))
        habits[index] = updated
        refreshForCurrentDay()
        persist()
        publishChange()
        return updated
    }

    @discardableResult
    func deleteHabit(id: UUID) -> Habit? {
        guard !isMirror, let index = habits.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = habits.remove(at: index)
        if case .publish = sync { recordTombstone(id) }
        refreshForCurrentDay()
        persist()
        publishChange()
        return removed
    }

    @discardableResult
    func toggleCheckOff(id: UUID) -> Habit? {
        let today = TaskCompletionDay(date: now(), calendar: calendar)
        // A habit made not due by an edit stays on Today while it has a check-off, so it can be unchecked.
        guard let index = habits.firstIndex(where: { $0.id == id }),
              habits[index].isDue(on: now(), calendar: calendar) || habits[index].checkOffs.contains(today)
        else { return nil }

        let habit = habits[index]
        let isCheckedOff = !habit.checkOffs.contains(today)

        if case .mirror(let transport) = sync {
            // An absolute state for the Watch's own day, replayed over the snapshot until the
            // phone acknowledges it (ADR 0003).
            let command = HabitCommand(id: UUID(), action: .setCheckOff(habitID: id, day: today, isCheckedOff: isCheckedOff))
            outbox.append(command)
            persistOutbox()
            recomputeHabits()
            refreshForCurrentDay()
            transport.send(command)
            return habits.first { $0.id == id }
        }

        let updated = habit.settingCheckOff(on: today, to: isCheckedOff)
        habits[index] = updated
        refreshForCurrentDay()
        persist()
        publishChange()
        return updated
    }

    func moveHabits(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !isMirror, let first = source.first, let last = source.last, first >= 0, last < habits.count,
              (0...habits.count).contains(destination) else { return }

        let moving = source.map { habits[$0] }
        var reordered = habits.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        reordered.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        habits = reordered.enumerated().map { $1.withOrder(Int64($0)) }
        refreshForCurrentDay()
        persist()
        publishChange()
    }

    /// Applies a Watch command on the phone (`.publish` side) in arrival order, last applied
    /// wins (ADR 0003). The stated day is recorded even if it is late or a schedule edit has
    /// happened since; schedule history decides whether it counts. A command for a deleted
    /// habit changes nothing. Every command is acknowledged: recorded as processed and carried
    /// in the next snapshot, so the Watch can retire it.
    private func applyCommand(_ command: HabitCommand) {
        guard !processedCommandIDs.contains(command.id) else { return }

        switch command.action {
        case .setCheckOff(let habitID, let day, let isCheckedOff):
            if !tombstonedHabitIDs.contains(habitID),
               let index = habits.firstIndex(where: { $0.id == habitID }) {
                habits[index] = habits[index].settingCheckOff(on: day, to: isCheckedOff)
            }
        }

        processedCommandIDs.append(command.id)
        if processedCommandIDs.count > Self.maxBoundedSetSize {
            processedCommandIDs.removeFirst(processedCommandIDs.count - Self.maxBoundedSetSize)
        }
        persistProcessedCommandIDs()
        refreshForCurrentDay()
        persist()
        publishChange()
    }

    private func recordTombstone(_ id: UUID) {
        tombstonedHabitIDs.append(id)
        if tombstonedHabitIDs.count > Self.maxBoundedSetSize {
            tombstonedHabitIDs.removeFirst(tombstonedHabitIDs.count - Self.maxBoundedSetSize)
        }
        persistTombstones()
    }

    /// Gives habits saved before creation days were recorded their fallback day, and saves it.
    private func backfillCreationDays() {
        let today = TaskCompletionDay(date: now(), calendar: calendar)
        let loaded = isMirror ? baseHabits : habits
        guard loaded.contains(where: { $0.createdOn == nil }) else { return }
        let filled = loaded.map { $0.createdOn == nil ? $0.withCreatedOn($0.resolvedCreatedOn(fallback: today)) : $0 }
        if isMirror { baseHabits = filled } else { habits = filled }
        persist()
    }

    /// Re-evaluates Today's list against the clock. Check-offs are keyed to calendar days, so
    /// after midnight yesterday's check-offs no longer put a habit in the done group.
    func refreshForCurrentDay() {
        let today = TaskCompletionDay(date: now(), calendar: calendar)
        let date = now()
        let onToday = habits.filter { $0.isDue(on: date, calendar: calendar) || $0.checkOffs.contains(today) }
        let entries = onToday.map { habit -> TodayHabit in
            let isCheckedOffToday = habit.checkOffs.contains(today)
            let progress = habit.weekProgress(on: date, calendar: calendar)
            return TodayHabit(
                habit: habit,
                isDone: isCheckedOffToday || progress?.isTargetMet == true,
                isCheckedOffToday: isCheckedOffToday,
                weekProgress: progress,
                streak: habit.streak(on: date, calendar: calendar)
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

    /// Saves the habits: the phone's own, or the Watch's last snapshot (the outbox is saved apart).
    private func persist() {
        guard let data = try? JSONEncoder().encode(isMirror ? baseHabits : habits) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func persistOutbox() {
        guard let data = try? JSONEncoder().encode(outbox) else { return }
        userDefaults.set(data, forKey: outboxKey)
    }

    private func persistTombstones() {
        guard let data = try? JSONEncoder().encode(tombstonedHabitIDs) else { return }
        userDefaults.set(data, forKey: tombstonesKey)
    }

    private func persistProcessedCommandIDs() {
        guard let data = try? JSONEncoder().encode(processedCommandIDs) else { return }
        userDefaults.set(data, forKey: processedCommandIDsKey)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, forKey key: String, in userDefaults: UserDefaults) -> Value? {
        userDefaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
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
