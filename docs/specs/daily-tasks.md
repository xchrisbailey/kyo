# Daily tasks on iPhone, iPad, and Apple Watch

Status: Product behavior confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Hoy presents one day at a time, but its Tasks section currently contains fixed sample rows. Users cannot save a task, complete it, correct its text, or carry unfinished work into tomorrow. The Apple Watch task list is also a static preview.

## Solution

Make Tasks a simple daily list of text entries and checkboxes within the existing layout. On iPhone and iPad, the bottom Add button starts a blank row directly in the list; Return saves the task. Completed tasks move below active tasks and appear gray. Unfinished tasks carry forward automatically. Apple Watch supports adding tasks and toggling completion against the same synchronized list.

## User Stories

1. As a Hoy user, I want to see tasks for the current day, so that the list fits the app's daily focus.
2. As an iPhone or iPad user, I want the bottom Add button to open a blank task row, so that I can enter a task directly in the list.
3. As an iPhone or iPad user, I want Return to save the task text, so that adding a task takes few steps.
4. As a Hoy user, I want a task to need only text, so that I can capture it without scheduling or categorizing it.
5. As a Hoy user, I want active tasks in creation order with new tasks at the bottom of that group, so that their position is predictable.
6. As a Hoy user, I want to check a task off, so that I can record that it is finished.
7. As a Hoy user, I want completed tasks below active tasks and grayed out, so that I can distinguish remaining work from finished work.
8. As a Hoy user, I want creation order preserved within the completed group, so that completion does not introduce a second sorting rule.
9. As a Hoy user, I want to uncheck a completed task, so that I can correct an accidental completion.
10. As a Hoy user, I want an unchecked task restored to its original creation-order position among active tasks, so that the list stays predictable.
11. As an iPhone or iPad user, I want to tap task text to edit it inline, so that I can correct or refine an entry.
12. As an iPhone or iPad user, I want to swipe a task to delete it, so that I can remove an unwanted entry.
13. As a Hoy user, I want unfinished tasks to carry into the next day, so that they are not lost when the date changes.
14. As a Hoy user, I want completed tasks associated with the day they were finished, so that tomorrow starts without yesterday's completed items.
15. As an Apple Watch user, I want to add a task from my wrist, so that I can capture something without opening my phone.
16. As an Apple Watch user, I want to check and uncheck tasks, so that I can update the list from my wrist.
17. As a phone and Watch user, I want both devices to show the same task data, so that changes made on either device are reflected on the other.
18. As a Hoy user, I want my saved tasks to survive closing and reopening the app, so that the list remains useful between sessions.
19. As a Hoy user, I want the task summary to reflect the real list, so that the displayed completion count is accurate.

## Implementation Decisions

- Preserve the existing overall layout and replace the static task rows with functional daily task views on iPhone, iPad, and Watch.
- A task's user-facing content is text and a completion checkbox. Remove the sample time annotation; due dates and times are not part of this feature.
- On iPhone and iPad, the bottom Add action opens a focused blank row in the task list. Return commits the entry. Tapping existing task text starts inline editing; the checkbox independently toggles completion. Swipe-to-delete removes a task.
- Reject blank or whitespace-only entries. Abandoning an empty draft must not create a task. This is a supporting validation requirement rather than an additional product feature.
- Partition tasks into active and completed groups. Sort both groups by stable creation order. Completing, reopening, editing, synchronizing, and carrying a task forward must not reset its creation order.
- Carry unfinished tasks into the current day without duplicating them, including when the app has not been opened for several days. Completed tasks retain their completion-day association.
- Use the actual current day for task behavior and its visible date context, replacing the static date where required for this feature. Historical browsing and editing are separate work.
- Derive task completion summaries from the current day's task data on each device.
- Introduce a shared task model and a task-list interface for the two platform views. The interface owns observable task operations and day behavior; storage and device communication remain behind it.
- Persist saved task changes and synchronize the paired phone/Watch task list. Stable task identity is required so that delivery retries and rollover do not duplicate entries. Choose the concrete storage and synchronization mechanisms during implementation; none exists in the starter today.
- Watch supports adding, completing, and reopening tasks using suitable native text input. Editing and deleting on Watch are outside this scope.
- Preserve accessible task names and completion state when converting the decorative checkbox rows into interactive controls.
- Keep lasting target/build configuration changes in the project's XcodeGen definition and regenerate the checked-in project when necessary.

## Testing Decisions

Test approach proposed during specification review:

- Use one primary behavior-testing boundary: the shared task-list interface consumed by the phone and Watch views. Assert observable lists and results rather than private storage layout, helper calls, or view structure.
- Cover add, edit, delete, complete, reopen, creation-order preservation, active/completed grouping, blank input, and derived task counts.
- Control the current day in tests to verify overnight carryover, reopening after several days, completion-day retention, and repeated rollover without duplication.
- Verify persistence by saving changes and reopening the task list against the same test storage.
- Exercise two task-list instances connected by a controllable transport to verify phone/Watch convergence for supported operations and duplicate delivery. Do not mock the task behavior under test.
- Complement these checks with focused platform interaction checks: bottom Add focuses a row, Return saves, text editing and checkbox taps act independently, swipe deletes, completed rows appear gray, and Watch input/toggling works.
- Build both app schemes. Check actual paired-device communication in a suitable paired simulator or device environment; a transport substitute cannot establish that platform integration works.
- There is no existing test target or comparable automated test suite in the repository. Add the minimum test configuration needed for these observable behaviors.

## Out of Scope

- Implementing the feature as part of this specification request.
- Due dates, task times, reminders, priorities, tags, subtasks, recurring tasks, and manual reordering.
- Editing or deleting tasks on Apple Watch.
- New historical-day navigation or editing workflows.
- General cloud account synchronization across multiple phones or tablets beyond the requested paired phone/Watch behavior.
- Implementing Habits, Memos, or Meals, or redesigning the overall app layout.

## Further Notes

- Execution policy for future implementation: the active orchestration model owns orchestration and review; the coder assignment is **Luna, high reasoning** (`gpt-6-luna`, `high`). The review role intentionally follows whichever model is running orchestration rather than naming a fixed reviewer model.
- This policy is recorded for future execution. No implementation agents should be launched by this spec-writing request.
- The product behavior above was confirmed in the design interview. Persistence, synchronization robustness, validation, and accurate summaries are supporting requirements for making that behavior work reliably.
- Publish this specification to the configured GitHub issue tracker with the `ready-for-agent` label. That label describes specification readiness; it does not authorize implementation or launch implementation agents.
