# On-device transcription and Apple Intelligence for memos

Research for [#52](https://github.com/xchrisbailey/kyo/issues/52), part of the memos map ([#51](https://github.com/xchrisbailey/kyo/issues/51)). Gathered 2026-10-01 against the iOS 27 / watchOS 27 SDK documentation.

## Question

What do iOS 27 and watchOS 27 offer for on-device speech-to-text and Apple Intelligence text generation, and what are their limits? Kyo plans to record voice memos with a live on-device transcript, generate a short title from the transcript, and suggest action items to turn into tasks. The Watch records audio and the phone transcribes it.

## Answer in brief

- **Transcription.** On iPhone and iPad, `SpeechAnalyzer` with the `SpeechTranscriber` module transcribes both live audio and files entirely on device. The language model is a system asset downloaded through `AssetInventory`. It needs a network connection once per locale, then works offline. Some locales and older hardware aren't supported, so `DictationTranscriber` (same API, older on-device dictation model) is the fallback. **The Speech framework is not available on watchOS at all**, so the Watch can only capture audio and hand the file to the phone.
- **Title and action items.** On Apple Intelligence devices in supported regions and languages, with Apple Intelligence turned on, the Foundation Models framework's on-device `SystemLanguageModel` handles this. Guided generation (`@Generable`) can return a typed `{ title, actionItems: [String] }` in one call. The on-device context window is 4,096 tokens per session, and that budget covers instructions, the schema, the transcript, and the output, so long memos need chunking. On every other device, the memo has to work without AI: a date or first-line title, and no suggestions.
- **Watch AI.** In watchOS 27 the Foundation Models framework comes to watchOS, but only for `PrivateCloudComputeLanguageModel`, the server model. `SystemLanguageModel` is not available on watchOS. PCC also needs a managed entitlement. That supports the plan to do memo AI on the phone.

## SpeechAnalyzer / SpeechTranscriber

### Platforms

- `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`: iOS 26.0+, iPadOS 26.0+, Mac Catalyst, macOS 26.0+, tvOS 26.0+, visionOS 26.0+. **watchOS is not listed.** ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber))
- The Speech framework as a whole lists iOS, iPadOS, Mac Catalyst, macOS, and visionOS. It has no watchOS entry, and `SFSpeechRecognizer` isn't available there either. ([Speech](https://developer.apple.com/documentation/speech))
- WWDC25 states it directly: SpeechTranscriber "is available for all platforms but watchOS with certain hardware requirements." ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/))
- `DictationTranscriber` lists iOS, iPadOS, Mac Catalyst, macOS, and visionOS 26.0+. It has no tvOS or watchOS entry. ([DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber))
- New in iOS 27 (June 2026): `CaptureInputSequenceProvider` reads from a capture device such as the microphone, `AssetInputSequenceProvider` reads from an audio file or asset, and `AnalyzerInputConverter` converts `AVAudioBuffer`s. Each produces analyzer input in the right format. ([Speech updates](https://developer.apple.com/documentation/updates/speech), [CaptureInputSequenceProvider](https://developer.apple.com/documentation/speech/captureinputsequenceprovider), [AssetInputSequenceProvider](https://developer.apple.com/documentation/speech/assetinputsequenceprovider))

### Device support and iPad

- `SpeechTranscriber.isAvailable` is "A Boolean value that indicates whether this module is available given the device's hardware and capabilities." `supportedLocales` "is empty if the device does not support the transcriber." Apple's guidance: "If it does not, consider disabling the feature or using `DictationTranscriber` instead." ([SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [supportedLocales](https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocales))
- iPadOS is a supported platform. Apple doesn't publish the exact hardware floor ("certain hardware requirements"), so Kyo has to check `isAvailable` at run time on both iPhone and iPad rather than assume support.
- `DictationTranscriber` "supports the same languages, speech-to-text model, and devices as iOS 10's on-device SFSpeechRecognizer". Unlike `SFSpeechRecognizer`, it doesn't require users to turn on Siri or keyboard dictation. ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)) It "does not support languages or locales that `SFSpeechRecognizer` only supports via network access". ([DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber))
- Simulator: developers on the Apple Developer Forums report that `SpeechTranscriber.isAvailable` is `false` and `supportedLocales` is empty in the Simulator. This is a community report with no Apple reply, so treat it as likely but unconfirmed. Plan to test transcription on a device. ([forum thread 802969](https://developer.apple.com/forums/thread/802969))

### Languages and locales

- Apple's documentation doesn't list the supported languages. The authoritative source is `SpeechTranscriber.supportedLocales` (supported and downloadable) and `installedLocales` (already on the device). Use `supportedLocale(equivalentTo: Locale.current)` to map the user's locale to a supported one. It returns `nil` when no equivalent exists. ([SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [SpeechAnalyzer example](https://developer.apple.com/documentation/speech/speechanalyzer))
- WWDC25 shows the language list only on a slide ("these languages, with more to come"). The list grows with OS releases, so Kyo shouldn't hard-code it.

### Model assets (download) and offline behavior

- "Before using the `SpeechAnalyzer` class, you must install assets required by the modules you plan to use. These assets are machine-learning models downloaded from Apple's servers and managed by the system. Once you download, install, or use an asset, the system retains and updates it automatically, and shares it with other apps." ([AssetInventory](https://developer.apple.com/documentation/speech/assetinventory))
- The flow: build the module, then call `AssetInventory.assetInstallationRequest(supporting: [transcriber])`. That returns `nil` if nothing is needed, otherwise a request whose `downloadAndInstall()` you await. The download "may finish immediately" if the assets are preinstalled or another app already fetched them. The system consolidates repeated requests. ([AssetInventory](https://developer.apple.com/documentation/speech/assetinventory), [AssetInstallationRequest](https://developer.apple.com/documentation/speech/assetinstallationrequest))
- Locale reservations: an app gets a limited number of locale reservations. `maximumReservedLocales` "may vary between devices according to storage space". `reserve(locale:)` happens automatically, and `release(reservedLocale:)` frees one. "The system may unsubscribe your app from assets that haven't been used in a while." ([AssetInventory](https://developer.apple.com/documentation/speech/assetinventory), [maximumReservedLocales](https://developer.apple.com/documentation/speech/assetinventory/maximumreservedlocales)) WWDC25 called these `allocatedLocales` / `deallocate(locale:)`. The current docs use `reservedLocales` / `release(reservedLocale:)`.
- Offline: "transcription is entirely on device but the models need to be fetched." The model "does not increase the download or storage size of your application, nor does it increase the run-time memory size. It operates outside of your application's memory space". ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)) The first memo in a new locale therefore needs a network connection. After that, recording and transcription work offline. If the system later drops an unused asset, it has to be downloaded again.

### Live and file transcription

- Live: feed an `AsyncStream<AnalyzerInput>`. In iOS 27, `CaptureInputSequenceProvider.analyzerInputs` can supply it from the mic, or you can convert buffers yourself with `AnalyzerInputConverter`. Then pass the stream to `analyzeSequence(_:)` or `start(inputSequence:)`. ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer))
- File: `analyzeSequence(from:)`, `start(inputAudioFile:finishAfterFile:)`, or `AssetInputSequenceProvider`. This is the path for audio recorded on the Watch and transferred to the phone. ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer))
- Results arrive as an `AsyncSequence` (`transcriber.results`). `result.text` is an `AttributedString`. ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer))
- Live UI: the `progressiveTranscription` preset turns on `volatileResults` and `fastResults`. Volatile results are "delivered almost as soon as they're spoken but they are less accurate guesses", and they're replaced until a final result arrives (`result.isFinal`). `timeIndexedProgressiveTranscription` adds the `audioTimeRange` attribute (a `CMTimeRange` per run), which is useful for tapping a word to seek in playback. ([SpeechTranscriber.Preset](https://developer.apple.com/documentation/speech/speechtranscriber/preset), [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)) `fastResults` "Biases the transcriber towards responsiveness, yielding faster but also less accurate results." ([ReportingOption](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption))
- Finishing: you must call a finish method (`finalizeAndFinish(through:)`, `finalizeAndFinishThroughEndOfInput()`, `cancelAndFinishNow()`) or deallocate the analyzer. Otherwise the result streams don't terminate. An error from any module ends the whole session. ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer))
- Startup latency: `prepareToAnalyze(in:)` preloads resources. `SpeechAnalyzer.Options.ModelRetention` keeps the model loaded between analyzers. ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer))
- Concurrency: the system limits simultaneous analyses and throws `insufficientResources` when the limit is exceeded. One analyzer analyzes one input sequence at a time. ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)) Kyo should transcribe one memo at a time, for example by queuing Watch uploads.
- Accuracy: `AnalysisContext.contextualStrings` biases recognition toward given words. ([AnalysisContext](https://developer.apple.com/documentation/speech/analysiscontext)) The WWDC25 model is described as "good for long-form and distant audio, such as lectures, meetings, and conversations."
- Permissions: the WWDC25 sample requests only microphone permission before recording. Neither the session nor the docs I read mention `SFSpeechRecognizer.requestAuthorization` for SpeechAnalyzer. This is **unverified**. Confirm on device which Info.plist usage strings are required.

## Foundation Models (Apple Intelligence)

### Platforms and model availability

- The Foundation Models framework covers iOS, iPadOS, Mac Catalyst, macOS, and visionOS 26.0+, plus **watchOS 27.0+** (new). ([Foundation Models](https://developer.apple.com/documentation/foundationmodels))
- `SystemLanguageModel` (on-device) covers iOS, iPadOS, Mac Catalyst, macOS, and visionOS. **It is not available on watchOS.** ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel))
- `PrivateCloudComputeLanguageModel` (server, new in 27) covers iOS, iPadOS, Mac Catalyst, macOS, visionOS, and **watchOS 27.0+**. "To develop with PCC you must meet certain eligibility requirements" and request a managed entitlement. It doesn't work offline, carries a per-day usage limit (iCloud+ upgrades raise it), and has a 32K context window versus 4K on device. ([PrivateCloudComputeLanguageModel](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel), [Adding server-side intelligence with PCC](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute))

### Device and region eligibility

- "Model availability depends on whether the device and region supports Apple Intelligence." ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel))
- Apple Intelligence devices: iPhone 16 models or later, iPhone 15 Pro and Pro Max, iPhone Air, iPad mini (A17 Pro), iPads with M1 or later. Apple Watch Series 9 or later, Ultra 2 or later, and SE 3 qualify only when paired with an eligible iPhone. Storage: up to 8 GB on most devices, up to 14 GB on some. ([Apple Support: How to get Apple Intelligence](https://support.apple.com/en-us/121115))
- Languages: English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, Chinese (Simplified and Traditional), Japanese, and Korean. Apple Intelligence doesn't currently work on devices bought in mainland China. Changing the Siri language can make Apple Intelligence unavailable until the matching assets download. ([Apple Support](https://support.apple.com/en-us/121115))
- Check at run time with `SystemLanguageModel.default.availability`. Its `.unavailable` reasons are `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, and `.modelNotReady` (downloading or other system reasons). "It can take some time for the model to download and become available when a person turns on Apple Intelligence." ([UnavailableReason](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason), [Generating content…](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models))
- Language check: `SystemLanguageModel.default.supportsLocale()` (defaults to the current locale, including the per-app language setting). At request time, an unsupported language throws `LanguageModelError.unsupportedLanguageOrLocale`. ([Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models))
- The model changes with OS updates. There are three versions so far: 26.0–26.3, 26.4, and 27.0. Apple advises re-testing prompts against each new model. ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels))

### Context size

- "Apple's on-device foundation model has a context window of 4096 tokens per session". The window covers "all prompts, instructions, tool definitions and their input and output, generable type schemas, and all of the model's responses." In English a token is about 3–4 characters. In Chinese, Japanese, and Korean it's about one character. ([Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window))
- `contextSize` and `tokenCount(for:)` (since 26.4, back-deployed) measure the budget before a request. Exceeding it throws `LanguageModelError.contextSizeExceeded`. ([contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize))
- What this means for memos: at roughly 150 spoken words per minute (an outside estimate, not Apple's), 4,096 tokens holds only about 15–20 minutes of English speech before instructions and output, and far less in CJK. Use a fresh session per memo. For long transcripts, Apple's guidance is to split into chunks, process each chunk in its own session, and combine the results. ([Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window))

### Guided generation for a title and action items

- `@Generable` structs with `@Guide` constraints give typed output, and "the framework provides strong guarantees that the model generates instances of your type." Arrays can be capped with `@Guide(.maximumCount(n))`. Every guide description and property name is part of the schema and costs tokens, so keep them short. ([Foundation Models](https://developer.apple.com/documentation/foundationmodels), [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window))
- A shape that fits within these rules (illustrative, not tested):

  ```swift
  @Generable
  struct MemoSummary {
      @Guide(description: "A title of at most six words")
      var title: String
      @Guide(.maximumCount(5))
      var actionItems: [String]
  }
  ```

- Summarizing and extracting entities are listed capabilities. Math, code, and multi-step logical reasoning are listed as things to avoid. ([Generating content…](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models))
- Guardrails can throw `LanguageModelError.guardrailViolation` on sensitive transcript content. Other errors are `refusal`, `rateLimited`, and `timeout`. ([LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror))

### Latency

- Apple gives no numbers. "It may take a few seconds for the on-device foundation model to generate the response." Shorter requested output ("in a few words") cuts generation time. ([Generating content…](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models))
- `prewarm(promptPrefix:)` loads the model early. Use it only when there's at least 1 second before the request. A good moment for Kyo is when recording stops. ([prewarm](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)))
- `streamResponse` streams partially generated `@Generable` content, so the title can appear first. In the background, use non-streaming `respond` to reduce `rateLimited` errors. ([streamResponse](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/streamresponse(to:generating:includeschemainprompt:options:)))
- A session handles one request at a time. Calling it again mid-request is a runtime error. ([Generating content…](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models))
- The Foundation Models instrument in Xcode reports per-request latency and token usage. ([Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels))

## Fallbacks each capability needs

| Capability | When unavailable | Fallback |
| --- | --- | --- |
| Live transcript (`SpeechTranscriber`) | `isAvailable == false` (hardware), or no `supportedLocale(equivalentTo:)` | Use `DictationTranscriber` for that device or locale. If that has no locale either, save the audio-only memo and offer transcription later. |
| Transcription assets | First use of a locale while offline, or download failed or pending | Record the audio anyway. Transcribe from the file (`analyzeSequence(from:)`) once assets install. Show download progress. |
| Transcription on Apple Watch | The Speech framework doesn't exist on watchOS | Record on the Watch, transfer the file, and transcribe on the phone. Show "transcribing on iPhone" until the transcript syncs back. |
| Simulator | The transcriber reportedly isn't available | Test on a device, and put the transcriber behind a protocol so tests can use a fake. |
| Title (`SystemLanguageModel`) | `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`, unsupported locale, guardrail or other error | Use a deterministic title (date/time, or the first words of the transcript) that the user can edit. Retry generation later for `.modelNotReady`. |
| Action-item suggestions | Same as the title, plus a transcript too long for 4K tokens | Hide suggestions; the memo is still useful. Chunk long transcripts across sessions, or suggest from the first chunk only. |
| AI on the Watch | `SystemLanguageModel` isn't on watchOS; PCC needs an entitlement and a network connection | Generate on the phone and sync the title and suggestions to the Watch. |

## Open points for later decisions

- Whether Kyo uses `DictationTranscriber` as a fallback, or only shows transcripts on `SpeechTranscriber` devices.
- What to do with a memo whose language Apple Intelligence doesn't support, though `SpeechTranscriber` does: transcript but no title or suggestions.
- Required Info.plist usage strings and permissions for SpeechAnalyzer: verify on device.
- Long memos: cap memo length, chunk, or summarize the first N minutes only.
- PCC is an option on both phone and Watch, but it adds an entitlement application, network dependence, and user quotas. It doesn't seem worth it for a title and a short list.
