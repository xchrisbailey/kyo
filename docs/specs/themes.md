# Themes

Status: Product behavior confirmed. Specification only; implementation is broken into separate tickets.

## Problem Statement

Kyo has one look. Its colors are written into each view, mostly as system colors, and every heading uses the system font. A user who wants Kyo to look different, or simply to feel like their own planner, has nothing to change, and Settings has no place to put such a choice.

## Solution

Give Kyo **themes**. A theme is a light palette, a dark palette, and a **header font**; the device's light or dark setting decides which palette shows. Kyo ships three:

- **Kyo**: the look Kyo has today, unchanged, and the default.
- **Neko**: Catppuccin Latte in light and Catppuccin Mocha in dark, with Geist Mono as the header font.
- **Techo**: a paper planner in light and a chalkboard in dark, with the handwritten Caveat as the header font.

The user picks a theme in a new **Appearance** group in Settings. Each theme is shown as a preview card, and tapping one applies it at once. The choice belongs to the device.

Terms follow `GLOSSARY.md`: **Theme**, **Header font**, **Today**, **Month**, **Section**, **Schedule**, **Event**. Settings is divided into **groups** (Appearance, Schedule); **Section** stays reserved for the groups on Today.

## User Stories

1. As a Kyo user, I want to choose a theme, so that Kyo looks the way I like.
2. As a Kyo user, I want Settings to have an Appearance group, so that I know where look-and-feel choices live.
3. As a Kyo user, I want each theme shown as a preview with its colors and its header font, so that I can choose without trying each one.
4. As a Kyo user, I want a theme to apply the moment I tap it, so that I can see it on the screen I'm on.
5. As a Kyo user, I want my theme kept across launches, so that I choose once.
6. As a Kyo user, I want each theme to have a light and a dark palette that follow my device setting, so that a theme never forces a bright screen at night.
7. As a Kyo user who updates the app, I want Kyo to look exactly as it did until I pick another theme, so that the update doesn't surprise me.
8. As a Kyo user, I want a theme to color the whole app, including sheets, navigation bars, and Settings, so that no screen is left in the old look.
9. As a Kyo user, I want section headers and screen titles set in the theme's header font, so that the theme has a character beyond color.
10. As a Kyo user, I want task, habit, and memo text to stay in the system font, so that what I read most stays easy to read.
11. As a Kyo user, I want the "kyo" wordmark and the large numerals to look the same in every theme, so that the brand and the layout hold steady.
12. As a Kyo user who uses a larger text size, I want the header font to grow with it, so that a theme doesn't undo my accessibility setting.
13. As a Kyo user, I want handwritten headers to look as large as the ones they replace, so that the theme isn't harder to read.
14. As a Kyo user, I want my calendar events to keep their own calendar colors in every theme, so that I still recognize them.
15. As a Kyo user, I want text to be readable against its background in every theme and both modes, so that no theme is a trap.
16. As a Kyo user with an iPhone and an iPad, I want each device to keep its own theme, so that I can suit each screen.
17. As a VoiceOver user, I want each preview card to announce its theme's name and whether it's selected, so that I can choose without seeing the colors.

## Implementation Decisions

### Vocabulary

- `GLOSSARY.md` defines **Theme** and **Header font**.
- The original look is the **Kyo theme**, always written with "theme" so it isn't confused with the app.

### What a theme holds

- A theme has a name, a header font, and two palettes, light and dark.
- A palette is a full set of named colors, not just an accent: screen background, sheet background, card, list row, primary, secondary and tertiary text, separator, fill, accent, the color drawn on top of the accent (a checkmark on a filled circle), scrim, warning, destructive (which also colors recording), and the four Month kind colors. If the app turns out to use a role this list misses, the role is added to the palette; a view never falls back to naming a color.
- Views take every color from the current theme. No view names a system color or a color literal directly. The exceptions are clear, system materials, and event colors. The existing `KyoPalette` and the accent literals duplicated beside it are replaced by this.
- Lists and sheets that name no color today, and so get iOS's own backgrounds, take their backgrounds and rows from the theme too.
- The Kyo theme's colors resolve to exactly the colors in use today, so introducing the palette changes nothing on screen. Its colors are the same system colors, not fixed copies of them, so they still shift for a sheet's raised background in dark and for Increase Contrast. Where two screens use different colors for the same role today, the Kyo theme keeps both.
- The Kyo theme's header font is the system font at today's sizes and weights.
- Event colors come from the user's calendars (`ScheduleColor`) and are not part of any theme.

