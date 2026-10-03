# EventKit for the Schedule section

Research for a read-only, compact list of today's calendar events in Kyo, with tap-to-open. Kyo is SwiftUI on iPhone and iPad. The deployment target in `project.yml` is **iOS 27.0**, not 26. Checked against Xcode 27.0 (27A266a, Swift 6.4, Swift 6 language mode).

Sources are Apple developer documentation (read through the `developer.apple.com/tutorials/data/documentation/...json` endpoints), WWDC23 transcripts, the Apple sample "Accessing Calendar using EventKit and EventKitUI", and the iOS SDK headers and `.swiftinterface` files shipped with Xcode 27. Each claim cites its source as [n]; the list is at the end. Text marked **Inference** is my reading, not something Apple states.

## 1. Access level, Info.plist keys, authorization states

**Reading needs full access.** "Your app can't request read-only access to either events or reminders. To read events or reminders from the event store, your app needs full access." [1] With write-only access, `calendars(for:)` returns "a single virtual calendar" and "requests for events on the virtual calendar return no results." [1] Write-only apps "cannot read any existing events … The app also can't read the calendar list." [8]

- Request access with `try await store.requestFullAccessToEvents() -> Bool` (iOS 17+). The completion-handler form calls back "on an arbitrary queue." [2]
- On iOS 17 and later, the old `requestAccess(to:)` "doesn't prompt for access and immediately calls the completion block with an error." [3]
- If you fetch before requesting access, "you'll need to reset the event store with the `reset()` method to receive data after they grant access." [2] The header also says the store broadcasts `EKEventStoreChangedNotification` when access is granted or declined, and that this notification "will also be posted if access to events or reminders is changed by the user." [15]
- WWDC23 guidance: "Only request full access if it is essential to the core experience of your app, and only request at a time when it is clear why the access is needed." "Full access prompts will be denied more often." Also: "Apps should only have one event store, so be sure to reuse this." [8]

**Info.plist.** Add `NSCalendarsFullAccessUsageDescription` (iOS 17+), which is "required if your app uses APIs that read and write the person's calendar data." [4] In `project.yml` this is `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`, next to the existing microphone and camera keys.

- **The legacy `NSCalendarsUsageDescription` isn't needed.** It has been deprecated since iOS 17 [5]. It's only a fallback for apps that also run on iOS 10–16 [1]. With an iOS 27 minimum, drop it. If it's the *only* key present, "iOS automatically denies any access request." [1]
- `NSContactsUsageDescription` is listed for EventKitUI only for apps "linked on iOS 10 through iOS 16" running on iOS 10–16 [1][8]. It isn't needed at iOS 27. **Inference:** worth confirming on a device that `EKEventViewController` triggers no Contacts prompt when it shows attendees.

**`EKAuthorizationStatus` (for `.event`)** [6][7]:

| Value | Apple's meaning | How Kyo should handle it |
|---|---|---|
| `.fullAccess` (iOS 17+) | "both read and write access" | Fetch and show events. |
| `.writeOnly` (iOS 17+) | "write-only access" | Treat as no read access. Kyo never requests this, but the state is reachable, because apps that "previously" had access are migrated to write-only by default on upgrade to iOS 17 [9]. You can "ask once to upgrade" to full access [9]: call `requestFullAccessToEvents()` again, once, from a user action. |
| `.denied` | "The person explicitly denied access" | Show a compact "Calendar access is off" row with a button that opens Settings (see §2). Never prompt again. |
| `.restricted` | "The person can't change your app's authorization status, possibly due to active restrictions such as parental controls" | Show an unavailable message with no Settings button, because the user can't change it. |
| `.notDetermined` | "The person hasn't chosen" | Show an opt-in "Show your calendar" affordance. Call `requestFullAccessToEvents()` only when the user taps it. |
| `.authorized` | Deprecated in iOS 17: "Check for the level of access (writeOnly or fullAccess) your app needs." | Unreachable in practice. Handle it with `@unknown default` / treat it as no access. |

Read status with `EKEventStore.authorizationStatus(for: .event)` [7]. Re-read it when the app returns to the foreground and on store-changed notifications, because the user can change it in Settings.

## 2. Asking again after denial

**No.** The system prompts "only … the first time your app requests full access to events; any subsequent instantiations of EKEventStore uses existing permissions." [2] The header repeats that "The user will only be prompted the first time access is requested." [15] Once the status is `.denied`, calling `requestFullAccessToEvents()` returns `false` without showing UI. The only exception is the one-time upgrade from `.writeOnly` to full [9].

