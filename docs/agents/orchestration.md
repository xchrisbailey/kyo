# Orchestration

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
  - the relevant ADRs and `GLOSSARY.md` terms;
  - what is out of bounds;
  - the build and test commands;
  - what to report back: the branch, the PR, a summary, and anything left open.
- Coders don't widen scope or make product or architecture decisions. They stop and report any open question to Opus.

**Parallel work and PRs.**

- Use one branch and one PR per ticket. Name the branch `<type>/<issue>-<slug>`, such as `feat/35-daily-habits`.
- Tickets whose blockers are all merged run in parallel, each in its own worktree, and each PR targets `main`. Parallel work is preferred.
- When a ticket depends on work that isn't merged yet, **stack** it:
  - The coder branches from the blocking ticket's branch and opens a draft PR against that branch.
  - Opus owns the stack. Coders never restructure one.
  - Coder branches come from separate worktrees, so build the stack on GitHub with `gh stack link <bottom PR> <next PR> …`, bottom first. It needs no local tracking.
  - A stack is linear. When two tickets share a base, link one into the stack and leave the other as a sibling PR based on the same branch.
  - Merge a stack with `gh stack merge <stack number> --squash --yes`. It merges every layer into `main` atomically. `gh pr merge` refuses a PR that is part of a stack.
  - Land a sibling after its base has merged: `git rebase --onto origin/main <old base branch> <sibling branch>`, push with `--force-with-lease`, retarget with `gh pr edit <pr> --base main`, wait for CI, then `gh pr merge --squash`.
  - `gh stack merge` leaves the merged branches on the remote. Delete them afterwards.
  - When a lower layer changes before the stack merges, restack by hand the same way: rebase each higher branch onto the changed one and force-push with lease.
  - Stacked PRs are in public preview. If `gh stack` fails, skip the stack: merge the bottom PR, then rebase and retarget each PR above it in turn.
- Keep stacks short. Don't stack work that could run in parallel.
- PR descriptions link the ticket with `Closes #<issue>` and name the PR this one is stacked on, if any.
- A skill that asks for one integration branch and merger agents, such as `implement-spec`, gets this per-ticket PR workflow instead.

**Review.**

- Opus reviews every PR before it's marked ready, checking it against:
  - the ticket's acceptance criteria;
  - the spec and ADRs;
  - the glossary;
  - `CODING_STANDARDS.md` and `AGENTS.md`.
- Opus also confirms that both app schemes build and the tests pass. CI covers the builds and `KyoTests` on every PR, and the UI tests only once a PR is ready: `KyoUITests` (two shards) on PRs that touch `Kyo/` or `KyoUITests/`, and `KyoWatchUITests` on PRs that touch `KyoWatch/`, `KyoWatchWidgets/`, `KyoWatchUITests/`, `Shared/`, or `project.yml`. Draft PRs skip the UI tests, so a coder's draft is checked by its own `scripts/test` runs until Opus marks it ready and CI runs them; a coder's report covers the rest, and counts only when it quotes the final `** TEST SUCCEEDED **` line of each run.
- Review findings go back to the same coder, which keeps its context, until the review passes.
- Opus reports the result to the user. Merge only when the user asks, or has already said to merge PRs that pass review.
