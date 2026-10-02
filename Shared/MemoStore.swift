import Combine
import Foundation
import SwiftData

/// What the views consume to capture and show **Memos**. Today's memos are listed newest
/// first. A memo belongs to the local calendar day it was created and never moves.
@MainActor
protocol MemoStoreBehavior: AnyObject {
    /// Only the memos whose day is Today, newest first.
    var memos: [Memo] { get }
    /// "2 memos" (or "1 memo") when Today has memos, "Notes & voice" when it has none.
    var sectionSubtitle: String { get }

    /// Any memo, from any day, by id.
    func memo(id: UUID) -> Memo?
    /// Saves a Written memo on Today. A memo with no text is discarded: returns `nil`.
    @discardableResult func addWrittenMemo(text: String) -> Memo?
    /// Saves new text immediately. Emptying the text keeps the memo until it's closed.
    @discardableResult func editMemo(id: UUID, text: String) -> Memo?
    /// Called when a memo's card closes. Discards a memo with no text, returning it.
    @discardableResult func closeMemo(id: UUID) -> Memo?
    /// Permanent: no undo and no trash.
    @discardableResult func deleteMemo(id: UUID) -> Memo?
}

@MainActor
final class MemoStore: ObservableObject, MemoStoreBehavior {
    @Published private(set) var memos: [Memo] = []
    @Published private(set) var currentDate: Date

    /// Held so the container, and with it the context, outlives every use of the store.
    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let now: () -> Date
    private let calendar: Calendar

    /// `now` and `calendar` make the current day controllable. A memo's day is taken from them
    /// when it's created and then kept.
    init(modelContainer: ModelContainer, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.modelContainer = modelContainer
        self.context = modelContainer.mainContext
        self.now = now
        self.calendar = calendar
        self.currentDate = calendar.startOfDay(for: now())
        discardEmptyMemos()
        refreshForCurrentDay()
    }

    var sectionSubtitle: String {
        switch memos.count {
        case 0: "Notes & voice"
        case 1: "1 memo"
        case let count: "\(count) memos"
        }
    }

    func memo(id: UUID) -> Memo? {
        records(withID: id).first?.memo
    }

    @discardableResult
    func addWrittenMemo(text: String) -> Memo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let createdAt = now()
        let record = MemoRecord(
            kind: .written,
            createdAt: createdAt,
            day: TaskCompletionDay(date: createdAt, calendar: calendar),
            text: trimmed
        )
        context.insert(record)
        save()
        refreshForCurrentDay()
        return record.memo
    }

    @discardableResult
    func editMemo(id: UUID, text: String) -> Memo? {
        guard let record = records(withID: id).first else { return nil }
        // Whitespace-only text is stored as empty, so "no text" is a single stored state.
        let stored = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        if record.text != stored {
            record.text = stored
            save()
            refreshForCurrentDay()
        }
        return record.memo
    }

    @discardableResult
    func closeMemo(id: UUID) -> Memo? {
        guard let record = records(withID: id).first, record.text.isEmpty else { return nil }
        return deleteMemo(id: id)
    }

    @discardableResult
    func deleteMemo(id: UUID) -> Memo? {
        let matches = records(withID: id)
        guard let first = matches.first else { return nil }
        let removed = first.memo
        for record in matches {
            context.delete(record)
        }
        save()
        refreshForCurrentDay()
        return removed
    }

    /// Re-reads which saved memos belong to the local current day.
    func refreshForCurrentDay() {
        let moment = now()
        currentDate = calendar.startOfDay(for: moment)
        let today = TaskCompletionDay(date: moment, calendar: calendar)
        let year = today.year
        let month = today.month
        let day = today.day
        let descriptor = FetchDescriptor<MemoRecord>(
            predicate: #Predicate { $0.dayYear == year && $0.dayMonth == month && $0.dayDay == day }
        )
        let fetched = ((try? context.fetch(descriptor)) ?? []).filter { $0.dayEra == today.era }
        memos = uniqueByID(fetched).map(\.memo).sorted(by: Self.isNewer)
    }

    /// Refreshes for the current day now, then again at every local midnight until cancelled.
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

    // MARK: Storage

    /// Every record with `id`. The schema has no unique constraint, so a second record with the
    /// same id is possible; callers act on the first and `deleteMemo` removes them all.
    private func records(withID id: UUID) -> [MemoRecord] {
        let descriptor = FetchDescriptor<MemoRecord>(predicate: #Predicate { $0.id == id })
        return Self.keepOrder((try? context.fetch(descriptor)) ?? [])
    }

    /// A memo emptied while its card was open, then left behind by a quit, is discarded on the
    /// next launch: a memo with no text is never kept.
    private func discardEmptyMemos() {
        let descriptor = FetchDescriptor<MemoRecord>(predicate: #Predicate { $0.text == "" })
        for record in (try? context.fetch(descriptor)) ?? [] {
            context.delete(record)
        }
        save()
    }

    private func save() {
        if context.hasChanges {
            try? context.save()
        }
    }

    /// One record per id. Extras are deleted (duplicates are removed by id in app code); the one
    /// kept never depends on fetch order.
    private func uniqueByID(_ records: [MemoRecord]) -> [MemoRecord] {
        var seen = Set<UUID>()
        var unique: [MemoRecord] = []
        for record in Self.keepOrder(records) {
            if seen.insert(record.id).inserted {
                unique.append(record)
            } else {
                context.delete(record)
            }
        }
        save()
        return unique
    }

    private static func keepOrder(_ records: [MemoRecord]) -> [MemoRecord] {
        records.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.text < rhs.text
        }
    }

    private static func isNewer(_ lhs: Memo, _ rhs: Memo) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
