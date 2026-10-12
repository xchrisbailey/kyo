# Deferred tasks

Status: Product behavior and testing boundaries confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Kyo users cannot set aside tasks intended for a later day. Future work stays mixed with tasks they can act on Today, and users must remember when to bring it back. They want to describe when in plain language, such as Friday, one week out, or one month out, and see the actual date before saving.

## Solution

Let users defer a task to a planned day during creation or through Do later on an existing task. Offer weekday, one-week, and one-month quick choices, a date picker, and a separate plain-text scheduling input interpreted by Apple Intelligence. Show the full resolved date for confirmation.

Deferred tasks stay out of Today's list and counts until their planned day. Users manage them in Later, ordered by planned day. Month shows planned and completed tasks distinctly and remains read-only. Once available, tasks follow normal unfinished-task carryover. Scheduling is one-time and date-only on iPhone and iPad; Watch shows tasks once available on Today.

## User Stories

1. As a Kyo user, I want to defer a task to a planned day, so that future work does not crowd Today.
2. As an iPhone user, I want to choose a planned day while creating a task, so that I can capture future work immediately.
3. As an iPad user, I want the same scheduling options, so that I can plan on either device.
4. As a Kyo user, I want a Do later action on an existing active task, so that I can move work out of Today.
5. As a Kyo user, I want creation and rescheduling to share one scheduling input, so that I learn one interaction.
6. As a Kyo user, I want weekday quick choices, so that common scheduling takes little effort.
7. As a Kyo user, I want a one-week quick choice, so that I can move a task to the same weekday next week.
8. As a Kyo user, I want a one-month quick choice, so that I can move a task to the same calendar day next month.
9. As a Kyo user, I want a date picker, so that I can select an exact date directly.
10. As a Kyo user, I want to type when in plain language, so that I do not need special date syntax.
11. As a Kyo user, I want Apple Intelligence to interpret my description on device, so that scheduling does not require a cloud service.
12. As a Kyo user, I want to preview the full calendar date before saving, so that I can catch an unexpected interpretation.
13. As a Kyo user, I want to correct the proposed date, so that my choice determines when the task appears.
14. As a Kyo user, I want task text kept separate from its scheduling description, so that dates in task text are not silently removed or acted on.
15. As a Kyo user, I want a bare weekday to include Today when it matches, so that interpretation follows the agreed rule.
16. As a Kyo user, I want next Friday to mean Friday in the next calendar week, so that the phrase has a consistent meaning.
17. As a Kyo user, I want one week out to use calendar days, so that daylight-saving changes do not shift the intended day.
18. As a Kyo user, I want one month out to use the same day next month, so that a month is not treated as a fixed number of days.
19. As a Kyo user, I want month-end handling when that day does not exist next month, so that January 31 can become February's final day.
20. As a Kyo user, I want clarification for ambiguous descriptions, so that the app does not silently guess.
21. As a Kyo user, I want a past-date interpretation to let me choose Today or another date, so that the app does not substitute a date without my choice.
22. As a Kyo user, I want an explanation when I enter a time, so that I understand scheduling supports calendar days only.
23. As a Kyo user, I want quick choices and a date picker when Apple Intelligence is unavailable, so that scheduling remains useful on my device.
24. As a Kyo user, I want to recover from interpretation errors using the date picker, so that a model failure does not block scheduling.
25. As a Kyo user, I want Later accessible from Tasks, so that I can find deferred work before its planned day.
26. As a Kyo user, I want Later ordered by planned day, so that the nearest work is easy to find.
27. As a Kyo user, I want stable creation order within a planned day, so that tasks have predictable positions.
28. As a Kyo user, I want to edit deferred task text, so that I can refine it without losing its planned day.
29. As a Kyo user, I want to reschedule a deferred task, so that I can adapt to changed plans.
30. As a Kyo user, I want to bring a deferred task back to Today, so that I can act on it immediately.
31. As a Kyo user, I want to delete a deferred task, so that abandoned work does not remain in Later.
32. As a Kyo user, I want future tasks excluded from Today's counts, so that the summary reflects available work.
33. As a Kyo user, I want a task to appear on its planned day, so that I do not need to restore it manually.
34. As a Kyo user, I want unfinished tasks to carry forward once available, so that missing a planned day does not lose work.
35. As a Kyo user, I want due deferred tasks to appear after several days away, so that availability does not depend on opening the app daily.
36. As a Kyo user, I want saved planned days to survive reopening, so that relative wording does not keep moving the date.
37. As a Kyo user, I want scheduling to preserve identity and creation order, so that moving a task does not duplicate it or reset its position.
38. As a Kyo user, I want normal completion and completion-day history once a task is available, so that existing daily behavior continues.
39. As a Kyo user, I want Month to distinguish planned and completed tasks, so that I can understand future work and past accomplishments.
40. As a Kyo user, I want Month to remain read-only, so that planning does not introduce another editing workflow.
41. As an Apple Watch user, I want deferred tasks hidden before their planned day, so that my wrist shows the same available work as Today.
42. As an Apple Watch user, I want cached tasks to become available without a live phone connection, so that planned-day rollover works offline after synchronization.
43. As a phone and Watch user, I want changes to preserve planned days across synchronization, so that edits do not undo scheduling.
44. As a phone and Watch user, I want retries and stale deliveries to avoid duplicates or resurrection, so that the list stays reliable.

