# Research: handing a Task to an AI agent (Claude, ChatGPT, T3 Code)

Issues: #133 (share a Task), #134 (share a Memo from its row). Researched 2026-10-05 against Anthropic, OpenAI, and Apple documentation, the T3 Code source (`pingdotgg/t3code` at commit `3e6b450`, 2026-10-05), and the T3 Code, Claude, and ChatGPT apps installed on the owner's Mac. Deployment targets are iOS 27 and watchOS 27.

## Question

Can Kyo let the user send a Task's text straight to an AI agent so the agent does the work? Three targets: Claude (apps, Claude Code, API), ChatGPT (apps, Codex, API), and T3 Code. For each: which entry points exist for a third-party iOS or watchOS app, what the user has to set up, what Kyo sends, whether a result can come back, and the limits.

How to read this: "verified" means I read it in the vendor's own documentation or source. "Observed locally" means I saw it in an installed app bundle or a running process on this Mac, and no documentation covers it. "Unverified" means I found no primary source. "Inference" is my reasoning from verified facts.

## Direction chosen

After reading this research the owner chose the share sheet only (2026-10-05): Kyo shares a Task or Memo to the Claude, ChatGPT, or T3 Code app on the phone, and the user finishes there. Sharing a Memo from its open card already shipped (#55); #133 adds Share to a Task row and #134 adds it to a memo row. The HTTP routes below (routines, the Claude and OpenAI APIs) are out; they stay in this file as the record of what was considered.

## Feasibility summary

| Target | Verdict | Most practical route | Agent starts without another tap? | Result back in Kyo? |
| --- | --- | --- | --- | --- |
| Claude | Possible with caveats | A Claude Code routine with an API trigger: Kyo POSTs the Task text to the routine's `/fire` endpoint with the user's per-routine token | Yes | Only a session ID and URL |
| ChatGPT | Possible with caveats, and weaker | The system share sheet, or a user-built Shortcut. For background work: the OpenAI API with the user's own API key | Share sheet: no. API: yes | Share sheet: no. API: yes, by polling |
| T3 Code | Possible with caveats | The system share sheet into the T3 Code iOS app, which opens a new task with the text as a draft | No. The user picks a project and sends | No |

- One mechanism covers all three with no accounts, keys, or network code in Kyo: a `ShareLink` on the Task. Claude documents accepting shared text. T3 Code's source shows a share extension that accepts text. ChatGPT's is unverified. It only hands the text over; the user finishes in the other app.
- Only Claude has a documented, per-user HTTP endpoint that starts an agent on the user's subscription from any HTTPS client. It's in research preview, the endpoint is marked experimental, and the routine's saved prompt has to opt in to acting on the text Kyo sends.
- Neither vendor lets a third-party app sign the user in with their subscription for general use. Anthropic forbids it outright unless approved. OpenAI's "Sign in with ChatGPT" is a limited trial and its open-source flow needs a loopback HTTP listener, which doesn't fit iOS.
- No target offers a documented URL scheme on iOS that takes a prompt. The documented deep links (`claude-cli://`, `codex://`) are desktop only and prefill without sending.
- All of these send Task text off the device. Kyo's AI is on device only today (see [memo-transcription-and-ai.md](memo-transcription-and-ai.md)), so any of these routes is a product decision, and App Review requires explicit consent before sharing personal data with third-party AI [S31].
- On Apple Watch, opening another app with a URL isn't available. A plain HTTPS call (the Claude routine route) is the only one that could run from the Watch; everything else relays through the phone.

A point about fit: Claude Code, Codex, and T3 Code are coding agents that work in a repository. A Task such as "fix the login redirect bug" suits them. A Task such as "book the dentist" doesn't; that kind goes to the Claude or ChatGPT chat apps, where the share sheet and Shortcuts routes are the only ones.

## Mechanisms that work the same for every target

### Share sheet

- Kyo can present the system share interface for a Task's text with SwiftUI `ShareLink` (iOS 16+, watchOS 9+). Strings need no preview, and `subject` and `message` can be pre-filled for services that support them [S25].
- What appears in the sheet is decided by the installed apps' share extensions, not by Kyo. Kyo can't check whether Claude, ChatGPT, or T3 Code is installed through the share sheet.
- Nothing comes back to Kyo. The receiving app owns what happens next.
- This is the lowest-risk route for App Review and privacy: the user picks the destination each time, and Kyo holds no credentials.

### Shortcuts, and App Intents in other apps

- Inference: the App Intents framework has no API for one app to run another app's intent. An app's intents are run by the system: Siri, Spotlight, Shortcuts, controls, and widgets. I found no Apple documentation of a cross-app call, and the docs I read describe only an app's own intents [S26]. So Kyo can't call "Ask Claude" directly.
- The documented cross-app path is a Shortcut the user builds. Kyo can run a named Shortcut by URL: `shortcuts://run-shortcut?name=[name]&input=text&text=[text]` [S27]. With `shortcuts://x-callback-url/run-shortcut?...&x-success=...`, "a parameter named result is appended to the URL and contains the textual output of the shortcut" [S28]. That gives a way to get text back into Kyo, through a `kyo://` URL scheme Kyo would have to register.
- Opening a URL handled by another app brings that app to the foreground [S29]. The Shortcuts route therefore leaves Kyo, runs, and returns.
- Kyo could also expose its own App Intent, such as "Get today's Tasks", so the user's Shortcut pulls Tasks from Kyo instead of Kyo pushing. That inverts the direction and needs no knowledge of the target app. Kyo already plans App Intents for memos ([memo-quick-capture.md](memo-quick-capture.md)).
- Setup burden: the user builds the Shortcut and Kyo must know its exact name. That's fragile and hard to explain inside a planner.

### URL schemes

- `UIApplication.open(_:options:completionHandler:)` launches whichever app handles a custom scheme, and isn't limited by `LSApplicationQueriesSchemes`. `canOpenURL(_:)` is: undeclared schemes always return `false`, and apps linked on iOS 27 may declare at most 25 [S29][S30].
- Universal links fall back to the browser when the app isn't installed [S30].

### Apple Watch

- `WKApplication.openSystemURL(_:)` exists "to initiate phone calls or send messages"; the URL goes to a system app [S32]. It isn't a way to launch a third-party app.
- SwiftUI's `openURL` exists on watchOS 7+ [S33]. Whether it can open a third-party Watch app with a custom scheme is unverified, and none of the three targets is documented to have a Watch app that takes a prompt. T3 Code's mobile source has no watchOS target (verified by search of `apps/mobile`).
- `ShareLink` is available on watchOS 9+ [S25]. Which share services a Watch offers for text is unverified.
- Inference: the Watch should either send the Task to the phone over the existing Watch Connectivity path and let the phone hand it off, or make one HTTPS request itself (Claude routine route). Direct networking from the Watch wasn't researched here.

## 1. Claude

### 1.1 Claude iOS app: App Intent, Shortcuts, share menu

Verified from Anthropic's help center (article last updated 2026-07-09), read through a summarizing fetch, so treat the wording as close but not exact [S1]:

- Requires iOS 18 or later. The app offers an "Ask Claude" App Intent, a widget, an "Analyze Photo with Claude" control, and use of the intent in Shortcuts.
- "Ask Claude" is reachable from Spotlight, Siri, the Share menu, and "any app that supports iOS intents". The article describes selecting text and using the Share menu "to send it directly to Claude".
- The intent uses the user's default model and counts toward their usage limits.
- The article's example Shortcut passes Shortcut Input into an "Ask Claude" action with a prompt.

What this means for Kyo:

- Share sheet: supported for text. Kyo sends the Task text; the user confirms in Claude's share UI. Nothing returns.
- Shortcut: the user builds one with "Ask Claude"; Kyo runs it by name [S27]. Whether "Ask Claude" hands its answer to the next Shortcut action, which the x-callback `result` needs, is unverified. The article's example suggests it, but I couldn't confirm it from the summarized text.
- This is a chat answer, not an agent doing work. It doesn't start a Claude Code session.
- A second help article covers Claude acting on iOS apps (Reminders, Calendar, Messages, Mail). That's Claude reaching into system apps, not other apps sending work to Claude [S2].

### 1.2 URL schemes and web links

- iOS: no documented URL scheme or universal link that carries a prompt. Unverified whether the iOS app registers `claude://`.
- Observed locally: the macOS Claude app (2.19675.0) registers the `claude` scheme, and its bundle contains routes such as `claude://claude.ai/new?surface=chat`, `claude://code/new`, and `claude://code/continue?session=last`. None I found carries a prompt parameter. Undocumented; don't build on it.
- `https://claude.ai/new?q=...`: no Anthropic documentation. Third-party pages describe it, and one reports it was removed in October 2025. Unverified and probably stale.
- `https://claude.ai/code/new` "start[s] a new Code session in the app" on a phone [S3]. No prompt parameter is documented.
- `claude-cli://open?q=...&cwd=...&repo=...` is documented, but it's for desktop Claude Code: it "opens Claude Code in a new terminal window" on macOS, Linux, and Windows. "The prompt is populated but not sent until you press Enter", and `q` is capped at 5,000 characters [S4]. Not usable from iOS.

### 1.3 Claude Code routine with an API trigger (the practical agent route)

Verified [S5][S6]:

- A routine is "a saved Claude Code configuration: a prompt, one or more repositories, and a set of connectors" that runs on Anthropic-managed cloud infrastructure. Routines are in research preview. Plans: Pro, Max, Team, Enterprise, with Claude Code on the web enabled.
- An API trigger gives the routine its own endpoint: `POST https://api.anthropic.com/v1/claude_code/routines/{routine_id}/fire`, with `Authorization: Bearer <per-routine token>` and `anthropic-version: 2023-06-01`. The token is prefixed `sk-ant-oat01-`, is created in the web UI at claude.ai/code/routines, is shown once, and is "scoped to a single routine": "it grants no read access, no access to other routines, and no access to account data".
- Body: optional `text`, freeform, up to 65,536 characters.
- Response: `claude_code_session_id` and `claude_code_session_url`. "The request returns once the session is created. It does not stream session output or wait for the session to complete."
- Billing: "Claude Code subscription usage on claude.ai", not API usage.
- Limits: 30 fires per hour per routine and 100 per hour per account. No idempotency key, so a retry creates a second session.
- Stability: "This is an experimental API. Request and response shapes, rate limits, and token semantics might change." No SDK support.
- The text arrives "wrapped in a `<routine-fire-payload>` block that labels it as untrusted data". The routine's saved prompt "must opt in to acting on fire text", for example "Carry out the task described in the routine-fire-payload block" [S5].
- Routines run without permission prompts, and commits and connector actions appear as the user [S5].

For Kyo:

- User setup: create a routine (prompt that opts in to the payload, repositories, environment, connectors), add an API trigger, then paste the URL and token into Kyo. Kyo stores the token in the Keychain.
- Kyo sends: the Task text as `text`. A plain HTTPS POST, so it could also be sent from the Watch (inference).
- Result: Kyo can show or open the session URL, which opens in the Claude app or browser. Kyo can't read the outcome: the token has no read access, and no status endpoint is documented. A routine could be written to report somewhere Kyo can read, but that's the user's design, not a Kyo feature.
- One routine means one fixed set of repositories. A user with several projects needs a routine per project and Kyo needs a picker.
- This is the user's own token for their own routine, used the way the docs describe ("anywhere you can make an authenticated HTTP request"). It isn't the "claude.ai login" that third-party apps are barred from offering (section 1.5). Still worth confirming with the terms before shipping to other users (open question 5).

### 1.4 Other Claude Code entry points

- Cloud sessions from the Claude app: the user starts them in the app's Code tab [S3]. No API for third-party apps to start one, apart from routines.
- Remote Control: connects the Claude app to a session on the user's computer [S3]. No third-party entry point documented.
- Dispatch: "a persistent conversation with Claude" in the Cowork tab; "You message Dispatch a task, and it decides how to handle it". Pro and Max only [S7]. No API or intent documented for another app to message it.
- Channels (research preview): an MCP server pushes messages into a Claude Code session that's already running on the user's machine. Telegram, Discord, and iMessage plugins are included; for iMessage, "texting yourself bypasses the gate automatically" [S8]. Inference: Kyo could open a prefilled message to the user's own number, which a running session with the iMessage channel would pick up. It requires a Mac with a session left open, and it's a long way from a supported integration.
- Headless (`claude -p`) and the Agent SDK run on a computer or server, not in an iOS app [S9].

### 1.5 Claude API

- Messages API: the direct model API. Auth is an API key or Workload Identity Federation, billed to the developer's Console workspace [S10].
- App Attest (new, beta): "authenticates iOS and macOS apps that call the Claude API directly from the device", with no key in the app. Tokens "expire after one hour, and authorize only Messages API calls", and "bills usage to your workspace". It's used through the Claude for Foundation Models Swift package, which "requires the OS 27 betas". It needs a physical device with a Secure Enclave, and the page names iOS and macOS only, so no watchOS [S10][S11]. This would make Kyo's owner pay for every user's usage.
- Managed Agents (beta, header `managed-agents-2026-04-01`): a hosted agent harness for "long-running tasks and asynchronous work", driven by sessions and events over HTTP with an API key [S12]. This is the API-key equivalent of a background agent job. App Attest tokens can't call it, so it needs a key in the app (the user's own) or a Kyo server.
- Subscriptions: "Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK" [S13]. Kyo can't offer "sign in with Claude" to use the user's plan.
- With a user-supplied API key, Kyo could call the Messages API or Managed Agents and show the result in Kyo. Costs fall on the user's Console account, and Kyo would have to build the agent behavior or configure a managed agent.

