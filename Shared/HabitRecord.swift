import Foundation
import SwiftData

/// The stored form of a `Habit` on the phone and iPad. Follows docs/adr/0004: no unique
/// constraints (duplicates are removed in app code), every attribute has a default or is
/// optional, and the to-many relationships are optional with inverses so the schema stays
/// CloudKit-ready. Each check-off and each schedule-history entry is its own record, so
/// logging a day touches one small record rather than rewriting the habit. Deleting a habit
/// cascades to both. The creation day is stored as flat integer fields, never a timestamp.
@Model
final class HabitRecord {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int64 = 0
    var createdEra: Int?
    var createdYear: Int?
    var createdMonth: Int?
    var createdDay: Int?

    @Relationship(deleteRule: .cascade, inverse: \HabitCheckOffRecord.habit)
    var checkOffs: [HabitCheckOffRecord]?

    @Relationship(deleteRule: .cascade, inverse: \HabitScheduleRecord.habit)
    var scheduleEntries: [HabitScheduleRecord]?

    /// Copies the habit's own fields. Its check-offs and schedule entries are separate records,
    /// attached by `SwiftDataHabitContent`.
    init(habit: Habit) {
        id = habit.id
        name = habit.name
        order = habit.order
        createdEra = habit.createdOn?.era
        createdYear = habit.createdOn?.year
        createdMonth = habit.createdOn?.month
        createdDay = habit.createdOn?.day
    }

    var createdOn: TaskCompletionDay? {
        guard let createdYear, let createdMonth, let createdDay else { return nil }
        return TaskCompletionDay(era: createdEra, year: createdYear, month: createdMonth, day: createdDay)
    }

    /// Copies `habit`'s own fields onto this record, touching a property only when it differs so
    /// an unchanged record stays clean.
    func update(from habit: Habit) {
        if name != habit.name { name = habit.name }
        if order != habit.order { order = habit.order }
        let day = habit.createdOn
        if createdEra != day?.era { createdEra = day?.era }
        if createdYear != day?.year { createdYear = day?.year }
        if createdMonth != day?.month { createdMonth = day?.month }
        if createdDay != day?.day { createdDay = day?.day }
    }
}

/// One calendar day a habit was checked off. A missed day is the absence of a record.
@Model
final class HabitCheckOffRecord {
    var era: Int?
    var year: Int = 0
    var month: Int = 0
    var day: Int = 0
    var habit: HabitRecord?

    init(day: TaskCompletionDay) {
        era = day.era
        year = day.year
        month = day.month
        self.day = day.day
    }

    var checkedOffDay: TaskCompletionDay {
        TaskCompletionDay(era: era, year: year, month: month, day: day)
    }
}

/// One entry of a habit's schedule history: a schedule and the day it took effect.
@Model
final class HabitScheduleRecord {
    /// The raw values are stored, so they are never renamed.
    enum Kind: String {
        case everyDay
        case weekdays
        case weeklyTarget
    }

    var kindRawValue: String = Kind.everyDay.rawValue
    /// For `.weekdays`: bit `n - 1` is set for `Calendar` weekday `n` (1 = Sunday). Otherwise 0.
    var weekdayMask: Int = 0
    /// For `.weeklyTarget`: the days per week. Otherwise 0.
    var weeklyTarget: Int = 0
    var fromEra: Int?
    var fromYear: Int = 0
    var fromMonth: Int = 0
    var fromDay: Int = 0
    var habit: HabitRecord?

    init(entry: HabitScheduleEntry) {
        let fields = Self.fields(of: entry.schedule)
        kindRawValue = fields.kind.rawValue
        weekdayMask = fields.mask
        weeklyTarget = fields.target
        fromEra = entry.from.era
        fromYear = entry.from.year
        fromMonth = entry.from.month
        fromDay = entry.from.day
    }

    var from: TaskCompletionDay {
        TaskCompletionDay(era: fromEra, year: fromYear, month: fromMonth, day: fromDay)
    }

    var schedule: HabitSchedule {
        switch Kind(rawValue: kindRawValue) ?? .everyDay {
        case .everyDay:
            return .everyDay
        case .weekdays:
            return .weekdays(Set(Self.weekdayRange.filter { weekdayMask & (1 << ($0 - 1)) != 0 }))
        case .weeklyTarget:
            return .weeklyTarget(weeklyTarget)
        }
    }

    var entry: HabitScheduleEntry {
        HabitScheduleEntry(schedule: schedule, from: from)
    }

    /// Whether this record already holds `schedule`.
    func holds(_ schedule: HabitSchedule) -> Bool {
        let fields = Self.fields(of: schedule)
        return kindRawValue == fields.kind.rawValue && weekdayMask == fields.mask && weeklyTarget == fields.target
    }

    /// Replaces the stored schedule, touching a property only when it differs.
    func update(to schedule: HabitSchedule) {
        let fields = Self.fields(of: schedule)
        if kindRawValue != fields.kind.rawValue { kindRawValue = fields.kind.rawValue }
        if weekdayMask != fields.mask { weekdayMask = fields.mask }
        if weeklyTarget != fields.target { weeklyTarget = fields.target }
    }

    /// `Calendar` weekday numbers; any other number in a schedule isn't a weekday and isn't stored.
    private static let weekdayRange = 1...7

    private static func fields(of schedule: HabitSchedule) -> (kind: Kind, mask: Int, target: Int) {
        switch schedule {
        case .everyDay:
            return (.everyDay, 0, 0)
        case .weekdays(let days):
            let mask = days.filter(weekdayRange.contains).reduce(0) { $0 | (1 << ($1 - 1)) }
            return (.weekdays, mask, 0)
        case .weeklyTarget(let target):
            return (.weeklyTarget, 0, target)
        }
    }
}
