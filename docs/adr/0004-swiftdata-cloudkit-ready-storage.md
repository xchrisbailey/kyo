# 4. SwiftData storage, ready for CloudKit

Status: accepted (tasks and habits implemented in #72, #73 and #74; written memos in #76 as `KyoSchemaV2`; voice audio and photos not yet)

## Context

Memos carry audio and up to 4 photos each and grow without limit. UserDefaults, where tasks and
habits live today, is meant for settings: Apple advises against keeping personal data there, and
it isn't encrypted. iCloud sync between iPhone and iPad is planned as a later effort, so whatever
store is chosen now has to make that move cheap.

## Decision

The phone's and iPad's own data moves to **SwiftData**. Memos start there, and tasks and habits
move there first, as their own change, before memos are built. The Watch keeps its small
UserDefaults caches: they are copies of what the phone sends, the phone stays the only writer
(ADR 0001–0003), and iCloud sync will never include the Watch.

**Audio and photos** are stored in SwiftData as `@Attribute(.externalStorage)` data, on separate
models attached to the memo, so listing and searching memos never loads media bytes. When iCloud
sync arrives, SwiftData syncs these as CloudKit assets with no extra code.

**Every model follows CloudKit's rules from day one:**

- no `.unique` or `#Unique`;
- every relationship optional, with its inverse set;
- no `.deny` delete rule;
- a schema that only ever adds.

Duplicates, such as a Watch recording delivered twice, are removed by id in app code. Until the
sync effort, the store is configured with `cloudKitDatabase: .none`, so an unrelated iCloud
entitlement can't switch sync on.

**Media formats:**

- Audio is AAC, mono, 48 kbps, about 3.6 MB for the full 10-minute cap, on both phone and Watch.
- Photos are stored as HEIC with the longest edge at 2048 px. The original isn't kept.

Memo content isn't indexed in system Spotlight.

## Considered options

- **SwiftData plus media as plain files.** Playback from a file is slightly simpler, but iCloud
  sync would later need a second sync system just for the files.
- **Memos only in SwiftData, tasks and habits left in UserDefaults.** Smaller now, but leaves
  personal text in UserDefaults and splits storage until the sync effort has to move it anyway.
- **Keeping full-resolution photos.** Several MB each, multiplied across iCloud storage and
  transfers, for no benefit inside a memo.

## Consequences

- Moving tasks and habits has to import existing UserDefaults data once, and keep the revisions,
  outbox, processed-command ids and tombstones that ADR 0001–0003 rely on.
- Without unique constraints, every place that can receive the same record twice (Watch
  commands, Watch recordings, and later iCloud) needs an explicit check by id.
- The schema can only grow. Renaming or removing a stored property later needs a migration plan
  that CloudKit accepts.
