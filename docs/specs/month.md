# Month on iPhone and iPad

Status: Product behavior confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Kyo's bottom bar has a Calendar button, but it opens a placeholder sheet: a compact date picker over the line "No entries in this sketch." There is no way to see what happened on another day or what is coming up. Tasks completed, habit check-offs, and memos all record their day, and events can be read for any day, yet none of it is visible outside Today.

## Solution

Replace the placeholder sheet with **Month**, a second main view on iPhone and iPad beside Today. It shows one calendar month as a grid of days. Each day carries up to four marks for what it holds: events, tasks completed, habits, and memos. Selecting a day shows its **Day summary** below the grid. Month is an overview: nothing is added or checked off from it, and **Today** stays the only day the user acts on. The Apple Watch loses its Calendar button and placeholder. Terms follow `GLOSSARY.md`: **Today**, **Month**, **Day summary**, **Event**, **Task**, **Habit**, **Check-off**, **Memo**.

## User Stories

1. As a Kyo user, I want to see a whole month at once, so that I can tell which days were busy and which were empty.
2. As a Kyo user, I want a mark on each day for events, tasks completed, habits, and memos, so that I can tell what kind of day it was without opening it.
3. As a Kyo user, I want to tell a day when I did every due habit from a day when I did only some, so that I can spot where I slipped.
4. As a Kyo user, I want to select a day and see what it holds, so that the marks lead somewhere.
5. As a Kyo user, I want to open a memo from a past day, so that I can reread what I captured then.
6. As a Kyo user, I want to open an event from any day, so that I can check its details without leaving Kyo.
7. As a Kyo user, I want to look at future months, so that I can see what events are coming.
8. As a Kyo user, I want one control to get back to the current month, so that I never get lost.
9. As a Kyo user, I want to move between Today and Month from the bottom bar, so that both are one tap away.
10. As a Kyo user, I want to add a task, habit, or memo while Month is showing, so that capture is never blocked.
11. As a Kyo user who turned the Schedule off, I want Month to leave my calendars alone, so that it never asks for access I declined.
12. As a VoiceOver user, I want each day read with its date and what it holds.
13. As a Kyo user who can't tell colors apart, I want the marks to differ by position, so that color is never the only signal.

## Implementation Decisions

### Scope

- iPhone and iPad only. The Watch gets no Month.
- Month is read-only for tasks, habits, and check-offs. Nothing is added to, checked off on, or moved to a day other than Today. Opening a memo or an event from the Day summary is allowed and behaves as it does elsewhere in Kyo.
- Any month can be shown, past or future, with no bound in either direction.

### Reaching Month

- The bottom bar becomes a two-way switch. **Today** and **Month** swap the main content, and the bar stays visible on both. The selected one is drawn the way Today is drawn now.
- The Calendar button is relabelled **Month** and keeps the `calendar` icon. `CalendarPreviewSheet` and the `.calendar` sheet case are removed.
- Kyo always launches into Today. The selected view isn't remembered across launches.
- Month always opens on the current month with Today selected, each time the user switches to it.

### The + menu while Month is showing

- **Task** switches to Today and focuses the task field, as it does now.
- **Habit**, **Written memo**, and **Voice memo** open their sheets over Month. Dismissing one leaves the user on Month, and the marks and Day summary update.
- Quick-capture shortcuts and Watch behavior are unchanged.

### The grid

- One calendar month, with a header showing the month and year.
- Weeks start on the device locale's first weekday, the same rule the **Weekly target** uses. A weekday header row sits above the grid.
- Move between months by swiping horizontally or with chevrons beside the header. When any month other than the current one is showing, a control jumps back to the current month and selects Today.
- Today's cell is highlighted as the current day. The selected day has its own highlight, distinct from Today's.
- If the day rolls over while Month is showing, the current-day highlight moves to the new Today. The selection stays where the user put it.

### Marks

- Each day cell has four fixed slots, in this order: events, tasks, habits, memos. A kind that doesn't apply leaves its slot empty, so position carries the meaning and color is a second cue.
- A one-line legend sits under the grid.
- **Events**: marked when at least one event overlaps the day. A multi-day event marks every day it overlaps. All-day events count. The mark is one neutral color, not the calendar's color.
- **Tasks**: marked when at least one task was completed on that day. The same rule applies to Today; open tasks never produce a mark.
- **Habits**: two states.
  - Filled when every habit due that day has a check-off.
  - Hollow when the day has at least one check-off but not every due habit was checked off.
  - Empty when the day has no check-offs, whether or not habits were due.
  - A weekly-target habit is never due on a particular day. Its check-off counts toward "at least one check-off" and can't hold a day back from filled. A day whose only check-offs are weekly-target ones, with no other habit due, is filled.
  - Due is judged by the schedule the habit had on that day, not its current one.