The supported recovery is to deep-link to Kyo's page in Settings: `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)` (or SwiftUI `openURL`). This "launch[es] the Settings app and display[s] your app's custom settings." [10] Apple's sample does the same: after denial, "In subsequent launches, the app displays a message prompting the user to grant the app full access in Settings." [11] `openSettingsURLString` is on Apple DTS's list of documented, supported settings links [19].

## 3. Fetching one day, change notifications, concurrency

**Fetch.**

```swift
let cal = Calendar.current
let start = cal.startOfDay(for: day)
let end = cal.date(byAdding: .day, value: 1, to: start)!
let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selectedCalendars) // nil = all
let events = store.events(matching: predicate).sorted { $0.compareStartDate(with: $1) == .orderedAscending }
```

- `predicateForEvents(withStart:end:calendars:)` must be used. A hand-built predicate isn't accepted, and the header says one "not created with the predicate creation functions … an exception is raised." [12][15] Passing `calendars: nil` searches all calendars [13]. Ranges are capped at four years [12].
- Results are "in the default time zone" [12] and "not necessarily [in] chronological order", so sort them. Apple suggests `compareStartDate(with:)` [13][8].
- `events(matching:)` "is synchronous." Apple advises running it off the main thread [13][14]. WWDC23 adds "Use the shortest range possible for the best performance" [8], and a single day is the shortest practical range.
- **Recurring events.** The predicate fetch returns individual occurrences as `EKEvent`s. **Inference:** this is Apple's sample behavior; the docs don't state it in one sentence. Occurrence facts that are documented:
  - `event(withIdentifier:)` "Locates the first occurrence" of a recurring event, not today's occurrence [16][13].
  - `calendarItemExternalIdentifier` "Recurring event identifiers are the same for all occurrences … you may want to use the start date" to tell them apart [17].
  - `occurrenceDate` is the original slot and stays the same even if that occurrence was moved (`isDetached`) [18].

  So **a stable row ID is `eventIdentifier` plus `occurrenceDate`** (or plus `startDate`), not `eventIdentifier` alone. Also, `eventIdentifier` "most likely changes" if the event moves to another calendar [20].
- **All-day events.** `isAllDay` flags them [21]. They are "floating," returned "in the default time zone" [18]. Show them in an "All day" group before timed events.
- **Events that span midnight.** Apple doesn't document the exact overlap semantics of the predicate. **Inference:** in practice it returns events that *overlap* `[start, end)`, so an event from 23:00 yesterday to 01:00 today appears. Kyo should clamp its display, for example showing "until 01:00" or "from 23:00", and should not assume `startDate >= startOfDay`. Cover this with a unit test against the seam (§6) and confirm it once on a real store.
- Day boundaries come from `Calendar.current` / `startOfDay`. That matches how Kyo already defines Today and the calendar week.

**Change notifications.**

- `EKEventStoreChangedNotification` / `.EKEventStoreChanged` "is posted whenever changes are made to the Calendar database … Individual changes are not described. When you receive this notification, you should refetch all EKEvent … objects you have accessed, as they are considered stale." "The system posts this notification on the main actor." [22] The header adds that it also fires when the user changes access, and that EventKitUI view controllers "automatically deal with this." [15]
- **New in iOS 26 and usable unconditionally at iOS 27:** `EKEventStore.EventStoreChanged`, a `NotificationCenter.MainActorMessage` with `Subject = EKEventStore`. Observe it with `NotificationCenter.default.addObserver(of: eventStore, for: .changed) { message in … }`. This is the Swift 6–friendly, main-actor-isolated form [23][24]. Apple's older sample uses `NotificationCenter.default.notifications(named: .EKEventStoreChanged)` in an `AsyncSequence` loop [11]. Either works.
- Refetch the day on change. Don't try `EKEvent.refresh()` on a whole list: the header calls it "fairly heavyweight … Do not use it to refresh the entire selected range." [25]
- Also refetch when the day rolls over and on foreground. Those aren't EventKit events.

**Swift concurrency and Sendable (Swift 6.4 SDK).**

- `EKEventStore`, `EKEvent`, `EKCalendar`, and `EKSource` are plain `NSObject` subclasses. Their documented conformances don't include `Sendable` [26]. The iOS 27 EventKit `.swiftinterface` adds only the `EventStoreChanged` message type [24].
- Don't mix objects between stores: "After receiving an object from an event store, don't use that object with a different event store." That covers `EKEvent`, `EKCalendar`, `EKSource`, and predicates [26].
- `requestFullAccessToEvents(completion:)` takes a `@Sendable` completion, and the async overload exists [2].
- **Inference / recommended shape:** keep one `EKEventStore` for the app, owned by a single isolation domain. One option is an `actor CalendarService` (or a `@MainActor` type if a one-day fetch measures as cheap). Fetch inside it, then map each `EKEvent` to a `Sendable` value snapshot (`struct ScheduleEvent: Sendable, Identifiable { id, title, start, end, isAllDay, calendarID, color }`) before it crosses to SwiftUI. Never let `EKEvent` escape the actor. Convert `cgColor` to a `Sendable` representation (RGBA components, or a SwiftUI `Color`) inside the actor.

