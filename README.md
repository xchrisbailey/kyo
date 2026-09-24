# Hoy

SwiftUI starter for iPhone, iPad, and Apple Watch. Requires Xcode 27 or later with the iOS and watchOS SDKs; deployment targets are iOS 27 and watchOS 27. Uses Swift 6 without third-party dependencies.

## Run

Open `Hoy.xcodeproj` in Xcode. Select the **Hoy** scheme and an iPhone or iPad simulator, or the **HoyWatch** scheme and an Apple Watch simulator. Install missing simulator runtimes through Xcode Settings → Components.

For physical devices, select your development team under Signing & Capabilities for both targets. Replace the placeholder `com.example.hoy` bundle identifiers in `project.yml`, including `WKCompanionAppBundleIdentifier`, then regenerate the project.

## Structure

- `Hoy/`: iPhone and iPad app entry point.
- `HoyWatch/`: companion Watch app entry point. It can launch independently of the iPhone app.
- `Shared/`: SwiftUI views and future shared models, compiled into both apps.
- `project.yml`: XcodeGen project definition. The generated Xcode project is checked in so XcodeGen is only needed when changing project configuration.

Run `xcodegen generate` after changing `project.yml`. Make lasting build-setting and target changes in that file, since regeneration replaces the Xcode project configuration.

## Build checks

```sh
xcodebuild -project Hoy.xcodeproj -scheme Hoy -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Hoy.xcodeproj -scheme HoyWatch -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

App icons, persistence, and phone/watch synchronization are not configured yet.
