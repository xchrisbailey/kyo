# Moving tasks and habits to SwiftData

Status: Design confirmed. Built before Memos, which stores its memos in the same SwiftData store.

## Problem Statement

On iPhone and iPad, Kyo keeps every task, habit, check-off and habit schedule as JSON in UserDefaults (`kyo.dailyTasks.v1` and `kyo.habits.v1`). UserDefaults is meant for settings: Apple advises against keeping personal data there, and it isn't encrypted. Memos will need a real store for text, audio and photos, and iCloud sync between iPhone and iPad is planned later. ADR 0004 moves the phone's and iPad's own data to SwiftData, and tasks and habits move first, as their own change, so Memos starts on one store that is ready for iCloud.

## Solution

Tasks and habits move to a single SwiftData store in the app's own container, on iPhone and iPad only. The first launch after the update imports existing tasks and habits from UserDefaults in one save, and leaves the old keys in place as a backup for one release. The records that link a phone to its Watch (revision, tombstones, processed command ids) stay in UserDefaults under their current keys. The task and habit stores keep their behavior interfaces. SwiftData sits behind them, so views and Watch sync don't change. The Watch keeps its UserDefaults caches. Every model follows CloudKit's rules from day one, with `cloudKitDatabase: .none`. The user sees nothing: no migration screen, and Kyo looks and behaves the same afterwards. Terms follow `CONTEXT.md`: **Task**, **Habit**, **Habit schedule**, **Check-off**, **Log**.

## User Stories

1. As a Kyo user, I want every task, habit, check-off and schedule I already have to be there after the update, so that updating Kyo never costs me anything.
2. As a Kyo user, I want the update to happen without a migration screen or a wait, so that I just keep using the app.
3. As a Kyo user, I want my streaks and week progress unchanged after the update, so that my habit record stays continuous.
4. As a Kyo user, I want unfinished tasks to keep carrying forward and completed ones to stay on the day they were finished, as before.
5. As a Kyo user, I want my data kept somewhere suited to personal data rather than in app settings, so that it gets proper protection.
6. As an Apple Watch user, I want my Watch to keep syncing with the phone through and after the update, with no re-pairing and no duplicated or lost changes.
7. As a Kyo user whose update was interrupted, I want the next launch to finish the move without duplicating anything, so that a crash or a full disk can't damage my data.
8. As a Kyo user, I want my old data kept as a backup for a release, so that a problem in the move can still be recovered.
9. As a future iCloud user, I want my tasks and habits already stored in a way iCloud can sync, so that turning sync on later doesn't need another move.

## Implementation Decisions

### Scope and store

- On iPhone and iPad, tasks and habits move from UserDefaults to SwiftData. The Watch is unchanged: its mirror stores keep their UserDefaults caches and outbox, since they're copies of what the phone sends and iCloud sync will never include the Watch (ADR 0004). (#64)
- There is one SwiftData store for tasks, habits and, later, memos. It lives at the default location in the app's own container. There's no App Group, because the widget extensions don't read data. (#64)
- The store is opened with `ModelConfiguration(..., cloudKitDatabase: .none)`, so an unrelated iCloud entitlement can't switch sync on. (ADR 0004)
- The schema is declared as `KyoSchemaV1: VersionedSchema` with a `SchemaMigrationPlan` that has no stages yet. Memos adds a version later. The schema only ever adds. (ADR 0004)
- A single factory in `Shared/` builds the container, on disk or in memory. The app creates one container at launch and passes it to both phone stores. If the on-disk store can't be opened, the app stops with a `fatalError` that names the cause; the old UserDefaults keys are still intact in this release.
- UI tests that set `KYO_TASK_STORAGE_KEY` get a fresh in-memory container and skip the import, so each run is isolated as it is today.

### Model shape

- Four models, each mapping to the value types the stores already use (`DailyTask`, `Habit`, `HabitScheduleEntry`, check-off days):
  - **`TaskRecord`**: id, text, creation order, completion flag and completion day.
  - **`HabitRecord`**: id, name, manager order, creation day, and two to-many relationships: its check-offs and its schedule entries.
  - **`HabitCheckOffRecord`**: one per calendar day a habit was checked off, with the day and its habit.
  - **`HabitScheduleRecord`**: one per entry in a habit's schedule history, with the schedule and the day it took effect, and its habit.
