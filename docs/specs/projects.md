# Projects

Status: Product behavior and testing boundaries confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Tasks for a body of work such as building Kyo are mixed with everyday tasks on Today. The user wants project work kept together without turning Today into a list of everything they may eventually do. Related memos should also be easy to find after their creation day has passed.

## Solution

Add one Projects section to Today, with a collapsible group for each project that has available tasks or tasks completed today. Keep everyday tasks in Tasks. All projects opens the full project list, and opening a project shows its complete task list and linked memos.

Project tasks can be held unscheduled, chosen for Today, or deferred to a planned day. Available unfinished tasks carry forward. Project memos keep their creation day and remain accessible through existing memo views. Archiving puts a project away without losing its content; restoration respects its previous task choices. Full project management is on iPhone and iPad, while Watch shows and supports acting on available project tasks.

## User Stories

1. As a Kyo user, I want a project to represent a named body of work, so that related work such as building Kyo stays together.
2. As a Kyo user, I want to keep a project active without a fixed finishing point, so that ongoing work fits the same model.
3. As an iPhone or iPad user, I want to create a project from All projects, so that I can start organizing a new body of work.
4. As an iPhone or iPad user, I want to rename an active project, so that its name can follow changes in my work.
5. As a Kyo user, I want projects listed in creation order, so that their position stays predictable.
6. As an iPhone or iPad user, I want All projects to separate active and archived projects, so that current work is easy to find.
7. As a Kyo user, I want one Projects section on Today, so that project work is separated without multiplying top-level sections.
8. As a Kyo user, I want Projects between Tasks and Habits, so that task work stays together in the existing layout.
9. As a Kyo user, I want available project tasks grouped by project, so that I can see which body of work each task belongs to.
10. As a Kyo user, I want everyday tasks to stay in Tasks, so that personal daily work remains distinct from project work.
11. As a Kyo user, I want a task to appear in only one Today list, so that organization does not create duplicate work.
12. As a Kyo user, I want only chosen or now-available planned project tasks on Today, so that eventual work does not crowd my day.
13. As an iPhone or iPad user, I want to tap a project name on Today to open its details, so that I can reach its full content.
14. As an iPhone or iPad user, I want All projects in the Projects header even when the section is collapsed or empty, so that every project remains reachable.
15. As a Kyo user, I want a project group hidden when it has no available tasks or tasks completed today, so that Today stays compact.
16. As a Kyo user, I want an empty Projects section to say No project tasks for today, so that I understand why it has no rows.
17. As an iPhone or iPad user, I want New project offered when no projects exist, so that the empty section helps me begin.
18. As a Kyo user, I want to collapse Projects and individual project groups, so that I can control how much project work Today shows.
19. As a Kyo user, I want collapse choices remembered across days and launches on each device, so that my layout stays consistent.
20. As a Kyo user, I want new projects expanded initially, so that their available tasks are visible when first shown.
21. As a Kyo user, I want choosing a task for Today to leave a collapsed project group collapsed, so that selection respects my layout.
22. As a Kyo user, I want each project group to show its own done count, so that I can see progress on today's project work.
23. As a Kyo user, I want Today's overall task count to include everyday and project tasks exactly once, so that the summary reflects all available work.
24. As a Kyo user, I want completed project tasks below unfinished ones on Today, so that remaining work is easier to scan.
25. As a Kyo user, I want yesterday's completed project tasks to leave Today, so that a new day shows current work.
26. As an iPhone or iPad user, I want project details to separate Today, Later, Unscheduled, and Completed tasks, so that I can distinguish availability and completion.
27. As an iPhone or iPad user, I want Completed to be collapsible, so that finished work remains accessible without dominating project details.
28. As a Kyo user, I want creation order preserved within project task lists except Later, so that edits and completion do not unexpectedly reorder work.
29. As a Kyo user, I want Later tasks ordered by planned day, so that upcoming work is easy to review.
30. As an iPhone or iPad user, I want tasks added inside a project to start Unscheduled, so that capturing an idea does not commit it to Today.
31. As an iPhone or iPad user, I want Do today on an unscheduled project task, so that I can choose it when I am ready to work on it.
32. As an iPhone or iPad user, I want Do later to use the existing scheduling flow, so that project planning behaves like other task planning.
33. As a Kyo user, I want a planned project task to become available when its planned day arrives, so that my previous choice takes effect.
34. As a Kyo user, I want available unfinished project tasks to carry forward, so that unfinished work is not lost overnight.
35. As an iPhone or iPad user, I want Return to project on an unfinished available task, so that I can remove it from Today without deleting or completing it.
36. As an iPhone or iPad user, I want Return to project on a deferred task to clear its planned day, so that it becomes unscheduled again.
37. As a Kyo user, I want unscheduled project tasks excluded from Today, Later, Month, and their counts, so that unchosen work stays inside its project.
38. As an iPhone or iPad user, I want a task added directly in Today's project group to start on Today, so that capture there reflects my current intent.
39. As an iPhone or iPad user, I want Today's bottom Add menu to offer an optional project picker, so that I can capture project work without first navigating into it.
40. As an iPhone or iPad user, I want bottom-menu task capture to default to Today even with a project selected, so that its existing daily behavior remains predictable.
41. As an iPhone or iPad user, I want a future planned day chosen during capture to send the task to Later, so that scheduled work stays out of Today until available.
42. As a Kyo user, I want project tasks to support existing editing, completion, deletion, and sharing, so that organization does not reduce task capabilities.
43. As a Kyo user, I want reopening a completed project task to make it available on Today, so that I can act on work that is unfinished after all.
44. As an iPhone or iPad user, I want to move an existing task into a project or between projects, so that I can organize work I already captured.
45. As a Kyo user, I want moving a task to preserve its identity, text, order, completion, and planned day, so that organization does not change its meaning or timing.
46. As an iPhone or iPad user, I want Remove from project, so that a task can return to everyday work.
47. As a Kyo user, I want removing an unscheduled task from its project to make it available on Today, so that it remains reachable as an everyday task.
48. As a Kyo user, I want each task and memo to belong to at most one project, so that ownership and counts are unambiguous.
49. As an iPhone or iPad user, I want project assignment pickers to list only active projects, so that I do not add work to projects I have put away.
50. As an iPhone or iPad user, I want Add memo inside a project to assign that project automatically, so that related thoughts stay together.
51. As an iPhone or iPad user, I want project memos to support written and voice capture with existing memo features, so that I can use the capture method that fits the moment.
52. As an iPhone or iPad user, I want an optional project picker during everyday memo capture, so that a thought can be organized immediately.
53. As an iPhone or iPad user, I want to assign, switch, or remove a memo's project, so that I can organize existing thoughts without copying them.
54. As a Kyo user, I want project memos to keep their original creation day, so that organizing them does not rewrite my daily record.
55. As a Kyo user, I want project memos to remain in Today's memos when appropriate, Memo history, and Month, so that familiar routes still work.
56. As an iPhone or iPad user, I want project memos listed newest first inside the project, so that recent thoughts are easy to find.
57. As a Kyo user, I want Today's Projects section to show tasks while project memos live in project details, so that daily project work stays focused.
58. As an iPhone or iPad user, I want Archive project to retain all its content, so that I can put work away safely.
59. As a Kyo user, I want archived project tasks absent from Today and Later, so that put-away work stops competing for attention.
60. As an iPhone or iPad user, I want archived project details available for read-only reference, so that I can inspect past work before restoring it.
61. As a Kyo user, I want historical project completions and memos accessible while archived, so that archiving does not erase my daily record.
62. As an iPhone or iPad user, I want Restore project, so that I can resume work without recreating it.
63. As a Kyo user, I want restored available tasks to return to Today and future tasks to Later, so that restoration respects my previous choices.
64. As a Kyo user, I want a restored task whose planned day passed during archiving to become available on Today, so that it does not remain stranded in the past.
65. As a Kyo user, I want restored unscheduled tasks to stay inside the project, so that restoration does not choose new daily work for me.
66. As a Kyo user, I want completing every task to leave the project active, so that I decide when the body of work is put away.
67. As an iPhone or iPad user, I want one Later list with project names shown on project tasks, so that I can review all scheduled work together.
68. As an iPhone or iPad user, I want Month to identify project tasks using existing planned-day and completion-day rules, so that the overview reflects project work consistently.
69. As an Apple Watch user, I want a separate Projects section grouped by project, so that chosen project work is distinct from everyday tasks on my wrist.
70. As an Apple Watch user, I want to complete, reopen, edit, and delete available project tasks, so that supported daily task actions work from my wrist.
71. As a phone and Watch user, I want project task changes to converge after disconnection and retry, so that both devices show consistent work without duplication or resurrection.
72. As an Apple Watch user, I want synchronized future project tasks to become available on their planned day while offline, so that existing planned-day behavior continues to work.
73. As a Kyo user, I want saved projects, assignments, and availability choices to survive relaunch, so that my organization is durable.
74. As an existing Kyo user, I want an upgrade to preserve tasks, habits, memos, completion records, planned days, and pending Watch changes, so that adding projects does not damage my data.
75. As a VoiceOver user, I want project navigation, task controls, counts, and collapse states announced clearly, so that I can organize and act on project work accessibly.

