# Collapsible sections on Today

Status: Product behavior confirmed. Specification only; implementation is broken into separate tickets.

## Problem Statement

Every section header on Today shows a down chevron beside its title, on iPhone, iPad, and Apple Watch. The chevron says the section can be collapsed, but tapping it does nothing. Users who don't use a section every day, or who want Tasks near the top of a long Today, have no way to put a section out of the way.

## Solution

Make every **section** on Today collapsible. Tapping a section's header collapses it to the header alone; tapping again expands it. A **collapsed section** stays collapsed across launches and days until the user expands it, and each device remembers its own layout. A collapsed header still tells the user what's inside: Tasks and Habits show how many are done, and the Schedule and Memos keep the counts they already show. On the watch, a collapsed header shows a short count beside the title.

Terms follow `GLOSSARY.md`: **Today**, **Section**, **Collapsed section**, **Task**, **Habit**, **Memo**, **Schedule**, **Event**.

## User Stories

1. As a Kyo user, I want to tap a section's header to collapse it, so that the chevron does what it implies.
2. As a Kyo user, I want to tap a collapsed section's header to expand it, so that I can get its content back.
3. As a Kyo user, I want the chevron to point right when a section is collapsed and down when it's expanded, so that I can see each section's state at a glance.
4. As a Kyo user, I want to collapse the Schedule, Tasks, Habits, and Memos independently, so that Today shows only what I care about.
5. As a Kyo user, I want a collapsed section to stay collapsed when I relaunch Kyo, so that I don't redo my layout every time.
6. As a Kyo user, I want a collapsed section to stay collapsed on a new day, so that Kyo doesn't undo my layout every morning.
7. As a Kyo user with an iPhone and an iPad, I want each device to keep its own collapsed sections, so that a layout that suits one screen isn't forced on the other.
8. As an Apple Watch user, I want to collapse sections on the watch, so that I scroll less to reach the one I use.
9. As an Apple Watch user, I want the watch's collapsed sections to be separate from my phone's, so that I can keep the watch shorter.
10. As a Kyo user, I want a collapsed Tasks header to say how many tasks are done, such as "2 of 5 done", so that I know where I stand without expanding it.
11. As a Kyo user, I want a collapsed Habits header to say how many of today's habits are done, so that I know where I stand without expanding it.
12. As a Kyo user with no tasks, I want a collapsed Tasks header to say "No tasks", so that it doesn't read "0 of 0 done".
13. As a Kyo user with no habits, or none due today, I want a collapsed Habits header to say so, so that the summary matches what the expanded section would show.
14. As a Kyo user, I want a collapsed Schedule header to keep its event count, so that I still know how busy the day is.
15. As a Kyo user, I want a collapsed Memos header to keep its memo count, so that I still know whether I captured anything today.
16. As a Kyo user, I want **See all** to stay on a collapsed Memos header, so that I can still open my memos.
17. As a Kyo user, I want tapping **See all** to open my memos and not toggle the section, so that the two controls don't interfere.
18. As a Kyo user, I want expanded Tasks and Habits headers to keep their current notes, so that Today looks the same as it does now until I collapse something.
19. As a Kyo user who starts adding a task while Tasks is collapsed, I want Tasks to expand, so that I can see what I'm typing.
20. As a Kyo user, I want Tasks to stay expanded after I add that task, so that the task I just wrote doesn't disappear.
21. As a Kyo user who saves a memo or a habit from its sheet, I want a collapsed section to stay collapsed, so that Kyo respects my layout.
22. As a Kyo user who adds a suggested task from a memo, I want a collapsed Tasks section to stay collapsed, so that Kyo respects my layout.
23. As a Kyo user, I want the Schedule to come back showing more or showing less exactly as I left it when I expand the section, so that collapsing doesn't lose my place.
24. As a Kyo user who has turned the Schedule off in Settings and turns it back on, I want it to come back collapsed if I'd collapsed it, so that my layout is kept.
25. As an Apple Watch user, I want a collapsed Tasks or Habits header to show a count such as "2/5", so that I can read progress without expanding it.
26. As an Apple Watch user, I want a collapsed Memos header to show how many memos Today has.
27. As a VoiceOver user, I want each section header to be a button that announces whether the section is expanded or collapsed, so that I can use collapsing without seeing the chevron.
28. As a VoiceOver user, I want a collapsed header to read its summary, so that I get the same information sighted users do.
29. As a new Kyo user, I want every section expanded the first time I open Kyo, so that I see everything Kyo offers.

## Implementation Decisions

### Vocabulary