### 1.6 Indirect routes

- GitHub, `@claude`: the Claude Code GitHub Action responds when the trigger phrase appears "in an issue or pull request comment, in a pull request review, or in the body or title of a newly opened issue". The triggering user needs write access. Claude replies in a comment on the issue [S14]. Kyo would create an issue through the GitHub REST API with `@claude` in the body. Setup: the Action installed in the repository with an Anthropic API key or OAuth token as a secret, plus GitHub sign-in in Kyo. The result lands on GitHub, and Kyo could poll the issue.
- Routine GitHub triggers react only to pull request and release events, not issues [S5].
- Slack: mentioning `@Claude` with a coding task creates a Claude Code cloud session under the user's account (Pro and Max; Team and Enterprise are moving to Claude Tag) [S15]. Kyo would need Slack API access to post as the user. Heavy for a planner.
- Email to agent: none documented.

## 2. ChatGPT

OpenAI's Codex documentation now redirects from `developers.openai.com/codex` to `learn.chatgpt.com/docs`; citations use the new host. `help.openai.com` returned HTTP 403 to my fetches, so claims that would rest on the help center are marked unverified.

### 2.1 ChatGPT iOS app: Shortcuts, share sheet, URL scheme

- Shortcuts actions exposed by the ChatGPT iOS app ("Ask ChatGPT" and similar): unverified. Community posts describe them; I couldn't read an official page.
- The only first-party statement I found: ChatGPT for iOS 1.2026.139 (2026-05-25) "Added Spotlight and Shortcuts support for opening Codex Mobile directly" [S16]. That opens Codex in the app. It isn't documented to take a prompt.
- Share extension accepting text: unverified.
- `chatgpt://` scheme and `https://chatgpt.com/?q=...` prefill: not in the documentation I read. Unverified.
- Apple's Shortcuts "Use Model" action can target ChatGPT: the "Extension Model" option "Uses ChatGPT to handle your requests", and "the output responses are automatically optimized for the actions they're passed to" [S17]. It needs Apple Intelligence on an eligible device. This is verified on Apple's side, returns text to the Shortcut, and so pairs with the x-callback route. It's a chat answer, not an agent job.