## 4. Opening a specific event

**`EKEventViewController` (EventKitUI)** is the supported way to show one event's details.

- It's a `UIViewController` [27], so it works in SwiftUI through `UIViewControllerRepresentable`. Apple's sample wraps its EventKitUI controllers (`EKEventEditViewController`, `EKCalendarChooser`) this way and presents them in `.sheet` [11]. **Inference:** wrap it in a `UINavigationController` and present it as a sheet. Implement `EKEventViewDelegate.eventViewController(_:didCompleteWith:)` to dismiss; the delegate is told about Done, "Responded", and "Deleted" actions [28][29].
- **It needs full access, in practice.** You must set `event` "before displaying the view" [30], and you can only get an `EKEvent` for an existing event by fetching it, which requires full access [1]. Apple's sample lists "display events using EKEventViewController" among full-access capabilities [11]. Only the *chooser and editor* render out of process and work without access [1]; Apple doesn't say this of the event view controller.
- **Read-only:** `allowsEditing` defaults to `false`: "If false (the default), the event is not editable." [31] The header adds that even when it's `true`, Edit won't appear for read-only (subscribed) calendars or invitations [29]. Leave `allowsCalendarPreview` off too [29].
- **Caveat:** for invitations, the controller can still show accept/decline responses (`EKEventViewActionResponded`) [29]. That's a write path to the user's calendar even with `allowsEditing = false`. **Inference:** acceptable, since it's the system UI acting on the user's explicit tap, but note it for the spec.
- For recurring events, pass the *occurrence* you fetched for today, not `event(withIdentifier:)`, which returns the first occurrence [16]. With the value-snapshot design, re-fetch today's events inside the service on tap and match `eventIdentifier` plus `occurrenceDate`.
- EventKitUI is marked "not supported in extensions" [29], so this can't be used from Kyo's widgets.

**`calshow:` URL scheme.** It is **not documented**. It's absent from Apple's URL Scheme Reference [32]. Apple DTS's position on undocumented Apple schemes is: "Their use is unsupported. If you rely on such implementation details, things might work, or they might not, and that state might change over time," with a pointer to App Review Guideline 2.5.1 [19]. Developer-forum threads asking about it have no Apple answer [33]. Community usage passes a *date* (`calshow:<timeIntervalSinceReferenceDate>`). I found no Apple source for targeting a specific event. **Recommendation:** use `EKEventViewController`. If "Open in Calendar" is wanted, treat `calshow:` as an unsupported, best-effort extra, or skip it.

## 5. Calendar picker data

- **List:** `store.calendars(for: .event)` [34]. With write-only access it returns only the virtual calendar [1], so the picker requires full access too.
- **Identifier:** `EKCalendar.calendarIdentifier` "can be used as a local identifier." Look it up with `calendar(withIdentifier:)`. It is **not guaranteed stable**: "A full sync with the calendar will lose this identifier. You should have a plan for dealing with a calendar whose identifier is no longer fetch-able by caching its other properties." [35][36]
  - **Inference / recommendation:** persist the *excluded* (hidden) calendar IDs rather than the included ones, so a new or re-identified calendar shows by default. Drop unknown IDs quietly on load. Optionally cache `title` and `source.title` for each stored ID, so a re-synced calendar can be matched again.
  - Store these on-device (`UserDefaults`/`@AppStorage`). Calendar IDs are local to one device's database, so syncing them through CloudKit would be wrong. **Inference** based on "local identifier" [35].
- **Color:** `cgColor: CGColor!`, the iOS equivalent of macOS `color` [37]. Use SwiftUI `Color(cgColor:)`.
- **Grouping:** `calendar.source` is the account (`EKSource`, "the account a calendar belongs to") with `title`, `sourceType` (`EKSourceType`: local, Exchange, CalDAV, MobileMe, subscribed, birthdays), and `sourceIdentifier` [38][39]. `store.sources` order "isn't guaranteed" [40], so sort by `source.title` and then `calendar.title`. Delegate (shared-to-me) sources aren't in `sources` by default [41]. Ignore them for v1.
- Other useful properties: `title`, `type`, `isSubscribed`, `allowsContentModifications` [42].
- **Alternative: `EKCalendarChooser`** (EventKitUI) supports multiple selection with `displayStyle: .allCalendars` and returns `selectedCalendars` [43]. With full access it shows every calendar [11]. It's a UIKit sheet, so a native SwiftUI `List` built from `calendars(for:)` is likely a better match for Kyo's UI. Either is viable.

