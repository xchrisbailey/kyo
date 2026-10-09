# Themes on Apple Watch

Status: Product behavior confirmed. Specification only; implementation is broken into separate tickets.

## Problem Statement

A Kyo user can pick a **theme** on their iPhone, and the whole phone app changes to it. Their Apple Watch does not. It shows the same day, with the same tasks, habits and memos, in the look it has always had: a green accent on grey cards. Someone who chose Neko or Techo sees one app on the phone and what looks like a different one on the wrist.

## Solution

The Apple Watch shows the theme chosen on the iPhone it is paired with. Pick Neko on the phone and the Watch app's cards, text, accent and status colors become Neko's; pick Techo and they become the chalkboard's. There is nothing to set on the Watch. It keeps showing the last theme it was given when the phone is out of reach, and it shows the Kyo theme, which is the Watch's look today, until it has been given one.

The Watch uses each theme's dark palette on a black background, and keeps the system font for its headers.

Terms follow `GLOSSARY.md`: **Theme**, **Header font**, **Today**, **Section**, **Task**, **Habit**, **Memo**.

## User Stories

1. As a Kyo user with an Apple Watch, I want my Watch to show the theme I picked on my iPhone, so that Kyo looks like one app on both.
2. As a Kyo user, I want the Watch to change when I change the theme on my iPhone, so that I never have to set it twice.
3. As a Kyo user looking at my Watch while I change the theme on my phone, I want the Watch app to recolor at once, so that I can see the change took.
4. As a Kyo user whose Watch was asleep when I changed the theme, I want it to be in the new theme the next time I raise my wrist.
5. As a Kyo user away from my phone, I want my Watch to keep the theme it last had, so that the look doesn't reset when the phone is out of reach.
6. As a Kyo user who opens Kyo on the Watch before the phone has sent anything, I want it to look the way the Watch app always has, so that a fresh install isn't a surprise.
7. As a Kyo user who keeps the Kyo theme, I want my Watch to look exactly as it does today, so that this feature changes nothing for me.
8. As a Kyo user, I want the Watch app's cards, text, checkmarks and buttons to take the theme's colors, so that the whole screen reads as that theme.
9. As a Kyo user, I want warning and recording colors on the Watch to come from the theme, so that the recorder belongs to the same look.
10. As a Kyo user, I want the Watch background to stay black, so that the app sits on the Watch like every other app and the screen's edge stays hidden.
11. As a Kyo user, I want Watch headers to stay in the system font, so that they stay readable at the Watch's small sizes.
12. As a Kyo user, I want text on the Watch to be readable against its card and against black in every theme.
13. As a Kyo user whose phone app is newer than my Watch app, I want the Watch to fall back to the Kyo theme for a theme it doesn't know, and to switch by itself once the Watch app updates.
14. As a Kyo user with an iPad, I want the iPad's theme to stay the iPad's, so that it doesn't change my Watch.
15. As a Kyo user, I want my Watch face's complication to keep the look my Watch face gives it.

## Implementation Decisions

### Vocabulary

- `GLOSSARY.md` gains one sentence under **Theme**: the Apple Watch shows the iPhone's theme, in its dark palette and without the header font.
- ADR 0007 records why the Watch follows the phone and how the choice travels.

### Where the Watch's theme comes from

- The Watch shows the theme chosen on the iPhone it is paired with. The phone is the only writer. The Watch has no theme setting.
- An iPad's theme is its own and never reaches the Watch.
- The phone puts the chosen theme's id in the application context that already carries the task, habit and memo snapshots, under its own key, and writes it in the same single write as the snapshots (ADR 0003). It publishes the id when the phone app starts, as the snapshots are, and again when the theme changes, so a Watch paired or reinstalled later still gets it.
- A context that arrives without a theme id leaves the Watch's stored theme alone.
- The Watch reads the id both from the context waiting for it at launch and from one that arrives while it runs.
- The Watch stores the last id it received in its own `UserDefaults`, under a key that follows `CODING_STANDARDS.md`, injected so tests can supply their own.
- With nothing stored, the Watch shows the Kyo theme. An id it has no palette for also shows the Kyo theme and stays stored, so the Watch switches without another message once its app knows that theme.
- The Watch never asks the phone for the theme and never waits on it.
- A change that arrives while the Watch app is on screen recolors it at once, with no restart and no animation.

### What a theme is on the Watch

