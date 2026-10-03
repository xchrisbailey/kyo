# Memo storage and Watch audio transfer

Research for [#54](https://github.com/xchrisbailey/kyo/issues/54), part of the Memos map
([#51](https://github.com/xchrisbailey/kyo/issues/51)). Researched 2026-10-01 against Apple's
developer documentation and WWDC sessions. Targets: iOS 27, watchOS 27.

This note lays out facts and trade-offs. It doesn't make the decision; that belongs in the
Memos spec or an ADR.

## The question

Tasks and habits live in UserDefaults and reach the Watch as application-context snapshots
(ADR 0001–0003). Memos are different: they carry audio and up to 4 photos each, they grow
without limit, memo history must be searchable over titles, text, and transcripts, and iCloud
sync is planned for later. Two parts:

1. What storage fits memos?
2. How does a voice memo recorded on the Watch reliably reach the phone?

## Short answer

- **UserDefaults is out.** Apple positions it for settings, says not to store personal
  information in it, and stores it unencrypted.
- **Two realistic options:** (A) SwiftData with photo and audio bytes in
  `@Attribute(.externalStorage)` properties, or (B) SwiftData (or another index) for the
  metadata and text, with photos and audio as plain files the app manages.
- **The later iCloud move is what separates them.** SwiftData's built-in iCloud sync runs on
  `NSPersistentCloudKitContainer`, and it moves large binary attributes into `CKAsset`s on
  its own. Option A gets media sync with no extra work. Option B would need its own file sync
  (for example `CKSyncEngine` with `CKAsset`s) next to the database sync.
- **Whichever option is chosen, design for CloudKit from day one.** No unique constraints,
  every relationship optional, inverses set, and no `.deny` delete rule. CloudKit schemas only
  grow once promoted to production.
- **Watch → phone:** `WCSession.transferFile(_:metadata:)` queues the file and delivers it in
  the background whether or not the phone is reachable. The receiver must move the file
  synchronously inside `session(_:didReceive:)`, or the system deletes it. Apple doesn't
  document any size limit, retry policy, or whether queued transfers survive the Watch app
  being terminated. Kyo should keep the Watch's copy until the phone acknowledges the memo,
  following the outbox pattern from ADR 0002.

## Part 1: Storage

### What rules out UserDefaults

- Apple describes UserDefaults as "a persistent store for app-specific and system-wide
  settings", for "nonsensitive information, such as app-specific configuration details"
  ([UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)).
- "Don't store personal or sensitive information as settings. The defaults system stores
  information on disk in an unencrypted format" (same page). Memos are personal by nature.
- UserDefaults "updates its in-memory version of that information right away, and writes the
  value to disk asynchronously" (same page). Kyo's stores hold whole lists as encoded `Data`
  values. An unbounded memo history with media bytes would mean re-encoding and holding all of
  it in memory.
- It isn't a sync mechanism: "you don't use the defaults system to share data between devices"
  (same page).

### Option A: SwiftData with external-storage attributes

What Apple documents:

- `@Attribute(.externalStorage)` "stores the property's value as binary data adjacent to the
  model storage"
  ([externalStorage](https://developer.apple.com/documentation/swiftdata/schema/attribute/option/externalstorage)).
  Core Data's equivalent says the value "may be stored in a file external to the persistent
  store itself"
  ([allowsExternalBinaryDataStorage](https://developer.apple.com/documentation/coredata/nsattributedescription/allowsexternalbinarydatastorage)).
  The wording is "may": the framework decides per value.
- SwiftData's iCloud sync "uses the NSPersistentCloudKitContainer class from Core Data"
  ([Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)).
- In that mapping, String, Binary Data, and Transformable attributes each get a companion
  `CD_<name>_ckAsset` field. "If a field's value grows too large to store within the record
  size limit of 1MB, Core Data automatically converts the value to an external asset"
  ([Reading CloudKit Records for Core Data](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data)).
  Photos and audio stored as `Data` would therefore sync as `CKAsset`s with no extra code.
- Search over text uses ordinary predicates. `#Predicate` supports
  `localizedStandardContains`
  ([StringLocalizedStandardContains](https://developer.apple.com/documentation/foundation/predicateexpressions/stringlocalizedstandardcontains)),
  and `#Index` (iOS 18+) adds binary indices on chosen key paths, such as the memo's day or
  creation time ([Index(_:)](https://developer.apple.com/documentation/swiftdata/index(_:)-74ia2)).
- `.spotlight` "indexes the property's value so it can appear in Spotlight search results"
  ([spotlight](https://developer.apple.com/documentation/swiftdata/schema/attribute/option/spotlight)).
  That's system search, not in-app search. It may matter later, but it isn't what memo history
  needs.
- New in the 2027 releases (iOS 27), per WWDC26 "What's new in SwiftData"
  ([session 274](https://developer.apple.com/videos/play/wwdc2026/274/)):
  - `Query(sectionBy:)` groups fetch results into sections by a key path, for example memo
    history grouped by day.
  - `ResultsObserver` observes fetch results outside SwiftUI.
  - `HistoryObserver` reports new persistent-history transactions, which the session suggests
    "when your app needs to keep parts of the data store in sync with other systems". That
    could feed a Watch snapshot publisher.
  - A `.codable` attribute option exists, but its contents "can't be used in Predicates to
    filter results or for sorting". Searchable fields must stay plain attributes.

Trade-offs (my reading, not Apple's wording):

- An externally stored `Data` property still comes back as `Data`. Playback, such as
  `AVAudioPlayer(contentsOf:)`, and image decoding want a URL or a stream, so the app would
  write audio to a temporary file before playing it. Ten minutes of audio is a few MB (see
  Part 2), so the cost is small. Apple doesn't document a way to get the URL of the external
  file.
- Putting media on a separate model (for example, a memo with optional to-many relationships
  to photo and audio models) keeps list and search fetches from touching media bytes. CloudKit
  requires those relationships to be optional anyway (see below).
- Fewer moving parts: one store, one migration story, and deleting a memo removes its media
  through a cascade rule. No orphaned-file cleanup is needed.

### Option B: SwiftData (or another index) plus files on disk

The record holds text, transcript, title, day, and file names. Photos and audio are files in
the app container (or an App Group container, if an extension ever needs them).

- Search works the same as in A, because the text fields still live in the index.
- Playback and display read straight from file URLs, and media is never loaded into memory
  through the persistence layer.
- The app owns consistency. It has to write the file and the record in the right order, clean
  up orphans after a crash between the two, and delete files when a memo is deleted.
- **The iCloud cost.** `NSPersistentCloudKitContainer` syncs store attributes, not arbitrary
  files. Syncing the files later means building a second sync path. Apple's tool for that is
  `CKSyncEngine` (iOS 17+, watchOS 10+), with each file as a `CKAsset` on a record
  ([CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5),
  [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)). The engine handles
  scheduling and transient errors, but the app must persist the engine's state, supply record
  batches (at most 250 records per request), and handle conflicts such as
  `serverRecordChanged` itself. CloudKit puts fetched assets in a staging area that "the
  system regularly deletes", so the app must move them into its container
  ([CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)).
- A middle path: keep the whole memo model in a store you sync yourself with `CKSyncEngine`.
  That gives full control over records and assets but means writing all of the sync, not just
  the file part.

### CloudKit constraints that apply now, whichever option is chosen

From [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
and [Creating a Core Data Model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit):

- **No unique constraints.** CloudKit "is unable to enforce the unique property option". This
  covers `@Attribute(.unique)` and `#Unique`. Deduplication, such as of a Watch memo that
  arrives twice, has to happen in app code: fetch by id before inserting.
- **All relationships optional**, with inverses set, because records may sync out of order.
- **No `.deny` delete rule.**
- **The schema only grows.** After promotion to production, "you can't modify or delete
  existing record types". Plan field names and types carefully. Apple suggests a `version`
  attribute from the outset as one forward-compatibility strategy.
- `ModelConfiguration`'s `cloudKitDatabase` parameter defaults to `.automatic`, which picks
  the first CloudKit container in the entitlements
  ([init](https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:isstoredinmemoryonly:allowssave:groupcontainer:cloudkitdatabase:))).
  Until sync is wanted, passing `.none` explicitly keeps an unrelated iCloud entitlement from
  turning sync on by accident.
- Sync also needs the iCloud (CloudKit) capability and Background Modes → Remote
  notifications. That's for the later effort only.

### What the Watch stores

The Watch shows today's memo titles and records voice memos. It has no history, playback, or
editing. That fits the existing pattern: a small application-context snapshot of today's memo
titles under its own key, written in the same `updateApplicationContext` call as the task and
habit keys (ADR 0003). The Watch doesn't need SwiftData for memos. It only needs a local
outbox of recordings that haven't been acknowledged yet (see Part 2).

## Part 2: Watch → phone audio transfer

### What Apple documents about `transferFile(_:metadata:)`

From [transferFile(_:metadata:)](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)),
[WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession), and
[WCSessionDelegate](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate):

- It sends "a file that's local to the current device", along with an optional metadata
  dictionary, "asynchronously on a background thread". The system "may throttle delivery
  speeds to accommodate performance and power concerns".
- It can be called only while `activationState == .activated`. Calling it otherwise "is a
  programmer error". Kyo's transport already buffers task and habit commands until activation,
  and the same applies here.
- Background transfers (application context, user info, files) don't need the counterpart to
  be reachable. "When only one session is active, the active session may still send updates
  and transfer files, but those transfers happen opportunistically in the background." "All
  transfers are delivered in the order in which they were sent." WWDC21 says the same: "None
  of the background communication requires your counterpart app to be reachable when you send
  data" ([There and back again: Data transfer on Apple Watch](https://developer.apple.com/videos/play/wwdc2021/10003/)).
- **Metadata** must contain property-list types only. Otherwise the transfer fails through
  `session(_:didFinish:error:)`. This is where the memo id, recording time, the Watch's
  calendar day, and duration go.
- **Progress and cancellation:** the call returns a `WCSessionFileTransfer` with `progress`
  (iOS 12 / watchOS 5+), `isTransferring`, and `cancel()`. `outstandingFileTransfers` lists
  transfers "queued for delivery but have not yet been delivered"
  ([outstandingFileTransfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/outstandingfiletransfers)).
- **Sender completion:** `session(_:didFinish:error:)` for file transfers is called when a
  transfer "finished, either successfully or unsuccessfully". Apple suggests "trying to send
  the file again at a later time" on error
  ([session(_:didFinish:error:)](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didfinish:error:)-6dtcu)).
- **Receiver:** `session(_:didReceive:)` runs on a background thread. "If you don't move the
  file synchronously during your implementation of this method, the system deletes the file
  when the method returns"
  ([session(_:didReceive:)](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceive:))).
  WWDC21 adds: "if you call an async method to process the file from the inbox, you will most
  likely run into a problem because the file will be gone." Kyo's delegate currently hops to
  `@MainActor` with `Task { … }`. A file handler must move the file *before* that hop and pass
  on only the new URL plus the metadata.
- **Errors** that apply to files
  ([WCError.Code](https://developer.apple.com/documentation/watchconnectivity/wcerror/code)):
  - `payloadTooLarge` ("can occur for both data dictionaries and files")
  - `insufficientSpace` (on the receiving side)
  - `fileAccessDenied` (bad path or no access)
  - `transferTimedOut`
  - `deliveryFailed`
  - `sessionInactive` / `sessionNotActivated`
  - `watchAppNotInstalled` / `companionAppNotInstalled`
- **Simulator:** `transferFile` isn't supported, and `session(_:didReceive:)` is never called
  there. "Always test Watch Connectivity file transfers on paired devices." The transfer path
  needs a seam so it can be unit-tested, the way `TaskSnapshotTransport` is today, plus manual
  testing on hardware.
- **Watch background wake:** the paired device's `transferFile` triggers a
  `WKWatchConnectivityRefreshBackgroundTask` on the Watch. The app must keep it open until the
  session is activated and `hasContentPending` is false, and then complete it
  ([WKWatchConnectivityRefreshBackgroundTask](https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask),
  [Transferring data with Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)).
  This matters for phone → Watch traffic, such as acknowledgments. In SwiftUI it's
  `.backgroundTask(.watchConnectivity)`.
- **Multiple Watches:** while the iOS session is inactive or deactivated after a Watch switch,
  "you cannot initiate any new transfers". Kyo already re-activates in `sessionDidDeactivate`.

### What Apple doesn't document

These gaps shape the design, so they're listed explicitly:

- **No stated file size limit.** Only that `payloadTooLarge` can occur for files.
- **Whether the system copies the file when it queues it.** Nothing says the sender may delete
  or move its file before `didFinish`. Assume it may not.
- **Whether queued file transfers survive the Watch app being terminated or the Watch
  rebooting.** For `transferUserInfo`, the WCSession overview says transfers "continue when
  the current app is suspended or terminated". The file-transfer text only says files transfer
  "in the background".
- **Whether iOS launches the phone app in the background to receive a file.** Apple documents
  the background wake for `sendMessage` (WWDC21: "your iOS app will be activated in the
  background to receive the message"). `hasContentPending` describes data "received in the
  background but … not yet delivered" to the delegate, which suggests files can wait until the
  phone app next activates its session. The design shouldn't assume the phone processes a memo
  promptly.
- **Exactly what `didFinish` with no error confirms.** It means the transfer finished. It
  doesn't say the receiving app has moved or persisted the file.

### Size estimate (arithmetic, not from Apple)

The cap is about 10 minutes (#51). AAC mono at 64 kbps works out to 64,000 / 8 × 600 s ≈
4.8 MB. At 32 kbps it's about 2.4 MB. Uncompressed 16 kHz 16-bit PCM would be about 19 MB. The
codec and bitrate choice drives transfer time and Watch storage more than anything else.

### A reliability pattern that fits Kyo's existing sync

This follows ADR 0002's outbox and acknowledgment design. It's offered as an option, not a
decision.

1. **Record to a file the Watch owns**, in the Watch app's container, named by a new memo id
   (UUID). Write an outbox entry (memo id, file name, recorded-at, Watch calendar day,
   duration) to persistent storage *before* starting the transfer.
2. **Transfer** with `transferFile(url, metadata: ["kyo.memoID": …, "kyo.recordedAt": …, …])`
   once the session is activated. Buffer until then, as the transport does for commands.
3. **Phone receive:** inside `session(_:didReceive:)`, synchronously move the file into the
   phone's memo media location under the memo id. If it's already there (a duplicate), discard
   the new copy. Then hop to the main actor to create the memo with a "transcript pending"
   state. Deduplicate by memo id in code, since CloudKit-compatible models can't use unique
   constraints.
4. **Acknowledge** in the memo snapshot the phone already publishes for the Watch's list. An
   `acknowledgedMemoIDs` field mirrors `acknowledgedCommandIDs`.
5. **Watch cleanup:** delete the local audio file and outbox entry only when the memo id shows
   up as acknowledged. Don't rely on `didFinish` alone, for the reason given above. On
   `didFinish` with an error, or on app launch, re-send any outbox entry with no outstanding
   transfer. Check `outstandingFileTransfers` first so a retry doesn't queue a duplicate, the
   same way the transport already cancels duplicate `transferUserInfo` items.
6. **Storage pressure on the Watch:** with retries and no acknowledgment (for example, the
   phone app not opened for days), recordings pile up. A cap or warning on the number of
   unacknowledged recordings may be worth specifying.

Alternatives considered:

- **`sendMessageData`**: needs the phone to be reachable and is meant for small, immediate
  payloads. It has the same weakness ADR 0001 gave for rejecting `sendMessage`.
- **`transferUserInfo` with audio inside the dictionary**: it's for dictionaries, and
  `payloadTooLarge` applies. Files are what `transferFile` is for: "use this method in cases
  where you want to send more than a dictionary of values".
- **Recording straight to iCloud from the Watch**: depends on network access and the future
  sync effort, which is out of scope now.

## Things a later decision should know

- **Unique constraints and CloudKit don't mix.** If iCloud is coming, don't use
  `#Unique`/`.unique` on the memo id, even though it's tempting for Watch dedupe. Dedupe in
  code.
- **Option A is the only one where media sync comes free** with SwiftData's iCloud sync.
  Option B's file layout is simpler at runtime but adds a second sync system later.
- **The Watch transfer has undocumented edges** (size limits, surviving termination, phone
  background launch). An acknowledgment-driven outbox doesn't depend on any of them.
- **The existing WC delegate pattern** (`Task { @MainActor in … }`) is wrong for files. The
  move has to happen synchronously in the callback.
- **File transfers can't be tested in Simulator.** Plan a transport seam for unit tests, plus
  checks on paired hardware.
- **Data protection** (whether the store and media files are readable while the phone is
  locked and the app is woken in the background) wasn't covered here. It's worth checking when
  the storage choice is made.

## Sources

- [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)
- [Schema.Attribute.Option.externalStorage](https://developer.apple.com/documentation/swiftdata/schema/attribute/option/externalstorage)
- [Schema.Attribute.Option.spotlight](https://developer.apple.com/documentation/swiftdata/schema/attribute/option/spotlight)
- [NSAttributeDescription.allowsExternalBinaryDataStorage](https://developer.apple.com/documentation/coredata/nsattributedescription/allowsexternalbinarydatastorage)
- [Index(_:)](https://developer.apple.com/documentation/swiftdata/index(_:)-74ia2)
- [Unique(_:)](https://developer.apple.com/documentation/swiftdata/unique(_:))
- [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Creating a Core Data Model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)
- [Reading CloudKit Records for Core Data](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data)
- [ModelConfiguration init](https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:isstoredinmemoryonly:allowssave:groupcontainer:cloudkitdatabase:))
- [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)
- [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)
- [PredicateExpressions.StringLocalizedStandardContains](https://developer.apple.com/documentation/foundation/predicateexpressions/stringlocalizedstandardcontains)
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [WCSession.transferFile(_:metadata:)](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:))
- [WCSession.outstandingFileTransfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/outstandingfiletransfers)
- [WCSession.hasContentPending](https://developer.apple.com/documentation/watchconnectivity/wcsession/hascontentpending)
- [WCSession.transferUserInfo(_:)](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))
- [WCSessionDelegate](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate)
- [WCSessionDelegate.session(_:didReceive:)](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceive:))
- [WCSessionDelegate.session(_:didFinish:error:) (file)](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didfinish:error:)-6dtcu)
- [WCSessionFileTransfer](https://developer.apple.com/documentation/watchconnectivity/wcsessionfiletransfer)
- [WCError.Code](https://developer.apple.com/documentation/watchconnectivity/wcerror/code)
- [WKWatchConnectivityRefreshBackgroundTask](https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask)
- [Transferring data with Watch Connectivity (sample)](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- WWDC21 [There and back again: Data transfer on Apple Watch](https://developer.apple.com/videos/play/wwdc2021/10003/)
- WWDC26 [What's new in SwiftData](https://developer.apple.com/videos/play/wwdc2026/274/)
