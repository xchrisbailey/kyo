import Foundation

/// Whether the on-device language model can take a request right now.
enum OnDeviceLanguageAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        /// This device doesn't support Apple Intelligence.
        case deviceNotEligible
        /// Apple Intelligence is turned off in Settings.
        case appleIntelligenceNotEnabled
        /// The model is still downloading, or isn't ready for another system reason.
        case modelNotReady
        /// The device's language or region isn't one the model supports.
        case unsupportedLanguage
    }

    var isAvailable: Bool { self == .available }
}

/// What a request asks the model to do. A request's own instructions and answer take part of the
/// context, so each task has its own text budget. Generating **Voice memo** titles will add a case.
enum OnDeviceLanguageTask: Sendable {
    case suggestTasks
}

/// The language-model seam: Apple Intelligence, kept out of the rest of the app. The real one is
/// `FoundationOnDeviceLanguageModel`, which wraps the Foundation Models on-device model; tests use a
/// fake that reports each availability state and scripts the answers. The model is on iPhone and
/// iPad only, so nothing that runs on the Watch uses this.
@MainActor
protocol OnDeviceLanguageModel: AnyObject {
    /// Checked now: the device, region, language and setting all count.
    var availability: OnDeviceLanguageAvailability { get }

    /// How many tokens of a memo's text a request for `task` can carry: the context window less
    /// the request's instructions, its answer schema and room for the answer.
    func textBudget(for task: OnDeviceLanguageTask) async -> Int

    /// How many tokens `text` takes.
    func tokenCount(of text: String) async -> Int

    /// Up to 5 tasks the user could do, proposed from a **Memo**'s text, which already fits
    /// `textBudget(for: .suggestTasks)`. Throws when the model refuses, runs out of context or
    /// fails for any other reason.
    func suggestTasks(from text: String) async throws -> [String]
}

extension OnDeviceLanguageModel {
    /// The part of `text` that fits a request for `task`, from the start: all of it when it fits,
    /// otherwise its longest beginning that does (cut on a character boundary, with trailing
    /// whitespace dropped). There's no splitting across requests. Empty when nothing fits.
    func fittingStart(of text: String, for task: OnDeviceLanguageTask) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let budget = await textBudget(for: task)
        guard budget > 0, !trimmed.isEmpty else { return "" }
        if await tokenCount(of: trimmed) <= budget { return trimmed }

        // The longest prefix, in characters, that still fits; token count only grows with length.
        let characters = Array(trimmed)
        var fits = 0
        var tooLong = characters.count
        while tooLong - fits > 1 {
            if Task.isCancelled { return "" }
            let middle = (fits + tooLong) / 2
            if await tokenCount(of: String(characters[..<middle])) <= budget {
                fits = middle
            } else {
                tooLong = middle
            }
        }
        return String(characters[..<fits]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Has no language model: always unavailable for the device, so every feature takes its
/// no-Apple-Intelligence path.
@MainActor
final class NoLanguageModel: OnDeviceLanguageModel {
    var availability: OnDeviceLanguageAvailability { .unavailable(.deviceNotEligible) }
    func textBudget(for task: OnDeviceLanguageTask) async -> Int { 0 }
    func tokenCount(of text: String) async -> Int { 0 }
    func suggestTasks(from text: String) async throws -> [String] { [] }
}
