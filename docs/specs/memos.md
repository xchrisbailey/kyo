# Memos on iPhone, iPad, and Apple Watch

Status: Draft for review. Specification only; implementation requires a separate user request.

## Problem Statement

Kyo presents one day at a time, but its Memos section still shows fixed sample rows ("An idea for the weekend", a voice row "Thoughts on my walk") on iPhone, iPad, and Apple Watch, under a fixed "Notes & voice" subtitle. Users can't write or record a memo, attach a photo, find an older memo, or turn what they said into tasks. There's no fast way to start capturing a thought from outside the app, and the Watch can't record anything.

## Solution

Make Memos a real feature within the existing layout. A user adds a **Written memo** or a **Voice memo** from the bottom Add menu, or jumps straight into capture from a Control Center or Lock Screen control, the Action button, Siri and Shortcuts, or a Watch complication. A voice memo keeps its audio and gets an on-device **Transcript**, live while recording and finalized on stop, plus an on-device Apple Intelligence title where available. Either kind can carry up to 4 photos. Today shows today's memos; older ones live in **Memo history**, reached through a "See all" link that opens a searchable Memos sheet. An open memo can be edited, shared, deleted, or turned into tasks through **Memo → Task**, which proposes **Suggested tasks** that the user adds to **Today**. The Watch lists today's memos and records voice memos, which the phone transcribes. Memos are stored in SwiftData, ready for a later iCloud sync. Terms follow `CONTEXT.md`: **Memo**, **Written memo**, **Voice memo**, **Transcript**, **Memo history**, **Suggested task**, **Task**, **Today**.

## User Stories

1. As a Kyo user, I want to add a written memo or a voice memo from the bottom Add button, so that memos start from the same place as tasks and habits.
2. As a Kyo user, I want a written memo's first line to be its title, so that I don't have to name it separately.
3. As a Kyo user, I want to save a memo that is only photos, so that I can capture something I saw without typing.
4. As a Kyo user, I want an empty memo to be thrown away rather than saved, so that my list doesn't fill with blanks.
5. As a Kyo user, I want to see my words appear while I record, so that I know Kyo is hearing me.
6. As a Kyo user, I want a voice memo saved the moment I stop, so that nothing is lost while the transcript is finalized.
7. As a Kyo user, I want to discard a recording I started by accident, so that nothing is saved.
8. As a Kyo user, I want a warning near the 10-minute limit and an automatic save when I reach it, so that a long recording is never lost.
9. As a Kyo user, I want my voice memo to keep its audio even if transcription fails, and to be transcribed later, so that I can still listen to it and eventually read it.
10. As a Kyo user, I want a voice memo to get a short, meaningful title on its own, so that I can tell my recordings apart.
11. As a Kyo user, I want to rename a voice memo and edit its transcript without changing the audio, so that I can fix mistakes.
12. As a Kyo user, I want to attach up to 4 photos to any memo, from the camera or my library, including while recording.
13. As a Kyo user, I want Today to list today's memos newest first, with their times and voice durations, so that I can scan my day.
14. As a Kyo user, I want to tap a memo to open it, and have my edits save on their own.
15. As a Kyo user, I want to play a voice memo and scrub through it while reading its transcript.
16. As a Kyo user, I want to delete a memo by swiping or long-pressing, with a confirmation for voice memos, so that I don't lose a recording by accident.
17. As a Kyo user, I want to share a memo's text and photos through the share sheet, so that I can send it to another app.
18. As a Kyo user, I want Kyo to suggest tasks from a memo and let me pick and edit them before adding them to Today, so that what I said becomes something I'll act on.
19. As a Kyo user on a device without Apple Intelligence, I want Memo → Task to still let me type tasks, so that the action is never missing.
20. As a Kyo user, I want to see all my memos, grouped by day, from a "See all" link, so that older memos are still within reach.
21. As a Kyo user, I want to search memo titles, text, and transcripts and see where each match is, so that I can find a memo I half remember.
22. As a Kyo user, I want to edit, share, delete, and make tasks from an older memo just like a memo from today.
23. As a Kyo user, I want a Control Center, Lock Screen, or Action button control that starts recording at once, so that I can capture a thought in one press.
24. As a Kyo user, I want to say "Record a memo in Kyo" or "Write a memo in Kyo", so that I can capture hands-free or from Shortcuts.
25. As a Kyo user, I want a quick-capture action to bring back a capture I already have open rather than replace it, so that nothing I was doing is lost.
26. As a Kyo user, I want a recording to pause for a phone call and offer Resume, and to keep going when I lock the phone or switch apps.
27. As a Kyo user, I want whatever I recorded to be saved if Kyo quits mid-recording.
28. As an Apple Watch user, I want to see today's memos on my wrist.
29. As an Apple Watch user, I want to record a voice memo from the Watch, a complication, or a Watch control, even when my phone isn't nearby, and have it transcribed on my phone later.
30. As an Apple Watch user, I want to see which recordings haven't reached my phone yet, so that I know they're safe but waiting.
31. As a phone and Watch user, I want each Watch recording to arrive exactly once, and a memo I deleted never to come back.
32. As a Kyo user, I want my memos, audio, and photos to survive closing and reopening the app.