## Implementation Decisions

- Extend the shared task model and TaskListBehavior with an optional planned day, deferred-task access, planned-day queries, and operations for scheduled creation, deferral, rescheduling, and returning a task to Today. Existing unscheduled tasks remain available immediately.
- Store planned days as calendar-day values consistent with the existing completion-day model, rather than absolute timestamps. Resolve dates using the device calendar and local Today. Saved days remain fixed; do not reinterpret the original relative phrase on reopening or shift the chosen day when the time zone changes.
- Add optional planned-day fields through an additive CloudKit-ready SwiftData schema change. Existing records and older decodable tasks and snapshots without a planned day remain unscheduled. Follow the existing storage decision.
- Today includes available incomplete tasks and today's completed tasks, preserving grouping, creation order, counts, and completion history. Later contains incomplete tasks whose planned day is after Today, sorted by planned day then creation order. A planned day is not a deadline.
- Scheduling and edits preserve identity, creation order, and unrelated completion data. Do later applies to active tasks; scheduling does not implicitly reopen a completed task. Reopening remains an explicit operation.
- Use one shared scheduling workflow for creation and Do later, exposing preview, correction, and confirmation above language extraction and calendar arithmetic. Draft scheduling remains separate from saved task changes: cancellation or interpretation failure must not mutate a task. Late results from an obsolete input must not replace the current preview.
- Keep task text and scheduling descriptions separate. Do not infer scheduling from task text or strip apparent dates from it. Preserve the existing text-only creation path.
- A bare weekday means its next occurrence, including Today when it matches. Next Friday means Friday in the next calendar week, respecting the device calendar's first weekday.
- One week out means the same weekday next week through calendar-day addition. One month out means the same calendar day next month, clamped to that month's final day. Leap years and daylight-saving changes follow calendar semantics.
- Preview the full resolved date before saving for every input route. A past date requires choosing Today or another date. Ambiguous or unsupported descriptions require clarification or a date-picker choice. Explain that times are unsupported when present, rather than silently dropping them.
- Extend OnDeviceLanguageModel and its Foundation Models adapter to extract typed date intent. Calendar calculations determine the actual day; generated arithmetic is not authoritative. Reuse availability handling and the controllable model substitute, following the task planned-day decision.
- Quick choices and a date picker work independently of Apple Intelligence. Device ineligibility, unsupported language, disabled AI, model readiness, refusals, invalid output, and request failures retain manual scheduling. Do not introduce cloud interpretation.
- Later is accessible from Tasks on iPhone and iPad with edit, reschedule, delete, and bring-to-Today actions.
- Extend Month task content and summaries with distinct planned and completed states and accessible state descriptions. Preserve read-only interaction and completion-day history; do not invent future completions.
- Preserve phone-authoritative snapshots and Watch-command reconciliation. Snapshots and Watch caches retain planned-day data needed for local rollover; sending only visible tasks would prevent offline emergence.
- Scheduling and Later remain on iPhone and iPad. Watch edits, completion commands, and replay preserve planned-day metadata. Duplicate delivery, acknowledgments, and tombstones retain their existing guarantees.
- Use existing activation and day-boundary refresh behavior for visibility. No rollover notification is required. Offline emergence applies to the last synchronized data; a device cannot display a schedule it has never received.

