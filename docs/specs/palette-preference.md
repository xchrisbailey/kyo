# Palette preference

Status: Product behavior confirmed. Specification only; built as one ticket, #223.

## Problem Statement

Kyo always follows the device's light or dark setting. A **theme** has a light and a dark palette, and a user who prefers one of them, such as Techo's chalkboard during the day, can't keep it. The themes spec (`docs/specs/themes.md`) left an override out of scope and added the Appearance group in Settings with room for it.

## Solution

Give Kyo a **palette preference**: System, Light, or Dark. System follows the device's light or dark setting and is the default, so nothing changes until the user picks another. Light and Dark keep that palette of the current theme whatever the device is set to.

The user picks it with a control under the theme picker in the Appearance group. It applies at once, to everything inside Kyo, and the choice belongs to the device.

Terms follow `GLOSSARY.md`: **Palette preference**, **Theme**. Settings is divided into **groups**, as in the themes spec.

## User Stories

1. As a Kyo user, I want to keep a theme's dark palette during the day, or its light palette at night, so that I see the half of the theme I like.
2. As a Kyo user, I want the choice to default to following my device, so that an update changes nothing.
3. As a Kyo user, I want the choice to hold when I switch themes, so that I set it once.
4. As a Kyo user, I want alerts, menus, the keyboard, and the event detail to match the palette I chose, so that no part of Kyo flashes the other one.
5. As a Kyo user, I want the choice to apply the moment I tap it, so that I can see it on the screen I'm on.
6. As a Kyo user, I want the choice kept across launches, so that I choose once.
7. As a Kyo user with an iPhone and an iPad, I want each device to keep its own choice, so that I can suit each screen.
8. As a VoiceOver user, I want the control to announce what it sets and which value is selected, so that I can choose without seeing it.

## Implementation Decisions

### Vocabulary

- `GLOSSARY.md` defines **Palette preference**. Its values are written System, Light, and Dark.
- "Appearance" stays the name of the Settings group only. "Mode", "dark mode", "color scheme", and "override" are not used for this.

### What it decides

- There is one palette preference for the app. It applies to whichever theme is current; switching themes doesn't change it, and a theme has no preference of its own.
- System shows the palette the device's light or dark setting calls for, and follows the device when that setting changes. This is the behavior before this spec.
- Light always shows the current theme's light palette, and Dark its dark palette.

### Reach

- The preference applies to everything inside Kyo: what Kyo lays out, and what iOS draws for it, including alerts, confirmation dialogs, context menus, the keyboard, pickers, the share sheet, the camera, and the system event detail.
- The preference is set once per window, on the window's light or dark style, not passed to each view. SwiftUI's preferred color scheme isn't used: with it, an open sheet doesn't return to the device's setting when the user goes back to System. Theme colors already resolve from the system's light or dark trait, and no view reads the color scheme itself; that stays true.
- A screen that is open when the preference changes redraws in the new palette, including an open sheet, and going back to System returns it to the device's setting without a relaunch.
- What iOS draws outside the running app stays on the device's setting: the launch screen, the quick-capture controls in Control Center and on the Lock Screen, and the Watch complication. With Dark chosen on a device in light, the launch screen can show light for a moment before Kyo appears. This is a known limit and is accepted.
- The Apple Watch ignores the preference. It keeps showing the theme's dark palette, and the preference is never sent to it. ADR 0007 is unchanged.

### Choosing and remembering

- The Appearance group gains a segmented control under the theme picker with three segments: System, Light, Dark.
- The control has no visible label. Its accessibility label is "Palette".
- Tapping a segment applies it immediately, with no confirmation, and Settings itself redraws.
- The theme picker's preview cards don't change. Each still shows its theme's light and dark palettes side by side, whatever the preference is.
- On iPad, every window shows the same preference, and changing it in one window changes them all.
- The choice persists in the device's own `UserDefaults`, injected so tests can supply their own, under a key that follows `CODING_STANDARDS.md`. It isn't in the SwiftData store and isn't synced.
- With nothing stored, the preference is System. A stored value that names no current preference also gives System.

## Testing Decisions

- Test external behavior through the model the views consume, not view structure. There are no snapshot tests.
- Test the choice with an injected `UserDefaults` suite: it starts as System; a pick is read back by a new model on the same defaults; an unknown stored value gives System.
- Prior art: `ThemeChoiceBehaviorTests`.
- One UI test on iPhone: open Settings, pick Dark, relaunch, and find it still selected. It uses the launch variable that names the `UserDefaults` suite, as `ThemeUITests` does.
- The look is reviewed from PR screenshots: Dark chosen on a device in light and Light chosen on a device in dark, each showing Today, Settings, one confirmation dialog, and the keyboard.
- The contrast tests already cover every theme in both palettes and need no change.
- Build both app schemes.

## Out of Scope

- A palette preference per theme.
- Showing only the chosen palette on the preview cards.
- A launch screen that looks the same in light and dark.
- The Apple Watch, phone widgets and controls, and Watch widgets.
- Syncing the preference between devices.
- A text size setting. #224 was closed as not planned: Kyo follows the device text size, and iOS's per-app text size covers wanting Kyo alone larger or smaller.

## Further Notes

- Decisions were made in one grilling session on #223 and #224. No ADR was written: per-device storage is easy to reverse and doesn't touch sync or storage design.
- This supersedes two lines in `docs/specs/themes.md`: "The app always follows the device's light or dark setting. There is no override." and, under Reach, that what iOS draws "still follow[s] light and dark", which now means the palette the preference picks.
- Execution policy: as in the themes spec.