- Each check-off and each schedule-history entry is its own record attached to its habit, not an array inside it, so later iCloud sync merges them record by record. (#64)
- Calendar days (completion, creation, check-off and effective-from days) are stored as flat integer fields: optional era, year, month and day, matching `TaskCompletionDay`. They are never stored as timestamps.
- A habit schedule is stored as flat fields: a kind (every day, weekdays or weekly target), a weekday list and a target. The `HabitSchedule` enum isn't stored as a Codable blob.
- Relationships are stored unordered, so order comes from data. Tasks sort by creation order, habits by manager order, schedule entries by their effective-from day (a habit has at most one entry per day), and check-offs by day.

### CloudKit rules

- Every model follows ADR 0004 from day one:
  - no `.unique` or `#Unique`;
  - every attribute has a default value or is optional;
  - every relationship is optional, with its inverse set;
  - no `.deny` delete rule.
- Deleting a habit cascades to its check-offs and schedule entries. (ADR 0004)
- Without unique constraints, app code removes duplicates by id. When loading, a second `TaskRecord` or `HabitRecord` with an id already seen is deleted. So is a second check-off for the same habit and day, or a second schedule entry for the same habit and effective-from day. (ADR 0004)

### Stores and the persistence seam

- `TaskListBehavior` and `HabitListBehavior` stay the same, as do the stores' published lists, their day-rollover methods and the `TaskListSync`/`HabitListSync` roles. Views and Watch sync code don't change. (#64)
- The stores keep working on their value types in memory. Only how content is loaded and saved changes. Each store takes an optional model container:
  - A phone or standalone store (`.publish` or no sync role) loads and saves its content through SwiftData and requires a container.
  - A Watch mirror store (`.mirror`) keeps its UserDefaults content and takes no container.
- Saving reconciles the store's current list with the stored records. It updates changed records, inserts new ones, deletes missing ones (including a habit's removed check-offs and replaced schedule entries), then calls `save()` once on the main context.
- A failed save is ignored, as a failed UserDefaults write is today: the in-memory list stays as it is, and the next change tries again.

### Watch-link records

- The phone's revision, tombstoned ids and processed command ids stay in UserDefaults under their current keys (`<storageKey>.revision`, `.tombstones`, `.processedCommands`, for both task and habit stores). They are local to one phone and its Watch, must never sync through iCloud, and stay byte-for-byte untouched by the move. (#64, ADR 0001–0003)
- No revision bump is needed. The phone publishes the same content at the same revision, and the Watch keeps what it has.
- When the phone applies a Watch command, it saves the content change before recording the command as processed. A crash between the two re-applies the command on redelivery. That's harmless: every command is an absolute state, and an add is skipped when its task id exists. A tombstone is still recorded before the deleted content is saved, so a late add can never bring a deleted task or habit back. (ADR 0002)

### One-time import

- On the first launch after the update, before the stores are created, existing tasks and habits are decoded from `kyo.dailyTasks.v1` and `kyo.habits.v1` with the current decoders and inserted into SwiftData in a single save. Decoding still upgrades older data (a habit saved before schedule history gets one entry). The stores' existing creation-day backfill still runs on load. (#64)
- A completed import is recorded in UserDefaults under `kyo.swiftDataImport.v1`, set only after the save succeeds. Later launches skip the import.
- A failed save rolls back, leaves the flag unset, and deletes nothing. The import is retried on the next launch. (#64)
- Running the import again never creates duplicates: a task or habit whose id is already in the store is skipped, which covers a crash between the save and the flag. (#64)
- A key that is missing imports nothing. A key that can't be decoded also imports nothing, matching today's stores, which show an empty list for undecodable data. Either way the import still counts as done.
- The old keys stay untouched for one release as a backup. Nothing writes to them after the import. A later release deletes them. (#64)
- The import reads only content keys, never the Watch-link records.
- The move is invisible: no migration screen, no progress, no message. (#64)

### Configuration

- Lasting target and build changes go in `project.yml`, and the checked-in project is regenerated. New `Shared/` files the tests need are added to the `KyoTests` target's source list.

## Testing Decisions

- Existing behavior tests (task list, habit list, order, edit and delete, streaks, and phone/Watch sync) run unchanged in what they assert. Their phone and standalone stores run on an in-memory SwiftData container instead of a UserDefaults suite. Watch mirror stores stay on UserDefaults suites. Assertions stay on observable lists and results through `TaskListBehavior` and `HabitListBehavior`, never on stored records.
- Reopen tests save, create a new store on the same in-memory container, and check that the same lists come back. This covers check-offs, schedule history, manager order, completion days and creation order.
- New import tests run against a UserDefaults suite holding saved data in the current format, plus an in-memory container:
  - tasks and habits come through intact, including check-offs, schedule histories, completion days and order, with the same Today lists, streaks and week progress as before;
  - the Watch-link records (revision, tombstones, processed command ids) are left byte-for-byte unchanged, and a phone store built afterwards publishes at the same revision;
  - the old content keys are left unchanged;
  - an import whose save fails leaves the flag unset and the keys intact, and the retry succeeds;
  - running the import twice, or again after a save that succeeded without setting the flag, creates no duplicates;
  - missing and undecodable keys import nothing and finish the import;
  - habits saved before schedule history or creation days were recorded come through with the same behavior they have today.
- A test seeds duplicate records directly (same task id, same habit id, same habit and day) and checks that loading shows each once.
- Build both app schemes. The Watch build must still compile `Shared/` with the SwiftData code it never runs.

## Out of Scope

- Memos and their models. They come in the Memos spec as a schema version that only adds.
- iCloud sync, CloudKit containers and entitlements. The store stays at `cloudKitDatabase: .none`.
- Moving the Watch's caches, the Watch outbox, or any Watch-link record off UserDefaults.
- Deleting the old UserDefaults keys. That happens in a later release.
- Any change a user can see, and any change to the snapshot or command formats sent between phone and Watch.
- An App Group or shared container for extensions.

## Further Notes

- Decisions trace to the Wayfinder map "Wayfinder: Memos" (#51): [Memo storage choice](https://github.com/xchrisbailey/kyo/issues/63), [Moving tasks and habits to SwiftData](https://github.com/xchrisbailey/kyo/issues/64), and ADR 0004.
- The work is delivered as three stacked tickets: tasks on SwiftData, then habits on SwiftData, then the import. They merge together, before any release, so no build ships with SwiftData stores but without the import.
- Execution: **Opus 5.5** (`claude-opus-5-5`) runs orchestration and owns review. Coding goes to **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`).
