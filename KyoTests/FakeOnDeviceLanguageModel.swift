import Foundation
import XCTest

/// A stand-in for Apple Intelligence: reports whichever availability a test sets, answers with
/// scripted suggestions or an error, and remembers every text it was asked about. Tokens are
/// characters, so a test controls what fits by the length of its text.
@MainActor
final class FakeOnDeviceLanguageModel: OnDeviceLanguageModel {
    struct Failure: Error {}

    enum Answer {
        case suggestions([String])
        case failure
    }

    var availability: OnDeviceLanguageAvailability = .available
    var answer: Answer = .suggestions([])
    /// What `textBudget` answers, in tokens (characters).
    var budget = 1_000
    /// While `true`, `suggestTasks` waits for `finishPendingRequest()`.
    var holdsRequest = false

    /// Every text `suggestTasks` received, in order.
    private(set) var receivedTexts: [String] = []
    private var pendingRequest: CheckedContinuation<Void, Never>?

    init(availability: OnDeviceLanguageAvailability = .available, answer: Answer = .suggestions([])) {
        self.availability = availability
        self.answer = answer
    }

    func textBudget(for task: OnDeviceLanguageTask) async -> Int { budget }

    func tokenCount(of text: String) async -> Int { text.count }

    func suggestTasks(from text: String) async throws -> [String] {
        receivedTexts.append(text)
        if holdsRequest {
            await withCheckedContinuation { pendingRequest = $0 }
        }
        switch answer {
        case .suggestions(let suggestions): return suggestions
        case .failure: throw Failure()
        }
    }

    func finishPendingRequest() {
        pendingRequest?.resume()
        pendingRequest = nil
    }
}
