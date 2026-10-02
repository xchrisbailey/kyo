import Combine
import Foundation

/// One row of the Watch's Memos section: a memo the phone has confirmed, or a recording the
/// phone hasn't yet.
enum WatchListedMemo: Equatable, Identifiable, Sendable {
    case synced(WatchMemo)
    /// A recording still in the outbox: "Voice memo", with its time and "Waiting for iPhone".
    case waiting(WatchRecordingEntry)

    var id: UUID {
        switch self {
        case .synced(let memo): memo.id
        case .waiting(let entry): entry.id
        }
    }

    var createdAt: Date {
        switch self {
        case .synced(let memo): memo.createdAt
        case .waiting(let entry): entry.startedAt
        }
    }

    var title: String {
        switch self {
        case .synced(let memo): memo.title
        case .waiting: Memo.voiceFallbackTitle
        }
    }

    var isPhotoOnly: Bool {
        if case .synced(let memo) = self { return memo.isPhotoOnly }
        return false
    }

    var isVoice: Bool {
        switch self {
        case .synced(let memo): memo.kind == .voice
        case .waiting: true
        }
    }

    /// The row's second line. A waiting recording's is "9:41 AM · Waiting for iPhone".
    func detailLine(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        switch self {
        case .synced(let memo): memo.detailLine(locale: locale, timeZone: timeZone)
        case .waiting(let entry): "\(WatchMemo.timeText(of: entry.startedAt, locale: locale, timeZone: timeZone)) · Waiting for iPhone"
        }
    }

    func accessibilityLabel(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        switch self {
        case .synced(let memo): memo.accessibilityLabel(locale: locale, timeZone: timeZone)
        case .waiting: "Voice memo, \(title), \(detailLine(locale: locale, timeZone: timeZone))"
        }
    }
}

/// The Watch's mirror of the phone's memos: the last `MemoListSnapshot` cached in UserDefaults
/// (ADR 0004 keeps the Watch off SwiftData), filtered to the Watch's own Today. The Watch never
/// writes memos here. With an `outbox`, recordings the phone hasn't confirmed yet are listed as
/// waiting, and the snapshot's `acknowledgedMemoIDs` retire them. See
/// `docs/adr/0005-watch-memo-sync.md`.
@MainActor
final class WatchMemoList: ObservableObject {
    static let storageKey = "kyo.watchMemos.v1"

    /// Today's memos the phone has confirmed, newest first.
    @Published private(set) var todayMemos: [WatchMemo] = []
    /// Today's recordings the phone hasn't confirmed, newest first. They can't be deleted on the
    /// Watch.
    @Published private(set) var waitingRecordings: [WatchRecordingEntry] = []
    /// Everything the Memos section lists, newest first: confirmed memos and waiting recordings.
    @Published private(set) var listedMemos: [WatchListedMemo] = []

    /// Where the Watch's own recordings wait for the phone, or `nil` when it has none.
    let outbox: WatchRecordingOutbox?

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let storageKey: String
    private var snapshot: MemoListSnapshot?
    private var outboxEntries: [WatchRecordingEntry] = []
    private var outboxObservation: AnyCancellable?

    /// Whether a memo snapshot has ever arrived. Until one has, an empty list means "not synced
    /// yet" rather than "no memos today".
    var hasSynced: Bool { snapshot != nil }

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = WatchMemoList.storageKey,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        outbox: WatchRecordingOutbox? = nil,
        sync transport: any MemoSnapshotTransport
    ) {
        self.outbox = outbox
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.now = now
        self.calendar = calendar
        self.snapshot = userDefaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(MemoListSnapshot.self, from: $0) }
        // The snapshot cached from before a quit may already confirm recordings.
        if let outbox, let acknowledged = snapshot?.acknowledgedMemoIDs {
            outbox.retire(acknowledged: Set(acknowledged))
        }
        outboxEntries = outbox?.entries ?? []
        outboxObservation = outbox?.$entries.dropFirst().sink { [weak self] entries in
            self?.outboxEntries = entries
            self?.refreshForCurrentDay()
        }
        refreshForCurrentDay()
        // Registered last: the transport may call the handler synchronously.
        transport.setMemoSnapshotHandler { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    /// Per ADR 0001's rule, only a revision strictly greater than the last one applied (or any,
    /// if none was) replaces the cached snapshot. Independent of that check, the recordings the
    /// snapshot acknowledges are always retired from the outbox, as for commands in ADR 0002.
    private func apply(_ incoming: MemoListSnapshot) {
        outbox?.retire(acknowledged: Set(incoming.acknowledgedMemoIDs))
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
            .sorted { Self.isNewer(($0.createdAt, $0.id), ($1.createdAt, $1.id)) }
        // A recording the phone has already listed is its memo now.
        let listed = Set(todayMemos.map(\.id))
        waitingRecordings = outboxEntries
            .filter { $0.day == today && !listed.contains($0.id) }
            .sorted { Self.isNewer(($0.startedAt, $0.id), ($1.startedAt, $1.id)) }
        listedMemos = (todayMemos.map(WatchListedMemo.synced) + waitingRecordings.map(WatchListedMemo.waiting))
            .sorted { Self.isNewer(($0.createdAt, $0.id), ($1.createdAt, $1.id)) }
    }

    private static func isNewer(_ lhs: (Date, UUID), _ rhs: (Date, UUID)) -> Bool {
        if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
        return lhs.1.uuidString > rhs.1.uuidString
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
