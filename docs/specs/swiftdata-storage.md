# Moving tasks and habits to SwiftData

Status: Product behavior confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Kyo keeps every task and habit, with each habit's schedule history and log, as JSON in UserDefaults on iPhone and iPad (`kyo.dailyTasks.v1` and `kyo.habits.v1`). UserDefaults is meant for settings: Apple advises against keeping personal data there, and it isn't encrypted. Memos are coming next, with audio and photos that grow without limit, and they can't live in UserDefaults at all. iCloud sync between iPhone and iPad is planned for later, and the storage chosen now has to make that move cheap. If memos went into SwiftData while tasks and habits stayed behind, Kyo would have two storage systems until the sync effort had to move them anyway.

## Solution

On iPhone and iPad, tasks and habits move from UserDefaults to one SwiftData store, the same store memos will use. The first launch after the update imports existing tasks and habits from UserDefaults into SwiftData in a single save, and leaves the old keys in place for one release as a backup. The models follow CloudKit's rules from day one, with sync switched off, so a later iCloud effort doesn't need a schema rewrite. `TaskListStore` and `HabitListStore` keep their interfaces, with SwiftData behind them, so the views and the Watch sync code don't change. The records that tie a phone to its Watch (revisions, tombstones, processed command ids) stay in UserDefaults. The Apple Watch keeps its UserDefaults caches as they are. Users see no change. Terms follow `GLOSSARY.md`: **Task**, **Habit**, **Habit schedule**, **Check-off**, **Log**, **Streak**, **Week progress**.

## User Stories

1. As a Kyo user, I want all my tasks, including unfinished ones carried forward and completed ones, to still be there after the update, so that updating never costs me data.
2. As a Kyo user, I want my habits to keep their names, order and schedules after the update, so that Today and the habit manager look the same as before.
3. As a Kyo user, I want every check-off in a habit's log to survive the update, so that my streaks and week progress don't reset.
4. As a Kyo user, I want a habit's past schedules to survive the update, so that past days are still judged by the schedule they had.
5. As a Kyo user, I want the update to need nothing from me, with no migration screen or prompt, so that I can open Kyo and carry on.
6. As a Kyo user, I want Kyo to try the move again next time if it fails, without losing or doubling anything, so that a bad launch doesn't damage my data.
7. As a Kyo user, I want my tasks and habits never to appear twice, however many times the app is launched during the move.
8. As a Kyo user, I want my old data to stay on the device for a while after the update, so that a problem in the new storage can still be recovered from.
9. As an Apple Watch user, I want my Watch to keep showing the same tasks and habits right after the phone updates, and keep accepting my changes, so that the Watch doesn't need re-pairing or a fresh sync.
10. As an Apple Watch user, I want changes I made on the Watch just before the phone updated to still reach the phone exactly once, so that nothing is lost or applied twice.
11. As a Kyo user, I want a task or habit I deleted before the update to stay deleted, even if the Watch sends a late change for it.
12. As a Kyo user, I want my tasks and habits kept in storage meant for personal data rather than in app settings.
13. As a Kyo user who will later use iCloud sync between iPhone and iPad, I want today's storage to be ready for it, so that turning sync on later doesn't need another move.
14. As a Kyo developer, I want the existing task and habit behavior tests to keep passing against an in-memory SwiftData store, so that the move is proven not to change behavior.
15. As a Kyo developer, I want memos to build on a store that already holds tasks and habits, so that the Memos work starts from one storage system.

## Implementation Decisions

### Scope