### The themes

- **Neko**: Latte in light, Mocha in dark, using Catppuccin's published values. Base is the screen background, the surface colors are cards, Text and the Subtext colors are the text levels, and **Mauve** is the accent. Warning, destructive, and the Month kind colors are drawn from Catppuccin's other accents. Header font: Geist Mono.
- **Techo**: light is warm cream paper with blue-black ink text and a red margin-line accent; dark is a deep slate-green chalkboard with chalk-white text and a chalk-yellow accent. Header font: Caveat.
- Exact values that aren't published (all of Techo, and Neko's choice of kind colors) are chosen at implementation and reviewed from the PR screenshots, in light and dark.
- Primary text meets WCAG AA contrast, 4.5:1, against every background it sits on, in every theme and both modes. Secondary text, the accent, and the color drawn on the accent meet 3:1. Tertiary text is for hints and disabled states and has no floor. Contrast is measured on the color as drawn, after a translucent color is blended with what's behind it.
- These floors are ones today's look and Catppuccin's published values can meet almost everywhere; a stricter floor would force changing them. Where the Kyo theme or a published Neko value still misses one, the color is left alone and the pair is recorded in the contrast test with its ratio. The Kyo theme's recorded misses are on iOS's system orange and red; Neko's are on Catppuccin's Peach in light, which the owner chose to keep as published.
- The same 3:1 floor applies to text and glyphs drawn in or on the warning and destructive colors.
- Geist Mono and Caveat are bundled with the app in the two weights headers use, semibold and bold. Both are under the SIL Open Font License.

### Header font

- The header font sets section headers and screen titles: the section headers on Today, the large "Today" title, the Month's month name, navigation bar titles, and the day-group and summary titles in Memos and the Month.
- Navigation bar titles go through one shared title style that every screen uses. iOS gives no direct way to set their font, so if no approach can restyle an open screen at once without touching screens iOS draws, navigation bar titles stay in the system font and the rest of this list stands.
- Letter spacing belongs to the theme with the font. The Kyo theme keeps today's, and Neko and Techo use their fonts' own. Caveat's last letter reaches past its own width and would be cut off at the text's edge, so Techo's headers end with a no-break space that gives it room without adding space between letters.
- Everything else stays in the system font: body text, task, habit and memo text, numbers, and controls.
- The "kyo" wordmark and the large numerals keep their rounded system design in every theme.
- The header font scales with the device text size the way headers do today.
- A theme can adjust its header size, for all headers or for one kind, so that its headers look the same size as the Kyo theme's. Caveat needs this; it reads smaller than the system font at the same point size.
- Navigation bar titles grow with the device text size no further than iOS's own navigation titles do.
- Headers come from one shared place, so the ad hoc titles in Memos and the Month stop carrying their own font.

### Reach

