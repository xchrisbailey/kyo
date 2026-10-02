import Foundation

/// A highlighted piece of text: the part of a memo's text or transcript around a match, with
/// the matched words marked. Ranges index into `text`.
struct MemoSnippet: Equatable, Sendable {
    let text: String
    let highlights: [Range<String.Index>]
}

/// One memo in the Memos sheet. While searching, `snippet` is set when the match lies deep in
/// the text or transcript, past what the row's detail line shows.
struct MemoSearchResult: Identifiable, Equatable, Sendable {
    let memo: Memo
    let snippet: MemoSnippet?

    var id: UUID { memo.id }
}

/// The memos of one local calendar day, newest first, under a header: "Today", "Yesterday", then
/// "Mon, Sep 28" (with the year for an earlier year).
struct MemoDayGroup: Identifiable, Equatable, Sendable {
    let day: TaskCompletionDay
    let title: String
    let results: [MemoSearchResult]

    var id: String { "\(day.era ?? 0)-\(day.year)-\(day.month)-\(day.day)" }
}

/// What the Memos sheet shows: the day groups for a search (every memo, for an empty search), as
/// many memos as the limit asked for.
struct MemoGroupsPage: Equatable, Sendable {
    /// The search the page answers, trimmed. Empty when listing every memo.
    let query: String
    /// Today first when it has memos, then earlier days, newest first.
    let groups: [MemoDayGroup]
    /// `true` when memos beyond the limit are left to load.
    let hasMore: Bool

    /// "No memos match "<query>"" when a search found nothing, otherwise `nil`.
    var noResultsMessage: String? {
        guard !query.isEmpty, groups.isEmpty else { return nil }
        return "No memos match \u{201C}\(query)\u{201D}"
    }

    static let empty = MemoGroupsPage(query: "", groups: [], hasMore: false)
    /// How many memos one page loads.
    static let pageSize = 40
}

/// Matching a search against memo text, and the snippets and highlights that show where.
enum MemoSearch {
    /// A match this far into a row's detail is out of sight on its one line, so the detail line
    /// shows a snippet around it instead.
    static let visibleDetailLength = 40
    private static let snippetLead = 20
    private static let snippetTrail = 50

    /// The search with surrounding whitespace removed.
    static func term(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where `query` occurs in `text`, ignoring case, accents and character width, including
    /// inside a word, in order.
    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let term = term(query)
        guard !term.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var from = text.startIndex
        while from < text.endIndex,
              let range = text.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: from..<text.endIndex
              ),
              !range.isEmpty {
            found.append(range)
            from = range.upperBound
        }
        return found
    }

    /// A snippet of the memo's text or transcript around the first match, when that match sits
    /// past the start of the detail line. `nil` when the match is in the title or near the start
    /// of the detail, or when there is none.
    static func snippet(for memo: Memo, query: String) -> MemoSnippet? {
        guard let detail = memo.searchableDetail,
              let match = ranges(of: query, in: detail).first,
              detail.distance(from: detail.startIndex, to: match.lowerBound) > visibleDetailLength
        else { return nil }

        var start = detail.index(match.lowerBound, offsetBy: -snippetLead, limitedBy: detail.startIndex) ?? detail.startIndex
        // Start on a whole word: skip the rest of one the window cut in half.
        if start > detail.startIndex, !detail[detail.index(before: start)].isWhitespace {
            while start < match.lowerBound, !detail[start].isWhitespace { start = detail.index(after: start) }
            while start < match.lowerBound, detail[start].isWhitespace { start = detail.index(after: start) }
        }
        var end = detail.index(match.upperBound, offsetBy: snippetTrail, limitedBy: detail.endIndex) ?? detail.endIndex
        while end < detail.endIndex, !detail[end].isWhitespace { end = detail.index(after: end) }

        let text = (start > detail.startIndex ? "…" : "") + detail[start..<end] + (end < detail.endIndex ? "…" : "")
        return MemoSnippet(text: text, highlights: ranges(of: query, in: text))
    }
}

/// The header over a day's memos in the Memos sheet.
enum MemoDayHeader {
    static func title(for day: TaskCompletionDay, today: TaskCompletionDay, calendar: Calendar) -> String {
        if day == today { return String(localized: "Today") }
        let components = DateComponents(era: day.era, year: day.year, month: day.month, day: day.day, hour: 12)
        guard let date = calendar.date(from: components) else { return "" }
        let todayComponents = DateComponents(era: today.era, year: today.year, month: today.month, day: today.day, hour: 12)
        if let todayDate = calendar.date(from: todayComponents),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: todayDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        var style = Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: calendar.locale ?? .current,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .weekday(.abbreviated)
        .month(.abbreviated)
        .day()
        if day.year != today.year { style = style.year() }
        return date.formatted(style)
    }
}
