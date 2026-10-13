# Projects

Status: Design interview in progress. Only the decisions below are confirmed; implementation requires a separate user request.

## Problem Statement

Tasks for a body of work such as building Kyo are mixed with everyday tasks on Today. The user wants related project work kept together and separated from everyday tasks.

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

## Open Decisions

- Restoration of previously chosen or scheduled tasks and editing archived content.
- Empty sections, project ordering, capture defaults, and task actions at the edges of the lists.

Terms follow root GLOSSARY.md. No implementation or architecture decision has been made.
