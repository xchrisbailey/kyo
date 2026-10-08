# Month on iPhone and iPad

Status: Product behavior confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Kyo's bottom bar has a Calendar button, but it opens a placeholder sheet: a compact date picker over the line "No entries in this sketch." There is no way to see what happened on another day or what is coming up. Tasks completed, habit check-offs, and memos all record their day, and events can be read for any day, yet none of it is visible outside Today.

## Solution

Replace the placeholder sheet with **Month**, a second main view on iPhone and iPad beside Today. It shows one calendar month as a grid of days. Each day carries up to four marks for what it holds: events, tasks completed, habits, and memos. Selecting a day shows its **Day summary** below the grid. Month is an overview: nothing is added or checked off from it, and **Today** stays the only day the user acts on. The Apple Watch loses its Calendar button and placeholder. Terms follow `GLOSSARY.md`: **Today**, **Month**, **Day summary**, **Event**, **Schedule**, **Task**, **Habit**, **Habit schedule**, **Weekly target**, **Check-off**, **Log**, **Memo**.

## User Stories

### Reaching Month

1. As a Kyo user, I want a Month button in the bottom bar, so that the month is one tap from Today.
2. As a Kyo user, I want the bottom bar to stay visible on Month, so that I can get back to Today in one tap.
3. As a Kyo user, I want the bar to show which of Today and Month I'm on, so that I always know where I am.
4. As a Kyo user, I want Kyo to open on Today every time, so that the day I act on is always first.
5. As a Kyo user, I want Month to open on the current month with Today selected, so that I start from now each time.

### The grid

6. As a Kyo user, I want to see a whole month at once, so that I can tell which days were busy and which were empty.
7. As a Kyo user, I want the month and year shown above the grid, so that I know which month I'm looking at.
8. As a Kyo user, I want weeks to start on my locale's first weekday, so that the grid matches every other calendar I use.
9. As a Kyo user, I want Today highlighted in the grid, so that I can find it at a glance.
10. As a Kyo user, I want the day I selected highlighted differently from Today, so that I don't confuse the two.
11. As a Kyo user, I want to swipe between months, so that browsing is quick.
12. As a Kyo user, I want chevrons to change month, so that I don't have to swipe.
13. As a Kyo user, I want to look at any past month, so that I can go back as far as my data does.
14. As a Kyo user, I want to look at future months, so that I can see what events are coming.
15. As a Kyo user, I want one control to get back to the current month, so that I never get lost.
16. As a Kyo user, I want the Today highlight to move when midnight passes, so that Month is never a day behind.

### Marks

17. As a Kyo user, I want a mark on days that have events, so that I can see when I was or will be busy.
18. As a Kyo user, I want a multi-day event to mark every day it covers, so that a trip shows as a run of days.
19. As a Kyo user, I want all-day events to count, so that birthdays and holidays are marked too.
20. As a Kyo user, I want a mark on days when I completed at least one task, so that I can see when I got things done.
21. As a Kyo user, I want a filled habit mark on days when I checked off every due habit, so that perfect days stand out.
22. As a Kyo user, I want a hollow habit mark on days when I checked off only some, so that I can spot where I slipped.
23. As a Kyo user with a weekly-target habit, I want its check-off to count on the day I did it, so that the day isn't shown as empty.
24. As a Kyo user who changed a habit's schedule, I want past days judged by the schedule they had, so that an edit never rewrites the past.
25. As a Kyo user, I want a mark on days that have memos, so that I can find the days I wrote or recorded something.
26. As a Kyo user, I want each kind of mark always in the same position, so that I learn where to look.
27. As a Kyo user who can't tell colors apart, I want the marks to differ by position, so that color is never the only signal.
28. As a Kyo user, I want a short legend under the grid, so that I don't have to guess what a mark means.
29. As a Kyo user, I want future days to show only event marks, so that I'm not shown things that can't have happened yet.
30. As a Kyo user, I want the marks to update when I complete a task, check off a habit, or add or delete a memo, so that Month is never stale.

### Calendars and access

31. As a Kyo user who hid a calendar in Settings, I want it hidden in Month too, so that the choice applies everywhere.
32. As a Kyo user who turned the Schedule off, I want Month to leave my calendars alone, so that it never shows events I chose not to see.
33. As a Kyo user who hasn't granted calendar access, I want Month to work without it and not prompt me, so that looking at a month is never interrupted.
34. As a Kyo user, I want event marks to update when my calendar changes, so that a new meeting shows up without relaunching.