## 6. Simulator and tests

- EventKit works in the iOS and iPadOS simulators. Apple's sample says to "build and run it in the Simulator" [11], and the simulator has its own Calendar database. The simulator Calendar starts empty apart from built-in calendars (**inference**). Events added there persist per simulator device.
- **Permission control in tests:**
  - `XCUIApplication.resetAuthorizationStatus(for: .calendar)` resets the permission "such that the system will display the authorization prompt the next time." The app "might get terminated" if running [44]. `XCUIProtectedResource.calendar` exists [44].
  - `xcrun simctl privacy <device> grant|revoke|reset calendar <bundle-id>` from the command line. Its help warns: "Using this command to bypass those requirements can mask bugs." [45] **Unverified:** whether `grant calendar` gives `.fullAccess` or `.writeOnly`. Test it before relying on it.
  - The permission alert belongs to SpringBoard. UI tests that hit a real prompt need `addUIInterruptionMonitor` or `springboard` element queries, which are fragile across OS versions.
- **Seeding events:** there's no Apple API to seed the simulator calendar from the UI-test process. **Inference:** you could write events from the app process with full access (`EKEvent(eventStore:)` and `save(_:span:)`), but that mutates per-device state that leaks between tests and parallel clones.
- **Recommendation: a protocol seam.** **Inference**, consistent with Apple's guidance to reuse one store and keep EventKit objects inside it.

  ```swift
  protocol CalendarService: Sendable {
      func authorizationStatus() -> CalendarAccess          // Kyo enum: .notDetermined/.denied/.restricted/.writeOnly/.full
      func requestFullAccess() async throws -> Bool
      func calendars() async -> [ScheduleCalendar]          // Sendable snapshots: id, title, color, sourceTitle
      func events(on day: Date, excluding: Set<String>) async -> [ScheduleEvent]
      func changes() -> AsyncStream<Void>                   // store-changed + access-changed
  }
  ```

  - `EventKitCalendarService` (an actor holding the single `EKEventStore`) is the only type that imports EventKit.
  - `FakeCalendarService` returns canned events and can simulate each authorization state.
  - Unit tests drive the Schedule view model through the fake. Cover all-day, spanning midnight, recurring occurrences with the same `eventIdentifier`, hidden calendars, and every authorization state.
  - UI tests select the fake through a launch environment variable. The repo already does this with `app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"` in `KyoUITests/`, so add, for example, `KYO_FAKE_CALENDAR=full|denied|notDetermined|empty`. No real prompt or real events are needed.
  - Tapping an event opens `EKEventViewController`, which needs a real `EKEvent`. Put the "open event" action behind the seam too (for example `func makeEventViewController(for id: ScheduleEvent.ID) -> UIViewController?` on the live service). With the fake, a UI test asserts that a placeholder sheet appeared, not the system view.
- Both app schemes build for the simulator unchanged. EventKit and EventKitUI are system frameworks on iOS, so no extra entitlement is needed. The `com.apple.security.personal-information.calendars` entitlement is for sandboxed macOS apps only [1].

## Sources

