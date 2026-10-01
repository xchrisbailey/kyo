# Habits on iPhone, iPad, and Apple Watch

Status: Product behavior confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Kyo presents one day at a time, but its Habits section still shows fixed sample rows ("Morning walk · 20 min") on iPhone, iPad, and Apple Watch, and the "Habits done" summary is hard-coded. Users can't define a habit, say which days it's due, check it off, or see whether they're keeping it up.

## Solution

Make Habits a real feature within the existing layout. A user adds a habit from the bottom Add menu and gives it a habit schedule: every day, specific weekdays, or a weekly target (N times per week). Each day, Today's Habits section lists the habits due that day for the user to check off. Every check-off is logged, and each row shows light feedback: a streak, or week progress for weekly targets. Habits are managed in a new Settings sheet. The Watch shows the same list and can check habits off. Terms follow `CONTEXT.md`: **Habit**, **Habit schedule**, **Weekly target**, **Check-off**, **Log**, **Streak**, **Week progress**.

## User Stories

1. As a Kyo user, I want to add a habit from the bottom Add button, so that habits and tasks start from the same place.
2. As a Kyo user, I want to give a habit a schedule of every day, specific weekdays, or a number of times per week, so that it matches how often I mean to do it.
3. As a Kyo user, I want Today to list only the habits due today, so that the section reflects today's commitments.
4. As a Kyo user, I want a weekly-target habit to show every day until I've done it enough times that week, so that I can fit it in on any day.
5. As a Kyo user, I want to check off a habit, so that I record doing it today.
6. As a Kyo user, I want to uncheck a habit, so that I can fix an accidental tap without leaving a trace.
7. As a Kyo user, I want checked-off habits grouped below the ones still to do, so that I can see what's left at a glance.
8. As a Kyo user, I want a weekly-target habit that has met its target to stop asking for attention while still letting me check it off again, so that extra effort counts without nagging.
9. As a Kyo user, I want to see a habit's current streak, so that I'm motivated to keep it going.
10. As a Kyo user, I want a weekly-target habit to show week progress like 2/3, so that I know how many more days I need this week.
11. As a Kyo user, I want days a habit isn't due to leave its streak alone, so that a Mon/Wed/Fri habit isn't punished on Tuesday.
12. As a Kyo user, I want today's unchecked habit not to break my streak before the day is over, so that the streak isn't shown as broken in the morning.
13. As a Kyo user, I want to tap a habit's name on Today to edit it, so that quick fixes happen where I see the habit.
14. As a Kyo user, I want a Settings screen listing all my habits, including ones not due today, so that I can manage them in one place.
15. As a Kyo user, I want to reorder habits in Settings and have Today follow that order, so that the list is arranged the way I like.
16. As a Kyo user, I want editing a habit's schedule to affect only Today onward, so that past effort keeps counting.
17. As a Kyo user, I want to delete a habit, along with its log, after a confirmation.
18. As an Apple Watch user, I want to see today's habits and check them off from my wrist.
19. As a phone and Watch user, I want both devices to agree on today's habits and check-offs, including after midnight when the phone app isn't open.
20. As a Kyo user, I want the "Habits done" summary to match the list, so that the count is accurate.
21. As a Kyo user, I want my habits and log to survive closing and reopening the app.

## Implementation Decisions

### Habit schedules and weekly targets