### Day summary

35. As a Kyo user, I want to select a day and see what it holds, so that the marks lead somewhere.
36. As a Kyo user, I want the Day summary headed by that day's date, so that I know which day I'm reading.
37. As a Kyo user, I want the day's events listed in time order with all-day events first, so that it reads like the Schedule.
38. As a Kyo user, I want to open an event from any day, so that I can check its details without leaving Kyo.
39. As a Kyo user, I want to see the tasks I completed on a day, so that I can remember what I did.
40. As a Kyo user, I want to see which due habits I checked off and which I didn't, so that I know what I skipped.
41. As a Kyo user, I want to see the day's memos, so that I can find what I captured.
42. As a Kyo user, I want to open a memo from a past day, so that I can reread, play, or edit it.
43. As a Kyo user, I want tasks and habits in the Day summary to be plain text with no checkbox, so that I don't expect to change the past.
44. As a Kyo user, I want Today's Day summary to show what I've done so far, so that it reads like any other day.
45. As a Kyo user, I want a future day to list its events, so that I can plan around them.
46. As a Kyo user, I want an empty day to say so in one line, so that I know nothing is missing.
47. As a Kyo user, I want the Day summary to update after I edit or delete a memo opened from it, so that it matches what I just did.

### Adding while Month is showing

48. As a Kyo user, I want the + menu available on Month, so that capture is never blocked.
49. As a Kyo user, I want adding a task from Month to take me to Today with the field ready, so that the task lands where tasks live.
50. As a Kyo user, I want adding a habit or a memo from Month to return me to Month, so that I keep my place.

### Accessibility and devices

51. As a VoiceOver user, I want each day read with its date and what it holds, so that the marks aren't visual only.
52. As a VoiceOver user, I want to hear which day is selected and which is Today.
53. As a Dynamic Type user, I want the grid and Day summary to respect my text size.
54. As an iPad user, I want the same Month as on iPhone, so that both devices behave alike.
55. As an Apple Watch user, I want the placeholder Calendar button gone, so that the Watch has nothing that does nothing.

## Implementation Decisions

### Scope

- iPhone and iPad only. The Watch gets no Month. The Watch receives a trimmed habit log (the current streak and this week only), so it couldn't show past months correctly even if the grid fit.
- Month is read-only for tasks, habits, and check-offs. Nothing is added to, checked off on, or moved to a day other than Today. Opening a memo or an event from the Day summary is allowed and behaves as it does elsewhere in Kyo.
- Any month can be shown, past or future, with no bound in either direction.
- No schema changes. Month reads what is already stored and stores nothing of its own.

### Modules

- **Month model (new).** The one module the Month view consumes and the one seam Month is tested through. Given a clock and a calendar, it exposes: the shown month and its header text; the grid's weeks and days; each day's marks; which day is Today and which is selected; the selected day's Day summary; and whether the shown month is the current one. It accepts: select a day, go to the previous or next month, and go back to the current month. It observes the task, habit, memo, and Schedule modules and recomputes when any of them changes.
- **Task list (modified).** Gains a read-only query for the tasks completed on a given day, and for which days in a range have a completed task. Its full list is private today.
- **Memo store (modified).** Gains a read-only query for the memos of a given day, and for which days in a range have a memo. It exposes only Today's memos and paged history today.
- **Habit list (modified).** It already exposes every habit with its log and the habit schedule it had on a given day. Its existing due check can't be used as it stands: it answers "due" for a weekly-target habit on every day, and for any habit on days before it was created. Month needs a read-only query that answers whether a habit counted as due on a day under the Marks rules below. Today's behavior, streaks, and week progress must not change.
- **Schedule model (modified).** Gains a query for the visible events in a date range. It applies the same rules the Schedule section uses: no events unless **Show schedule** is on and access is full, and hidden calendars filtered out. Month gets events only through this query, so the selection rule lives in one place.
- **Calendar service (unchanged).** It already fetches events for any range and has a fake.
- **Today view and bottom bar (modified).** The bar switches the main content between Today and Month. The placeholder sheet is removed. The stores, the day-rollover and calendar-change observation, the recorder, and quick-capture handling that the Today view owns now must keep running while Month is showing, and switching back must not recreate them or lose Today's state, including a typed, unsubmitted task.
- **Watch Today view (modified).** The Calendar button and its "Past days" placeholder are removed.