## Implementation Decisions

### Build order and storage

- The SwiftData storage spec (`docs/specs/swiftdata-storage.md`, #65) is implemented first. It moves tasks and habits from UserDefaults to SwiftData on the phone and iPad, behind their existing store interfaces. Memos build on that store. (#63, #64)
- One SwiftData store holds tasks, habits, and memos, in the app's own container. There's no App Group, because the widget extensions don't read data. (#64)
- Audio and photos are `@Attribute(.externalStorage)` data on separate models attached to the memo, so listing and searching memos never loads media bytes, and a later iCloud sync carries them as CloudKit assets. See `docs/adr/0004-swiftdata-cloudkit-ready-storage.md`. (#63)
- Every memo model follows ADR 0004's CloudKit rules from day one: no `.unique` or `#Unique`, every relationship optional with its inverse set, no `.deny` delete rule, and a schema that only adds. Duplicates are removed by id in app code. The store uses `cloudKitDatabase: .none` until the sync effort. (#63)
- Audio is AAC, mono, 48 kbps (about 3.6 MB for 10 minutes), on both phone and Watch. Photos are stored as HEIC with the longest edge at 2048 px; the original isn't kept, and sharing sends the stored copy. (#63)
- Memo content isn't indexed in system Spotlight. Search lives in the Memos sheet. (#63)
- The Watch doesn't use SwiftData. It keeps a small UserDefaults cache of the memo snapshot plus its own recording outbox and audio files. (#63, #59)

### The memo and its day

- A memo belongs to the device's local calendar date when it was created, stored like `TaskCompletionDay`. It never moves on edit or time-zone change. (#55)
- A voice memo's day is the day recording started, so a recording that crosses midnight belongs to the earlier day. A Watch recording belongs to the day the Watch started recording, not the day the phone received it. (#55)
- Today shows only memos whose day is Today. Everything older is memo history. (#51, #58)
- A **Written memo** is one body of text: the first line is the title and the rest is the detail. A memo with no text and no photos is discarded rather than saved. A photo-only memo is allowed. (#55)
- A **Voice memo** has audio, a **Transcript** (its only text, editable; there's no separate notes field), a title, a duration, and up to 4 photos. Editing the transcript never changes the audio. (#55)
- Delete is permanent. It removes the memo, its audio, and its photos, with no undo or trash. Tasks already created from the memo stay. (#55)

### Titles

- Written memo: its first line. Photo-only memo: "Photo memo". (#55, #56)
- Voice memo: an on-device Apple Intelligence title generated once, when the transcript is finalized. The user can rename it. It's never regenerated automatically, not even when the transcript is edited, and there's no "Regenerate title" action. Without a generated or user title, it falls back to "Voice memo". (#55, #56)
- Fallback titles appear in two forms. In a row whose time column is visible, they read just **"Voice memo"** or **"Photo memo"**. Where no time column is visible, such as in shared text, they read "Voice memo · 9:41 AM" or "Photo memo · 9:41 AM". (#56; see Open questions on memo history)

### Recording a voice memo (iPhone/iPad)

- The full-screen recorder shows the elapsed time, a waveform, and a large live transcript, with **Discard** (saves nothing) and **Stop** (saves). Photos can be attached while recording. (#56)
- States: **Recording** → **Transcribing** → **Transcribed**, or **No transcript** if transcription failed. Transcribing also covers audio arriving from the Watch. (#55)
- The memo is saved as soon as recording stops, before the final transcript exists, in the Transcribing state. (#55)
- The cap is 10 minutes. A warning shows during the last 30 seconds. At 10:00 the recording stops and saves as normal, with a haptic and a "Recording stopped at 10 minutes" note on the memo. (#55, #56)
- A memo with no transcript keeps its audio, which still plays. It retries automatically when the cause clears (for example once the speech model has downloaded), and its open memo shows a manual **Try again** button. (#55, #56)

### Transcription

- On iPhone and iPad, `SpeechAnalyzer` with `SpeechTranscriber` transcribes on device: live from the microphone while recording (the progressive preset's volatile results), and from the saved file for retries and Watch recordings. iOS 27's `CaptureInputSequenceProvider` and `AssetInputSequenceProvider` supply the input. (#52)
- Check `SpeechTranscriber.isAvailable` and `supportedLocale(equivalentTo:)` at run time on both iPhone and iPad; Apple publishes neither the language list nor the hardware floor. Where `SpeechTranscriber` can't serve the device or locale, fall back to `DictationTranscriber` (same API, older on-device model). If neither works, the memo is kept as audio with No transcript. (#52)
- The speech model is a system asset installed through `AssetInventory`. A locale's first use needs one network download, then works offline. The system may drop unused assets. A pending or failed download leaves the memo in No transcript until it can be retried. (#52, #55)
- Speech-recognition authorization isn't required; `SpeechAnalyzer` needs only microphone access. (#53, #61)
- The Speech framework isn't on watchOS, so the Watch only records and the phone transcribes the file. (#52)
- The system limits simultaneous analyses (`insufficientResources`), so transcription should run one memo at a time, queuing Watch recordings and retries. (#52, research)

### Apple Intelligence

- The Foundation Models on-device `SystemLanguageModel` generates voice memo titles and Suggested tasks, using guided generation (`@Generable` with `@Guide(.maximumCount(n))`). (#52)
- It needs an Apple Intelligence device, a supported region and language, and Apple Intelligence turned on. Check `availability` (`.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`) and `supportsLocale()`. (#52)
- The on-device context window is 4,096 tokens per session. If a transcript or text doesn't fit, the title and suggestions come from the part that fits, starting at the beginning. There's no splitting across sessions. (#55, #57)
- Fallbacks: no AI title means the "Voice memo" fallback title (editable). No AI for Memo → Task means the manual sheet described below. (#51, #57)
- `SystemLanguageModel` isn't on watchOS, and Private Cloud Compute isn't used. All AI runs on the phone; the Watch receives titles in the memo snapshot. (#52, #59)
- The model changes with OS versions, so prompts are re-tested on each release. (#52)

### Capturing on iPhone/iPad

- The bottom **+** menu gains **Written memo** and **Voice memo**, after Task and Habit. (#56)
- Written memo opens a compose sheet with Cancel and Save and a photo menu (camera or library), up to 4 photos. Saving a memo with no text and no photos discards it. (#55, #56)
- Voice memo opens the full-screen recorder above. (#56)

### Today's Memos section

- Rows are ordered newest first. (#55, #56)
- Each row shows an icon for its kind (written, voice, voice with no transcript, photo), the title, and a detail line: the text or transcript excerpt, a "Transcribing…" spinner, or "No transcript". (#56)
- Up to 4 photo thumbnails sit under the detail line. (#56)
- On the right: the creation time ("9:41 AM") and, for voice memos, the duration. (#55, #56)
- The section subtitle shows the count ("2 memos"), or "Notes & voice" when there are none. (#51, #56)
- Tapping a row opens the memo. Swiping or long-pressing a row deletes it; voice memos confirm first. (#51, #56)
- A **See all** link in the section header opens the Memos sheet whenever any memo exists, including when Today has none, and is hidden when there are no memos. (#58)

### The open memo

- An open memo is a card sheet. From the top: kind · time · duration, a large title (editable for voice memos), an action row (**Share**, **Memo → Task**, **Delete**), a photo carousel with an add slot, then the text or transcript editor. (#56)
- For voice memos, the audio player (play/pause and scrubber) is pinned to the bottom. While Transcribing, the transcript area shows "Transcribing…"; with No transcript, it shows **Try again**. (#56)
- Edits save immediately; there's no Save button. Emptying a written memo and closing it discards the memo. (#56; see Open questions)
- Delete in the action row follows the row rule: voice memos confirm first. (#56, prototype)

### Photos

- Up to 4 photos per memo, written or voice, from the camera or the photo library, added in the compose sheet, while recording, or in the open memo's carousel, and removable there. (#51, #56)
- "Choose from Library" uses the system photo picker, which needs no permission and shows no prompt. (#66)
- "Take Photo" shows the system camera prompt on first use. If camera access is denied, that menu item shows "Camera access is off" with **Open Settings**, and "Choose from Library" keeps working. (#66)
- Photos aren't searched. (#58)

### Sharing

- The open memo's **Share** button opens the iOS share sheet; Claude, ChatGPT, and other installed apps appear there. There are no per-app buttons. (#55)
- It shares the text (title, then body or transcript) plus any photos, never the audio. A voice memo with no transcript shares only its photos; if it has none, Share is unavailable. (#55)

### Memo → Task

- Suggestions are generated on demand each time the user taps **Memo → Task** on an open memo, from its current text or transcript. Nothing is precomputed or stored. While the model works, the sheet shows "Finding suggested tasks…". (#57)
- Works for written and voice memos alike. (#57)
- Up to 5 Suggested tasks, all ticked to start with, each editable. "Add to Today (n)" creates the ticked ones as tasks on **Today**, even from a memo in memo history. (#57)
- If Apple Intelligence is unavailable (unsupported device, region or language, or turned off), or the model finds nothing, the same sheet opens with "No suggestions", one blank task row, and **Add another**. Memo → Task is never hidden. (#57)
- A task created from a memo is a plain task with no reference to the memo, so the Task model and its Watch sync are unchanged. (#57)
- While the sheet is open, added suggestions show "Added" and can't be added again. Reopening Memo → Task suggests from scratch, with no memory of earlier additions. (#57)

### The Memos sheet: memo history and search

- **See all** opens the Memos sheet, the only way into memo history in this effort. (#58)
- A **Today** group sits at the top, then memo history grouped by day, newest first. Day headers read "Today", "Yesterday", then "Mon, Sep 28"; dates from an earlier year show the year. iOS 27's `Query(sectionBy:)` fits this grouping. (#58, #54)
- Rows are identical to Today's rows. (#58)
- A search field at the top matches titles, written memo text, and transcripts, ignoring case and accents and matching part of a word (`#Predicate` with `localizedStandardContains`). Results are the same day-grouped list, filtered. When a match is deep in the text or transcript, the detail line shows a snippet around it with the matched words highlighted. With no results: "No memos match "<query>"". (#58, #54)
- A past memo has the same actions as one from Today: open the same card sheet, edit text or transcript, rename, add or remove photos, Share, Memo → Task (tasks land on Today), and delete (voice memos confirm first). (#58)

### Quick capture

- Two actions: **Record memo** (voice) and **Write memo** (written). Each is surfaced as a Control Center / Lock Screen control, which can also be assigned to the Action button, and as a Siri/Shortcuts App Shortcut, which also shows in Spotlight and the Shortcuts app. (#61)
- Siri phrases: "Record a memo in Kyo" and "New voice memo in Kyo" for voice; "Write a memo in Kyo" and "New memo in Kyo" for written. Phrases use `\(.applicationName)`. (#61, #53)
- **Record memo** brings Kyo to the front, opens the full-screen recorder, and starts recording immediately, with a haptic and the red timer running. An accidental press is dealt with by Discard. **Write memo** opens the compose sheet. On a locked phone, iOS asks the user to unlock before Kyo opens. (#61)
- If a recording is in progress, or a written memo is open with unsaved text, quick capture starts nothing new: Kyo comes to the front showing the capture already open, and nothing is lost or interrupted. (#61)
- On the Watch, a complication and the Watch's own "Record memo" control (voice only) open Kyo on the Watch and start recording immediately, even when the phone is out of reach. iPhone controls that open the iPhone app don't appear on the Watch, so the Watch needs its own widget extension. (#61, #53)
- Intents declare `supportedModes = .foreground(.immediate)`, never the deprecated `openAppWhenRun`, so the app is in the foreground before `perform()` runs and can start recording. (#53, #61)
- New targets: `KyoWidgets` (iOS widget extension with the controls) and `KyoWatchWidgets` (watchOS widget extension with the Watch control and accessory complications). The `AppShortcutsProvider` lives in the app target. Intents are compiled into both the app and the extension; iOS 27's `allowedExecutionTargets = .main` can pin them to the app. (#53)
- Left to implementation (#61): the intent shape (one start-recording intent per action, or an open intent with a screen target); routing (a shared `@MainActor` router called from `perform()`, which also works on watchOS, versus `TargetContentProvidingIntent`, which is iOS-only); and whether complications need a registered `kyo://` URL scheme for `widgetURL`.

### Permissions and recording interruptions

- `Kyo` and `KyoWatch` both need `NSMicrophoneUsageDescription`; `Kyo` needs the camera usage string. (#53, #66)
- On first use, the microphone prompt appears inside Kyo (including when started from quick capture), and recording starts once access is allowed. (#61)
- If microphone access is denied on the phone, the recorder shows "Kyo needs microphone access to record" with **Open Settings**, and nothing is saved. (#61)
- A call, Siri, or another app taking the audio pauses recording. When the interruption ends, the recorder shows "Paused" with **Resume** and **Stop**; the elapsed time and the 10-minute cap carry on from where they were. (#66)
- Leaving Kyo or locking the screen doesn't stop recording; it continues in the background with the system recording indicator. This needs the audio background mode. (#66)
- If Kyo quits or crashes mid-recording, whatever was recorded up to that point is saved as a voice memo and transcribed. (#66)

### Apple Watch

- The Memos section lists all of today's memos, newest first. Each row shows an icon for its kind, the title, and a detail line of time · duration · photo count ("9:41 AM · 0:42 · 2 photos"), or "Transcribing…" / "No transcript" when that applies. (#60)
- Rows aren't tappable: there's no detail view, playback, or editing on the Watch, and no deleting. (#51, #60)
- A **Record** button sits at the top of the Memos section. It opens a full-screen recorder with the elapsed time, a simple level meter, **Stop** (saves), and **Discard** (saves nothing). There's no live transcript. The 10-minute cap matches the phone: a warning in the last 30 seconds, then an automatic stop and save. (#60)
- Haptics: "start" when recording starts, "success" when it stops and saves, and "notification" for the cap warning. (#60)
- Recordings not yet confirmed by the phone show straight away as "Voice memo · Waiting for iPhone". A waiting recording can't be deleted on the Watch; it's deleted on the phone after it arrives. (#59, #60)
- With no memos today: "No memos today" plus the Record button. If no memo snapshot has ever arrived, recording still works; the list shows only waiting recordings plus the same "Open Kyo on iPhone" hint tasks and habits use. (#60)
- If microphone access is denied, the recorder shows "Kyo needs microphone access. Turn it on in Settings on Apple Watch." and saves nothing. If the Watch is out of space, recording fails with "Not enough space on Apple Watch". (#59, #60)

### Watch sync

See `docs/adr/0005-watch-memo-sync.md`. (#59)

- The phone stays the only writer of memos, as in ADR 0001–0003.
- **Phone → Watch.** A memo snapshot under its own context key and revision, written in the same `updateApplicationContext` call as the task and habit keys (ADR 0003). For each of today's memos it carries id, day, creation time, kind, title, voice state, duration, and photo count. No text, transcript, audio, or photos. The Watch shows only memos whose day is its own Today, so the list empties at midnight without the phone.
- **Watch → phone.** The Watch records to a file it owns, named by a new memo id, and writes an outbox entry (memo id, start time, Watch calendar day, duration) before sending. It calls `transferFile(_:metadata:)` with that entry as metadata once the session is activated.
- The phone moves the file synchronously inside `session(_:didReceive:)`, before any hop to the main actor, because the system deletes it when the method returns. The existing handlers hop to the main actor first, so files need their own handler. The phone then creates the memo as Transcribing on the Watch's day and transcribes it.
- The phone confirms by listing the memo id in the snapshot's `acknowledgedMemoIDs`, mirroring `acknowledgedCommandIDs`. The Watch deletes its file and outbox entry only on that confirmation, never on `didFinish`. On a failed transfer, and on launch, it resends any entry not already in `outstandingFileTransfers`. Once confirmed, the phone's version of the memo replaces the waiting row.
- The phone keeps a bounded, persisted set of Watch memo ids it has received, like its processed command ids. A repeat delivery is ignored but still confirmed, so a retry can't duplicate a memo or bring back one the user deleted. This is a Watch-link record and, per #64, stays out of SwiftData.
- There's no cap on waiting recordings. Accepted limitation: iOS isn't documented to wake the phone app for a file, so a recording may wait until Kyo next runs on the phone.

### Platform and project

- Preserve accessible names and states: each row's label includes its kind, title, time, and duration or transcript state; recorder controls and the player are labelled.
- Keep lasting target and build configuration changes (the two widget extensions, usage strings, the audio background mode) in `project.yml` and regenerate the checked-in project when needed.

## Testing Decisions

- Use one primary behavior-testing boundary on the phone: the memo store interface the views consume, backed by an in-memory SwiftData store as the SwiftData spec sets up. Assert observable memos, titles, states, ordering, groups, search results, and created tasks, not storage layout or view structure.
- Control the current day, clock, and calendar to cover: a memo's day, including a recording that crosses midnight, a time-zone change, and a Watch recording's day; Today versus memo history; newest-first order; the section subtitle; See all visibility; first-line titles, photo-only memos, discarding empty memos, and the 4-photo limit; voice states through Transcribing, Transcribed, and No transcript, with automatic and manual retry; the AI title generated once, renaming, and no regeneration on transcript edits; the cap auto-save and its note; deletion removing audio and photos while created tasks remain; and share contents, including the no-transcript cases.
- Put transcription behind a **transcriber seam** (live and file) with a fake that returns scripted partial and final results, fails, or reports unavailable or a missing asset. `SpeechTranscriber` doesn't run in the Simulator, so no test depends on it.
- Put Apple Intelligence behind a **language-model seam** with a fake that reports each availability state and returns scripted titles and suggestions, errors, or nothing. Cover the fallback title, the manual Memo → Task sheet, the 5-suggestion limit, "Added" de-duplication within one open sheet, a fresh start on reopening, tasks landing on Today from memo history, and a long transcript whose input is cut from the start (assert what text the fake received).
- Test the recorder's state with a controlled clock and a fake audio source: elapsed time, the warning in the last 30 seconds, auto-stop at 10:00, Discard saving nothing, pause on interruption with Resume and Stop, the cap carrying over a pause, and saving a partial recording found after a crash.
- Test search through the store: titles, written text, and transcripts; case, accents, and partial words; photos not matched; the snippet and highlight ranges; and the no-results state.
- Verify persistence by saving memos with media and reopening the store against the same test storage.
- Exercise a phone memo store and a Watch memo list connected by a **controllable WatchConnectivity file-transfer seam**, alongside the existing `ControllableTaskTransport` and `ControllableHabitTransport`. The seam should delete a received file once the handler returns, as the system does. Cover: the outbox written before sending; deletion only on `acknowledgedMemoIDs`, not on `didFinish`; resending after a failure and on launch without duplicating an outstanding transfer; duplicate and late delivery; a recording delivered after the user deleted it; the Watch's day used for the memo; waiting rows; the never-synced state; Watch rollover past midnight with no new snapshot; and the shared context write keeping task and habit snapshots intact. Don't mock the memo behavior under test.
- Complement these with focused platform interaction checks: the + menu entries, compose sheet, recorder, open-memo card, swipe and long-press delete with the voice confirmation, See all and search, the Memo → Task sheet, quick-capture routing including bringing an open capture forward, and the Watch Record button.
- Build both app schemes and both widget extensions.
- Device testing is required for: transcription (live and file, asset download, offline use after download, the `DictationTranscriber` fallback, iPhone and iPad); Foundation Models on an Apple Intelligence device and on one without it; microphone and camera prompts; background recording, call and Siri interruptions, and crash recovery; Watch file transfer on a paired iPhone and Watch (it doesn't work in the Simulator), extending `WatchSyncSmokeUITests` where possible; the controls, Action button, Siri phrases, and Watch complication and control, including whether a foreground Watch control opens the Watch app and whether `widgetURL` needs a registered scheme; and Watch haptics.

## Open questions

These are undecided or contradictory between the sources and need a decision before or during implementation.

1. **Fallback titles in memo history.** #56 says the time-stamped form ("Voice memo · 9:41 AM") is used "in memo history", but #58 says memo history rows are identical to Today's rows, which show the time column and so would use the bare form. Which applies? The same question applies to the title the memo snapshot sends to the Watch, whose rows show the time in the detail line.
2. **Emptying a written memo that has photos.** #56 says emptying a written memo and closing it discards the memo; #55 allows photo-only memos and discards only a memo with no text and no photos. The spec assumes a memo is discarded only when it has neither. Confirm.
3. **AI title timing edge cases.** If the user renames a voice memo while it's still Transcribing, does the generated title still replace it? If the model is `.modelNotReady` when the transcript is finalized, is the title generated later, or does the memo keep the fallback for good ("generated once")?
4. **Memo → Task with no text.** What does Memo → Task do on a voice memo that is Transcribing or has No transcript, or on a photo-only memo? The prototype showed "Suggestions need some text to read"; no ticket decides it.
5. **Share edge cases.** Is Share unavailable while a voice memo is Transcribing (like No transcript)? Does sharing a photo-only memo include the "Photo memo · 9:41 AM" title as text, or only the photos?
6. **Live transcript unavailable.** What does the phone recorder show when live transcription can't run (first use of a locale offline, asset downloading, unsupported locale)? Is download progress shown anywhere?
7. **Empty transcript.** Is a recording that produced no words Transcribed with an empty transcript, or No transcript?
8. **Transcription locale.** Is the transcript always in the device locale (`supportedLocale(equivalentTo: Locale.current)`), or is there any per-memo language choice?
9. **Today's empty state.** The subtitle reads "Notes & voice" when empty, but the row text isn't decided, including when older memos exist (the prototype used "No memos yet" / "Tap + to add one").
10. **The cap note.** Is "Recording stopped at 10 minutes" stored on the memo and shown whenever it's opened (as in the prototype), or shown only when the recording stops?
11. **Quick capture with other sheets open.** What happens when Record memo or Write memo fires while an existing memo's card, the Memos sheet, or audio playback is open? #61 decides only the case of an in-progress capture.
12. **Watch recording interruptions.** #66 covers the phone only. Does a Watch recording continue when the wrist drops or the app leaves the foreground, pause for a call, or survive a Watch app crash?
13. **Watch never-synced hint wording.** #60 says "the same 'Open Kyo on iPhone' hint tasks and habits use"; habits use "Open Kyo on iPhone to sync habits". The memo wording isn't set.
14. **Watch Siri phrase.** The research notes the Watch app could offer its own App Shortcut; #61 lists only the complication and the Watch control. Confirm there's no Watch Siri phrase.
15. **Data protection.** The research didn't cover whether the store and media are readable while the phone is locked, which matters for background recording and for receiving Watch files.

## Out of Scope

- AI summaries of voice memos.
- Pinning a memo so it stays on Today past its day.
- Scheduling tasks for a future day. Memo → Task always creates the task on Today; dated tasks would be a separate Tasks effort.
- iCloud sync between iPhone and iPad (**planned as a future effort**), sharing audio and exporting memos, playback or editing on the Watch, and the Meals section.
- Background recording through a Live Activity without opening Kyo.
- Implementation. This map produces the two specs only.
- Indexing memo content in system Spotlight (decided in #63).
- Filter chips in the Memos sheet, and reaching past memos through the Calendar tab or any past-day view (decided in #58).

## Further Notes

- Decisions trace to the Wayfinder map "Wayfinder: Memos" (#51) and its tickets #52–#61, #63, #64, and #66, and to ADR 0004 (`docs/adr/0004-swiftdata-cloudkit-ready-storage.md`) and ADR 0005 (`docs/adr/0005-watch-memo-sync.md`).
- API names and constraints come from the research on branches `research/memo-transcription-and-ai`, `research/memo-quick-capture`, and `research/memo-storage-and-watch-transfer`. The capture UI the user picked (variant A capture with B's photo button while recording, variant C open-memo card, shared rows) is preserved on branch `prototype/memo-capture`.
- Build order: the SwiftData storage spec (#65, `docs/specs/swiftdata-storage.md`) is implemented and merged first. Memos build on that store.
- Execution policy for future implementation: **Opus 5.5** (`claude-opus-5-5`) runs orchestration and owns review; the coder assignment is **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`), through the `coder` agent, per `AGENTS.md`.
- No implementation agents should be launched by this spec-writing request. The `ready-for-agent` label describes specification readiness; it doesn't authorize implementation.
