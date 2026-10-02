import Foundation

/// A **Memo** as the rest of the app sees it: a captured thought that belongs to the local
/// calendar day it was created. Only **Written memos** exist so far; a **Voice memo** will add
/// its audio, transcript and duration later without reshaping this type.
struct Memo: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case written
        case voice
    }

    let id: UUID
    let kind: Kind
    let createdAt: Date
    /// The local calendar day the memo was created on. Never moves on edit or time-zone change.
    let day: TaskCompletionDay
    /// A Written memo's whole text: the first line is the title and the rest is the detail.
    let text: String

    /// A Written memo's first non-blank line, trimmed. Empty when the memo has no text.
    var title: String {
        Self.title(ofWrittenText: text)
    }

    /// The text after the title line, with line breaks collapsed to spaces. `nil` when there is
    /// no more text.
    var detail: String? {
        Self.detail(ofWrittenText: text)
    }

    static func title(ofWrittenText text: String) -> String {
        lines(of: text).first ?? ""
    }

    static func detail(ofWrittenText text: String) -> String? {
        let rest = lines(of: text).dropFirst().joined(separator: " ")
        return rest.isEmpty ? nil : rest
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
