# Deferred tasks

Status: Product behavior confirmed. Specification only; implementation requires a separate user request.

## Confirmed behavior

- A user can defer a task to a planned day. It stays out of Today's active list until that day arrives. The planned day is not a deadline.
- Deferral is one-time. Recurring tasks are outside this feature.
- Scheduling is available during task creation and through a Do later action on an existing task.
- Both entry points share a scheduling input with weekday, one-week, and one-month choices, plus plain-text date descriptions.
- Apple Intelligence interprets the plain-text description. The user sees the actual calendar date before saving.

## Browsing and editing

- A Later list is accessible from Tasks and ordered by planned day, preserving task creation order within a day.
- Users can edit, reschedule, delete, or bring a deferred task back to Today from Later.
- Month shows planned tasks and completed tasks as distinct states. Month remains read-only; edits happen through Tasks or Later.
- Scheduling is available on iPhone and iPad. Apple Watch shows tasks when they become available on Today; Watch scheduling and a Watch Later list are outside this feature.

## Date interpretation

- Interpret each description relative to Today on the user's device. Preview the full resolved calendar date before saving.
- A bare weekday means its next occurrence, including Today if that weekday is today.
- Next Friday means Friday in the next calendar week, using the device's calendar-week convention.
- One week out means the same weekday next week, using calendar days rather than a fixed elapsed duration.
- One month out means the same calendar day next month, clamped to that month's final day if necessary.
- Dates are calendar days, not times or reminder triggers. If the description includes a time, explain that times are unsupported rather than silently discarding it.
- For a resolved past date, ask the user to select Today or another date. Do not silently substitute a date.
- Ambiguous or unsupported descriptions require clarification or a date-picker choice before saving.
- Once saved, the planned day is fixed; reopening the task does not reinterpret the original relative phrase.

## Apple Intelligence

- Apple Intelligence extracts the date intent from the user's separate scheduling input. Task text remains task text; do not silently remove apparent dates from it.
- Calendar calculations resolve extracted weekdays, relative units, and explicit date components into the actual date. See ADR 0008.
- Quick choices and a date picker remain available when Apple Intelligence is unavailable, unsupported, not ready, or unable to resolve the input.
- Use the existing on-device language-model boundary and availability handling. Do not introduce a cloud interpretation service.

## Carryover and synchronization

- A deferred task stays out of Today's list and counts before its planned day.
- On or after its planned day, it appears as an active task. Unfinished tasks then follow existing carryover behavior, including when the app has not opened for several days.
- Preserve task identity, creation order, saved text, and completion history when scheduling or rescheduling. Existing completion grouping and count behavior still applies.
- Planned-day data survives persistence and phone/Watch synchronization. Watch date rollover must not expose deferred tasks early or depend on the phone being reachable at the boundary.
- Follow existing phone-authoritative reconciliation and additive CloudKit-ready storage constraints. Delivery retries or stale Watch edits must not duplicate tasks or erase planned days.

## Validation for implementation

- Verify deferring new and existing tasks, Later ordering, rescheduling, bringing a task to Today, and deletion.
- Verify Today visibility and counts before, on, and after the planned day, including missed launches and existing completion behavior.
- Verify same-weekday scheduling across daylight-saving changes; month-end and leap-year handling; weekday ambiguity; past dates; unsupported times; and uncertain AI responses.
- Verify persistence and phone/Watch convergence, including offline rollover, retries, and edits that must preserve planned days.
- Verify Month distinguishes planned and completed tasks without introducing editing there.
- Verify quick choices and the date picker work without Apple Intelligence, and that saving never depends on an unconfirmed AI interpretation.

## Existing product constraints

Today remains the day's action surface; Later manages deferred tasks without opening an editable future-day view. Month remains read-only. This feature extends the original daily-task specification's scope to planned days, while deadlines, task times, reminders, and recurring tasks remain outside scope.
