# Development

Kyo is a SwiftUI app for iPhone, iPad, and Apple Watch. It requires Xcode 27 or later with the iOS and watchOS SDKs; deployment targets are iOS 27 and watchOS 27. It uses Swift 6 without third-party dependencies.

## Run

Open `Kyo.xcodeproj` in Xcode. Select the **Kyo** scheme and an iPhone or iPad simulator, or the **KyoWatch** scheme and an Apple Watch simulator. Install missing simulator runtimes through Xcode Settings → Components.

For physical devices, Kyo signs automatically with the development team set in `project.yml`. If you build with a different team, change `DEVELOPMENT_TEAM` and the `computer.srcery.kyo` bundle identifiers there, including `INFOPLIST_KEY_WKCompanionAppBundleIdentifier`, then regenerate the project.

## Structure

- `Kyo/`: iPhone and iPad app.
- `KyoWatch/`: companion Watch app. It can launch independently of the iPhone app.
- `KyoWidgets/` and `KyoWatchWidgets/`: quick-capture controls and Watch complications.
- `Shared/`: models, stores, and sync code compiled into both apps.
- `KyoTests/` and `KyoUITests/`: unit and UI tests.
- `project.yml`: XcodeGen project definition. The generated Xcode project is checked in so XcodeGen is only needed when changing project configuration.

`KyoTests` has no host app. It compiles all of `Shared/` (a new file there is picked up with no `project.yml` change; one that must stay out of the bundle needs an `excludes` entry) and the `Kyo/` files it tests, which are listed one at a time.

Run `xcodegen generate` after changing `project.yml`. Make lasting build-setting and target changes in that file, since regeneration replaces the Xcode project configuration.

## Build checks

`scripts/check` runs these as part of the pre-merge checks (see Tests below). To run one alone:

