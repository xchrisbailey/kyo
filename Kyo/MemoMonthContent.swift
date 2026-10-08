import Combine
import Foundation

/// What Month shows for memos: a mark on each day that has one, and the day's memos as rows that open the memo.
@MainActor
final class MemoMonthContent: MonthContentSource {
    let kind = MonthKind.memos
    private let store: MemoStore

    init(store: MemoStore) {
        self.store = store
    }

    /// Fires after every change to the saved memos.
    var changes: AnyPublisher<Void, Never> {
        store.$revision.dropFirst().map { _ in }.eraseToAnyPublisher()
    }

    func content(on days: [Date]) -> [Date: MonthKindDay] {
        guard let first = days.min(), let last = days.max() else { return [:] }
        return Dictionary(uniqueKeysWithValues: store.daysWithMemos(from: first, through: last).map {
            ($0, MonthKindDay(mark: .filled))
        })
    }
}