### Reaching Month

- The bottom bar becomes a two-way switch. **Today** and **Month** swap the main content, and the bar stays visible on both. The selected one is drawn the way Today is drawn now.
- The Calendar button is relabelled **Month** and keeps the calendar icon.
- Kyo always launches into Today. The selected view isn't remembered across launches.
- Month always opens on the current month with Today selected, each time the user switches to it.

### The + menu while Month is showing

- **Task** switches to Today and focuses the task field, as it does now.
- **Habit**, **Written memo**, and **Voice memo** open their sheets over Month. Dismissing one leaves the user on Month, and the marks and Day summary update.
- Quick-capture shortcuts work while Month is showing exactly as they do on Today: a voice or written memo capture opens over Month straight away, and a task capture switches to Today and focuses the task field. Watch behavior is unchanged.

### The grid

- One calendar month, with a header showing the month and year. The grid holds only that month's days: cells before the 1st and after the last day are blank, with no dates, marks, or selection.
- Weeks start on the device locale's first weekday, the same rule the **Weekly target** uses. A weekday header row sits above the grid.
- Move between months by swiping horizontally or with chevrons beside the header. When any month other than the current one is showing, a control jumps back to the current month and selects Today.
- Today's cell is highlighted as the current day. The selected day has its own highlight, distinct from Today's.
- If the day rolls over while Month is showing, the current-day highlight moves to the new Today. The selection stays where the user put it. If the new Today is in the next month, the shown month stays and the jump-back control appears.
- Marks and the Day summary always follow the shown month and the selected day, whichever month that is.

### Marks

- Each day cell has four fixed slots, in this order: events, tasks, habits, memos. A kind that doesn't apply leaves its slot empty, so position carries the meaning and color is a second cue.
- A one-line legend sits under the grid.
- **Events**: marked when at least one visible event overlaps the day. A multi-day event marks every day it overlaps. All-day events count. The mark is one neutral color, not the calendar's color.
- **Tasks**: marked when at least one task was completed on that day. The same rule applies to Today; open tasks never produce a mark.
- **Habits**: three states.
  - Filled when every habit due that day has a check-off.
  - Hollow when the day has at least one check-off but not every due habit was checked off.
  - Empty when the day has no check-offs, whether or not habits were due.
  - A weekly-target habit is never due on a particular day. Its check-off counts toward "at least one check-off" and can't hold a day back from filled. A day whose only check-offs are weekly-target ones, with no other habit due, is filled.
  - Due is judged by the habit schedule the habit had on that day, not its current one.
  - A habit isn't due before the day it was created, so creating a habit never turns earlier days hollow.
  - Deleting a habit deletes its log, so its marks and Day summary rows disappear from past days. This is expected; Month keeps nothing of its own.
- **Memos**: marked when the day has at least one memo.
- Days after Today can only ever carry the event mark. A task, check-off, or memo recorded against a later day (after a time zone or clock change) produces no mark and no row until that day is Today or earlier.
- A day counts as holding an event when the event overlaps the span from the start of that day to the start of the next, so an all-day event that ends at midnight doesn't mark the following day.
- Exact colors are chosen at implementation and reviewed from the PR screenshot, in light and dark.

### Events and calendar access

- When **Show schedule** is off, or access isn't full, Month shows no event marks, lists no events in the Day summary, and shows no prompt. Connecting stays in Today and Settings.
- Events are fetched for the shown month. Refetch when the event store reports a change, when the shown month changes, when the app returns to the foreground, and when the Settings selection changes.
- Kyo still stores no events.

### Day summary

- Shown below the grid for the selected day, headed by that day's date.
- It lists, in this order:
  - **Events**: all of the day's visible events in time order, all-day first, shown as Schedule rows are. On Today they match the Schedule exactly, including "Now", "Until", and dimming of ended events. On any other day each timed row shows its start time, is never dimmed, and is never read as ended, since those are relative to Today. Tapping one opens the system event detail for that day's occurrence, as the Schedule does.
  - **Tasks**: the tasks completed on that day. Plain rows, not tappable, with no checkbox control.
  - **Habits**: every habit due that day with whether it was checked off, plus any other habit checked off that day: a weekly-target habit, or one whose schedule no longer made it due that day. Every check-off that counts toward the mark has a row. A habit that was due and not checked off is shown as unchecked. Plain rows, not tappable. An unchecked habit is the absence of a check-off, not a record of its own.
  - **Memos**: the day's memos. Tapping one opens it in the same sheet the Memos sheet uses, with whatever that sheet allows: editing, deleting, photos, and Memo → Task, which still adds the task to Today.
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