- **Memos**: marked when the day has at least one memo.
- Future days can only ever carry the event mark.
- Exact colors are chosen at implementation and reviewed from the PR screenshot, in light and dark.

### Events and calendar access

- Month reads events through the existing `CalendarService`, for the visible month's range, and applies the Schedule's hidden-calendars selection.
- When **Show schedule** is off, or access isn't `.fullAccess`, Month shows no event marks, lists no events in the Day summary, and shows no prompt. Connecting stays in Today and Settings.
- Refetch when the event store reports a change, when the visible month changes, when the app returns to the foreground, and when the Settings selection changes.
- Kyo still stores no events.

### Day summary

- Shown below the grid for the selected day, headed by that day's date.
- It lists, in this order:
  - **Events**: all of the day's events in time order, all-day first, shown as Schedule rows are. Tapping one opens the system event detail for that day's occurrence, as the Schedule does.
  - **Tasks**: the tasks completed on that day. Plain rows, not tappable, with no checkbox control.
  - **Habits**: every habit due that day with whether it was checked off, plus any weekly-target habit checked off that day. A habit that was due and not checked off is shown as unchecked. Plain rows, not tappable. An unchecked habit is the absence of a check-off, not a record of its own.
  - **Memos**: the day's memos. Tapping one opens it in the same sheet the Memos sheet uses, with editing, deleting, photos, and Memo → Task as that sheet allows.
- A kind with nothing for the day is left out.
- Today's Day summary follows the same rules: events, tasks completed so far, habits with their state, and memos. Open tasks appear only in the Today view.
- A future day lists events only.
- A day with nothing shows one muted line, "Nothing on this day".

### Accessibility and layout

- Each day cell is a single accessibility element reading the date and what it holds, for example "Tuesday 6 October, 2 events, 3 tasks completed, all habits done, 1 memo". The hollow habit state reads "some habits done". The cell carries the selected trait when selected and says when it is Today.
- Day summary rows read as they do in their Today sections.
- The grid and Day summary respect Dynamic Type.
- iPad uses the same stacked layout within the existing Today width.

### Apple Watch

- Remove the Watch's Calendar button and its "Past days" placeholder from `WatchTodayView`. Nothing replaces it.
- This is independent of the rest and can ship first, as its own ticket.

## Testing Decisions

- Put Month's behavior in a shared model the view consumes, with a controllable clock and calendar and the fake calendar service. Assert observable marks, rows, and states, not view structure.
- Cover: the grid for a month, including locale week start; each mark's rule; the three habit states, including weekly-target check-offs and a habit whose schedule changed after the day in question; multi-day and all-day events; hidden calendars filtered out; no event marks and no prompt with Show schedule off or without access; the Day summary for a past day, Today, a future day, and an empty day; moving between months and jumping back; day rollover while Month is showing; and refresh after a memo, check-off, or task completion changes.
- UI tests stay few, in line with the UI test audit: one that switches to Month and back, and one that selects a seeded day and opens a memo from its Day summary.
- Check by hand on a real device: swiping between months with a large calendar account, and Dynamic Type at accessibility sizes.
- Build both app schemes.

## Out of Scope

- Implementing the feature as part of this specification request.
- Adding, editing, checking off, or rescheduling tasks or habits on any day other than Today.
- Dated or future tasks, and showing tasks that were left unfinished on a past day. A task records only the day it was completed.
- Marking future days with due habits.
- A week view, a year view, or a separate full-screen page for a day.
- Month on the Apple Watch, widgets, and complications.
- Remembering the selected view or month across launches.
- A side-by-side iPad layout. See Further Notes.

## Further Notes

- **Planned follow-up: side-by-side on iPad.** On a wide screen, show the grid and the Day summary next to each other rather than stacked. It was left out of this spec to keep the first version to one layout, and is intended as a later change.
- This spec overturns three earlier out-of-scope decisions: "events for any day other than Today" and the bottom bar's Calendar sheet in `docs/specs/schedule.md`, "browsing past days" in `docs/specs/habits.md`, and "reaching past memos through the Calendar tab or any past-day view" (#58) in `docs/specs/memos.md`. Checking off past days and a per-habit history view remain out of scope.
- No ADR was written. This is a product-scope change that is easy to reverse and is explained by this spec and `GLOSSARY.md`.
- Decisions were made in one grilling session. The ticket breakdown is done separately.
- No implementation agents should be launched by this spec-writing request. Delegation follows `docs/agents/orchestration.md`.