- A theme colors everything Kyo lays out: Today, the Month, sheets, navigation bars, the Settings list, and control tints.
- What iOS draws stays as iOS draws it: alerts, context menus, the keyboard, pickers, and the system event detail. These still follow light and dark (since `docs/specs/palette-preference.md`, the palette the user's preference picks). Their buttons may pick up the theme's accent as a tint; that's accepted.
- Themes apply to the iPhone and iPad app only. Phone widgets, the watch app, and watch widgets keep the Kyo look. (The watch app is superseded by `docs/specs/watch-themes.md`.)

### Choosing and remembering

- Settings gains an **Appearance** group above Schedule. It holds the theme picker and nothing else for now.
- The picker shows one preview card per theme, with the theme's light and dark colors and its name set in its header font. The current theme is marked as selected.
- Tapping a card applies the theme immediately, with no confirmation, and Settings itself redraws in it.
- The app always follows the device's light or dark setting. There is no override. (Superseded by `docs/specs/palette-preference.md`.)
- There is one current theme for the app. On iPad, every window shows it, and picking a theme in one window changes them all.
- The choice persists in the device's own `UserDefaults`, injected so tests can supply their own, under a key that follows `CODING_STANDARDS.md`. It isn't in the SwiftData store and isn't synced.
- With nothing stored, the theme is Kyo. A stored value that names no current theme also gives Kyo.

## Testing Decisions

- Test external behavior through the model the views consume, not view structure. There are no snapshot tests; the look is reviewed from PR screenshots in light and dark.
- Test the theme choice with an injected `UserDefaults` suite: it starts as Kyo; a pick is read back by a new model on the same defaults; an unknown stored value gives Kyo.
- Test contrast by computation, to the floors above: for every theme and both modes, primary text, secondary text and the accent against each background they sit on, and the on-accent color against the accent. Colors are resolved for the mode and blended before measuring, so a translucent color isn't read as opaque. A theme added later is covered without a new test.
- Prior art: the `CollapsedSections` tests (state persisted through injected defaults).
- UI tests on iPhone cover what the model can't: open Settings, pick a theme, relaunch, and find it still selected; and a bundled header font grows with the device text size. A launch variable names the `UserDefaults` suite the choice is kept in, so the test starts clean and the relaunch reads the same suite.
- The palette ticket has no behavior to test beyond the existing suites staying green; its review is a before-and-after screenshot comparison showing no change.
- Build both app schemes.

## Out of Scope

- Theming phone widgets, the watch app, and watch widgets. (The watch app is superseded by `docs/specs/watch-themes.md`; the phone has no widgets a theme could change.)
- A light, dark, or system override. (Superseded by `docs/specs/palette-preference.md`.)
- Font sizing and any other Appearance setting. (A text size setting, #224, was closed as not planned; Kyo follows the device text size.)
- Syncing the theme between devices.
- User-made themes, or editing a theme's colors or font.
- Changing the app icon with the theme.
- Recoloring events.

## Further Notes

- Decisions were made in one grilling session. No ADR was written: per-device storage and the palette are easy to reverse and don't touch sync or storage design.
- This supersedes the lines in `docs/specs/habits.md` saying Settings holds only the Schedule group.
- Not discussed in the session, and the spec author's call: which Catppuccin accents become Neko's warning, destructive, and kind colors, and the exact shape of a preview card. Each can be changed in review.
- Decided from screenshots after the themes shipped (#212–#219), and now part of the look:
  - Neko's light cards and rows are Mantle, with Surface0 for the unselected weekday chip.
  - Techo's light controls are tinted pen blue; vermilion stays its accent.
  - In the Kyo theme's dark mode, marks drawn on the accent are dark. This and the next item are the places the Kyo theme was changed on purpose.
  - In the Month, a long month name stays on one line and shrinks to fit, in every theme.
  - Techo's headers use Caveat's own letter spacing, with room for the last letter added as a space after the text.
  - The audio player bar is drawn on the card color in Neko and Techo; the Kyo theme keeps the system material.
  - The screen shown when the store fails to open takes the theme's screen background, which in the Kyo theme is the grouped grey.
- An adversarial pass on the ticket breakdown changed this spec before any code was written: the palette's extra roles, system colors for the Kyo theme, the contrast floors, the large titles joining the header font, the fallback for navigation bar titles, and one theme across iPad windows.
- Suggested tickets, in order, each stacked on the one before:
  1. The palette and shared headers, with the Kyo theme only and no visible change.
  2. The Appearance group, the picker, the stored choice, and the Neko theme with Geist Mono.
  3. The Techo theme with Caveat.
- Execution policy: **Opus 5.5** (`claude-opus-5-5`) runs orchestration and owns review; the coder assignment is **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`).