## Implementation Decisions

- Use the established domain vocabulary: Project, Archived project, Task, Unscheduled project task, Planned day, Today, Later, Month, Memo, and Collapsed section. A Project may remain active indefinitely.
- Add project identity, name, creation order, and archive state to persistent content. Tasks and memos have optional project association; one content record belongs to at most one project. Moving or displaying content never copies it.
- Represent unscheduled project task availability explicitly. A missing planned day alone cannot mean Unscheduled: existing everyday tasks without planned days are available on Today. Archiving preserves availability and planned days rather than rewriting them.
- Preserve existing task and memo identities, creation order or creation time, completion-day records, and calendar-day associations through assignment changes. Remove from project converts an unscheduled task to an available everyday task; otherwise timing and completion stay intact.
- Extend the existing task-list and memo interfaces rather than creating parallel task or memo storage. Use one project-list/detail behavior interface consumed by the project screens to compose these capabilities and own project lifecycle operations. Exact types and storage relationships remain implementation choices.
- Today order is Schedule, Tasks, Projects, Habits, Memos. Tasks shows everyday tasks only. Projects groups tasks from active projects that are available or completed today. Overall Today task summaries count both lists exactly once; each project group has its own done count.
- Preserve existing task ordering on Today: unfinished before completed, creation order within each. Completed tasks leave Today after their completion day; available unfinished tasks carry forward until returned to their project or the project is archived.
- Keep Today and Month in bottom navigation. All projects remains in the Projects header when empty or collapsed. Tapping a project name opens its details. All projects separates active and archived projects and offers New project.
- Projects use creation order. Project details show Tasks and Memos; task lists are Today, Later, Unscheduled, and collapsible Completed. Preserve creation order within each task list except Later, which uses planned-day order. Memos are newest first.
- Projects and project groups can collapse independently. Persist collapse choices per device across launches and days using the existing collapse-state approach with stable identities. New projects start expanded. Choosing a task for Today does not expand a collapsed project group.
- Keep the Projects header visible without available work. The expanded empty section says No project tasks for today and offers New project when no projects exist.
- Inside a project, Add task assigns the project and starts Unscheduled. Do today makes it available; Do later uses the existing scheduling workflow. Return to project makes an unfinished task Unscheduled and clears its planned day, whether invoked from Today or Later.
- A task added directly in Today's project group starts on Today. Today's bottom Add menu keeps everyday capture, with an optional project picker; task capture there starts on Today unless a future planned day is chosen. Reopening a completed project task makes it available on Today.
- Add memo inside a project assigns it automatically. The bottom Add menu offers optional project assignment for memos. Move to project and Remove from project apply to existing tasks and memos; assignment pickers list only active projects.
- Linked memos retain all existing written and voice memo capabilities and their day-based visibility. They also appear inside their project without duplicating records or day-based counts. Today's Projects section displays tasks, not memos.
- Archive project keeps its content but holds its tasks out of Today and Later. Archived project details and reference views opened from them are read-only until restored. Historical completions and memos remain accessible in Month and Memo history; existing memo actions through those day-based routes remain available. Archiving does not cancel in-flight recording, transcription, title generation, or media saving. Finishing all tasks never archives the project automatically.
- Restore project preserves Unscheduled tasks, returns previously available unfinished tasks to Today, returns future deferred tasks to Later, and makes deferred tasks whose planned day has arrived available on Today. Completed tasks retain their completion-day behavior.
- Later stays one list across everyday and active project tasks, ordered by planned day and displaying project names. Month uses existing planned-day and completion-day rules and identifies project tasks. Unscheduled project tasks appear in neither view.
- On iPhone and iPad, implement full project management. On Watch, add a Projects section grouped by project with supported task completion, reopening, editing, and deletion. Project creation, assignment, All projects, and project memo browsing stay on iPhone and iPad.
- Continue phone-authoritative task snapshots and Watch commands under ADRs 0001 and 0002. Carry enough project identity, display information, and availability in synchronized data for Watch grouping, archive/restore updates, and local planned-day rollover. Future incomplete project tasks remain available to the Watch cache for offline rollover; Unscheduled and archived project tasks must not emerge on Watch Today.
- Preserve revisions, pending-command replay, acknowledgments, duplicate-delivery handling, and delete tombstones. Existing Watch adds remain everyday tasks because Watch project assignment is outside scope. Project organization must not be inferred or overwritten by task edit or completion commands. Apply queued Watch commands under the existing receipt-order rules even when their project has been archived, while keeping archived tasks out of active views; archiving must not discard queued edits or completion, or undo deletion after restoration.
- Continue memo synchronization under ADR 0005. Project association does not remove an otherwise eligible memo from the Watch's existing day-based memo list or introduce project memo browsing there.
- Persist phone/iPad content in SwiftData under ADR 0004: additive schema evolution, no unique constraints, optional relationships with inverses where relationships are used, no deny delete rules, and application-level identity deduplication. Keep existing external media storage behavior and leave CloudKit sync disabled as it is today.
- Plan the storage and Watch cache/payload migrations before coding. Existing content upgrades with no project association and its prior availability, completion, and day records intact. Preserve existing device collapse preferences when extending them.
- Planned days remain fixed calendar dates of availability under ADR 0008. Reuse quick choices, date confirmation, and optional on-device interpretation; do not reinterpret saved dates or turn them into deadlines.
- Follow existing accessibility behavior and identifier conventions for section buttons, project navigation, task rows, and capture controls. Keep navigation and collapse controls independently operable.

