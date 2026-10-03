# Research: opening Kyo straight into voice memo recording

Issue: #53. Researched 2026-10-01 against Apple developer documentation and WWDC sessions (WWDC22 to WWDC26). Deployment targets are iOS 27 and watchOS 27.

## Question

How can iOS 27 and watchOS 27 open Kyo directly into recording a voice memo from:

1. a Control Center or Lock Screen control that also works on the Action button,
2. a Siri or Shortcuts App Intent, and
3. a Watch complication or Smart Stack control?

Recording in the background without opening the app is out of scope.

## Short answer

- All three surfaces can run one App Intent, called `StartVoiceMemoIntent` here. It declares `static let supportedModes: IntentModes = .foreground(.immediate)`, so the system brings the app to the foreground before `perform()` runs. The intent then tells the app's router to show the recording screen. On iOS, `TargetContentProvidingIntent` with `onAppIntentExecution` is a cleaner way to route; it isn't available on watchOS.
- iPhone surfaces (Control Center, Lock Screen, Action button) come from a `ControlWidget` with a `ControlWidgetButton(action: StartVoiceMemoIntent())`. It lives in a new iOS widget extension. The intent has to be compiled into both the app and the extension.
- Siri, Spotlight, Shortcuts, and the Action button (which can also run an App Shortcut) come from an `AppShortcutsProvider` in the app target. Every phrase must contain `\(.applicationName)`, for example "Record a memo in \(.applicationName)".
- On watchOS 26 and later, the watch app needs its own widget extension. That extension provides a `ControlWidget` for Control Center, the Smart Stack, and the Ultra Action button, plus accessory-family widgets that serve as complications and deep-link with `widgetURL`. The iPhone control can't do this job: iPhone controls that bring the iPhone app to the foreground don't appear on Apple Watch.
- Recording can start in `perform()` or at the routed screen, because the app is already in the foreground. Microphone permission needs `NSMicrophoneUsageDescription`. The first-run prompt appears inside the app. If transcription uses `SpeechAnalyzer`/`SpeechTranscriber`, it doesn't need speech-recognition authorization, but it isn't available on watchOS.
- No App Group is needed just to open the app. New targets: `KyoWidgets` (iOS widget extension) and `KyoWatchWidgets` (watchOS widget extension).

## 1. iPhone control: Control Center, Lock Screen, Action button

What it is. A control is a `ControlWidget` built with WidgetKit. It can "execute an action, launch your app to a specific view, or launch a locked camera capture extension from Control Center, the Lock Screen, or by using the Action button" [S1]. Controls come in two kinds, buttons and toggles, and "Buttons perform discrete actions, which can include launching your app" [S2]. Kyo needs a button. Controls are added to a Widget Extension target (Xcode template with "Include Control") and listed in the extension's `WidgetBundle` [S1].

Opening the app. Apple's guidance: "Set your control's action to an app intent that conforms to OpenIntent to open your app when someone uses a control. Using OpenIntent allows you to take someone to a specific area of your app" [S1]. `OpenIntent` requires a `target` parameter, meaning the entity or enum to open [S3]. For Kyo, the target could be an `AppEnum` such as `KyoScreen.recordVoiceMemo`, or Kyo could skip `OpenIntent` and use a plain `AppIntent` with foreground `supportedModes`:

- `supportedModes` (iOS/watchOS 26+) replaces `openAppWhenRun`. The modes are `.background`, `.foreground`, `.foreground(.immediate)` ("bring the app to the foreground immediately after the system resolves the intent's parameters, before the action runs"), `.foreground(.dynamic)`, and `.foreground(.deferred)` [S4]. WWDC25 uses `static let supportedModes: IntentModes = .foreground` for a navigation intent [S5].
- `openAppWhenRun` has been deprecated since 26.0 ("Please provide 'supportedModes' instead"). Setting it to `true` "generates an error if the app intent runs in an app extension" [S6]. Don't use it.
- `OpenURLIntent` (iOS 18+/watchOS 11+) opens a universal link. "The system automatically brings your app to the foreground", and the URL goes to the app's URL handling [S7]. Apple's docs describe only universal links. Whether it accepts a custom scheme is unverified, so prefer an intent-based approach. Kyo has no associated domains.

Target membership. "The system requires the Target Membership of the app intent to be set to both the app and the widget extension to open the app" [S1]. The alternatives are a shared framework or Swift package registered with `AppIntentsPackage` in each target. Static libraries and Swift packages are supported as of the 26 releases [S8][S5]. iOS 27 adds `allowedExecutionTargets: ExecutionTargets` (`.main`, `.appIntentsExtension`, `.widgetKitExtension`). It overrides the system heuristic for which process runs an intent compiled into several targets [S9]. Set `StartVoiceMemoIntent` to `.main`. Source: WWDC26 session only; the API reference page was not fetched (unverified detail).