1. Accessing the event store: https://developer.apple.com/documentation/eventkit/accessing-the-event-store
2. `requestFullAccessToEvents(completion:)`: https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)
3. `requestAccess(to:completion:)` (deprecated): https://developer.apple.com/documentation/eventkit/ekeventstore/requestaccess(to:completion:)
4. `NSCalendarsFullAccessUsageDescription`: https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription
5. `NSCalendarsUsageDescription` (deprecated): https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsusagedescription
6. `EKAuthorizationStatus` and its cases: https://developer.apple.com/documentation/eventkit/ekauthorizationstatus (`/fullaccess`, `/writeonly`, `/denied`, `/restricted`, `/notdetermined`, `/authorized`)
7. `authorizationStatus(for:)`: https://developer.apple.com/documentation/eventkit/ekeventstore/authorizationstatus(for:)
8. WWDC23 "Discover Calendar and EventKit": https://developer.apple.com/videos/play/wwdc2023/10052/
9. WWDC23 "What's new in privacy" (Calendar section): https://developer.apple.com/videos/play/wwdc2023/10053/
10. `UIApplication.openSettingsURLString`: https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring
11. Sample code "Accessing Calendar using EventKit and EventKitUI": https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui
12. `predicateForEvents(withStart:end:calendars:)`: https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforevents(withstart:end:calendars:)
13. Retrieving events and reminders: https://developer.apple.com/documentation/eventkit/retrieving-events-and-reminders
14. `events(matching:)`: https://developer.apple.com/documentation/eventkit/ekeventstore/events(matching:)
15. iOS 27 SDK header `EventKit.framework/Headers/EKEventStore.h` (Xcode 27.0): `initWithAccessToEntityTypes:` discussion, `eventsMatchingPredicate:`, `predicateForEventsWithStartDate:…`, `EKEventStoreChangedNotification` discussion
16. `event(withIdentifier:)`: https://developer.apple.com/documentation/eventkit/ekeventstore/event(withidentifier:)
17. `calendarItemExternalIdentifier`: https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier
18. `occurrenceDate`: https://developer.apple.com/documentation/eventkit/ekevent/occurrencedate; `isDetached`: https://developer.apple.com/documentation/eventkit/ekevent/isdetached
19. Apple DTS (Quinn), "Supported URL schemes" forum post: https://developer.apple.com/forums/thread/761314
20. `eventIdentifier`: https://developer.apple.com/documentation/eventkit/ekevent/eventidentifier
21. `isAllDay`: https://developer.apple.com/documentation/eventkit/ekevent/isallday
22. `EKEventStoreChangedNotification`: https://developer.apple.com/documentation/eventkit/ekeventstorechangednotification
23. `EKEventStore.EventStoreChanged` (iOS 26+): https://developer.apple.com/documentation/eventkit/ekeventstore/eventstorechanged
24. iOS 27 SDK `EventKit.swiftmodule/arm64e-apple-ios.swiftinterface` (Xcode 27.0): `EventStoreChanged: NotificationCenter.MainActorMessage`, `MessageIdentifier.changed`
25. iOS 27 SDK header `EKEvent.h`: `refresh` discussion; also https://developer.apple.com/documentation/eventkit/ekevent/refresh()
26. `EKEventStore` (overview and conformances): https://developer.apple.com/documentation/eventkit/ekeventstore; `EKEvent`: https://developer.apple.com/documentation/eventkit/ekevent
27. `EKEventViewController`: https://developer.apple.com/documentation/eventkitui/ekeventviewcontroller
28. `EKEventViewDelegate`: https://developer.apple.com/documentation/eventkitui/ekeventviewdelegate
29. iOS 27 SDK header `EventKitUI.framework/Headers/EKEventViewController.h`: class discussion, `allowsEditing`, `allowsCalendarPreview`, `EKEventViewAction`, `NS_EXTENSION_UNAVAILABLE_IOS`
30. `EKEventViewController.event`: https://developer.apple.com/documentation/eventkitui/ekeventviewcontroller/event
31. `allowsEditing`: https://developer.apple.com/documentation/eventkitui/ekeventviewcontroller/allowsediting
32. Apple URL Scheme Reference (archive; no `calshow`): https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/Introduction/Introduction.html
33. Developer Forums, unanswered `calshow` threads: https://developer.apple.com/forums/thread/67452, https://developer.apple.com/forums/thread/104410
34. `calendars(for:)`: https://developer.apple.com/documentation/eventkit/ekeventstore/calendars(for:)
35. `calendarIdentifier`: https://developer.apple.com/documentation/eventkit/ekcalendar/calendaridentifier
36. `calendar(withIdentifier:)`: https://developer.apple.com/documentation/eventkit/ekeventstore/calendar(withidentifier:)
37. `cgColor`: https://developer.apple.com/documentation/eventkit/ekcalendar/cgcolor
38. `EKSource`: https://developer.apple.com/documentation/eventkit/eksource
39. `EKSourceType`: https://developer.apple.com/documentation/eventkit/eksourcetype
40. `EKEventStore.sources`: https://developer.apple.com/documentation/eventkit/ekeventstore/sources
41. `delegateSources`: https://developer.apple.com/documentation/eventkit/ekeventstore/delegatesources
42. `EKCalendar`: https://developer.apple.com/documentation/eventkit/ekcalendar
43. `EKCalendarChooser`: https://developer.apple.com/documentation/eventkitui/ekcalendarchooser
44. Xcode 27 header `XCUIAutomation.framework/Headers/XCUIApplication.h` (`resetAuthorizationStatusForResource:`) and `XCUIProtectedResource.h` (`XCUIProtectedResourceCalendar`)
45. `xcrun simctl help privacy` (Xcode 27.0)
