import Foundation
import Network
import Speech

/// What the file transcriber and the live transcriber share: which Speech module serves the
/// device's language, the speech model install, a gate that lets one analysis run at a time, and
/// the signals that something blocking transcription has cleared. Every Speech-framework call
/// outside the transcribers' own analysis code lives here.
///
/// Nothing here asks for speech-recognition permission: `SpeechAnalyzer` doesn't use it.
final class SpeechSupport: @unchecked Sendable {
    static let shared = SpeechSupport()

    /// A recognized stretch of speech. A volatile one is a guess that a later result replaces.
    struct Heard: Sendable {
        let text: String
        let isFinal: Bool
    }

    /// A module chosen for the device's language, and its results as plain text.
    struct Choice: Sendable {
        let module: any SpeechModule
        let heard: @Sendable () -> AsyncThrowingStream<Heard, any Error>
    }

    enum Resolution: Sendable {
        case ready(Choice)
        /// A module serves the language, but its model isn't installed yet. Its install has
        /// been started, and readiness is reported when it finishes.
        case notInstalled
        /// Neither `SpeechTranscriber` nor `DictationTranscriber` serves this device or language.
        case unsupported
    }

    enum Purpose: Sendable {
        /// From the microphone while recording: results that change as words are heard.
        case live
        /// From a saved file: final results only.
        case file
    }

    /// One analysis at a time, live or file.
    let gate = AnalysisGate()
    /// Yields when an install finishes or the network comes back. See `readinessUpdates()`.
    let readiness: AsyncStream<Void>

    private let readinessContinuation: AsyncStream<Void>.Continuation
    private let installer = AssetInstaller()
    private let pathMonitor = NWPathMonitor()
    private let deviceLocale: @Sendable () -> Locale

    init(deviceLocale: @escaping @Sendable () -> Locale = { Locale.current }) {
        self.deviceLocale = deviceLocale
        (readiness, readinessContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        watchNetwork()
    }

    /// Picks the module for the device's language, checked now: `SpeechTranscriber` where this
    /// device and language support it, otherwise `DictationTranscriber`. A module whose model
    /// isn't installed is skipped for one that is; with none installed, the preferred one's
    /// install starts in the background.
    func resolve(_ purpose: Purpose) async -> Resolution {
        let device = deviceLocale()
        var pending: Choice?

        if SpeechTranscriber.isAvailable,
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: device)
        {
            let transcriber = SpeechTranscriber(
                locale: locale,
                preset: purpose == .live ? .progressiveTranscription : .transcription
            )
            let choice = Choice(module: transcriber) { Self.stream(transcriber.results) { ($0.text, $0.isFinal) } }
            switch await AssetInventory.status(forModules: [transcriber]) {
            case .installed: return .ready(choice)
            case .supported, .downloading: pending = choice
            default: break
            }
        }

        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: device) {
            let transcriber = DictationTranscriber(
                locale: locale,
                preset: purpose == .live ? .progressiveLongDictation : .longDictation
            )
            let choice = Choice(module: transcriber) { Self.stream(transcriber.results) { ($0.text, $0.isFinal) } }
            switch await AssetInventory.status(forModules: [transcriber]) {
            case .installed: return .ready(choice)
            case .supported, .downloading: pending = pending ?? choice
            default: break
            }
        }

        guard let pending else { return .unsupported }
        await installer.install(pending.module) { [readinessContinuation] in
            readinessContinuation.yield()
        }
        return .notInstalled
    }

    private static func stream<Results: AsyncSequence & Sendable, Result: Sendable>(
        _ results: Results,
        _ read: @escaping @Sendable (Result) -> (AttributedString, Bool)
    ) -> AsyncThrowingStream<Heard, any Error> where Results.Element == Result {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await result in results {
                        let (text, isFinal) = read(result)
                        continuation.yield(Heard(text: String(text.characters), isFinal: isFinal))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The network coming back can unblock a model download that failed offline.
    private func watchNetwork() {
        let continuation = readinessContinuation
        let wasSatisfied = Locked(false)
        pathMonitor.pathUpdateHandler = { path in
            let isSatisfied = path.status == .satisfied
            let before = wasSatisfied.exchange(isSatisfied)
            if isSatisfied && !before { continuation.yield() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "kyo.speech.network"))
    }
}

/// Lets one analysis run at a time. The system limits simultaneous analyses and throws
/// `insufficientResources` past it, so file analyses wait their turn and a live one only starts
/// when the gate is free.
actor AnalysisGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func tryAcquire() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Downloads and installs a speech model through `AssetInventory`, one install at a time. The
/// system shares the model across apps and may drop one that goes unused, so an install can be
/// needed again later.
private actor AssetInstaller {
    private var isInstalling = false

    func install(_ module: any SpeechModule, onInstalled: @escaping @Sendable () -> Void) {
        guard !isInstalling else { return }
        isInstalling = true
        Task {
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try await request.downloadAndInstall()
                }
                onInstalled()
            } catch {
                // Offline or the download failed: the memo stays No transcript, and the network
                // coming back or the next launch tries again.
            }
            self.finished()
        }
    }

    private func finished() {
        isInstalling = false
    }
}

/// A value shared between a callback and the code that set it up.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    /// Stores `new` and returns what was there.
    func exchange(_ new: Value) -> Value {
        lock.withLock {
            let old = value
            value = new
            return old
        }
    }
}