## Testing Decisions

- The user confirmed the existing-interface approach. Prefer the highest existing behavior boundaries and the fewest new seams. Primary coverage extends TaskListBehavior and its store: assert Today and Later contents, counts, identity, dates, ordering, and operation results rather than private collections, helper calls, or storage layout.
- Exercise shared scheduling through observable preview and confirmation results using the existing controllable OnDeviceLanguageModel substitute. Extend it for date intents and errors rather than mocking task behavior or introducing a public seam for every parser and calendar helper.
- Prior art: TaskListBehaviorTests for operations and controlled rollover; TaskStoragePersistenceTests and UserDefaultsImportTests for storage compatibility; TaskListSyncTests, WatchOriginatedSyncTests, and WatchEditDeleteSyncTests for transport convergence and metadata preservation; MonthTasksBehaviorTests for Month; MemoTaskBehaviorTests for model availability and asynchronous requests.
- Use controlled clocks, calendars, time zones, an in-memory store, and the existing controllable transport. Cover visibility before, on, and after the planned day; missed launches; repeated refresh; carryover; counts; ordering; creation; deferral; rescheduling; bring-to-Today; deletion; and unchanged completion behavior.
- Verify observable date previews for weekday matches Today, next-week Friday under different first-weekday conventions, weekly scheduling across daylight-saving boundaries, month-end overflow, leap-year February, and fixed saved dates after reopening or time-zone changes.
- Verify no save from an unconfirmed, past, ambiguous, invalid, or time-containing interpretation. Cancellation and late results must not commit an obsolete preview. Model availability states and failures retain quick choices and the date picker.
- Verify real persistence reopening and existing-data compatibility, including older records and decodable snapshots without the field. Avoid tests that merely mirror storage field names.
- Connect real phone and Watch task stores through the controllable transport. Cover planned-day preservation, future filtering, cached offline rollover, delayed commands, retries, and out-of-order snapshots. Preserve deletion and acknowledgment guarantees. A substitute transport cannot establish actual WatchConnectivity integration.
- Extend Month's existing behavior boundary for future planned rows and marks, distinct states, rescheduling and deletion updates, and completion history. Add focused screen checks for read-only interaction and accessible labels.
- Follow TaskCheckboxUITests and MonthUITests for focused platform checks: creation and Do later, preview and confirmation, Later actions, fallback, and unchanged text-only creation. Do not duplicate every business rule through screen tests.
- Build phone and Watch schemes and run relevant existing and extended tests. Check synchronization in a suitable paired simulator or device environment and actual AI interpretation on a supported device; scripted output cannot prove model accuracy.

## Out of Scope

- Implementing this feature during the specification request or launching implementation agents.
- Recurring tasks, deadlines, task times, reminders, notifications, priorities, tags, subtasks, and manual reordering.
- Watch scheduling, a Watch Later list, or Apple Intelligence running on Watch.
- Editing from Month or editable future-day views.
- Automatically extracting schedules from task text, silently accepting uncertain interpretations, or cloud language services.
- Replacing storage or sync architecture, expanding iCloud sync, or guaranteeing offline knowledge of changes never received.

## Further Notes

- Today remains the available-work surface; Later manages deferred tasks and Month provides a read-only overview. This extends the original daily-task feature to planned days.
- Product decisions were confirmed in the design interview, including the same weekday next week and the same calendar day next month with month-end handling. Testing boundaries were separately confirmed during specification synthesis.
- Use the glossary's Task, Deferred task, Planned day, Later, Today, Month, and Day summary terms. Existing phone-authoritative synchronization and additive CloudKit-ready storage decisions apply. The calendar-day decision explains why AI extracts intent and calendar calculations determine the date.
- Publish as ready-for-agent. The label describes specification readiness; implementation requires a separate request.
