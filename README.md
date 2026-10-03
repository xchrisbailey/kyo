# Kyo

SwiftUI starter for iPhone, iPad, and Apple Watch. Requires Xcode 27 or later with the iOS and watchOS SDKs; deployment targets are iOS 27 and watchOS 27. Uses Swift 6 without third-party dependencies.

## Run

Open `Kyo.xcodeproj` in Xcode. Select the **Kyo** scheme and an iPhone or iPad simulator, or the **KyoWatch** scheme and an Apple Watch simulator. Install missing simulator runtimes through Xcode Settings → Components.

For physical devices, select your development team under Signing & Capabilities for both targets. Replace the placeholder `com.example.kyo` bundle identifiers in `project.yml`, including `WKCompanionAppBundleIdentifier`, then regenerate the project.

## Structure

- `Kyo/`: iPhone and iPad app entry point.
- `KyoWatch/`: companion Watch app entry point. It can launch independently of the iPhone app.
- `Shared/`: SwiftUI views and future shared models, compiled into both apps.
- `project.yml`: XcodeGen project definition. The generated Xcode project is checked in so XcodeGen is only needed when changing project configuration.

Run `xcodegen generate` after changing `project.yml`. Make lasting build-setting and target changes in that file, since regeneration replaces the Xcode project configuration.

## Build checks

```sh
xcodebuild -project Kyo.xcodeproj -scheme Kyo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Kyo.xcodeproj -scheme KyoWatch -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## CI

`.github/workflows/ci.yml` runs on every pull request and every push to `main`, on the `xcode-27` GitHub-hosted runner. It:

- builds the **Kyo** and **KyoWatch** schemes with the commands above;
- runs the **KyoTests** scheme on the iPhone 17 simulator (`KyoUITests` is not run);
- regenerates `Kyo.xcodeproj` with XcodeGen and fails if it differs from the checked-in project.

The XcodeGen version is pinned in the workflow (`XCODEGEN_VERSION`). If the project check fails, install that version, run `xcodegen generate`, and commit the result. A newer push to the same ref cancels the run in progress.

## Sync

Tasks are saved to UserDefaults on each device (`Shared/DailyTask.swift`) and kept in sync
between the paired iPhone and Watch over WatchConnectivity: the phone publishes a full snapshot
of the current day's tasks after every change, and the Watch mirrors it. The Watch can also add,
toggle, edit, and delete tasks from its own UI; those become commands sent back to the phone,
which stays the single writer of the synchronized list. See
`docs/adr/0001-phone-authoritative-task-snapshots.md` for the snapshot reconciliation rule and
`docs/adr/0002-watch-commands-and-phone-reconciliation.md` for how Watch-originated commands are
applied and acknowledged.

To check real device-to-device delivery, boot a paired iPhone and Watch simulator (or use a
paired device), install both apps, launch the Watch app, then run the `KyoUITests` target with
`KYO_WATCH_SYNC_SMOKE=1` set, which enables `WatchSyncSmokeUITests` (skipped by default).
