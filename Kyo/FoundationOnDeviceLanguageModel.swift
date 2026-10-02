import FoundationModels

/// What the model proposes for a memo: a few tasks, each a short phrase. Every property name and
/// guide description counts against the 4,096-token context, so they stay short.
@Generable
private struct ProposedTasks {
    @Guide(description: "Short tasks the memo implies", .maximumCount(5))
    var tasks: [String]
}

/// What the model proposes as a **Voice memo**'s title: a few words. Kept short for the same
/// reason as above.
@Generable
private struct ProposedTitle {
    @Guide(description: "A title of 2 to 6 words, with no quotes or final period")
    var title: String
}

/// The real `OnDeviceLanguageModel`: Apple Intelligence through the Foundation Models on-device
/// `SystemLanguageModel`. Every Foundation Models call lives here, so the rest of the app is tested
/// through the seam. The model isn't on watchOS or in a Simulator without Apple Intelligence, so
/// its output is checked on an Apple Intelligence device.
@MainActor
final class FoundationOnDeviceLanguageModel: OnDeviceLanguageModel {
    private let model = SystemLanguageModel.default

    /// Room kept for the answer and the prompt's framing words, which the counts above don't cover.
    private static let reservedTokens = 400

    private static let suggestTasksInstructions = """
        You read a short personal memo and propose tasks the writer should do. \
        Only propose tasks the memo clearly implies. Phrase each as a short action. \
        Propose none when the memo has nothing to do.
        """

    private static let titleInstructions = """
        You read the transcript of a spoken personal memo and write a short title for it. \
        Name what the memo is about in plain words, in the language of the transcript.
        """

    var availability: OnDeviceLanguageAvailability {
        switch model.availability {
        case .available:
            // The model can be installed while the device language isn't one it supports.
            model.supportsLocale() ? .available : .unavailable(.unsupportedLanguage)
        case .unavailable(.deviceNotEligible):
            .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable:
            .unavailable(.modelNotReady)
        }
    }

    func textBudget(for task: OnDeviceLanguageTask) async -> Int {
        switch task {
        case .suggestTasks:
            await budget(instructions: Self.suggestTasksInstructions, schema: ProposedTasks.generationSchema)
        case .title:
            await budget(instructions: Self.titleInstructions, schema: ProposedTitle.generationSchema)
        }
    }

    private func budget(instructions: String, schema: GenerationSchema) async -> Int {
        let instructionTokens = (try? await model.tokenCount(for: Instructions(instructions))) ?? 150
        let schemaTokens = (try? await model.tokenCount(for: schema)) ?? 100
        return max(0, model.contextSize - instructionTokens - schemaTokens - Self.reservedTokens)
    }

    func tokenCount(of text: String) async -> Int {
        // When counting fails, assume the worst (a token per character) so the text is cut, not refused.
        (try? await model.tokenCount(for: Prompt(text))) ?? text.count
    }

    func suggestTasks(from text: String) async throws -> [String] {
        // A new session for every memo: nothing carries over between requests.
        let session = LanguageModelSession(model: model, instructions: Self.suggestTasksInstructions)
        let response = try await session.respond(to: "Memo:\n\(text)", generating: ProposedTasks.self)
        return response.content.tasks
    }

    func generateTitle(from text: String) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: Self.titleInstructions)
        let response = try await session.respond(to: "Transcript:\n\(text)", generating: ProposedTitle.self)
        return response.content.title
    }
}
