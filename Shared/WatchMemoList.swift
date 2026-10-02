import Foundation

/// The Watch's mirror of the phone's memos: the last `MemoListSnapshot` cached in UserDefaults
/// (ADR 0004 keeps the Watch off SwiftData), filtered to the Watch's own Today. The Watch never
/// writes memos here. See `docs/adr/0005-watch-memo-sync.md`.
@MainActor
final class WatchMemoList: ObservableObject {
    static let storageKey = "kyo.watchMemos.v1"

    /// Today's memos, newest first.
    @Published private(set) var todayMemos: [WatchMemo] = []

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let storageKey: String
    private var snapshot: MemoListSnapshot?

    /// Whether a memo snapshot has ever arrived. Until one has, an empty list means "not synced
    /// yet" rather than "no memos today".
    var hasSynced: Bool { snapshot != nil }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = WatchMemoList.storageKey,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        sync transport: any MemoSnapshotTransport
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.now = now
        self.calendar = calendar
        self.snapshot = userDefaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(MemoListSnapshot.self, from: $0) }
        refreshForCurrentDay()
        // Registered last: the transport may call the handler synchronously.
        transport.setMemoSnapshotHandler { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    /// Per ADR 0001's rule, only a revision strictly greater than the last one applied (or any,
    /// if none was) replaces the cached snapshot.
    private func apply(_ incoming: MemoListSnapshot) {
        guard snapshot.map({ incoming.revision > $0.revision }) ?? true else { return }
        snapshot = incoming
        if let data = try? JSONEncoder().encode(incoming) {
            userDefaults.set(data, forKey: storageKey)
        }
        refreshForCurrentDay()
    }

    /// Re-evaluates which memos belong to the Watch's own Today, newest first.
    func refreshForCurrentDay() {
        let today = TaskCompletionDay(date: now(), calendar: calendar)
        todayMemos = (snapshot?.memos ?? [])
            .filter { $0.day == today }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString > $1.id.uuidString
            }
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
}