## Testing Decisions

The user approved these testing boundaries together with the seven-ticket implementation breakdown.

- Prefer the existing view-consumed TaskListBehavior and MemoStoreBehavior boundaries for task availability, assignment, completion, counts, and memo day preservation. Use one additional project-list/detail behavior boundary for project creation, rename, archive/restore, grouped Today content, and full project lists. Exercise real task and memo stores behind it, rather than mocking the collaborating behavior being verified.
- Test observable actions and results, not view structure, private helpers, particular database relationships, or which internal methods were called. Assert stable identities, visible lists, counts, preserved dates, persistence after reopening, and convergence after delivery.
- Cover project creation and rename, creation ordering, active/archived listing, read-only archived details, and project ownership changes through the behavior interfaces. Verify moving content never duplicates it and invalid assignments cannot create orphaned content.
- Drive availability with controlled clocks and calendars: project capture starts Unscheduled; Do today, Do later, Return to project, and reopening transition the same task; unfinished available tasks carry forward; completed tasks leave Today at rollover; unscheduled tasks do not become available merely because time passes.
- Exercise capture defaults from project details, a Today project group, and the bottom Add menu. Verify schedule confirmation and moving existing tasks retain the chosen planned day and intact text.
- Assert disjoint everyday and project Today lists, correct total and per-project counts, task ordering, empty project sections, and group visibility with only tasks completed today. Verify Later and Month projections identify project tasks without counting them twice.
- Verify memo assignment preserves identity, creation day, ordering, written text or transcript, audio, and photos. Use existing memo capture/media coverage for unchanged behavior and focused project tests for association and visibility through project details, Today, Memo history, and Month.
- Archive a project with available, future, unscheduled, and completed tasks plus memos. Advance the clock before restoration and verify each availability state, retained historical access, and the read-only behavior while archived. Verify completed-all projects remain active.
- Test relaunch persistence and an installed pre-project database upgrade through real storage, including existing unassigned tasks, deferred tasks, past completions, habits, memos, and external media. Assert no unintended availability or identity changes.
- Extend existing phone/Watch synchronization tests with controllable delivery: grouping metadata, phone rename and archive/restore updates, Watch completion/edit/delete, disconnected retries, duplicate and stale snapshots, task deletion, and future project tasks becoming available offline. Verify acknowledged commands retire and neither archive updates nor task commands accidentally clear project membership or resurrect content.
- Reuse the existing collapse-state boundary for section and stable project-group preferences. Verify independent device preferences, defaults for new projects, persistence, and choosing tasks without expanding collapsed groups.
- Prior art: TaskListBehaviorTests and TaskSchedulingBehaviorTests for task actions and controlled dates; MemoStoreBehaviorTests and MemoHistoryBehaviorTests for day-based memo visibility; MonthTasksBehaviorTests for read-only Month projections; TaskStoragePersistenceTests for real-store reopening and installed-schema upgrades; TaskListSyncTests, DeferredTaskSyncTests, WatchOriginatedSyncTests, and WatchEditDeleteSyncTests for controllable phone/Watch convergence; CollapsedSectionsBehaviorTests and WatchCollapsedCountBehaviorTests for collapse state and summaries.
- Add focused UI checks only for behavior model tests cannot establish: All projects and project detail navigation, context-sensitive capture and assignment, independent header controls, actual section/group collapse, Watch task controls, and VoiceOver labels and states. Use existing launch-state injection for isolation.
- Build both app schemes and run the required local checks for the final implementation commit. Use a paired device or supported paired simulator check for actual task synchronization; simulated delivery proves behavior, not platform transport integration. Changes to actual memo file transfer require paired-device verification as specified by ADR 0005.

