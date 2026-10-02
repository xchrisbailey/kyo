# 5. Watch memo sync: memo snapshot plus file outbox

Status: accepted (implemented)

## Context

The Watch shows today's memos and records voice memos. It has no playback or editing, and it
can't transcribe: watchOS has no Speech framework, so the phone transcribes every recording.
Recordings are audio files of up to about 3.6 MB (ADR 0004). They must reach the phone even when
it's out of reach when the user records, and they must never be lost or duplicated.

## Decision

The phone stays the only writer of memos, as in ADR 0001–0003.

**Phone → Watch.** Memos get their own **memo snapshot and revision** under their own context
key. It's written in the same `updateApplicationContext` call as the task and habit keys
(ADR 0003). For each of today's memos it carries:

- id and day;
- creation time and kind (written or voice);
- title;
- voice state (Transcribing, Transcribed, No transcript) and duration;
- photo count.

No text, transcript, audio or photos are sent. The Watch shows only memos whose day is its own
Today, so the list empties at midnight without the phone app running.

**Watch → phone.** A recording travels with `WCSession.transferFile(_:metadata:)`:

1. The Watch records to a file it owns, named by a new memo id. Before sending, it writes an
   outbox entry (memo id, start time, Watch calendar day, duration) to persistent storage.
2. It calls `transferFile` once the session is activated, with the entry as metadata. Delivery
   doesn't need the phone to be reachable.
3. Inside `session(_:didReceive:)`, the phone moves the file synchronously, before any hop to
   the main actor, because the system deletes it when the method returns. It then creates the
   memo in the Transcribing state, on the Watch's day, and transcribes it.
4. The phone confirms by listing the memo id in the memo snapshot's `acknowledgedMemoIDs`,
   which mirrors `acknowledgedCommandIDs`.
5. The Watch deletes its file and outbox entry only when it sees that confirmation. A successful
   `didFinish` isn't treated as delivery. On a failed transfer, and on launch, the Watch resends
   any entry that isn't already in `outstandingFileTransfers`.

**Duplicates and deletion.** The phone keeps a bounded, persisted set of Watch memo ids it has
received, like its processed command ids. A repeat delivery is ignored but still confirmed, so
a retry can't duplicate a memo or bring back one the user deleted. There are no unique
constraints (ADR 0004); the check is in code.

**Waiting.** Until the phone confirms it, the Watch shows each outbox recording in its list
straight away as "Voice memo · Waiting for iPhone". Once confirmed, the phone's version
replaces it. There's no cap on waiting recordings. If the Watch runs out of space, recording
fails with "Not enough space on Apple Watch".

## Considered options

- **`sendMessageData`.** Needs the phone to be reachable and suits small, immediate payloads.
  It's rejected for the same reason ADR 0001 rejected `sendMessage`.
- **Audio inside `transferUserInfo`.** That call is for dictionaries and fails with
  `payloadTooLarge`. Files are what `transferFile` is for.
- **Trusting `didFinish`.** Apple doesn't document that it means the receiving app has stored
  the file, so deleting the Watch copy then could lose a memo.
- **Sending text and transcripts to the Watch.** No Watch screen shows them, and it would grow
  the context payload.

## Consequences

- iOS isn't documented to wake the phone app to receive a file. A recording can wait in the
  WatchConnectivity inbox until Kyo next runs on the phone, and the Watch shows "Waiting for
  iPhone" until then.
- File transfer doesn't work in the Simulator. The transfer path needs a seam for unit tests,
  like `TaskSnapshotTransport`, plus manual testing on a paired iPhone and Watch.
- The phone's WatchConnectivity delegate needs a file handler that does its work
  synchronously. The existing handlers hop to the main actor first.
