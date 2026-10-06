import Foundation

/// What the iOS share sheet receives for a **Memo**: its text and its photos, never its audio.
///
/// The text is the title, a blank line, then the body (a Written memo's text after its first
/// line, or a Voice memo's **Transcript**). A Voice memo that is Transcribing or has No transcript,
/// and a photo-only memo, have no text and share only their photos.
struct MemoSharePayload: Equatable, Sendable {
    /// The text to share, or `nil` when the memo shares only its photos.
    let text: String?
    /// The stored copy of each photo, in the order the memo has them.
    let photos: [Data]

    /// `true` when there is nothing to share.
    var isEmpty: Bool { text == nil && photos.isEmpty }

    /// The payload for `memo`. `currentText` is the memo's text as it stands in the open card, and
    /// `photos` its photo bytes (a photo that couldn't be read is left out).
    ///
    /// A fallback title uses the time-stamped form, "Voice memo · 9:41 AM", formatted for
    /// `locale` in `timeZone`. The bare form is only for rows that show a time column.
    static func make(
        for memo: Memo,
        currentText: String,
        photos: [Data],
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> MemoSharePayload {
        MemoSharePayload(
            text: text(for: memo, currentText: currentText, locale: locale, timeZone: timeZone),
            photos: photos
        )
    }

    /// The payload for `memo`, reading each photo's bytes through `loadPhoto` only now. The open
    /// card and a memo row both build their share items through this, so they send the same thing.
    static func make(
        for memo: Memo,
        currentText: String,
        loadPhoto: (UUID) -> Data?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> MemoSharePayload {
        make(
            for: memo, currentText: currentText, photos: memo.photoIDs.compactMap(loadPhoto),
            locale: locale, timeZone: timeZone
        )
    }

    /// Whether a memo row offers Share: `canShare` for the memo as saved, with no open editor.
    /// A Written memo's text and a Voice memo's Transcript are the memo's own `text`, which is
    /// what the open card starts from.
    static func canShare(_ memo: Memo) -> Bool {
        canShare(memo, currentText: memo.text)
    }

    /// Whether Share is available for `memo`: it has shareable text or at least one photo. Reads
    /// no photo bytes, so the card can ask it while it is open.
    static func canShare(_ memo: Memo, currentText: String) -> Bool {
        text(for: memo, currentText: currentText) != nil || !memo.photoIDs.isEmpty
    }

    static func text(
        for memo: Memo,
        currentText: String,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        switch memo.kind {
        case .written:
            let (title, body) = split(currentText)
            guard !title.isEmpty else { return nil }
            return joined(title: title, body: body)
        case .voice:
            guard memo.transcriptState == .transcribed else { return nil }
            let transcript = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return nil }
            let title = memo.voiceTitle.isEmpty
                ? timeStamped(Memo.voiceFallbackTitle, at: memo.createdAt, locale: locale, timeZone: timeZone)
                : memo.voiceTitle
            return joined(title: title, body: transcript)
        }
    }

    /// "Voice memo · 9:41 AM", with the time in the user's locale and time zone.
    static func timeStamped(_ title: String, at date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        return "\(title) · \(date.formatted(style))"
    }

    private static func joined(title: String, body: String) -> String {
        body.isEmpty ? title : "\(title)\n\n\(body)"
    }

    /// A Written memo's first non-blank line, trimmed, and everything after it with its line
    /// breaks kept and the surrounding blank space removed.
    private static func split(_ text: String) -> (title: String, body: String) {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)[...]
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines = lines.dropFirst()
        }
        guard let first = lines.first else { return ("", "") }
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (first.trimmingCharacters(in: .whitespaces), body)
    }
}
