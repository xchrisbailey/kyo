# 7. The Watch follows the phone's theme through the snapshot context

Status: accepted (specified in `docs/specs/watch-themes.md`; not yet implemented)

## Context

A **theme** is chosen on the iPhone or iPad and kept in that device's own `UserDefaults`. The
themes spec (`docs/specs/themes.md`) made the choice per device on purpose and added nothing to
the phone–Watch sync described in ADR 0001–0005. The Watch app kept its own look.

Theming the Watch needs an answer to where its theme comes from. The Watch has no Settings
screen, it shows the same day as the phone, and it can launch with the phone out of reach.

## Decision

The Watch shows the theme chosen on the iPhone it is paired with. The phone is the only writer,
as in ADR 0001.

The phone puts the chosen theme's id in the same application context that carries the task,
habit, and memo snapshots, under its own key, and writes it **in the single
`updateApplicationContext` call** that writes the snapshots (ADR 0003). It publishes again when
the theme changes.

The Watch stores the last id it received and shows that theme whether or not the phone is
reachable. Before it has received one it shows the Kyo theme. An id it has no palette for also
shows the Kyo theme, and stays stored so the Watch switches once its app knows that theme.

## Considered options

- **A theme chosen on the Watch.** It matches "the choice belongs to the device", but it means
  building a Watch Settings screen for one choice, and a Watch that looks different from the
  phone showing the same day.
- **Follow the phone, with an override on the Watch.** Two sources of truth for a look, and the
  same Settings screen.
- **Send the id through `transferUserInfo`, like a command.** That channel queues every message
  and delivers them in order. A look preference wants the opposite: only the latest value, when
  the Watch next wakes, which is what the application context gives.

## Consequences

- The theme id is a fourth key in the application context. Any code that writes the context
  without it erases it on the Watch, exactly as ADR 0003 describes for the snapshots. It must go
  through the transport's one publish path.
- "The choice belongs to the device" now has an exception: the Watch has no choice of its own. An
  iPad's theme never reaches the Watch.
- The phone and Watch can be on different app versions, so the Watch must tolerate an id it
  doesn't know.
- The Watch holds its own copy of each theme's dark colors, because the phone's theme code is
  built on iOS-only color APIs. A test keeps the two in step.
