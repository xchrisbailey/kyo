# Projects

Status: Design interview in progress. Only the decisions below are confirmed; implementation requires a separate user request.

## Problem Statement

Tasks for a body of work such as building Kyo are mixed with everyday tasks on Today. The user wants related project work kept together and separated from everyday tasks.

## Confirmed Decisions

- A Project is a named body of work that groups related tasks separately from everyday tasks. It need not have a known finishing point.
- Today has one Projects section, with a collapsible group for each project, rather than a separate top-level section for every project.
- The full task list is accessible inside the project. Today shows only project tasks the user has chosen for today.
- Chosen project tasks carry forward when unfinished, like existing tasks.

## Open Decisions

- Where the full project list and project details are reached, including projects with no tasks chosen for today.
- How project tasks are captured, chosen for Today, scheduled for a future day, and returned to the project without completing them.
- Whether projects include memos and how those relate to existing day-based memos.
- Project lifecycle and removal behavior.
- Section placement, counts, completed tasks, Later, Month, and Apple Watch behavior.

Terms follow root GLOSSARY.md. No implementation or architecture decision has been made.