- A habit schedule is one of: **every day**; **specific weekdays** (at least one); or a **weekly target** of 1–6 days per calendar week. A daily habit uses "every day", so 7 isn't offered. (#24)
- The week starts on the device locale's first weekday (`Calendar.current.firstWeekday`), not on a rolling window. (#24)
- A weekly-target habit appears on Today every day of the week, including after its target is met. It can be checked off at most once per day. Days past the target count (for example 4/3). (#24)
- The target isn't prorated: a habit created mid-week has its full target that week. (#24)

### Check-offs and the log

- A check-off records that a habit was done on a calendar day. It stores the device's local calendar date when checked (like `TaskCompletionDay`), never a timestamp, so it doesn't move across time zones. It has no time, note, or quantity. (#25)
- Only Today's habits can be checked off. Unchecking removes the check-off entirely. (#25)
- Misses aren't stored. They're worked out from the log and the habit's schedule history. The log is kept for the habit's lifetime. (#25)

### Streaks and week progress

- Every-day and specific-weekday habits count their streak in consecutive **due days** with a check-off. Weekly-target habits count consecutive **weeks** in which the target was met. (#26)
- Days that aren't due neither add to a streak nor break it. Only a due day without a check-off, or a finished week that missed its target, breaks it. (#26)
- Today is still open: an unchecked Today never breaks the streak, and checking it off adds one. The current week adds one once its target is met and never breaks the streak while in progress. Check-offs past the target add nothing more. (#26)
- A weekly-target habit's first, partial week counts if the target is met and is ignored if not. (#26)
- Week progress is the current week's check-offs against the weekly target and can exceed it. There's no best/longest streak. (#26)

### Schedule changes and deletion

- A habit keeps a dated history of its schedules. An edit takes effect from Today, and each past day is judged by the schedule in effect then. (#28)
- An edit within the same unit (between every day and specific weekdays, or one weekly target to another) carries the streak over. Switching between a day-based schedule and a weekly target starts a new streak from Today. The log is untouched. (#28)
- A new weekly target applies to the whole current week. (#28)
- If an edit makes Today not due, a check-off already made today stays in the log. The habit stays on Today until the day ends, and that check-off doesn't count toward the streak. (#28)
- Renaming changes nothing else. Deleting is permanent: the habit and its whole log are removed after a confirmation that says so. There's no undo and no archive. (#28)

### Adding and managing (iPhone/iPad)

- The bottom Add button opens a native menu: **Task** (first; starts the existing inline task draft) and **Habit**. (#27)
- **Habit** opens a habit form sheet: a name, a segmented schedule picker (Every day / Weekdays / Weekly target), then weekday chips in locale week order or a 1–6 stepper. Save requires a non-blank name and, for weekdays, at least one day. (#27)
- Tapping a habit's name on Today opens the same form for editing, with **Delete habit** at the bottom. (#27)
- A gear button in the Today header, across from the "kyo" wordmark, opens a **Settings** sheet of grouped entries. This spec defines one entry, **Habits ›**, which leads to the habit manager. The manager lists every habit with its schedule summary and marks those not due today. It has + to add, tap to edit (both push the habit form), swipe to delete, and drag to reorder in Edit mode. (#27)
- The manager's order controls Today's order. New habits go to the end. (#27)

### Today's Habits section (iPhone/iPad)

- Today lists due habits, plus any habit an edit made not due that already has a check-off today. (#29)
- Habits still to do come first, then the **done group**. Each group keeps the manager's order. A habit is done if it's checked off today, or if it's a weekly-target habit whose target is already met this week. A met-but-unchecked habit sits in the done group with an empty circle that can still be tapped. (#29)
- Done rows are gray without strikethrough. (#29)
- Right side of each row: day-based habits show their streak as a flame symbol and number, hidden at 0. Weekly targets show week progress, then the week streak when it's at least 1 (e.g. "2/3 · 🔥 4w"). The schedule summary isn't shown on Today. (#29)
- Tapping the circle toggles the check-off. Tapping the name opens the habit form. (#29)
- The "Habits done" summary is X / Y: Y is every habit on Today's list, and X is how many are in the done group. (#29)
- Empty states: "No habits yet" with a hint that + adds one, and "Nothing due today" when habits exist but none are due. (#29)

### Apple Watch

- The Watch uses the same list rules: manager order, then the done group, gray with no strikethrough, and met-but-unchecked weekly habits stay tappable. (#31)
- Right side of each row: day-based habits show 🔥 streak (hidden at 0). Weekly targets show only week progress ("2/3"). (#31)
- Tapping anywhere on the row toggles the check-off. There's no swipe and no editing. The Watch can't create, edit, reorder, or delete habits, and its + stays tasks-only. (#31)
- A `.success` haptic plays when a habit is checked off, and nothing when it's unchecked. (#31)
- The Watch "Habits" summary stat uses the same X / Y rule. (#31)
- Empty states: "Open Kyo on iPhone to sync habits" if no habit snapshot has ever been received, "No habits yet. Add them on iPhone." when synced with no habits, and "Nothing due today". (#31)

### Persistence and synchronization

- Habits, their schedule histories, and their logs persist on each device, and the phone is authoritative. See `docs/adr/0003-habit-sync.md`. (#30)
- The phone publishes a habit snapshot with its own revision, separate from the task snapshot. Both snapshots go in a single `updateApplicationContext` call, because each call replaces the whole context dictionary. (#30)
- The habit snapshot carries every habit (id, name, manager order, dated schedule history) and a trimmed log: enough check-offs to reproduce each current streak and this week's week progress. The Watch computes Today's habits, the done group, streaks, and week progress with the same rules code in `Shared/`, so it stays correct across midnight without the phone. (#30)
- The Watch sends one command, **set check-off** (habit, calendar day, checked or not), as an absolute state. The day comes from the Watch's clock and is accepted by the phone even if it arrives late. Commands reuse ADR 0002's outbox, retry, dedupe, and acknowledgment, and the Watch replays unacknowledged commands so taps show immediately. (#30)
- The phone applies commands and its own changes in arrival order, and the last one applied wins. A check-off for a deleted habit is ignored but acknowledged, and deleted habit ids are tombstoned. A check-off arriving after a schedule edit is still recorded, and the schedule history decides whether it counts. Habit creation, edits, reordering, and deletion travel only from the phone, in snapshots. (#30)
- Preserve accessible names and states: each circle is labelled with the habit name and its done state, with the streak or week progress included.
- Keep lasting target/build configuration changes in `project.yml` and regenerate the checked-in project when needed.

## Testing Decisions

- Use one primary behavior-testing boundary: the shared habit-list interface consumed by the phone and Watch views, mirroring the task-list approach. Assert observable lists, groups, streaks, week progress, and results, not storage layout or view structure.
- Control the current day and calendar (including the first weekday) in tests to cover: due-day selection for each schedule kind; weekly-target visibility before and after the target is met; check-off and uncheck; done-group membership; streaks across non-due days, an open Today, and an in-progress week; the first partial week; schedule edits within and across units; a mid-week target change; an edit that makes Today not due; deletion; and summary counts.
- Verify persistence by saving changes and reopening the habit list against the same test storage.
- Exercise a phone and a Watch habit list connected by a controllable transport. Cover convergence, duplicate and late delivery, a check-off for a deleted habit, a check-off after a schedule edit, Watch rollover past midnight with no new snapshot, and the shared context write keeping the task snapshot intact. Don't mock the habit behavior under test.
- Complement these with focused platform interaction checks: the Add menu and habit form, tap-name-to-edit, the Settings → Habits manager (add, edit, reorder, delete), done-group styling, and toggling a habit on the Watch.
- Build both app schemes. Check real paired-device delivery in a paired simulator or on devices, extending `WatchSyncSmokeUITests`.

## Out of Scope

- Implementing the feature as part of this specification request.
- A habit history view, browsing past days, checking off past days, and best/longest streaks.
- "Every N days" schedules, and quantity or duration targets.
- Archiving or pausing habits, including a vacation mode.
- Creating, editing, reordering, or deleting habits on Watch.
- Mixing habits into the Tasks list.
- Settings groups other than Habits.
- Reminders or notifications for habits.

## Further Notes

- Decisions trace to the Wayfinder map "Wayfinder: Habits" (#23) and its tickets #24–#31. The habit-management prototype is preserved on branch `prototype/habit-management`.
- Execution policy for future implementation: **Opus 5.5** (`claude-opus-5-5`) runs orchestration and owns review; the coder assignment is **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`).
- No implementation agents should be launched by this spec-writing request. The `ready-for-agent` label describes specification readiness; it doesn't authorize implementation.