```sh
xcodebuild -project Kyo.xcodeproj -scheme Kyo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Kyo.xcodeproj -scheme KyoWatch -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Tests

Run the pre-merge checks through `scripts/check`. It runs everything the change needs, one check at a time, and records the result against the commit; see the CI section for the rules and the record. The rest of this section is about running one suite.

Run tests through `scripts/test <scheme> [extra xcodebuild arguments]`, for example `scripts/test KyoTests`, `scripts/test KyoUITests -only-testing:KyoUITests/SectionCollapseUITests`, or `scripts/test KyoWatchUITests`. Each run gets its own simulator and derived data, so runs from separate worktrees can't interfere, and both are removed afterwards. The script picks an iPhone or Apple Watch simulator from the scheme's test targets, so `--platform` is only an override. Don't call `xcodebuild test` directly.

UI suites queue. `scripts/test KyoUITests` and `scripts/test KyoWatchUITests` (a narrow `-only-testing` run included) take a lock shared by every worktree on the machine before they create their simulator, so only one UI suite runs at a time; several at once each run far slower and can time out under the load. A run that has to wait prints one line naming the holder (worktree and scheme) and starts when the lock is free. The lock is released when the run ends, however it ends. A lock whose holder process is gone is stale, and the next run takes it over. `KyoTests` and the build checks don't take the lock. The lock is the symlink `kyo-ui-lock` in `${TMPDIR:-/tmp}`; its target names the holder.

Never pass `CODE_SIGNING_ALLOWED=NO` to a test run. An unsigned build gives the `KyoWatchWidgets` extension a linker signature whose identifier is `KyoWatchWidgets` instead of its bundle identifier. The Shortcuts daemon then rejects the extension, WidgetKit asserts in `WatchRecordMemoControl`, and the extension is killed when the Watch app first launches on a fresh simulator (#150). `scripts/test` builds signed for the simulator, which needs no account. The build checks above can stay unsigned because they never launch the app.

## CI

**The test workflows are paused.** `CI`, `UI Tests` and `Watch UI Tests` are disabled in GitHub Actions (`gh workflow disable`), so pull requests and pushes to `main` run nothing but TestFlight. Their files stay in `.github/workflows/` as described below; turn them back on with `gh workflow enable "CI"`, `gh workflow enable "UI Tests"` and `gh workflow enable "Watch UI Tests"`. While they're paused, every PR is checked locally before it merges, with `scripts/check`:

```sh
scripts/check                  # the checks the changed paths call for
scripts/check --base <ref>     # changed paths measured from <ref> instead of the merge-base with origin/main
scripts/check --all            # every check, whatever changed
scripts/check --quick          # builds and KyoTests only; the UI suites are recorded as skipped
scripts/check --show [<commit>]
```

It refuses to run with uncommitted changes, because it records the result for `HEAD`. It works out the changed paths between the base and `HEAD`, runs the checks below that those paths call for one at a time (the UI suites queue behind the lock described under Tests), and keeps going after a failure so the record is complete. It exits non-zero if any check failed or was skipped.

The record is a plain-text file named by the full commit SHA in `${TMPDIR:-/tmp}/kyo-check/`, so any worktree or agent can read it. It holds the commit, base and branch, when it ran, each check that ran with the reason, its final `** BUILD SUCCEEDED **` or `** TEST SUCCEEDED **` (or FAILED) line, its test count and the path of its log, each check that did not run with the reason, and a last line that is exactly one of `RESULT: PASS`, `RESULT: FAIL` or `RESULT: PARTIAL`. PARTIAL means a run was `--quick`, or a check the paths called for was skipped. A rerun on the same commit replaces the record. `scripts/check --show [<commit>]` prints the record for a commit (default `HEAD`) without running anything and exits 0 for PASS, 1 for FAIL or PARTIAL, and 2 when there is no record. The pre-merge checks have passed when `scripts/check --show` on the PR's head commit prints `RESULT: PASS`.

The checks:

- both build checks above;
- `scripts/test KyoTests`;
- `scripts/test KyoUITests` when the PR touches `Kyo/`, `KyoUITests/` or `Shared/`, and `scripts/test KyoWatchUITests` when it touches `KyoWatch/`, `KyoWatchWidgets/`, `KyoWatchUITests/` or `Shared/`;
- `xcodegen generate` with no resulting diff when the PR touches `project.yml`.

`.github/workflows/ci.yml` runs on every pull request and every push to `main`, on the `xcode-27` GitHub-hosted runner. It:

- builds the **Kyo** and **KyoWatch** schemes with the commands above;
- runs the **KyoTests** scheme on the iPhone 17 simulator (`KyoUITests` runs separately, see below);
- regenerates `Kyo.xcodeproj` with XcodeGen and fails if it differs from the checked-in project.

`.github/workflows/ui-tests.yml` runs the **KyoUITests** scheme on the same simulator, only on pull requests that change files under `Kyo/` or `KyoUITests/`, or the workflow file, and only once the PR is ready: a draft skips the jobs, and marking the PR ready (`ready_for_review`) starts them. Run `scripts/test KyoUITests` locally while a PR is a draft. The suite is split across two runners, each with its own simulator, as the jobs **Test KyoUITests (1/2)** and **(2/2)**. Shard 1 names its classes with `-only-testing` (`SectionCollapseUITests`, `HabitsSheetUITests`, `ScheduleUITests`, `ScheduleEventDetailUITests`), balanced by measured time. Shard 2 runs everything else by skipping shard 1's classes with `-skip-testing`, so a new UI test class runs in shard 2 without any workflow change; to rebalance, move a class by editing shard 1's `-only-testing` line and shard 2's `-skip-testing` list together. `WatchSyncSmokeUITests` skips itself there. A failed or timed-out shard uploads its result bundle as an artifact named `KyoUITests-xcresult-<shard>`.

Each UI test shard builds first (`build-for-testing`) and tests second (`test-without-building`), and nothing boots the simulator in between: xcodebuild boots it for the test. Do not add a step that boots the simulator before the build or before xcodebuild starts. A freshly booted iOS simulator holds the runner's three cores at a load average of several hundred for the rest of the job, which made xcodebuild take two to four minutes to print its invocation and made the build more than twice as slow (#166). The Watch job does not need this: the watchOS simulator is light enough that its job takes under two minutes in all.

`.github/workflows/watch-ui-tests.yml` runs the **KyoWatchUITests** scheme as the **Test KyoWatchUITests** job, on a freshly booted watchOS 27 simulator (a new one is created if the runner has none). It runs only on ready pull requests (a draft skips it, like the UI tests above) that change `KyoWatch/`, `KyoWatchWidgets/`, `KyoWatchUITests/`, `Shared/`, `project.yml`, or the workflow file. It builds signed for the simulator, without `CODE_SIGNING_ALLOWED=NO`, and the first-launch smoke test is the regression test for #150: the job fails if the Watch app is built unsigned. A failed or timed-out run uploads its result bundle as an artifact.

The XcodeGen version is pinned in the workflow (`XCODEGEN_VERSION`). If the project check fails, install that version, run `xcodegen generate`, and commit the result. A newer push to the same ref cancels the run in progress.

## Storage and sync

On iPhone and iPad, tasks, habits, and memos live in one SwiftData store. Its models follow CloudKit's rules, with sync switched off (`docs/adr/0004-swiftdata-cloudkit-ready-storage.md`). The Watch keeps its own caches in UserDefaults.

The paired iPhone and Watch stay in sync over WatchConnectivity. The phone is the single writer: it publishes a snapshot of the current day's tasks, habits, and memos after every change, and the Watch mirrors it. Changes made on the Watch become commands sent back to the phone, and Watch voice recordings travel to the phone as files. The ADRs record the rules:

- `docs/adr/0001-phone-authoritative-task-snapshots.md`: snapshot reconciliation.
- `docs/adr/0002-watch-commands-and-phone-reconciliation.md`: how Watch-originated commands are applied and acknowledged.
- `docs/adr/0003-habit-sync.md`: the habit snapshot and its trimmed log.
- `docs/adr/0005-watch-memo-sync.md`: the memo snapshot and the recording outbox.

To check real device-to-device delivery, boot a paired iPhone and Watch simulator (or use a paired device), install both apps, launch the Watch app, then run the `KyoUITests` target with `KYO_WATCH_SYNC_SMOKE=1` set, which enables `WatchSyncSmokeUITests` (skipped by default).

## TestFlight

Every push to `main` runs `.github/workflows/testflight.yml`, which archives the `Kyo` scheme (with the Watch app and widgets) unsigned, then signs it with Xcode automatic signing on export and uploads it to TestFlight. It can also be started by hand from the Actions tab (`workflow_dispatch`). The build number is the workflow run number; the marketing version comes from `project.yml`.

Signing uses an App Store Connect API key, so no certificates or provisioning profiles are stored. Add these repository secrets to turn it on:

- `ASC_KEY_ID`: the key's ID.
- `ASC_ISSUER_ID`: the issuer ID shown above the keys list in App Store Connect.
- `ASC_KEY_P8`: the full contents of the downloaded `.p8` file.

Until all three exist, the job skips itself with a notice and the push stays green. The app record for `computer.srcery.kyo` must already exist in App Store Connect. If a run fails, the `xcodebuild-logs` artifact holds the archive and export logs.
