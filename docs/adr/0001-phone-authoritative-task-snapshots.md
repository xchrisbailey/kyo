# 1. Phone-authoritative task snapshots over WatchConnectivity

## Context

Hoy's daily task list (`TaskListStore` in `Shared/DailyTask.swift`) is saved to UserDefaults on
each device. Issue #13 asks the Watch to show the same list the phone maintains: additions,
edits, deletions, completion changes, and day rollover should all appear on Watch, without
duplicating or resurrecting tasks under repeated or out-of-order delivery. Issue #14 (not
implemented here) will let the Watch originate its own changes.

This is the first ADR in the repo; `docs/agents/domain.md` says architecture decisions belong in
`docs/adr/`.

## Decision

The phone is the only writer. The Watch is a read-only mirror in this slice.

Delivery uses WatchConnectivity's `applicationContext`: after every saved change, the phone calls
`WCSession.updateApplicationContext(["hoy.taskSnapshot": <JSON Data>])` with a
`TaskListSnapshot(revision:tasks:)`, where `tasks` is the phone's current-day list. The system
keeps only the latest context, dropping anything superseded before delivery, which matches
"latest full list wins" exactly. On launch, the Watch also reads
`session.receivedApplicationContext` directly, in case a context arrived before the Watch had a
handler registered.

The revision is a hybrid logical clock, so it is comparable across restarts and reinstalls
without a shared counter:

```
revision = max(previousRevision + 1, Int64(now().timeIntervalSince1970 * 1000))
```

The phone persists this revision under `"\(storageKey).revision"`, stored as `NSNumber(value:
Int64)` and read back via `(object(forKey:) as? NSNumber)?.int64Value` — never `Int`, which is
32-bit on arm64_32 watchOS. A fresh install or a reset UserDefaults suite has no stored revision;
the phone seeds one from the wall clock (`Int64(now().timeIntervalSince1970 * 1000)`) and
persists it before its first publish, rather than publishing at revision 0 forever, which a
Watch holding a higher revision from a previous install would ignore indefinitely.

The phone republishes its current snapshot at the same revision on store creation, on
`WCSession` activation, and on `sessionWatchStateDidChange`, so a Watch that connects or
reconnects gets caught up even without a new phone-side change.

**Reconciliation rule:**

> The Watch applies an incoming snapshot only if its revision is strictly greater than the last
> revision it applied, or if it has never applied one. Applying a snapshot replaces the Watch's
> stored task list with the snapshot's tasks. Otherwise the snapshot is ignored. Each device
> works out its visible day from its stored list and its own clock.

On the Watch, applying a snapshot writes the tasks first and the revision second, so a crash
between the two leads to an idempotent re-apply (the same snapshot is simply re-applied, which is
harmless) rather than a state where the revision has advanced but the tasks have not.

Day rollover sends no message. Each device calls `refreshForCurrentDay()` against its own clock;
the Watch does this on scene activation and via `TaskListStore.refreshAtEachDayBoundary()`, the
same mechanism the phone uses. A completed task that rolled off the visible list on one device
and a task added after rollover on the other reconcile correctly the next time either side
publishes, because the snapshot always carries the full list, not a delta.

## Rejected alternatives

- **Per-task last-writer-wins plus tombstones.** Correct for concurrent multi-writer edits, but
  this slice has exactly one writer (the phone). A single incrementing revision on a full
  snapshot is simpler and gives the same convergence guarantees the tests require (no
  duplication, no resurrection) without needing per-task metadata or tombstone garbage
  collection.
- **`transferUserInfo` for snapshots.** Queues and guarantees delivery of every message, which is
  wrong for full-list sync: we want the latest list, not a replay of every historical snapshot.
  `applicationContext`'s "keep only the latest" behavior is exactly the desired semantics.
- **`sendMessage`.** Requires the counterpart to be immediately reachable and fails otherwise;
  Watch/phone connectivity is intermittent by nature, and a snapshot that fails to send here
  would simply be lost instead of waiting for the next successful context update.

## Consequences

- Sync covers only the current day's list, matching everything else in `TaskListStore`.
  Historical days are out of scope.
- The hybrid clock assumes each device's wall clock does not move backwards relative to its own
  prior writes. If a phone is reinstalled and its clock is set to a time earlier than what the
  Watch last saw, the reinstalled phone's snapshots could be ignored as stale until its clock (or
  its revision, via new writes) catches back up. This is judged an acceptable edge case for a
  personal two-device sync feature.
- Until #14, any local mutation attempted on the Watch (there is none in this slice's UI, but the
  mutation methods still work if called) would be silently overwritten by the next phone
  snapshot, since the Watch never publishes.
- **Extension for #14:** the Watch will send commands (add, toggle) through `transferUserInfo`,
  which queues reliably even while the phone is unreachable. The phone will keep tombstones for
  deletions and a Watch-side outbox so that Watch-originated commands survive being sent before
  the phone is reachable, and so that a late-arriving Watch command cannot resurrect a task the
  phone has since deleted.