How the app learns which screen to show. There are three documented options:

1. `perform()` runs in the app process and calls a shared navigator. WWDC25 marks `perform()` `@MainActor` and calls `Navigator.shared.navigate(to:)` [S5]. Dependencies can be injected with `@Dependency` after `AppDependencyManager.shared.add { ... }` in `App.init` [S5]. This works on iOS and watchOS.
2. `TargetContentProvidingIntent` plus `.onAppIntentExecution(StartVoiceMemoIntent.self) { ... }` on a view. The closure runs "before the app comes to the foreground and before the intent's perform() method is called". It can only read parameters [S10][S11]. Scenes can be matched with `handlesExternalEvents(preferring:allowing:)`. This requires `UIApplicationSupportsMultipleScenes = YES` "even if your app has only one scene" [S12]. Kyo's generated Info.plist already has `UIApplicationSupportsMultipleScenes => true`, checked in the current Debug build. Availability: iOS/iPadOS/Mac Catalyst/tvOS/visionOS 26+, with no watchOS [S10][S11].
3. URLs: `widgetURL`/`Link` deliver to `onOpenURL(perform:)` [S13]. That fits widgets and complications, not controls.

Action button. Any control can be assigned to the Action button. For a button with an `OpenIntent` action, the default hint is "Hold to Open MyApp"; `.displayName` and a custom hint configure it [S14]. App Shortcuts can also be placed on the Action button (section 2).

## 2. Siri and Shortcuts: App Intent and App Shortcut

- Put an `AppShortcutsProvider` in the app target that returns an `AppShortcut(intent: StartVoiceMemoIntent(), phrases: [...], shortTitle:, systemImageName:)` [S5][S15].
- "Each phrase must include the applicationName placeholder. Phrases can include up to one intent parameter" [S5]. Use `\(.applicationName)` instead of a literal name so Siri also matches synonyms [S16]. Examples: "Record a memo in \(.applicationName)" and "New voice memo in \(.applicationName)". A bare "Record a memo" won't trigger Kyo through an App Shortcut.
- Placement: "featured prominently when searching in Spotlight... Siri... configured to run from the Action Button or Apple Pencil squeeze... show in the Shortcuts app without any user setup" [S5]. No registration is required [S17].
- Limit: "your app can have a maximum of 10 app shortcuts" [S16]. This is from WWDC22 and was not re-verified for iOS 27. The same session says intents that launch the app "won't be shown in Spotlight" [S16]. WWDC25's statement that App Shortcuts are featured in Spotlight [S5] suggests this has changed, so treat the WWDC22 claim as outdated and unverified.
- `AppShortcutsProvider` exists on watchOS 9+ [S15], so the watch app can offer its own Siri phrase.
- Schemas: `@AppIntent(schema:)` conforms intents to Apple Intelligence assistant schemas and can attach `AudioRecordingIntent` [S18]. No voice-memo-specific domain was found (unverified). It isn't needed for a Siri phrase.

## 3. Apple Watch: complication, Smart Stack, controls

Controls (watchOS 26+). Watch controls can be placed "in the Control Center, the Smart Stack, and use them with the Action button on Apple Watch Ultra" [S19][S20]. There are two sources:

- iPhone app controls appear on the watch even without a watch app. However, "the action is performed on the companion iPhone... controls whose actions foreground the iPhone app will not appear on Apple Watch" [S19]. Kyo's iPhone record control will not show on the watch.
- Watch app controls are built "using the same API used to build controls for iOS. When the control is tapped, the action is performed on the Apple Watch" [S19]. They live in a watchOS widget extension. A watch control whose intent uses `.foreground(.immediate)` should open the watch app. This is inferred from the shared API; no source states it explicitly for watchOS, so it's unverified and needs a device test.

Complications. On Apple Watch, accessory widgets serve as complications and Smart Stack widgets. To add them, "add a watchOS widget extension to your project... Implementing WidgetKit complications works like creating widgets" [S21]. The families are `accessoryCircular`, `accessoryRectangular`, `accessoryInline`, and the watch-only `accessoryCorner` [S22]. Tapping a widget opens its app by default. `widgetURL` selects the screen, and `Link` adds extra tap targets in `accessoryRectangular` and larger families. The URL is delivered to `onOpenURL(perform:)` [S13]. `widgetURL` is available on watchOS 9+ [S23]. A custom URL such as `kyo://record` works as an internal route. Whether the scheme must be registered in `CFBundleURLTypes` for widget taps is not stated in the docs (unverified). Registering it is harmless, but it lets other apps open the URL.