### 2.2 `codex://` deep links (desktop only)

Verified [S18]:

- "The ChatGPT desktop app keeps the `codex://` URL scheme for compatibility". `codex://new?prompt=<text>&path=<absolute-path>&originUrl=<git-remote-url>` and `codex://threads/new?...` open a new local chat.
- "The link opens a new chat with the decoded prompt in the composer. It doesn't send the prompt automatically."
- Observed locally: the installed ChatGPT.app (bundle ID `com.openai.codex`) registers `codex`, `http`, and `https`.
- Nothing in the docs says the iOS app handles `codex://`. Unverified, and unlikely to help Kyo.

### 2.3 Codex Cloud, Codex Remote, and automations

- Codex Cloud runs coding tasks in the cloud against a GitHub repository; tasks start from ChatGPT on web, mobile, or desktop [S19]. I found no public REST API for creating a cloud task. The CLI has `codex cloud exec`, which "submits a task directly", marked experimental, and "Authentication follows the same credentials as the main CLI" [S20]. That's a terminal tool, not something an iOS app calls.
- Codex Remote: the ChatGPT iOS app starts and steers tasks on a connected Mac or PC [S21]. No third-party entry point documented.
- Scheduled tasks can also run "when a supported Gmail, Slack, or GitHub event occurs": new Gmail messages filtered by sender or subject, new Slack messages in chosen channels, or GitHub pull request activity. They're available on web and mobile on eligible plans [S22]. Inference: this allows email-to-agent. The user creates a task triggered by mail with a subject such as "Kyo task", and Kyo opens a prefilled email for the user to send. It's indirect, costs the user a tap in Mail, and "ChatGPT may combine" close events into one run.
- Workspace agent trigger: `POST https://api.chatgpt.com/v1/workspace_agents/<id>/trigger` with a body such as `{"input":"..."}` and a Workspace Agent access token. Tokens come from the ChatGPT admin console, need an admin to enable them, and Codex access tokens are "currently supported for ChatGPT Business and Enterprise workspaces" [S23][S24]. Not available to an individual Plus or Pro user. The response shape isn't documented on the page I read.

