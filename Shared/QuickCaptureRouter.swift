import Combine
import Foundation

/// Decides what quick capture does when an intent (a control, Siri, Shortcuts or Spotlight) asks
/// for **Record memo** or **Write memo**, and hands that decision to the screen showing Today.
///
/// The intent's `perform()` calls `perform(_:)` once the app is in the foreground. The router
/// never touches UI: it reads the `Surface` Today reports and publishes one `Request` for Today
/// to apply, so the rules live here and are testable. It's `@MainActor` and has no UIKit, so the
/// Watch's quick capture can reuse it.
///
/// A request can arrive before Today exists (a cold launch from a control), so it waits in
/// `pending` until Today takes it.
///
/// The Watch uses it the same way, for **Record memo** only: its control calls it from the intent's
/// `perform()`, and its complications' `widgetURL` arrives as `Action(url:)`.
@MainActor
final class QuickCaptureRouter: ObservableObject {
    static let shared = QuickCaptureRouter()

    enum Action: Equatable, Sendable {
        /// **Record memo**: the recorder opens and records straight away.
        case recordMemo
        /// **Write memo**: the compose sheet opens.
        case writeMemo

        /// The URL a Watch complication opens Kyo with (`widgetURL`). Only **Record memo** has one:
        /// the Watch has no written memo.
        static let recordMemoURL = URL(string: "kyo://record-memo")!

        init?(url: URL) {
            guard url == Self.recordMemoURL else { return nil }
            self = .recordMemo
        }
    }

    /// What's on screen over Today, as far as quick capture cares.
    enum Surface: Equatable {
        /// Nothing is presented over Today.
        case none
        /// The full-screen recorder: a recording is in progress (or the recorder is showing why it
        /// can't record).
        case recorder
        /// The compose sheet. `hasUnsavedDraft` is `true` once it holds text or a photo.
        case compose(hasUnsavedDraft: Bool)
        /// Any other sheet: an open memo card, the Memos sheet, Settings and so on.
        case otherSheet
    }

    enum Target: Equatable {
        case recorder
        case compose
    }

    struct Command: Equatable {
        let target: Target
        /// `true` to open `target` now. `false` when it's already open and in progress, so Kyo
        /// only comes to the front showing it and nothing new starts.
        let startsNew: Bool
        /// `true` when a sheet is open that has to close before `target` opens. Closing a memo card
        /// or the Memos sheet stops any playback; their edits are already saved.
        let closesOpenSheets: Bool
    }

    /// A command with the order it was made in, so Today applies each request once.
    struct Request: Equatable {
        let sequence: Int
        let command: Command
    }

    /// The request Today hasn't applied yet.
    @Published private(set) var pending: Request?

    /// What Today is showing. Today keeps this up to date.
    private(set) var surface: Surface = .none
    private var sequence = 0

    init() {}

    func report(surface: Surface) {
        self.surface = surface
    }

    /// Routes `action` against what's showing now and queues the result for Today.
    func perform(_ action: Action) {
        sequence += 1
        pending = Request(sequence: sequence, command: Self.command(for: action, over: surface))
    }

    /// Today calls this once it has applied `request`. A newer request is left waiting.
    func markApplied(_ request: Request) {
        if pending == request { pending = nil }
    }

    /// The rules. A recording, or a written memo with unsaved text or photos, wins over either
    /// action. Otherwise the requested capture opens, closing any open sheet first.
    static func command(for action: Action, over surface: Surface) -> Command {
        let wanted: Target = action == .recordMemo ? .recorder : .compose
        switch surface {
        case .recorder:
            return Command(target: .recorder, startsNew: false, closesOpenSheets: false)
        case .compose(hasUnsavedDraft: true):
            return Command(target: .compose, startsNew: false, closesOpenSheets: false)
        case .compose(hasUnsavedDraft: false):
            // An empty compose sheet has nothing to lose: Write memo keeps it, Record memo replaces it.
            if wanted == .compose {
                return Command(target: .compose, startsNew: false, closesOpenSheets: false)
            }
            return Command(target: .recorder, startsNew: true, closesOpenSheets: true)
        case .otherSheet:
            return Command(target: wanted, startsNew: true, closesOpenSheets: true)
        case .none:
            return Command(target: wanted, startsNew: true, closesOpenSheets: false)
        }
    }
}
