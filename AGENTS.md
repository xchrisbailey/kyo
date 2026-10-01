## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues for `xchrisbailey/kyo`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

Use a single-context layout. See `docs/agents/domain.md`.

### Git workflow

Use Conventional Commits for every commit, such as `feat: add task entry` or `docs: specify daily tasks`.
Commit and push completed changes to the GitHub remote. Before pushing, check the working tree and confirm the branch is up to date with its remote counterpart.

### Orchestration

**Roles.**

- **Opus 5.5** (`claude-opus-5-5`) is the main session. It plans, breaks work into tickets, delegates, reviews, and decides. Orchestration and review are never delegated.
- **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`) does all delegated coding and test writing, through the `coder` agent in `.claude/agents/coder.md`.
- Opus fixes trivial review nits itself. Anything larger goes back to a coder.
- When a spec or ticket records execution assignments, it uses these roles unless the user names others for that work.

**Delegation.**

- Each delegated task is confined to one ticket, or one clearly bounded piece of one.
- Run it in a subagent or a new thread with its own git worktree and branch.
- The brief must stand alone. Include:
  - the ticket link and its acceptance criteria;
  - the relevant ADRs and `CONTEXT.md` terms;
  - what is out of bounds;
  - the build and test commands;
  - what to report back: the branch, the PR, a summary, and anything left open.
- Coders don't widen scope or make product or architecture decisions. They stop and report any open question to Opus.

**Parallel work and PRs.**

- Use one branch and one PR per ticket. Name the branch `<type>/<issue>-<slug>`, such as `feat/35-daily-habits`.
- Tickets whose blockers are all merged run in parallel, each in its own worktree, and each PR targets `main`. Parallel work is preferred.
- When a ticket depends on work that isn't merged yet, **stack** it:
  - The coder branches from the blocking ticket's branch and opens a draft PR against that branch.
  - Opus owns the stack and manages it with [`gh stack`](https://github.github.com/gh-stack/) (the `github/gh-stack` extension):
    - `gh stack init <bottom-branch> <next-branch> …` adopts the existing branches, bottom first.
    - `gh stack submit --auto` pushes them and links the PRs as a stack on GitHub. It keeps new PRs as drafts; `--open` marks them ready.
    - `gh stack rebase` restacks the branches after a lower layer changes.
    - `gh stack sync --prune` runs after a lower layer merges.
    - `gh stack link <branches or PRs>` builds the stack on GitHub without local tracking, for example when the branches came from separate worktrees.
  - Coders never restructure a stack.
  - Always pass `--auto` (or explicit arguments), because `gh stack submit` otherwise opens an interactive editor.
  - Stacked PRs are in public preview. If `gh stack` fails, stack by hand instead: rebase onto the merged base or `main`, then retarget with `gh pr edit <pr> --base <branch>`.
- Keep stacks short. Don't stack work that could run in parallel.
- PR descriptions link the ticket with `Closes #<issue>` and name the PR this one is stacked on, if any.

**Review.**

- Opus reviews every PR before it's marked ready, checking it against:
  - the ticket's acceptance criteria;
  - the spec and ADRs;
  - the glossary;
  - this file.
- Opus also confirms that both app schemes build and the tests pass.
- Review findings go back to the same coder, which keeps its context, until the review passes.
- Opus reports the result to the user. Merge only when the user asks, or has already said to merge PRs that pass review.