## Out of Scope

- Implementing the feature or launching coding agents as part of this specification request.
- Permanent project deletion or automatic archiving when all tasks are completed.
- Priorities, subtasks, deadlines, reminders, tags, project nesting, and manual ordering.
- Full project management, project assignment, project memo browsing, and new Watch capture routes.
- Replacing Today and Month navigation, reordering arbitrary sections, or placing a separate top-level Today section for every project.
- Editing historical tasks through Month, changing existing memo day associations, or treating planned days as deadlines.
- New iCloud synchronization, accounts, servers, collaboration, or a second authoritative Watch writer.
- A separate project memo storage or media pipeline, and additional project-specific memo AI behavior.

## Further Notes

- The user accepted all recommendations in the design interview and confirmed the complete product design. This expanded specification synthesizes that discussion; it does not reopen product decisions.
- The user approved seven vertical implementation slices and the testing boundaries. Publish those child tickets with ready-for-agent and their blocking relationships; leave parent issue #253 unchanged under the to-tickets workflow.
- Keep this document as the specification's single home. The issue carries the Problem Statement, Solution, and a link to the document; implementation tickets should refer back to it.
- Root glossary definitions were updated during the interview. No architecture ADR was added for reversible layout choices. Any implementation decision that meaningfully changes existing storage or synchronization constraints needs explicit architectural review before coding.
- Follow repository orchestration for coding, review, and verification. The lead owns schema integration: after a slice changes the schema or migration chain, later branches must rebase and rerun installed-store migration and reopening checks before merge. Previously released schema shapes remain frozen. Ticket publication does not assign or start implementation.
