# Projects

Status: Product behavior confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Tasks for a body of work such as building Kyo are mixed with everyday tasks on Today. The user wants related project work kept together and separated from everyday tasks.

## Solution

Add one Projects section to Today, with a collapsible group per project showing only tasks chosen for today. Project details hold the full task list and linked memos. A project task is still a Task, with the existing editing, completion, deletion, and sharing behavior; its project association and availability determine where it appears.

## Confirmed Decisions

- A Project is a named body of work that groups related tasks separately from everyday tasks. It need not have a known finishing point.
- Today has one Projects section, with a collapsible group for each project, rather than a separate top-level section for every project.
- The full task list is accessible inside the project. Today shows only project tasks the user has chosen for today.
- Chosen project tasks carry forward when unfinished, like existing tasks.
- Keep Today and Month as the bottom navigation. An All projects link in the Projects header opens the full project list, including projects with no tasks chosen for today. Tapping a project's name on Today opens its full tasks and details.
- A task added inside a project stays in the project by default. Do today brings it onto Today; Do later selects a planned day through the existing scheduling flow. A task added directly in Today's project group starts on Today.
- Return to project removes an unfinished task from Today without deleting or completing it.
- A memo may belong to one project. It keeps its creation day and remains accessible through existing day-based memo views and Memo history, as well as inside the project.
- Today's Projects section shows tasks. Project memos are accessible inside the project.
- Archive project retains its tasks and memos for reference and holds its tasks out of Today and Later until restored. Completing all tasks does not automatically archive a project. Permanent project deletion is outside the first version.
- A task or memo belongs to at most one project. Move to project can assign or switch its project; Remove from project clears that association. Moving a task preserves its completion and planned day. Removing an unscheduled project task makes it an everyday task available on Today.
- Full project management is on iPhone and iPad. Watch shows chosen project tasks in a separate Projects section grouped by project, supporting completion, editing, and deletion like existing tasks. All projects, project memos, and project assignment are on iPhone and iPad in the first version.
- Today section order is Schedule, Tasks, Projects, Habits, Memos. Everyday tasks appear only in Tasks; chosen project tasks appear only under their project. The overall task count includes both. Each project group shows its own done count, and completed tasks stay below unfinished tasks until tomorrow. Collapse choices persist per device.
- Project details show the project name, Tasks, and Memos. Tasks are split into Today, Later, Unscheduled, and a collapsible Completed list. Creation order is preserved within each task list except Later, which uses planned-day order. Memos are newest first.
- Add task and Add memo inside a project automatically assign that project. The bottom Add menu keeps everyday capture and gains an optional project picker for tasks and memos. New project is available in All projects. Choosing a task for Today does not expand a collapsed project group.
- Later remains one list of scheduled tasks and shows project names on project tasks. Month includes project tasks under existing planned-day and completion-day rules, showing project names. Unscheduled project tasks appear in neither view.
- Priorities, subtasks, deadlines, and manual ordering are outside the first version.
- Archiving preserves task availability choices and planned days. On restore, previously available unfinished tasks return to Today; scheduled unfinished tasks whose planned day has arrived become available on Today; future tasks return to Later; unscheduled tasks stay inside the project. Past completions and memos remain visible in Month and Memo history while archived. Archived project details are read-only until restored.
- Keep the Projects header and All projects link visible when no project tasks are on Today. The expanded section says No project tasks for today and offers New project if no projects exist. Show a project group only when it has unfinished available tasks or tasks completed today. Projects use creation order; new projects start expanded. All projects separates active and archived projects. Active projects can be renamed.
- Inside a project, new tasks start Unscheduled. From Today's bottom Add menu, tasks start on Today even when a project is selected; choosing a future day sends them to Later. Moving existing tasks between projects preserves their timing.
- Return to project can also remove a task from Later: it clears the planned day and holds the task unscheduled in its project. Reopening a completed task makes it available on Today. Project memos support existing written and voice memo features. Assignment pickers list only active projects.

## Scope and Constraints

- No permanent project deletion, priorities, subtasks, deadlines, or manual ordering in the first version.
- No full project management, project assignment, or project memo browsing on Watch in the first version.
- Project association does not copy a task or memo. Counts and completion records must not count the same content twice.
- Planned days remain calendar days of availability, not deadlines, as in ADR 0008.
- Implementation must respect the phone-authoritative synchronization in ADRs 0001 and 0002 and the persistence constraints in ADR 0004. Storage representation, synchronization changes, migrations, and implementation ticket breakdown must be designed before coding.

## Acceptance and Validation

- A user can create and rename a project, open it from All projects or Today, and capture tasks and written or voice memos inside it.
- Unscheduled project tasks remain outside Today, Later, Month, and their counts. Do today, Do later, and Return to project move the same task between availability states without duplicating it or changing its project.
- Everyday tasks and available project tasks appear in their respective Today sections. Overall counts include both exactly once. Completion, reopening, and day rollover retain the existing task behavior.
- Moving tasks or memos between projects preserves their content and day associations. Removing an unscheduled task from its project makes it available as an everyday task.
- Archiving hides project tasks from Today and Later and makes project details read-only. Restoration respects preserved availability and planned days, including dates that passed while archived. Historical completions and memos remain accessible.
- Later and Month identify project tasks; project memos retain day-based access and appear in their project without duplication.
- Project and section collapse choices survive relaunch independently on each device. All projects stays reachable when Today has no project tasks.
- Phone and Watch converge for supported task changes, including archive and restore updates from the phone. Existing tasks and memos survive any storage or synchronization migration without acquiring an unintended project or losing their existing availability.
- Verify behavior through the model interfaces consumed by the views, with controlled days, persistence, and synchronization. Use focused UI checks for capture, navigation, project assignment, collapse behavior, and accessibility. Build both app schemes and run the required local checks against the final implementation commit.

Terms follow root GLOSSARY.md. No implementation has been authorized. The interview captured product behavior; no new architecture ADR was needed for the layout choices.