- **Collapse** and **expand** belong to sections. The Schedule's existing behavior, where it shows its next three events with "+N more", is renamed to **show more** and **show less** in code, tests, and the Schedule spec, matching its on-screen labels. The rename changes no behavior.
- `GLOSSARY.md` defines **Section** and **Collapsed section**.

### Collapse state

- One new shared model holds which sections are collapsed. Both the iPhone/iPad Today view and the watch Today view read and toggle it.
- The sections are Schedule, Tasks, Habits, and Memos. The watch has no Schedule section and ignores that one.
- The state persists in the device's own `UserDefaults`, injected so tests can supply their own. It isn't synced between devices and adds nothing to the phone–watch sync described in ADRs 0001–0005.
- Every section is expanded when nothing has been stored.
- The state isn't tied to a day. A day rollover doesn't change it.
- The header and the summary stats at the top of Today aren't sections and don't collapse.

### Header behavior

- The whole header row toggles the section: title, chevron, and note. On the Memos header, **See all** stays a separate button, stays visible when the section is collapsed, and never toggles the section.
- The chevron points down when expanded and right when collapsed.
- A collapsed section shows only its header. Its content, including empty-state rows and the Schedule's prompt lines, is hidden.
- Toggling animates with the default animation.
- The header is an accessibility button whose value is "expanded" or "collapsed". Its label includes the note or summary that's showing.

### Collapsed summaries

- iPhone and iPad, shown in place of the header's note only while the section is collapsed:
  - Tasks: "2 of 5 done", or "No tasks" when Today has none.
  - Habits: "1 of 3 done", counting only habits on Today's list; "No habits" when none exist; "Nothing due today" when none are due.
  - Schedule and Memos: their existing notes, unchanged.
- Expanded sections keep their current notes.
- Apple Watch, shown at the right of the header only while the section is collapsed: "2/5" for Tasks and Habits, and the number of Today's memos for Memos. When there's nothing to count (no tasks, no habits on Today's list, no memos), the watch shows no count.
- The counts match what the expanded section would show. A carried-forward task counts; a habit that isn't due today doesn't.
- The task and habit list models own their summary text, the way the Memos and Schedule models already own their header notes.

### Expanding automatically

- Starting a task draft on Today expands a collapsed Tasks section, and the expansion is remembered. This rule lives in the section model, not the view.
- Nothing else expands a section: saving a memo or a habit from a sheet, adding a suggested task from a memo, a watch command, a sync update, and a day rollover all leave it collapsed.

### Schedule

- Collapsing the Schedule section is independent of show more and show less. The Schedule keeps that state while collapsed and still returns to the short list on a new day.
- Turning the Schedule off in Settings hides the section as it does today and leaves its collapse state untouched.

## Testing Decisions

- Test external behavior through the models the views consume, not view structure.
- Test the section model directly with an injected `UserDefaults` suite: every section starts expanded; toggling collapses and expands one section without affecting the others; a new model built on the same defaults reads the same state back; starting a task draft expands Tasks and persists that; other actions leave the state alone.
- Test the collapsed summaries through the task and habit list models, alongside the existing counts: each wording above, including the empty cases, carried-forward tasks, and habits that aren't due.
- Prior art: `ScheduleCompactBehaviorTests` (state driven through a store with injected dependencies) and `MemoStoreBehaviorTests` (the section subtitle).
- UI tests on iPhone cover what the models can't: tapping a header hides and shows its rows, **See all** still opens the memos sheet from a collapsed Memos header, the task draft expands a collapsed Tasks section, and the state survives a relaunch. UI tests start from a clean collapse state through a launch variable, like `KYO_IN_MEMORY_STORE`.
- The Schedule rename is covered by the existing Schedule tests, renamed to match.
- Build both app schemes.

## Out of Scope

- Syncing collapsed sections between devices.
- Collapsing the header or the summary stats.
- Reordering or hiding sections, and a Settings screen for them.
- Showing the done counts on expanded Tasks and Habits headers.
- New summaries for the Schedule and Memos.
- Widgets and complications.

## Further Notes

- Decisions were made in one grilling session. No ADR was written: the choices are easy to reverse and don't touch sync or storage design.
- The watch showing no count for an empty collapsed section wasn't discussed in the session; it's the spec author's call and can be changed in review.
- Suggested tickets: rename the Schedule's collapse vocabulary; collapsible sections on iPhone and iPad (stacked on the rename, since both touch the Today and Schedule views); collapsible sections on Apple Watch (parallel).
- Execution policy: **Opus 5.5** (`claude-opus-5-5`) runs orchestration and owns review; the coder assignment is **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`).
