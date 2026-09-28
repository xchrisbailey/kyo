# 2. Watch commands and phone-side reconciliation

## Context

ADR 0001 made the phone the sole writer and the Watch a read-only mirror of phone-published
snapshots. Issue #14 asks the Watch to originate its own changes — adding tasks and
completing/reopening them — while the phone stays the single source of truth for the
synchronized list, so that both devices keep converging without duplication or resurrection.

The phone can't simply accept Watch-authored full-list snapshots: two independent writers
publishing competing full lists would need per-field merge logic ADR 0001 explicitly avoided,
and would reopen exactly the resurrection risk (a phone deletion undone by a stale Watch list)
that issue #14 calls out. Editing and deleting on Watch remain out of scope, which keeps the
set of Watch-originated mutations small enough to model as commands rather than full lists.

## Decision

The phone remains the only writer of the synchronized list. The Watch sends **commands**
describing the two mutations it's allowed to make; the phone applies them, and the phone's
next snapshot carries the result back.

**`TaskCommand`** (`Shared/TaskSync.swift`) has its own `id: UUID`, separate from any task id,
used purely for idempotency under retry and duplicate delivery. Its action is one of:

- `add(taskID:text:)` — trimmed, nonblank text; no `creationOrder`. The phone assigns the
  order on receipt, so a Watch add always sorts after whatever the phone already has at the
  moment it's applied — the phone's own adds are never reordered by a Watch add racing in.
- `setCompletion(taskID:isComplete:completedOn:)` — the *absolute* resulting state, computed
  from the Watch's own clock/calendar when the toggle happens (not "toggle whatever the phone
  currently has"), so completion-day retention follows the day the Watch believes it is,
  matching how the phone computes its own completion day.

**Delivery.** Commands travel over `WCSession.transferUserInfo`, which queues and delivers
reliably even while the counterpart is unreachable — unlike `applicationContext`, which is
correct for "latest full list wins" snapshots but would silently drop a command sent while the
phone was unreachable. `WatchConnectivityTaskTransport` buffers outgoing commands until the
session activates, and cancels any outstanding transfer of the same command id before
retransmitting so a retry doesn't pile up duplicate transfers in the queue.

**Phone-side application, per command, in receipt order:**

1. If the command's id is already in the phone's persisted processed-command-id set, ignore it
   entirely — it was already applied and acknowledged.
2. Otherwise apply it:
   - `add`: ignored (no task created) if a task with that id already exists, or if the id is in
     the phone's persisted tombstone set (see below). Otherwise appended with
     `creationOrder = phone's current max + 1`.
   - `setCompletion`: ignored if no task with that id exists. Otherwise the task's
     `isComplete`/`completedOn` are set exactly to the command's values.
3. Record the command id in the processed set (even if step 2 ignored it — an ignored command
   still needs to be acknowledged so the Watch can retire it from its outbox) and persist.
4. Publish a new snapshot (new revision) whose `acknowledgedCommandIDs` is the full processed
   set.

Deleting a task (still phone-only) adds its id to a persisted **tombstone** set. Both the
processed-command-id set and the tombstone set are bounded to their most recent 500 entries
(insertion order) so neither grows without bound over an install's lifetime, and both are
persisted under keys derived from the store's `storageKey`, the same way the revision is.

**Reconciliation rule for overlaps:**

> The phone applies its own locally-performed changes and Watch commands strictly in the order
> it receives or performs them. Last applied wins per task. Deletion is final: a tombstoned
> task id can never be recreated by a later or duplicated `add`, and a deleted task simply has
> no entry for a `setCompletion` to find. The phone's next published snapshot carries this
> result to the Watch; the Watch never resolves a conflict itself.

This is a direct extension of ADR 0001's single-writer model: the phone was already the only
device that mutates the authoritative list, and command application is just another kind of
phone-side mutation (alongside its own `addTask`/`editTask`/`deleteTask`/`toggleTask` calls)
that happens to be triggered by an incoming message instead of a local UI action.

**Watch-side state.** A `.mirror` `TaskListStore` keeps two persisted pieces instead of one:

- `baseTasks` — the tasks from the last snapshot it applied (this reuses the Watch's existing
  storage key/schema from ADR 0001 unchanged; only the meaning of "the list stored there"
  narrows from "the whole mirrored list" to "the base before local outbox replay").
- `outbox: [TaskCommand]` — its own ordered, not-yet-acknowledged commands, persisted under a
  new key derived from the same storage key.

