import Foundation
import SwiftData

/// The stored form of a `Memo` on the phone and iPad. Follows docs/adr/0004: no unique
/// constraints (duplicates are removed by id in app code), every attribute has a default or is
/// optional, and the schema only ever grows. The day is stored as flat integer fields matching
/// `TaskCompletionDay`, never as a timestamp.
///
/// A voice memo adds a duration, a transcript state and a cap flag here, and its audio on a
/// separate `MemoAudioRecord`. Its transcript is `text`. Photos will be separate models too,
/// attached through optional relationships with inverses.
@Model
final class MemoRecord {
    var id: UUID = UUID()
    /// `Memo.Kind.rawValue`, stored as a string so a later kind needs no migration.
    var kindRaw: String = Memo.Kind.written.rawValue
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var dayEra: Int?
    var dayYear: Int = 0
    var dayMonth: Int = 0
    var dayDay: Int = 0
    /// A written memo's text, or a voice memo's transcript.
    var text: String = ""
    var durationSeconds: Double = 0
    /// `Memo.TranscriptState.rawValue` for a voice memo; empty for a written memo.
    var transcriptStateRaw: String = ""
    var stoppedAtCap: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \MemoAudioRecord.memo) var audio: MemoAudioRecord?

    init(
        id: UUID = UUID(),
        kind: Memo.Kind,
        createdAt: Date,
        day: TaskCompletionDay,
        text: String,
        durationSeconds: Double = 0,
        transcriptState: Memo.TranscriptState? = nil,
        stoppedAtCap: Bool = false
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.dayEra = day.era
        self.dayYear = day.year
        self.dayMonth = day.month
        self.dayDay = day.day
        self.text = text
        self.durationSeconds = durationSeconds
        self.transcriptStateRaw = transcriptState?.rawValue ?? ""
        self.stoppedAtCap = stoppedAtCap
    }

    var kind: Memo.Kind {
        Memo.Kind(rawValue: kindRaw) ?? .written
    }

    var day: TaskCompletionDay {
        TaskCompletionDay(era: dayEra, year: dayYear, month: dayMonth, day: dayDay)
    }

    var transcriptState: Memo.TranscriptState? {
        get { Memo.TranscriptState(rawValue: transcriptStateRaw) }
        set { transcriptStateRaw = newValue?.rawValue ?? "" }
    }

    var memo: Memo {
        Memo(
            id: id,
            kind: kind,
            createdAt: createdAt,
            day: day,
            text: text,
            duration: durationSeconds,
            transcriptState: kind == .voice ? (transcriptState ?? .noTranscript) : nil,
            stoppedAtCap: stoppedAtCap
        )
    }
}
