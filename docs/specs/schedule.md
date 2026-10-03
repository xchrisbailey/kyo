# Schedule on iPhone and iPad

Status: Product behavior confirmed. Specification only; implementation requires a separate user request.

## Problem Statement

Kyo presents one day at a time, but Today shows nothing of what's already on the user's calendars. With the Meals section gone (ADR 0006), the top of Today has room for it. To see their meetings and appointments, users have to leave Kyo for the Calendar app.

## Solution

Add a compact **Schedule** section to the top of Today on iPhone and iPad, below the summary stats and above Tasks. It reads Today's **events** from the device's calendars through EventKit and never stores or changes them. Access is requested only when the user taps the section's prompt. The section shows all-day events on one line, then up to three upcoming timed events, with "+N more" to expand. Tapping an event opens the system event detail as a sheet. A new Schedule group in Settings turns the section off and picks which calendars it reads. Terms follow `CONTEXT.md`: **Today**, **Event**, **Schedule**.

## User Stories

1. As a Kyo user, I want to see Today's events at the top of Today, so that I can plan tasks around what's already scheduled.
2. As a Kyo user, I want Kyo to ask for calendar access only when I choose to connect it, so that the first launch isn't interrupted.
3. As a Kyo user who declined calendar access, I want a way to Settings from the section, so that I can change my mind.
4. As a Kyo user who doesn't want the Schedule, I want to dismiss it, so that Today stays the way I like it.
5. As a Kyo user, I want the section to stay compact, so that Tasks remain near the top.
6. As a Kyo user, I want all-day events on one line, so that birthdays and holidays don't crowd out timed events.
7. As a Kyo user, I want only upcoming events in the compact view, so that finished meetings don't fill the section by afternoon.
8. As a Kyo user, I want to expand the section to see everything today, including what's already over.
9. As a Kyo user, I want an event in progress marked "Now", so that I can see where I am in the day.
10. As a Kyo user, I want each event's calendar color, so that I can tell work from personal at a glance.
11. As a Kyo user, I want to tap an event to see its details, so that I can find the location, notes, or attendees without leaving Kyo.
12. As a Kyo user, I want to choose which calendars appear, so that shared or subscribed calendars I don't care about stay out.
13. As a Kyo user, I want calendars I add later to show up automatically, so that I don't have to revisit Settings.
14. As a Kyo user, I want the Schedule to update when my calendar changes and when the day rolls over, so that it's never stale.
15. As a VoiceOver user, I want each event read with its time, title, and calendar.

## Implementation Decisions

### Scope and the Event model

- iPhone and iPad only. Read-only: Kyo never creates, edits, or deletes events. Kyo stores no events; it reads them from EventKit each time.
- Reading events needs **full access**. EventKit has no read-only level. Request it with `requestFullAccessToEvents()`. Add `NSCalendarsFullAccessUsageDescription` through `project.yml` (`INFOPLIST_KEY_…`). Don't add the deprecated `NSCalendarsUsageDescription`.
- Fetch Today with `predicateForEvents(withStart:end:calendars:)` from the start of Today to the start of tomorrow, off the main thread, and sort the results. An event that overlaps Today is included even if it starts before Today or ends after it.
- EventKit types aren't `Sendable`. One live calendar service, an actor and the only code that imports EventKit, owns the single `EKEventStore` and converts events into `Sendable` value snapshots before they reach SwiftUI.
- A snapshot carries an identity of `eventIdentifier` plus `occurrenceDate`, so each occurrence of a recurring event is distinct. It also carries the title, start and end, all-day flag, location, calendar identifier, calendar color, and in-progress state.

### Permission flow

- `.notDetermined`: the section shows one line, "See today's events", with a **Connect** button. Tapping Connect shows the system prompt. A small dismiss control hides the section (see Settings).
- `.fullAccess`: show events.
- `.denied`, and `.writeOnly` or the deprecated `.authorized` treated as no read access: one muted line, "Calendar access is off", with an **Open Settings** button (`UIApplication.openSettingsURLString`) and a dismiss control. For `.writeOnly`, Connect may instead request the one allowed upgrade to full access.
- `.restricted`: one muted line, "Calendar access isn't available", with no button, because the user can't change it. It has a dismiss control.
- Dismissing any of these lines turns **Show schedule** off.

### The Schedule section