### 2.4 OpenAI API

- Responses API background mode: set `background` to `true`, then "poll response objects to check status over time". Auth is a Platform API key, billed at API rates [S34]. This is the one ChatGPT-side route where the result comes back into Kyo, as text from a model with whatever tools the request enables. It isn't the user's ChatGPT subscription, and it isn't Codex.
- Codex SDK and `codex exec` run on a computer or server ("Use the library server-side") [S35]. Codex app-server is for building desktop clients; "App-server authentication has never been permitted for commercial or hosted services" [S36].
- Sign in with ChatGPT: lets users "use their ChatGPT plan for eligible AI requests in your app". It's "currently available to selected commercial partners through a limited trial"; "ChatGPT plan usage is available to all open-source partners and selected private clients" [S37]. The open-source flow uses "an HTTP loopback callback on `127.0.0.1`", and many tools are unsupported in the preview, including hosted MCP/connectors and native computer use [S37]. Kyo's repository is public, so the open-source path is nominally open, but a loopback listener doesn't fit an iOS app (inference), and what it buys is Responses API calls, not Codex tasks.

### 2.5 Indirect routes

- GitHub: `@codex review` in a pull request comment requests a review. "If you mention `@codex` in a comment with anything other than `review`, Codex starts a legacy cloud chat using your pull request as context" [S38]. This is documented for pull requests only. I found nothing saying `@codex` in a plain issue starts work, so an issue-based handoff is unverified for Codex.
- Codex GitHub Action (`openai/codex-action@v1`) runs `codex exec` in a workflow with an API key [S39]. A repository could wire it to issue events itself. That's the user's CI design.
- Linear: "Assign an issue to Codex or mention `@Codex` in a comment, and Codex creates a cloud chat and replies with progress and results" (paid plans) [S40]. Kyo would create a Linear issue through Linear's API. It only makes sense if the user already lives in Linear.
- Slack: mention `@ChatGPT`; with Cloud delegation it sends repository work to Codex Cloud. A workspace owner or admin sets it up [S41].