- On iPhone and iPad, tasks and habits move from UserDefaults to SwiftData. The Watch keeps its UserDefaults caches unchanged. (#64, ADR 0004)
- All user content moves to SwiftData: tasks, habits, check-offs and schedule history. (#64)
- The Watch's caches stay in UserDefaults because they are copies of what the phone sends, the phone stays the only writer (ADR 0001–0003), and iCloud sync will never include the Watch. (ADR 0004)

### Watch-link records

- The records that tie one phone to its Watch stay in UserDefaults: the revision, tombstones, processed command ids and any outbox. They are local to one phone and its Watch and must never sync through iCloud. (#64)
- On the phone these are the keys `TaskListStore` and `HabitListStore` derive from their storage keys today, and they keep those names so nothing resets on update: `kyo.dailyTasks.v1.revision`, `.tombstones` and `.processedCommands`, and the same three suffixes on `kyo.habits.v1`. The `.outbox` keys are used only by the Watch's `.mirror` stores. (ADR 0001–0003, ADR 0004)
- The revisions, outbox, processed command ids and tombstones that ADR 0001–0003 rely on are kept across the move, so the phone's next snapshot continues from its current revision and a late or duplicated Watch command is still deduped or blocked by its tombstone. (ADR 0004)

### Import

- On the first launch after the update, existing tasks and habits are imported from `kyo.dailyTasks.v1` and `kyo.habits.v1` into SwiftData in a single save. (#64)
- The old keys stay untouched for one release as a backup. A later release deletes them. (#64)
- A failed import is retried on the next launch and deletes nothing. Running the import again never creates duplicates. (#64)
- SwiftData has no unique constraints here (see below), so the import's duplicate protection is an explicit check by id in app code. (ADR 0004)
- Nothing changes for the user: there's no migration screen, and everything looks the same afterwards. (#64)

### Model shape

- Each check-off and each schedule-history entry is its own record attached to its habit, not an array inside it, so later iCloud sync can merge them record by record. (#64)
- Every model follows CloudKit's rules from day one (#64, ADR 0004):
  - no `.unique` or `#Unique`;
  - every relationship optional, with its inverse set;
  - no `.deny` delete rule;
  - a schema that only ever adds.
- Duplicates are removed by id in app code. Every place that can receive the same record twice (the import, Watch commands, and later iCloud) needs an explicit check by id. (ADR 0004)
- Until the sync effort, the store is configured with `cloudKitDatabase: .none`, so an unrelated iCloud entitlement can't switch sync on. (#64, ADR 0004)
- Because the schema can only grow, renaming or removing a stored property later needs a migration plan that CloudKit accepts. (ADR 0004)

### Store structure

- One SwiftData store holds tasks, habits and memos, in the app's own container. There's no App Group, because the widget extensions don't read data. Memo models aren't part of this spec; they arrive with the Memos spec. (#64)
- The existing task and habit store interfaces stay the same, with SwiftData behind them, so views and the Watch sync code don't change. That covers `TaskListBehavior` and `HabitListBehavior`, the stores' published lists and `refreshForCurrentDay()`/`refreshAtEachDayBoundary()`, the `TaskListSync`/`HabitListSync` roles, and the snapshot, command and transport types in `Shared/TaskSync.swift`, `Shared/HabitSync.swift` and `Shared/WatchConnectivityTaskTransport.swift`. (#64)
- The same store classes run on both devices: `TaskListStore` and `HabitListStore` are `.publish` stores on the phone (`TodayView`) and `.mirror` stores on the Watch (`WatchTodayView`). Only the phone's content moves to SwiftData. The Watch's `.mirror` stores keep reading and writing `baseTasks`/`baseHabits`, the outbox and the revision in UserDefaults exactly as today. (#64, ADR 0004)
- Snapshots keep carrying the same `DailyTask` and `Habit` values, and the habit snapshot keeps its trimmed log, so the Watch receives exactly what it does today. (#64, ADR 0003)

### Decided during spec review

- **Import marker.** A successful import sets a UserDefaults flag (`kyo.swiftDataImport.v1.done`) after the SwiftData save succeeds. The import runs only while the flag is absent. A deleted task or habit therefore can't come back from the backup, and a failed import leaves the flag unset so it's retried. (#65)
- **The backup is frozen.** Once the import succeeds, the phone never writes task or habit content to `kyo.dailyTasks.v1` or `kyo.habits.v1` again, so the backup is the data from before the update. (#65)
- **A store that fails to open.** The phone shows a blocking "Kyo couldn't open your data" screen with **Try again**. It never creates a fresh empty store in place of one it couldn't open. (#65)
- **Store initializers.** The store classes get a persistence seam: SwiftData on the phone and iPad (`.publish` and standalone), UserDefaults on the Watch (`.mirror`). The behavior interfaces don't change. The `ModelContainer` is created once at app launch in `KyoApp` and handed to the stores. (#65)
- **Tests and UI tests.** Unit tests use a fresh in-memory `ModelContainer` per test. UI tests launch with an environment flag that selects an in-memory store, which replaces `KYO_TASK_STORAGE_KEY` on the phone. The Watch keeps its key-based isolation. (#65)
- **Stored formats.** Calendar days (completion days, check-offs, schedule-entry start days) are stored as their era, year, month and day integer fields, matching `TaskCompletionDay`, so no time-zone conversion is involved. A schedule is stored as a kind, a weekday bitmask and a weekly target. Order fields stay `Int64`. (#65)
- **Schema versioning.** The schema starts as `VersionedSchema` V1 with a `SchemaMigrationPlan`, so later additions (memos, iCloud sync) are explicit, additive versions. (#65)

## Testing Decisions

- Keep the existing behavior-testing boundary: `TaskListBehavior`, `HabitListBehavior` and the phone/Watch sync tests. The existing behavior tests run against an in-memory SwiftData store. Assert observable lists, groups, streaks, week progress and sync results, not storage layout. (#64)
- Add import tests, starting from UserDefaults data saved in the current format (#64):
  - tasks and habits, including check-offs and schedule history, are imported and present the same lists, streaks and week progress as before;
  - the Watch-link records (revision, tombstones, processed command ids) survive the import intact;
  - an import that fails is retried on the next launch, and nothing was deleted;
  - running the import twice creates no duplicates.
- Verify persistence by saving changes and reopening the stores against the same test storage, as the current tests do with a UserDefaults suite.
- Keep the phone and Watch sync tests with a controllable transport (`ControllableTaskTransport`, `ControllableHabitTransport`): the phone side on SwiftData, the Watch side on UserDefaults. Don't mock the behavior under test.
- Build both app schemes. Check real paired-device delivery after the move in a paired simulator or on devices, using `WatchSyncSmokeUITests`.

## Out of Scope

- Implementing the move as part of this specification request.
- Memo models, media storage and memo sync. They're in the Memos spec, which builds on this store.
- iCloud sync between iPhone and iPad, and any CloudKit container or entitlement. The store ships with `cloudKitDatabase: .none`.
- Changing the Watch's storage. Its UserDefaults caches stay as they are.
- Moving the Watch-link records (revisions, tombstones, processed command ids, outboxes) to SwiftData.
- Deleting the old `kyo.dailyTasks.v1` and `kyo.habits.v1` keys. A later release does that.
- An App Group or shared container for widget extensions.
- Any user-visible change, including a migration or progress screen.
- Changes to task or habit behavior, the snapshot formats, or the Watch commands.

## Further Notes

- Decisions trace to the Wayfinder map "Wayfinder: Memos" (#51), mainly [Moving tasks and habits to SwiftData](https://github.com/xchrisbailey/kyo/issues/64) and [Memo storage choice](https://github.com/xchrisbailey/kyo/issues/63), and to `docs/adr/0004-swiftdata-cloudkit-ready-storage.md`. Watch sync that must keep working is in `docs/adr/0001-*`, `0002-*` and `0003-habit-sync.md`.
- Ordering: this spec must be implemented and merged **before** any work from the Memos spec (`docs/specs/memos.md`) starts, because memos live in the store this spec creates.
- The release that deletes the old keys must only touch the phone and iPad. On the Watch, `kyo.dailyTasks.v1` and `kyo.habits.v1` are the `.mirror` stores' live caches, not a backup.
- Execution policy for future implementation: **Opus 5.5** (`claude-opus-5-5`) runs orchestration and owns review; the coder assignment is **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`), per `AGENTS.md`.
- No implementation agents should be launched by this spec-writing request. The `ready-for-agent` label describes specification readiness; it doesn't authorize implementation.