The Watch's visible and saved tasks are always `outbox` replayed over `baseTasks`, using the
same rules the phone uses to apply a command (add appends with current max order + 1 if absent;
setCompletion sets the given state if present). `addTask`/`toggleTask` build a command, append
it to the outbox, recompute, persist, and send it; they return the resulting task the same way
the phone's methods do. `editTask`/`deleteTask` on a `.mirror` store did nothing and returned
`nil` in #14, which kept them out of scope; #21 (below) adds their commands.

On receiving a snapshot, the Watch always drops any outbox entries whose ids appear in the
snapshot's `acknowledgedCommandIDs`, regardless of whether the snapshot's revision is new
enough to replace `baseTasks` — an ack means the phone has already resolved that command, so
there's no reason to keep resending it. `baseTasks` itself is only replaced when the revision
is strictly newer, exactly as ADR 0001 already specified. On store creation, after both
handlers are registered, the Watch resends every command still in its outbox as a retry;
duplicate delivery is harmless because the phone dedupes by command id.

## Rejected alternatives

- **Watch also publishes full-list snapshots (two writers, merge by revision or per-field
  last-writer-wins).** Requires inventing tie-breaking for concurrent edits to the same task
  from both sides and per-task metadata ADR 0001 deliberately avoided. It also reopens the
  resurrection problem: a Watch snapshot built before it learned about a phone deletion could
  republish the deleted task. Commands avoid this because the phone alone decides whether a
  command still applies against its current (possibly newer) state, including tombstones.
- **`sendMessage` for commands.** Same objection as ADR 0001's rejection of it for snapshots:
  requires the phone to be immediately reachable, and Watch/phone connectivity is intermittent
  by nature. `transferUserInfo`'s queuing is exactly the "survive disconnection, retry on
  reconnect" behavior commands need.
- **Unbounded processed-command-id / tombstone sets.** Correct but grows forever on a
  long-lived install with no benefit past a point; retaining the most recent 500 of each is
  enough to dedupe realistic retry/reconnect windows without unbounded storage growth.

## Consequences

- Editing and deleting were phone-only when this ADR was first written; #21 adds them to the
  Watch (see "#21: rename and delete commands" below).
- The phone's tombstone and processed-command-id sets are bounded, so an extremely long
  disconnection (thousands of intervening commands, or a task deleted and outliving 500 later
  deletions) could theoretically let a very stale duplicate slip through. This is judged
  acceptable for a personal two-device sync feature, the same way ADR 0001 accepted the
  reinstalled-phone clock edge case.
- Watch-originated adds always sort after the phone's own tasks at the moment they're applied,
  even if the Watch add happened first in wall-clock time. This is a deliberate, deterministic
  tie-break (see ADR 0001's and this ADR's ordering rule) rather than an attempt to preserve
  true chronological order across devices with independent clocks.

## #21: rename and delete commands

The Watch can now edit and delete tasks through the same outbox, retry, and acknowledgment
mechanism.

**New actions.** `TaskCommand.Action` gains `rename(taskID, text)`, which carries the full
trimmed, nonblank new text, and `delete(taskID)`. Adding enum cases keeps the synthesized
`Codable` compatible with outboxes persisted before this change. The phone and Watch apps ship
together (the Watch app is embedded), so an older phone never has to decode the new cases, and
no compatibility machinery is built for that.

**Phone application** (receipt order, dedupe by command id, every command acknowledged, exactly
as before):

- `rename` replaces the text of an existing task when the trimmed text is nonblank, keeping id,
  creation order, completion state, and completion day. Otherwise it is ignored. Renames follow
  the existing rule: the last applied wins, so a Watch rename that arrives after a phone rename
  overwrites it, and a phone rename made after the Watch rename was delivered overwrites that.
- `delete` removes the task if present and always records the tombstone, even when the task is
  already absent, so a later or duplicated `add` cannot recreate it.
- Delete wins in both arrival orders. A phone rename or toggle made after the delete arrives
  finds no task and does nothing; a phone change made before it is overwritten by the removal.
  A phone delete makes a later Watch `rename` or `delete` a no-op that is still acknowledged.

**Watch replay.** `editTask` returns `nil` and sends nothing for blank text or for an id absent
from the effective (replayed) list; `deleteTask` returns `nil` for an absent id. Otherwise each
appends its command to the outbox, recomputes, persists, and sends. Replay applies `rename` to a
present task and `delete` by removing it. Replay also keeps a local set of ids deleted so far
in that replay, mirroring the phone's tombstones: a later replayed `add` for a deleted id is a
no-op. This covers a task added and deleted on the Watch before the phone acknowledges the add.
The phone applies the add and then the delete in FIFO order and ends up tombstoned, and neither
device may show the task at any point after the delete, including when a snapshot that contains
the task acknowledges only the add (the outbox then holds just the `delete`, which removes it).