## 3. T3 Code

T3 Code describes itself as an "agent harness control surface" with an iOS app, an Android app, a web app, and an Electron desktop app; it drives Claude Code, Codex, and other agents already installed and signed in on the user's computer [S42]. The current release is v0.0.45 (2026-10-02), so everything below is pre-1.0 and can change. Findings are from source at commit `3e6b450`; I didn't test the iOS app on a device, and the App Store build may lag the source.

### 3.1 iOS app: share extension (the practical route)

Verified in source:

- The iOS app is configured with a share extension (`expo-sharing`) whose activation rule has `supportsText: true`, one web URL, and up to eight images, movies, or files. It's disabled only for personal-team development builds [S43].
- An incoming share is stored in a persisted inbox, then the app navigates to the new-task sheet with `incomingShareId`, where the shared text becomes the draft. The first screen is titled "Choose project" [S44][S45].
- So: Kyo shares the Task text, the user picks T3 Code in the share sheet, chooses a project, and sends. No auto-submit. Nothing returns to Kyo.
- The work runs on the user's computer, which "must stay running and reachable" [S46].

### 3.2 URL scheme

- Mobile: the app registers `t3code://` (plus `-dev` and `-preview` variants) and maps paths with React Navigation. `t3code://new` opens the new-task sheet, and `t3code://threads/:environmentId/:threadId` opens a thread [S44][S47]. The new-task routes read `incomingShareId`, `environmentId`, `projectId`, `branch`, and similar parameters. I found no parameter that carries prompt text, so a link can open the sheet but not fill it (verified by reading the route screens; a parameter elsewhere is possible but I didn't find one).
- Desktop: both installed builds register `t3code` and `t3code-dev` (observed locally in Info.plist). In source, the only `open-url` handler deals with provider sign-in handoff and return [S48]. The scheme otherwise serves the bundled client inside Electron [S49]. There's no deep link that creates a thread with a prompt.
- None of this is documented for third parties.

### 3.3 Local server, RPC, CLI, and MCP

- Observed locally: the desktop app runs a server on port 3773 bound to `0.0.0.0`, with `serverExposureMode` set to `network-accessible`. `GET /.well-known/t3/environment` answers without auth and returns the environment ID, server version, and capabilities.
- The server issues its own scoped sessions. Clients pair with a one-time link (`t3 pair`), or a headless client gets a token from `t3 auth session issue` ("Issue a scoped bearer access token for headless or remote clients"). Scopes include `orchestration:read`, `orchestration:operate`, and `access:write`. Clients then get a short-lived WebSocket ticket over authenticated HTTP and speak RPC over the socket [S50][S51][S52].
- Away from the LAN, the supported path is T3 Connect, a relay tied to a T3 account, or Tailscale [S46].
- Inference: a third-party app could pair as a client and dispatch the same commands the official apps use to create a thread and start a turn. But the contract lives in the repository's internal `packages/contracts`, no user doc presents it as a public API, the protocol is versioned for the project's own clients (`orchestrationProtocolVersion: 2`), and the product is at 0.0.x. Treat it as unsupported and likely to break.
- The `/mcp` endpoint requires "a valid provider-scoped MCP bearer credential" tied to an agent session the server itself started [S53]. It's for the agents T3 Code launches, not for outside clients.
- The `t3` CLI has `serve`, `pair`, `connect`, `auth`, `project add`, and `app` ("Open a project in the running T3 Code desktop app") [S51][S54]. I found no command that creates a thread from a prompt.
- Scheduled tasks exist in the product [S44]. I found no webhook or HTTP trigger for them.

### 3.4 What T3 Code adds over going direct

T3 Code wraps the user's own Claude Code and Codex logins on their computer. If Kyo hands a Task to T3 Code, the user chooses the project, the agent, and the model there. That fits a user who already runs everything through T3 Code, and it avoids Kyo holding any credential. It doesn't give Kyo anything programmatic that Claude's routine trigger doesn't.

## Comparison

| Mechanism | Target | Documented? | User setup | Kyo sends | Starts work unattended? | Result to Kyo | Main limits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Share sheet | Claude | Yes [S1] | Claude app installed | Task text | No | No | Chat answer, not an agent |
| Share sheet | ChatGPT | Unverified | ChatGPT app installed | Task text | No | No | Not confirmed |
| Share sheet | T3 Code | Source only [S43] | App installed and paired with a running computer | Task text | No, user picks project | No | Pre-1.0; computer must be on |
| User Shortcut run by URL | Claude ("Ask Claude") | Yes [S1][S27] | Build a Shortcut; tell Kyo its name | Task text | Yes, after leaving Kyo | Possibly, by x-callback (unverified for this action) | Fragile setup; chat answer |
| User Shortcut run by URL | ChatGPT ("Use Model") | Yes, by Apple [S17] | Build a Shortcut; Apple Intelligence device | Task text | Yes, after leaving Kyo | Yes, by x-callback [S28] | Chat answer; device eligibility |
| Routine `/fire` | Claude Code | Yes, experimental [S6] | Routine, API trigger, paste URL and token | Task text (HTTPS POST) | Yes | Session URL only | Research preview; one routine per repo set; paid plan |
| Messages API / Managed Agents | Claude API | Yes (Managed Agents beta) [S10][S12] | User's API key, or Kyo's App Attest registration | Task text | Yes | Yes | Per-token cost; no subscription use; Kyo builds the agent |
| Responses API background mode | OpenAI API | Yes [S34] | User's API key | Task text | Yes | Yes, by polling | Per-token cost; not Codex; no subscription use |
| Deep link with prompt | Claude Code, Codex | Yes, desktop only [S4][S18] | n/a | n/a | No, prefill only | No | Not on iOS |
| Workspace agent trigger | ChatGPT | Yes [S23] | Business or Enterprise workspace, admin-enabled token | Task text | Yes | Undocumented | Not for individual plans |
| GitHub issue with `@claude` | Claude Code Action | Yes [S14] | Action installed in repo; GitHub auth in Kyo | Issue title and body | Yes | On the issue; Kyo could poll | GitHub OAuth in Kyo; repo choice per Task |
| GitHub issue with `@codex` | Codex | Unverified for issues [S38] | n/a | n/a | n/a | n/a | Documented for pull requests only |
| Email-triggered task | ChatGPT | Yes [S22] | Scheduled task with a Gmail trigger | Prefilled email the user sends | Yes, after the user sends | No | Indirect; events may be combined |
| Paired RPC client | T3 Code | No (internal) [S50] | Pair Kyo with the user's server | RPC commands | Yes | Yes, in principle | Unsupported; breaks without notice |

## Privacy, cost, and App Review

- Privacy: Kyo's AI features run on device today. Each route here sends Task text to Anthropic, OpenAI, or the user's own computer. The share sheet and Shortcuts routes keep that an explicit user action per Task. The HTTP routes make Kyo the sender.
- App Review guideline 5.1.2(i): "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so" [S31]. The HTTP routes need a consent step and a privacy-label update. Inference: the share sheet, being user-initiated system UI, is the usual way to stay clear of this, but I didn't find Apple text that says so.
- Credentials: a routine token or API key in Kyo belongs in the Keychain. The routine token's scope is narrow by design (one routine, no read access) [S6]. An API key is not narrow.
- Cost: routines draw down the user's Claude subscription [S5]. API routes bill the user's developer account per token, or Kyo's with App Attest [S11]. The share sheet costs nothing beyond the user's existing plan.
- Safety: a routine runs with no approval prompts and acts as the user on GitHub and connectors [S5]. A mistyped or half-finished Task sent by a stray tap would run. Kyo should confirm before sending.

## Open questions for the owner

1. Which Tasks is this for? Coding work in a repository (Claude Code, Codex, T3 Code), or any errand (the chat apps)? The answer decides between the routine route and the share sheet.
2. Is sending Task text off the device acceptable for Kyo at all, given the on-device stance for memos? If yes, is a per-Task explicit action (share sheet) the limit, or may Kyo send by HTTP after one-time consent?
3. Is this for the owner's own use or for every Kyo user? Pasting a routine URL and token is reasonable for one person and a hard sell in a general release.
4. Should Kyo show anything after the handoff: a "sent to Claude" mark on the Task, a link to the session, or nothing? Should a handed-off Task still carry forward until checked off?
5. For the routine route: confirm with Anthropic's terms that a third-party app storing a user's own routine token is acceptable, since the docs describe scripts and internal tools rather than consumer apps.
6. Would the reverse direction serve better: a Kyo App Intent that returns today's Tasks, so any agent or Shortcut pulls from Kyo and Kyo integrates with nothing?
7. Does the Watch need this, or is it enough on iPhone and iPad?
8. Worth a device test before any spec: does the ChatGPT iOS app accept shared text, does "Ask Claude" return output to a Shortcut, and does the T3 Code App Store build behave as its source reads?

## Not verified

- Whether the Claude iOS app registers a URL scheme, and whether any Claude link carries a prompt. `claude.ai/new?q=` is from secondary sources only and reported removed.
- The exact wording of Anthropic's help articles [S1][S2], which I read through a summarizing fetch. Whether "Ask Claude" passes its answer to the next Shortcut action.
- Everything about the ChatGPT iOS app's own Shortcuts actions, share extension, and URL scheme (`help.openai.com` returned 403).
- Whether a public REST API exists for creating Codex Cloud tasks. None appears in the documentation index I read.
- Whether `@codex` on a GitHub issue, as opposed to a pull request, starts work.
- The workspace agent trigger's response format and plan availability beyond what the token page says.
- Whether Sign in with ChatGPT can work in an iOS app.
- T3 Code's share and deep-link behavior on a real device, and whether the App Store build matches the source I read. Whether some link parameter I didn't find carries a prompt.
- What `openURL` and `ShareLink` can reach on watchOS, and direct HTTPS from the Watch for this purpose.
- That no API lets one app run another app's App Intent. This is an inference from the absence of one in Apple's documentation.
- How App Review treats text sent through the share sheet under guideline 5.1.2(i).

## Sources

- [S1] Anthropic Help Center, "Use Claude app intents, shortcuts, and widgets on iOS": https://support.claude.com/en/articles/10263469-use-claude-app-intents-shortcuts-and-widgets-on-ios
- [S2] Anthropic Help Center, "Use Claude with iOS apps": https://support.claude.com/en/articles/11869619-use-claude-with-ios-apps
- [S3] Claude Code docs, "Claude Code on mobile": https://code.claude.com/docs/en/mobile
- [S4] Claude Code docs, "Launch sessions from links": https://code.claude.com/docs/en/deep-links
- [S5] Claude Code docs, "Automate work with routines": https://code.claude.com/docs/en/routines
- [S6] Claude Platform docs, "Trigger a routine through the API": https://platform.claude.com/docs/en/api/claude-code/routines-fire
- [S7] Claude Code docs, "Desktop", Sessions from Dispatch: https://code.claude.com/docs/en/desktop#sessions-from-dispatch
- [S8] Claude Code docs, "Push events into a running session with channels": https://code.claude.com/docs/en/channels
- [S9] Claude Code docs, "Run Claude Code programmatically": https://code.claude.com/docs/en/headless
- [S10] Claude Platform docs, "Authentication": https://platform.claude.com/docs/en/manage-claude/authentication
- [S11] Claude Platform docs, "App Attest for iOS and macOS apps": https://platform.claude.com/docs/en/manage-claude/app-attest
- [S12] Claude Platform docs, "Claude Managed Agents overview" and "Start a session": https://platform.claude.com/docs/en/managed-agents/overview and https://platform.claude.com/docs/en/managed-agents/sessions
- [S13] Claude Code docs, "Agent SDK overview": https://code.claude.com/docs/en/agent-sdk/overview
- [S14] Claude Code docs, "Claude Code GitHub Actions": https://code.claude.com/docs/en/github-actions
- [S15] Claude Code docs, "Claude Code in Slack": https://code.claude.com/docs/en/slack
- [S16] OpenAI, ChatGPT and Codex changelog, 2026-05-25 iOS entry: https://learn.chatgpt.com/docs/changelog#codex-2026-05-25-mobile
- [S17] Apple Support, "Use Apple Intelligence in Shortcuts on iPhone or iPad": https://support.apple.com/guide/shortcuts/use-apple-intelligence-in-shortcuts-tpg3vrvwmclv/ios
- [S18] OpenAI docs, "ChatGPT desktop app commands", Deep links: https://learn.chatgpt.com/docs/reference/commands
- [S19] OpenAI docs, "Codex Cloud": https://learn.chatgpt.com/docs/cloud
- [S20] OpenAI docs, "Command line options", `codex cloud`: https://learn.chatgpt.com/docs/developer-commands?surface=cli#cli-codex-cloud
- [S21] OpenAI docs, "Codex Remote" and "Remote connections": https://learn.chatgpt.com/docs/remote and https://learn.chatgpt.com/docs/remote-connections
- [S22] OpenAI docs, "Scheduled tasks": https://learn.chatgpt.com/docs/automations
- [S23] OpenAI docs, "Authenticate with Workspace Agent access tokens": https://developers.openai.com/workspace-agents/authentication
- [S24] OpenAI docs, "Access tokens": https://learn.chatgpt.com/docs/enterprise/access-tokens
- [S25] Apple, ShareLink: https://developer.apple.com/documentation/swiftui/sharelink
- [S26] Apple, OpenURLIntent: https://developer.apple.com/documentation/appintents/openurlintent
- [S27] Apple Support, "Run a shortcut from a URL": https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios
- [S28] Apple Support, "Use x-callback-url with Shortcuts": https://support.apple.com/guide/shortcuts/use-x-callback-url-apdcd7f20a6f/ios
- [S29] Apple, UIApplication.open(_:options:completionHandler:): https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)
- [S30] Apple, UIApplication.canOpenURL(_:): https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)
- [S31] Apple, App Review Guidelines, 5.1.2 Data Use and Sharing: https://developer.apple.com/app-store/review/guidelines/
- [S32] Apple, WKApplication.openSystemURL(_:): https://developer.apple.com/documentation/watchkit/wkapplication/opensystemurl(_:)
- [S33] Apple, OpenURLAction: https://developer.apple.com/documentation/swiftui/openurlaction
- [S34] OpenAI API docs, "Background mode": https://developers.openai.com/api/docs/guides/background
- [S35] OpenAI docs, "Codex SDK": https://learn.chatgpt.com/docs/codex-sdk
- [S36] OpenAI docs, "Codex App Server", Auth endpoints: https://learn.chatgpt.com/docs/app-server
- [S37] OpenAI docs, "Sign in with ChatGPT" (combined export): https://developers.openai.com/siwc/llms-full.txt
- [S38] OpenAI docs, "Review GitHub pull requests with Codex": https://learn.chatgpt.com/docs/third-party/github
- [S39] OpenAI docs, "Codex GitHub Action": https://learn.chatgpt.com/docs/github-action
- [S40] OpenAI docs, "Use Codex in Linear": https://learn.chatgpt.com/docs/third-party/linear
- [S41] OpenAI docs, "Use ChatGPT in Slack": https://learn.chatgpt.com/docs/third-party/slack
- [S42] T3 Code README: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/README.md
- [S43] T3 Code, `apps/mobile/app.config.ts` (share extension, URL scheme): https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/apps/mobile/app.config.ts
- [S44] T3 Code, `apps/mobile/src/Stack.tsx` (link paths, share presentation): https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/apps/mobile/src/Stack.tsx
- [S45] T3 Code, `apps/mobile/src/features/sharing/IncomingShareProvider.tsx`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/apps/mobile/src/features/sharing/IncomingShareProvider.tsx
- [S46] T3 Code, `docs/user/remote-access.md`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/docs/user/remote-access.md
- [S47] T3 Code, `apps/mobile/src/App.tsx` and `src/features/shortcuts/appShortcuts.ts`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/apps/mobile/src/App.tsx
- [S48] T3 Code, `apps/desktop/src/app/DesktopClerk.ts` (`open-url` handler): https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/apps/desktop/src/app/DesktopClerk.ts
- [S49] T3 Code, `docs/internals/remote.md`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/docs/internals/remote.md
- [S50] T3 Code, `docs/internals/environment-auth.md`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/docs/internals/environment-auth.md
- [S51] T3 Code, `apps/server/src/cli/auth.ts`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/apps/server/src/cli/auth.ts
- [S52] T3 Code, `packages/contracts/src/environmentHttp.ts`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/packages/contracts/src/environmentHttp.ts
- [S53] T3 Code, `apps/server/src/mcp/McpHttpServer.ts`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/apps/server/src/mcp/McpHttpServer.ts
- [S54] T3 Code, `apps/server/src/cli/app.ts`: https://github.com/pingdotgg/t3code/blob/3e6b45028ceec5820dacb37dc3852470ebdc9411/apps/server/src/cli/app.ts
