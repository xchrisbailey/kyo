import Foundation
import SwiftData

/// Where a `HabitListStore` keeps its habit content. In-memory logic always works on `Habit`
/// values; this seam only loads and saves them. A failed save is ignored, like the `try?`
/// UserDefaults writes it replaces.
@MainActor
protocol HabitContentPersistence {
    func load() -> [Habit]
    func save(_ habits: [Habit])
}

/// The Watch's (`.mirror`) content cache: one JSON array under a UserDefaults key, exactly as
/// before SwiftData.
struct UserDefaultsHabitContent: HabitContentPersistence {
    let userDefaults: UserDefaults
    let key: String

    func load() -> [Habit] {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Habit].self, from: data) else { return [] }
        return decoded
    }

    func save(_ habits: [Habit]) {
        guard let data = try? JSONEncoder().encode(habits) else { return }
        userDefaults.set(data, forKey: key)
    }
}

/// The phone's and any standalone store's content, kept as `HabitRecord`s (each with its own
/// check-off and schedule records) in the container's main context.
struct SwiftDataHabitContent: HabitContentPersistence {
    let modelContainer: ModelContainer

    private var context: ModelContext { modelContainer.mainContext }

    /// Loads every habit, first removing duplicate records (the schema has no unique
    /// constraints, so they are cleaned up here): habits that share an id, check-offs that
    /// share a habit and day, and schedule entries that share a habit and effective-from day.
    func load() -> [Habit] {
        let habits = uniqueHabitRecords().values.map { record -> Habit in
            let checkOffs = uniqueCheckOffs(of: record).values
                .map(\.checkedOffDay)
                .sorted { Self.sortKey($0) < Self.sortKey($1) }
            let history = uniqueScheduleEntries(of: record).values
                .sorted { Self.sortKey($0.from) < Self.sortKey($1.from) }
                .map(\.entry)
            return Habit(
                id: record.id,
                name: record.name,
                order: record.order,
                checkOffs: checkOffs,
                createdOn: record.createdOn,
                scheduleHistory: history
            )
        }
        saveIfChanged()
        return habits
    }

    /// Reconciles the stored records with `habits`: updates changed habits, check-offs and
    /// schedule entries, inserts new ones and deletes ones no longer present, then saves once.
    func save(_ habits: [Habit]) {
        let existing = uniqueHabitRecords()
        var missingIDs = Set(existing.keys)
        for habit in habits {
            missingIDs.remove(habit.id)
            if let record = existing[habit.id] {
                record.update(from: habit)
                reconcileCheckOffs(of: record, with: habit)
                reconcileScheduleEntries(of: record, with: habit)
            } else {
                insert(habit)
            }
        }
        // Deleting a habit cascades to its check-off and schedule records.
        for id in missingIDs {
            if let record = existing[id] {
                context.delete(record)
            }
        }
        saveIfChanged()
    }

    private func insert(_ habit: Habit) {
        let record = HabitRecord(habit: habit)
        context.insert(record)
        for day in Set(habit.checkOffs.map(DayKey.init)) {
            let checkOff = HabitCheckOffRecord(day: day.day)
            context.insert(checkOff)
            checkOff.habit = record
        }
        for entry in Self.uniqueEntries(habit.scheduleHistory).values {
            let scheduleRecord = HabitScheduleRecord(entry: entry)
            context.insert(scheduleRecord)
            scheduleRecord.habit = record
        }
    }

    private func reconcileCheckOffs(of record: HabitRecord, with habit: Habit) {
        var existing = uniqueCheckOffs(of: record)
        for day in Set(habit.checkOffs.map(DayKey.init)) {
            if existing.removeValue(forKey: day) == nil {
                let checkOff = HabitCheckOffRecord(day: day.day)
                context.insert(checkOff)
                checkOff.habit = record
            }
        }
        for removed in existing.values {
            context.delete(removed)
        }
    }