Smart Stack relevance. RelevanceKit lets widgets be suggested by date, sleep, fitness, location, and point-of-interest contexts [S19]. This is optional for Kyo.

Code sharing with iOS. The `ControlWidget`/App Intent source can be shared, but each platform needs its own extension target. The iOS extension can't serve the watch, as shown above. watchOS 27 adds Watch Connectivity updates for widgets (WWDC26 watchOS Group Lab search summary, not verified from a transcript) [S24]. Kyo doesn't need it, because the record control has no state.

## Shared code and targets

Proposed XcodeGen additions:

| Target | Type | Contents | Embedded in |
| --- | --- | --- | --- |
| `KyoWidgets` | iOS `app-extension` (WidgetKit) | `WidgetBundle` with the record `ControlWidget` | `Kyo` |
| `KyoWatchWidgets` | watchOS `app-extension` (WidgetKit) | `WidgetBundle` with the watch `ControlWidget` and accessory complication widget | `KyoWatch` |

- Shared source (for example `Shared/QuickCapture/`): `StartVoiceMemoIntent`, the control view, and the routing enum. Compile it into `Kyo`, `KyoWidgets`, `KyoWatch`, and `KyoWatchWidgets`. XcodeGen source lists can include it, as they already do for `Shared`. An `AppIntentsPackage` framework is an alternative, but it isn't required [S1][S8].
- `AppShortcutsProvider`: app targets only, one each in `Kyo` and `KyoWatch` if the watch gets a phrase.
- Navigation: a `@MainActor` router registered through `AppDependencyManager` in each app, or set from `perform()`. On iOS, `onAppIntentExecution` can be used instead. On watchOS, use the router or `onOpenURL`.
- App Group: not needed. The control and complication carry no data, and the intent runs in the app process. One becomes necessary only if a widget later shows memo data.
- Existing Info.plist: `INFOPLIST_KEY_NSMicrophoneUsageDescription` must be added to `Kyo` and `KyoWatch`.

## Permissions and launch constraints

- Microphone: every app that uses the microphone needs `NSMicrophoneUsageDescription`. Without it, "the app exits". Request access with `await AVAudioApplication.requestRecordPermission()` (iOS 17+/watchOS 10+). If permission is denied, recording returns silent samples, and the user has to change it in Settings [S25].
- First run from a control or Siri: the intent brings the app to the foreground before `perform()` runs [S4]. Request permission in the app, then start recording only if it's granted, otherwise show a "turn on microphone in Settings" state. Don't request permission inside `onAppIntentExecution`, which can only read parameters [S11].
- Starting while foreground: with `.foreground(.immediate)`, the app is active before the action runs [S4]. Activating an `AVAudioSession` with `.playAndRecord` and recording follows the normal foreground path, as in the WWDC25 SpeechAnalyzer sample [S26]. A forum thread reports that apps can't *start* recording in the background [S27]; the only primary-doc hint is the `cannotStartRecording` error description [S28]. Because of this, the intent must never run in the widget extension or background. That's one more reason for `.main` / `.foreground`.
- Transcription: `SFSpeechRecognizer` needs `requestAuthorization` and `NSSpeechRecognitionUsageDescription`, but "this process only applies to speech recognition using SFSpeechRecognizer. SpeechAnalyzer transcriber modules don't send audio data... to Apple's servers" [S29]. `SpeechAnalyzer` (iOS 26+) is not available on watchOS [S30][S26]. This matches the map's settled decision that Watch voice memos are transcribed on the phone. Locale models may need an `AssetInventory` download [S26].
- Out of scope, for the record: `AudioRecordingIntent` (iOS 18+/watchOS 11+) can start recording without opening the app, but "you must start a Live Activity when you begin the audio recording and keep it active... If you don't start a Live Activity, the audio recording stops" [S31]. iOS 27's `LongRunningIntent` likewise shows progress as a Live Activity [S9].

## Docs dating and iOS 27 notes

- The control and Action button docs date from iOS 18. `supportedModes`, `TargetContentProvidingIntent`, and watchOS controls date from the 26 releases. No iOS 27 or watchOS 27 change to them was found.
- iOS 27 additions that are relevant: `ExecutionTargets` [S9]. The WWDC26 WidgetKit session covers no control changes [S32].

## Open questions for the spec

