import Combine
import Foundation

/// One open **Memo → Task** sheet: the **Suggested tasks** for a **Memo**'s text and what the user
/// does with them. Suggestions are generated once, when the sheet opens, and aren't kept: opening
/// Memo → Task again makes a new one, with no memory of what was added.
///
/// The sheet has a manual path for when there are no suggestions, because the model is
/// unavailable, found nothing or failed, or because the memo has no text (Transcribing, No
/// transcript, or photo-only). It shows "No suggestions" with one blank task row and **Add
/// another**. Memo → Task is never hidden.
///
/// Adding creates plain tasks on **Today** through the task store. Nothing links a task back to
/// the memo.
@MainActor
final class MemoTaskSuggestions: ObservableObject, Identifiable {
    /// The most Suggested tasks a memo yields.
    static let maximumSuggestions = 5

    enum Phase: Equatable {
        /// "Finding suggested tasks…": the model is working.
        case finding
        /// Up to 5 Suggested tasks from the model.
        case suggestions
        /// "No suggestions": the manual path.
        case noSuggestions
    }

    struct Row: Identifiable, Equatable {
        let id: UUID
        var text: String
        /// Suggested tasks start ticked, and so does a row the user adds.
        var isTicked: Bool
        /// Created on Today already. An added row can't be added again or edited.
        var isAdded: Bool
    }

    @Published private(set) var phase: Phase
    @Published private(set) var rows: [Row]

    private let memoText: String
    private let model: any OnDeviceLanguageModel
    private let tasks: any TaskListBehavior

    /// `memoText` is the memo's current text or Transcript, empty when it has none.
    init(memoText: String, model: any OnDeviceLanguageModel, tasks: any TaskListBehavior) {
        self.memoText = memoText
        self.model = model
        self.tasks = tasks
        let hasText = !memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText, model.availability.isAvailable {
            phase = .finding
            rows = []
        } else {
            phase = .noSuggestions
            rows = [Self.blankRow()]
        }
    }

    /// How many ticked rows "Add to Today (n)" would add: ticked, not added yet, with text.
    var addableCount: Int {
        rows.filter { Self.isAddable($0) }.count
    }

    /// Finds the Suggested tasks. Does nothing unless the sheet is still finding them. The model
    /// sees only the part of the text that fits its context, from the start.
    func load() async {
        guard phase == .finding else { return }
        let text = await model.fittingStart(of: memoText, for: .suggestTasks)
        var suggestions: [String] = []
        if !text.isEmpty, !Task.isCancelled {
            suggestions = Self.cleaned((try? await model.suggestTasks(from: text)) ?? [])
        }
        // Closed while working: nothing to show.
        if Task.isCancelled { return }
        if suggestions.isEmpty {
            phase = .noSuggestions
            rows = [Self.blankRow()]
        } else {
            phase = .suggestions
            rows = suggestions.map { Row(id: UUID(), text: $0, isTicked: true, isAdded: false) }
        }
    }

    func edit(rowID: UUID, text: String) {
        update(rowID) { row in
            if !row.isAdded { row.text = text }
        }
    }

    func toggle(rowID: UUID) {
        update(rowID) { row in
            if !row.isAdded { row.isTicked.toggle() }
        }
    }

    /// **Add another**: a blank, ticked row. Only the manual path has it.
    @discardableResult
    func addAnother() -> UUID? {
        guard phase == .noSuggestions else { return nil }
        let row = Self.blankRow()
        rows.append(row)
        return row.id
    }

    /// **Add to Today (n)**: creates each addable row as a task on Today and marks it Added.
    @discardableResult
    func addToToday() -> Int {
        var added = 0
        for index in rows.indices where Self.isAddable(rows[index]) {
            if tasks.addTask(text: rows[index].text) != nil {
                rows[index].isAdded = true
                added += 1
            }
        }
        return added
    }

    // MARK: Helpers

    private func update(_ id: UUID, _ change: (inout Row) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        change(&rows[index])
    }

    private static func isAddable(_ row: Row) -> Bool {
        row.isTicked && !row.isAdded && !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func blankRow() -> Row {
        Row(id: UUID(), text: "", isTicked: true, isAdded: false)
    }

    /// Trimmed, without blanks or repeats (ignoring case), at most 5.
    private static func cleaned(_ suggestions: [String]) -> [String] {
        var seen = Set<String>()
        var kept: [String] = []
        for suggestion in suggestions {
            let text = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
            kept.append(text)
            if kept.count == maximumSuggestions { break }
        }
        return kept
    }
}
