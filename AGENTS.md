## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues for `xchrisbailey/hoy`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

Use a single-context layout. See `docs/agents/domain.md`.

### Git workflow

Use Conventional Commits for every commit, such as `feat: add task entry` or `docs: specify daily tasks`.
Commit and push completed changes to the GitHub remote. Before pushing, check the working tree and confirm the branch is up to date with its remote counterpart.

### Orchestration

The model running orchestration owns review as well as coordination. Do not assign a fixed reviewer model. Keep coder assignments explicit when a ticket specifies one.
