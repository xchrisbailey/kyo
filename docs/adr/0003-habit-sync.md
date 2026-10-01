# 3. Habit sync: separate snapshot, trimmed log, shared context write

Status: accepted (design for the Habits spec; not yet implemented)

## Context

Habits need to reach the Watch the same way tasks do (ADR 0001 and 0002), with check-offs from
the wrist. Two facts rule out simply copying the task design:

- `WCSession.updateApplicationContext` replaces the whole context dictionary on every call. The
  task snapshot is currently the only key, so a separate habit publish would erase it, and the
  reverse.
- The phone app usually isn't running at midnight. A Watch that only receives a ready-made
  "today's habits" view would keep showing yesterday's list until the phone app opens again.
  Tasks avoid this because the Watch can roll them over by itself. Habits need schedules and
  log data to work out what is due today and what a streak is.

## Decision

The phone stays the only writer, as in ADR 0001 and 0002. Habits get their **own snapshot and
revision**, separate from tasks, under their own context key. The transport keeps the latest
snapshot of each kind and always writes **both keys in a single `updateApplicationContext`
call**, so publishing one never drops the other.

The habit snapshot carries every habit (id, name, manager order, dated schedule history) and a
**trimmed log**: only the check-offs needed to reproduce each habit's current streak and this
week's week progress. That set is enough because, from then on, a streak can only grow by one
more due day or week, or break. Check-offs from before the current streak can't change what the
Watch computes. The Watch works out Today's due habits, done group, streaks, and week progress
with the same rules code in `Shared/` that the phone uses, so it stays correct across midnight
without hearing from the phone.

The Watch sends one command over `transferUserInfo`: **set check-off** (habit id, calendar day,
checked or not), an absolute state like the task `setCompletion` command. The day is the Watch's
local calendar date when the user tapped. The phone accepts the stated day even when the command
arrives late. Commands use ADR 0002's outbox, retry, dedupe-by-command-id, and acknowledgment
machinery. The Watch replays its unacknowledged commands over the last snapshot so a tap shows up
immediately.

Phone-side application, in arrival order, last applied wins:

- A check-off for a deleted habit is ignored but still acknowledged. Deleted habit ids are
  tombstoned so a late command can't bring a habit back.
- A check-off that arrives after a schedule edit is still recorded. The dated schedule history
  decides whether that day counts toward the streak.
- Habit creation, edits, reordering, and deletion happen only on the phone and reach the Watch
  in the next snapshot.

## Considered options

- **One combined Today snapshot (tasks and habits, one revision).** Ties two unrelated stores to
  a single clock and payload for no benefit beyond sharing the context write, which the
  transport handles anyway.
- **Full log in every snapshot.** Simplest, but the payload grows without limit over years and
  WatchConnectivity's context size limit isn't clearly documented.
- **Ready-made today's view.** Goes stale at midnight until the phone app runs.
- **Two writers.** Rejected for the same reasons as in ADR 0002.

## Consequences

- Very long streaks make the trimmed log larger (a multi-year daily streak carries one date per
  day). This is judged acceptable. If it ever matters, the snapshot can carry a streak count up
  to a date in place of the oldest check-offs without changing the reconciliation rule.
- Streak, due-today, and week-progress rules must stay in `Shared/` and behave identically on
  both devices. A rule that diverged would make the two devices disagree.

## #41: Watch check-off implementation

`HabitCommand` (`Shared/HabitSync.swift`) has its own `id` and one action,
`setCheckOff(habitID:day:isCheckedOff:)`. It travels over `transferUserInfo` under its own key
(`kyo.habitCommand`) through the same transport queueing and buffering as task commands.
`HabitListSnapshot` gains `acknowledgedCommandIDs`, decoding missing as empty.

The phone (`.publish`) store applies commands in arrival order and records the stated day even
when it is late. It keeps persisted, bounded (500) sets of processed command ids and deleted
habit ids, under keys derived from its `storageKey`, like the task store. Every command is
acknowledged, including one for a deleted or unknown habit, which changes nothing. Habits are
only ever created on the phone, so a tombstone never has a recreation to block today; it is
checked anyway, so no later change can bring a deleted habit back through a command.

The Watch (`.mirror`) store keeps `baseHabits` (the last snapshot, under the existing storage
key) and a persisted outbox. Its visible habits are the outbox replayed over `baseHabits`
(set the day's check-off state if the habit exists). Acknowledgments retire outbox entries
whatever the snapshot's revision, and the outbox is resent when the store is created. The Watch
validates a tap like the phone does: only a habit on Today's list, which includes one an edit
made not due that still has Today's check-off.