- Remove the Watch's Calendar button and its "Past days" placeholder. Nothing replaces it.
- This is independent of the rest and can ship first, as its own ticket.

## Testing Decisions

- A good test here drives Kyo the way a user would (complete a task, check off a habit, add a memo, seed events, move the clock) and asserts what Month reports: marks, Day summary rows, the shown month, the selection. It never asserts view structure or how the Month model computes its answer.
- **The Month model is the single seam.** Tests build it with real task, habit, and memo stores on in-memory storage, the existing fake calendar service, and a controllable clock and calendar. No new fakes are needed.
- Cover through that seam:
  - The grid for a month, including a locale that starts the week on Monday and one that starts on Sunday, and months that span five and six weeks.
  - Each mark's rule, including a multi-day event, an all-day event, and a task completed on one day not marking another.
  - The three habit states; a weekly-target check-off on its own and beside a missed due habit; a habit whose schedule changed after the day in question; a day before a habit was created; a deleted habit.
  - Hidden calendars filtered out; no event marks and no prompt with Show schedule off, and in each access state other than full.
  - The Day summary for a past day, Today, a future day, and an empty day, including row order and the unchecked habit row.
  - Moving to the previous and next month, across a year boundary, and jumping back to the current month.
  - Day rollover while Month is showing: the Today highlight moves and the selection stays.
  - Recomputing after a task is completed or uncompleted, a habit is checked off or unchecked, a memo is added, edited, or deleted, and the event store reports a change.
- Row order in the Day summary and phrase order in the day cell's VoiceOver label are fixed (events, tasks, habits, memos) and asserted.
- The new read-only queries on the task list, memo store, and Schedule model are exercised through the Month model, not with tests of their own, unless a rule can't be reached from there.
- Prior art: the Schedule's behavior tests (fake calendar service, fixed UTC calendar and locale, a clock closure, and a poll-until helper for refreshes that finish on their own tasks); the habit streak behavior tests (an in-memory container, a mutable clock moved day by day to build a log); the memo history behavior tests for memos grouped by day.
- UI tests stay few, in line with the UI test audit: one that switches to Month and back, and one that adds a memo on Today, switches to Month, and opens it from Today's Day summary. They use the existing launch variables for the in-memory store and the fake calendar; no new seeding variable is added, so past days are covered by the behavior tests.
- Check by hand on a real device: swiping between months with a large calendar account, and Dynamic Type at accessibility sizes.
- Build both app schemes.

## Out of Scope

- Implementing the feature as part of this specification request.
- Adding, editing, checking off, or rescheduling tasks or habits on any day other than Today.
- Dated or future tasks, and showing tasks that were left unfinished on a past day. A task records only the day it was completed.
- Marking future days with due habits.
- Keeping a deleted habit's log so past days still show it.
- A week view, a year view, or a separate full-screen page for a day.
- Month on the Apple Watch, widgets, and complications.
- Remembering the selected view or month across launches.
- A side-by-side iPad layout. See Further Notes.

## Further Notes

- **Planned follow-up: side-by-side on iPad.** On a wide screen, show the grid and the Day summary next to each other rather than stacked. It was left out of this spec to keep the first version to one layout, and is intended as a later change.
- This spec overturns three earlier out-of-scope decisions: events for any day other than Today and the bottom bar's Calendar sheet (Schedule spec), browsing past days (Habits spec), and reaching past memos through the Calendar tab or any past-day view (#58, Memos spec). Checking off past days and a per-habit history view remain out of scope.
- It respects the existing ADRs: the phone stays authoritative for tasks and habits (0001–0003), and nothing new is stored or synced (0004, 0005).
- No ADR was written. This is a product-scope change that is easy to reverse and is explained by this spec and `GLOSSARY.md`.
- An adversarial pass on the ticket breakdown tightened this spec: blank cells outside the month, event rows on other days, the future-day rule, habits checked off on a day they weren't due, and keeping Today's work running under Month.
- Decisions were made in one grilling session. The ticket breakdown is done separately.
- No implementation agents should be launched by this spec-writing request. Delegation follows `docs/agents/orchestration.md`.