- Colors only. The Watch does not use the **header font**: its section headers and titles stay in the system font in every theme, and no font is bundled with the Watch app.
- The Watch uses each theme's dark palette. Behind everything is true black, in every theme.
- From the theme come: the accent, the card and row surfaces, the text levels, the warning color, the destructive color (which also colors recording), the tint of the Edit button, and the color of a label drawn on a button filled with the accent, the warning color, or the destructive color.
- A theme colors what the Watch app sets itself. What watchOS draws stays as watchOS draws it: the clock, a sheet's close control, the text-input sheet, alerts, and a swipe action's own destructive styling.
- Neko and Techo on the Watch use the same values as their dark palettes on the phone.
- The Kyo theme on the Watch is the Watch's look today, unchanged: watchOS's own green, blue, red, orange and secondary text, its card grey at today's opacities, its buttons' own label colors, and the light-mode values its code already carries. Its palette holds those system colors themselves, not copies of them. Introducing the Watch palette changes nothing on screen.
- Neko and Techo have dark values only, as fixed color values. A surface's opacity is part of its palette value, not something a view applies on top.
- The one place the Watch draws on a translucent system material stays as it is.
- Both Watch screens are covered: Today and the recorder.
- The complication and the Watch's control are not themed. A Watch face tints its complications, and watchOS draws controls.

### Where the colors live

- The phone's theme code is built on iOS-only color APIs and is compiled only into the phone app, so the Watch has its own palette for the roles above, keyed by the same theme ids, in code both apps compile. Neko's and Techo's entries are plain color values a test can read; the Kyo theme's are watchOS system colors.
- Watch views read the current palette from the environment, with the Kyo theme as the default.
- Views in the Watch app take every color from the current Watch palette. No Watch view names a system color or a color literal directly, other than clear, black for the background, and the material above.
- The phone's theme files are not refactored for this.

## Testing Decisions

- Test external behavior through the models the views consume, not view structure. There is no Watch UI test for themes: a Watch UI test can't receive anything from a phone, and none asserts color.
- Test the Watch's theme model with an injected `UserDefaults` suite: it starts as Kyo; it adopts a received id; a new model on the same defaults reads it back; an unknown id shows Kyo and stays stored; a later known id replaces it.
- Test parity: for Neko and Techo, each color in the Watch palette equals the phone's dark palette value for the matching role (accent, card, list row, the text levels, warning, destructive, the labels on accent, warning and destructive fills, and the control tint for the Edit button). A theme added to one side without the other fails.
- Test contrast on Neko's and Techo's Watch palettes to the phone's floors, against black and against the card: primary text 4.5:1; secondary text and the accent 3:1; a button's label against its fill 3:1. The Kyo theme's Watch colors are watchOS system colors, which a test can't read, so they are not measured.
- Test the phone side through the transport: the published context carries the theme id with the snapshots still in it; it is published at start and again when the theme changes; and publishing a snapshot keeps it. Test the Watch side the same way for both paths a context arrives by, and for a context with no id.
- Delivery between a real phone and Watch can't be driven in tests; the PR says how the end-to-end path was exercised.
- A launch variable selects the Watch's theme storage, as collapsed sections have, so a screenshot run can start the Watch app in a chosen theme and an in-memory launch writes nothing lasting.
- Prior art: `CollapsedSections` and its tests (a per-device choice both apps share), the phone's `ThemeContrastTests` and `ContrastMeasure`, and the transport tests for the habit and memo snapshots.
- The look is reviewed from Watch simulator screenshots. For the palette ticket: Today and the recorder in the Kyo theme before and after, with no difference. For the follow ticket: the same screens in Neko and in Techo.
- `scripts/check` runs the Watch UI suite when Watch or shared code changes; it must still pass.
- Build both app schemes.

## Out of Scope

- A theme setting on the Watch, or an override of the phone's choice.
- The header font on the Watch, and bundling fonts with the Watch app.
- Theming the complication or the Watch's control.
- Phone widgets. The phone has only Control Center controls, which iOS draws; there is nothing in them for a theme to change (#221).
- Light palettes on the Watch for Neko and Techo.
- Removing the Watch's unused light-mode values from the Kyo theme.
- Syncing the theme between an iPhone and an iPad.

## Further Notes

- Decisions were made in one grilling session on #221 and #222. ADR 0007 was written, because this reverses the themes spec's "the choice belongs to the device" for the Watch and adds to phone–Watch sync.
- This supersedes the lines in `docs/specs/themes.md` that leave the Watch app out of themes.
- An adversarial pass on the ticket breakdown changed this spec before any code was written: publishing the id at start, a context without an id, the two paths a context arrives by, labels on filled buttons, what watchOS draws, the Kyo theme holding system colors and going unmeasured, opacity living in the palette, and the launch variable.
- Suggested tickets, in order: (1) the Watch palette, with the Kyo theme only and no visible change; (2) the phone publishes the choice and the Watch follows it, with Neko's and Techo's palettes.
- Execution policy: **Opus 5.5** (`claude-opus-5-5`) runs orchestration and owns review; the coder assignment is **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`). The follow ticket touches phone–Watch sync, so its branch gets an adversarial pass before review.