    private func reconcileScheduleEntries(of record: HabitRecord, with habit: Habit) {
        var existing = uniqueScheduleEntries(of: record)
        for (key, entry) in Self.uniqueEntries(habit.scheduleHistory) {
            if let scheduleRecord = existing.removeValue(forKey: key) {
                if !scheduleRecord.holds(entry.schedule) { scheduleRecord.update(to: entry.schedule) }
            } else {
                let scheduleRecord = HabitScheduleRecord(entry: entry)
                context.insert(scheduleRecord)
                scheduleRecord.habit = record
            }
        }
        for removed in existing.values {
            context.delete(removed)
        }
    }

    // MARK: Duplicates

    /// The habit records by id. Of records sharing an id, the one that sorts first by order,
    /// name, then most check-offs and schedule entries is kept and the rest are deleted, so the
    /// choice never depends on fetch order.
    private func uniqueHabitRecords() -> [UUID: HabitRecord] {
        guard let records = try? context.fetch(FetchDescriptor<HabitRecord>()) else { return [:] }
        var kept: [UUID: HabitRecord] = [:]
        for record in records.sorted(by: Self.keepsFirst) {
            if kept[record.id] == nil {
                kept[record.id] = record
            } else {
                context.delete(record)
            }
        }
        return kept
    }

    /// The habit's check-offs by day, deleting repeats of a day.
    private func uniqueCheckOffs(of habit: HabitRecord) -> [DayKey: HabitCheckOffRecord] {
        var kept: [DayKey: HabitCheckOffRecord] = [:]
        for record in habit.checkOffs ?? [] {
            let key = DayKey(record.checkedOffDay)
            if kept[key] == nil {
                kept[key] = record
            } else {
                context.delete(record)
            }
        }
        return kept
    }

    /// The habit's schedule entries by effective-from day. Of entries sharing a day, the one
    /// that sorts first by kind, weekdays then target is kept and the rest are deleted.
    private func uniqueScheduleEntries(of habit: HabitRecord) -> [DayKey: HabitScheduleRecord] {
        var kept: [DayKey: HabitScheduleRecord] = [:]
        for record in (habit.scheduleEntries ?? []).sorted(by: Self.keepsFirst) {
            let key = DayKey(record.from)
            if kept[key] == nil {
                kept[key] = record
            } else {
                context.delete(record)
            }
        }
        return kept
    }

    /// `entries` by effective-from day. If a habit value somehow repeats a day, the last entry wins.
    private static func uniqueEntries(_ entries: [HabitScheduleEntry]) -> [DayKey: HabitScheduleEntry] {
        Dictionary(entries.map { (DayKey($0.from), $0) }, uniquingKeysWith: { _, last in last })
    }

    private func saveIfChanged() {
        if context.hasChanges {
            try? context.save()
        }
    }

    private static func keepsFirst(_ lhs: HabitRecord, _ rhs: HabitRecord) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        let lhsCheckOffs = lhs.checkOffs?.count ?? 0
        let rhsCheckOffs = rhs.checkOffs?.count ?? 0
        if lhsCheckOffs != rhsCheckOffs { return lhsCheckOffs > rhsCheckOffs }
        return (lhs.scheduleEntries?.count ?? 0) > (rhs.scheduleEntries?.count ?? 0)
    }

    private static func keepsFirst(_ lhs: HabitScheduleRecord, _ rhs: HabitScheduleRecord) -> Bool {
        if lhs.kindRawValue != rhs.kindRawValue { return lhs.kindRawValue < rhs.kindRawValue }
        if lhs.weekdayMask != rhs.weekdayMask { return lhs.weekdayMask < rhs.weekdayMask }
        return lhs.weeklyTarget < rhs.weeklyTarget
    }

    /// Orders days chronologically; a missing era counts as the current one (1), as elsewhere.
    private static func sortKey(_ day: TaskCompletionDay) -> (Int, Int, Int, Int) {
        (day.era ?? 1, day.year, day.month, day.day)
    }
}

/// A calendar day as a dictionary key, since `TaskCompletionDay` isn't `Hashable`.
private struct DayKey: Hashable {
    let day: TaskCompletionDay

    init(_ day: TaskCompletionDay) { self.day = day }

    static func == (lhs: DayKey, rhs: DayKey) -> Bool { lhs.day == rhs.day }

    func hash(into hasher: inout Hasher) {
        hasher.combine(day.era)
        hasher.combine(day.year)
        hasher.combine(day.month)
        hasher.combine(day.day)
    }
}