- Position: below the summary stats, above Tasks, using the same `TodaySection` look. Its title is "Schedule". Its note is the event count ("3 events") or "Calendar" when there are none. The summary stats stay Tasks done / Habits done, with no events stat.
- All-day events come first as one line, "All day · Sam's birthday, Holiday", truncated to one line.
- Timed rows show a small dot in the calendar's color, the start time in the device's locale format, and the title. If there's a location, it goes on a second line only when it fits on one line; otherwise it's left out. Rows don't show the end time or duration.
- An in-progress event shows **Now**, in the accent color, in place of its start time. There are no countdowns or live timers.
- An event that started before Today shows "Until <end time>" if it has already ended, and "Now" if it's still running.
- Collapsed view: up to **3** events that are in progress or still to come, then a "+N more" row when more remain (upcoming or past). Tapping it expands the section in place to show all of Today's events in time order, with past events dimmed. A "Show less" row collapses it again. The expanded state isn't remembered across launches.
- Empty states (one muted line, section still shown): "Nothing scheduled" when Today has no events, and "Nothing else today" when every event has ended. Expanding still shows the past events.
- Tapping a timed row or the all-day line opens the system event detail (`EKEventViewController` with `allowsEditing = false`) in a sheet, wrapped with `UIViewControllerRepresentable`. Pass Today's occurrence, not `event(withIdentifier:)`. The all-day line opens the first event when there's one, and a list to choose from when there are several. Invitation replies (Accept / Maybe / Decline) in the system sheet are allowed; Kyo itself never writes. Don't use the undocumented `calshow:` URL.

### Refreshing

- Refetch when the event store reports a change (`EKEventStore.EventStoreChanged` / `EKEventStoreChangedNotification`, which also fires on access changes). Also refetch when Today rolls over (the existing `significantTimeChangeNotification` path), when the app returns to the foreground, and when the Settings selection changes.
- The "Now" marker and the collapsed upcoming set are recomputed at each event's start and end time while Today is on screen, for example with a `TimelineView` or a scheduled refresh.

### Settings

- The Settings sheet gains a **Schedule** group:
  - **Show schedule**: a switch, on by default. Off hides the section entirely. Turning it back on shows the current access state.
  - **Calendars ›**: a native SwiftUI list of `calendars(for: .event)` grouped by account (`EKSource`, sorted by title), each calendar with its color and a checkmark. All are checked by default. It's available only with full access; otherwise it shows the same access line as Today.
- Store the **hidden** calendar identifiers on this device only (not synced). New or re-synced calendars are included automatically. A hidden identifier that no longer exists is ignored.

### Accessibility and layout

- Each row is a single accessibility element, for example "10:00 AM, Design review, Work calendar" or "Now, Design review, Work calendar", with past rows marked as ended. The all-day line reads "All day: …".
- The section respects Dynamic Type. At accessibility sizes the location line is dropped before the title wraps.
- iPad uses the same section within the existing Today width.

## Testing Decisions

- Put a `CalendarService` protocol between the app and EventKit, covering authorization status, requesting access, fetching Today's event snapshots, listing calendars, change notifications, and producing the value used to open an event. The live actor is the only code that imports EventKit.
- Test the Schedule's behavior through the shared Schedule model that the view consumes, with a fake service and a controllable clock and calendar. Cover each authorization state; all-day grouping; the collapsed set of three upcoming events and the "+N more" count; expand and collapse; past dimming; "Now" and "Until"; events spanning midnight; recurring occurrences as distinct rows; hidden calendars filtered out and unknown hidden ids ignored; refresh on a store change, on day rollover, and on a Settings change; and both empty states. Assert observable rows and states, not view structure.
- UI tests select the fake service through a launch variable, like `KYO_IN_MEMORY_STORE`, to drive each permission state and a seeded day. Use `resetAuthorizationStatus(for: .calendar)` only where the real system prompt is under test.
- Check by hand on a real device: an event that started yesterday, the event detail sheet for an invitation, and whether the sheet triggers a Contacts prompt.
- Build both app schemes.

## Out of Scope

- Implementing the feature as part of this specification request.
- The Apple Watch, widgets, and complications.
- Creating, editing, or deleting events, and turning an event into a task.
- Reminders (`EKReminder`).
- Showing events for any day other than Today, and changes to the bottom bar's Calendar (Past days) sheet, including renaming it.
- An events stat in the summary row.
- Syncing the calendar selection between devices.

## Further Notes

- EventKit facts and sources are on branch `research/eventkit-schedule` (`docs/research/eventkit-schedule.md`). It targets the iOS 27 SDK.
- Decisions were made in one grilling session after ADR 0006 freed the top of Today. No Wayfinder map was charted.
- Execution policy for future implementation: **Opus 5.5** (`claude-opus-5-5`) runs orchestration and owns review; the coder assignment is **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`).
- No implementation agents should be launched by this spec-writing request. The `ready-for-agent` label describes specification readiness; it doesn't authorize implementation.