1. Should the control open a recording screen that waits for a tap, or start recording immediately? Starting immediately is technically possible once the app is in the foreground, but a stray Action-button press would record silently.
2. Should there be one intent for every surface (`StartVoiceMemoIntent`), or an `OpenIntent` with a `KyoScreen` target that also covers written memos later?
3. The map settles that the Watch records and the phone transcribes (`SpeechAnalyzer` doesn't run on watchOS). Open: does a Watch quick-capture surface start recording on the Watch even when the phone is out of reach, with transcription deferred until sync?
4. Use iOS routing through `onAppIntentExecution`, or one router-based approach shared with watchOS?
5. Register a `kyo://` URL scheme for complication deep links, or rely on the default "open app" tap plus a watch control?
6. Which Siri phrases and synonyms, and should the App Shortcut appear in Spotlight?

## Sources

- [S1] Creating controls to perform actions across the system: https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system
- [S2] WWDC24 "Extend your app's controls across the system": https://developer.apple.com/videos/play/wwdc2024/10157/
- [S3] OpenIntent: https://developer.apple.com/documentation/appintents/openintent
- [S4] AppIntent.supportedModes: https://developer.apple.com/documentation/appintents/appintent/supportedmodes
- [S5] WWDC25 "Get to know App Intents": https://developer.apple.com/videos/play/wwdc2025/244/
- [S6] AppIntent.openAppWhenRun (deprecated): https://developer.apple.com/documentation/appintents/appintent/openappwhenrun
- [S7] OpenURLIntent: https://developer.apple.com/documentation/appintents/openurlintent
- [S8] WWDC25 "Explore new advances in App Intents": https://developer.apple.com/videos/play/wwdc2025/275/
- [S9] WWDC26 "Discover new capabilities in the App Intents framework": https://developer.apple.com/videos/play/wwdc2026/345/
- [S10] TargetContentProvidingIntent: https://developer.apple.com/documentation/appintents/targetcontentprovidingintent
- [S11] onAppIntentExecution(_:perform:): https://developer.apple.com/documentation/swiftui/view/onappintentexecution(_:perform:)
- [S12] Directing app intents to your app's scenes: https://developer.apple.com/documentation/appintents/directing-app-intents-to-your-apps-scenes
- [S13] Linking to specific app scenes from your widget or Live Activity: https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity
- [S14] Adding refinements and configuration to controls: https://developer.apple.com/documentation/widgetkit/adding-refinements-and-configuration-to-controls
- [S15] AppShortcutsProvider: https://developer.apple.com/documentation/appintents/appshortcutsprovider
- [S16] WWDC22 "Implement App Shortcuts with App Intents": https://developer.apple.com/videos/play/wwdc2022/10170/
- [S17] App Shortcuts: https://developer.apple.com/documentation/appintents/app-shortcuts
- [S18] AppIntent(schema:): https://developer.apple.com/documentation/appintents/appintent(schema:)
- [S19] WWDC25 "What's new in watchOS 26": https://developer.apple.com/videos/play/wwdc2025/334/
- [S20] WWDC25 "What's new in widgets": https://developer.apple.com/videos/play/wwdc2025/278/
- [S21] Creating accessory widgets and watch complications: https://developer.apple.com/documentation/widgetkit/creating-accessory-widgets-and-watch-complications
- [S22] WidgetFamily.accessoryCorner: https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycorner
- [S23] widgetURL(_:): https://developer.apple.com/documentation/swiftui/view/widgeturl(_:)
- [S24] WWDC26 watchOS Group Lab: https://developer.apple.com/videos/play/wwdc2026/8014/
- [S25] AVAudioApplication.requestRecordPermission(): https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:)
- [S26] WWDC25 "Bring advanced speech-to-text to your app with SpeechAnalyzer": https://developer.apple.com/videos/play/wwdc2025/277/
- [S27] Developer Forums, "Can AVAudioRecorder start recording in the background?" (lower trust): https://developer.apple.com/forums/thread/21757
- [S28] AVAudioSession.ErrorCode.cannotStartRecording: https://developer.apple.com/documentation/coreaudiotypes/avaudiosession/errorcode/cannotstartrecording
- [S29] Asking permission to use speech recognition: https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition
- [S30] SpeechAnalyzer: https://developer.apple.com/documentation/speech/speechanalyzer
- [S31] AudioRecordingIntent: https://developer.apple.com/documentation/appintents/audiorecordingintent
- [S32] WWDC26 "WidgetKit foundations": https://developer.apple.com/videos/play/wwdc2026/277/
