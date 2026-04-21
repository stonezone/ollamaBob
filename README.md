# OllamaBob

Native macOS menu-bar AI assistant for local Ollama models.

OllamaBob runs as a SwiftUI/AppKit app, talks directly to Ollama over `http://localhost:11434`, owns its own Swift agent loop, and keeps local persistence in SQLite via GRDB.

## Current Highlights

- Current app version: `1.0.3`
- Primary model: `gemma4:e4b`
- Fallback model: `qwen3:14b`
- Rich presentation pipeline:
  - `present(kind=html)` opens Bob's in-app rich view window
  - `present(kind=url)` opens the default browser
  - `present(kind=file)` opens the default macOS app for that file
  - assistant-message artifact chips route through the same presentation service
- Naughty Bob v1:
  - master uncensored-mode setting
  - per-conversation `UNCENSORED` toggle/badge
  - tools forced off in uncensored mode
  - no silent fallback to the normal model stack
  - compaction skipped in uncensored mode

## Setup

Requirements:

- macOS 14+
- local Ollama server on `http://localhost:11434`
- Xcode command-line tooling / SwiftPM toolchain

Recommended local models:

```bash
ollama pull gemma4:e4b
ollama pull qwen3:14b
```

Optional for uncensored-mode conversations:

```bash
ollama pull huihui_ai/qwen3-abliterated:8b
```

Optional external services:

- `BRAVE_API_KEY` — enables the `web_search` tool
- `JARVIS_API_KEY` — inner call API key for Jarvis `/call/*`
- `OPERATOR_API_SECRET` — outer operator secret also required by the current Jarvis `/call/*` contract

External CLI dependencies (install separately via Homebrew):

```bash
brew install yt-dlp   # required for youtube_search / youtube_download
```

Built-in tools that use macOS native binaries (`sips`, `units`, `osascript`) require no extra installs.

## Build And Run

Run from `OllamaBob/`:

```bash
swift build
swift test
./build.sh --run
```

Useful commands:

```bash
swift run OllamaBob
./build.sh
```

## Tools

Bob ships with 20+ first-party tools across these categories:

| Category | Tools |
|----------|-------|
| Files | `read_file`, `write_file`, `move_file`, `create_directory`, `list_directory`, `search_files` |
| Shell | `shell` (approval depends on command) |
| Git | `git_status`, `git_diff` |
| Web | `web_search` |
| Phone | `phone_call`, `phone_hangup`, `phone_status` *(gated by Jarvis settings and both Jarvis secrets)* |
| Presentation | `present` (html, url, file) |
| Media | `ocr`, `speak`, `image_convert` |
| Utility | `weather`, `unit_convert` |
| YouTube | `youtube_search`, `youtube_download` *(requires `yt-dlp` on PATH)* |
| Clipboard | `clipboard_read`, `clipboard_write` |
| Automation | `applescript` |
| Memory | `remember`, `list_facts`, `forget` |

## Enabling Uncensored Bob

There are two switches:

1. Enable the feature globally in Preferences.
   - `Preferences -> Models -> Enable Uncensored Mode`
2. Enable it for the current conversation.
   - click the `UNCENSORED` pill in the chat UI

Notes:

- If the configured uncensored model is not installed, Bob shows a banner with the exact `ollama pull ...` command.
- Uncensored mode is per-conversation and persists with that conversation.
- Tools are intentionally disabled in uncensored mode in v1.

## Enabling Jarvis Phone Tools

Jarvis phone tools stay hidden until all of these are true:

1. `Preferences -> Tools -> Enable Jarvis phone service` is on
2. `Jarvis API key` is filled in
3. `Operator secret` is filled in

Current request contract:

- `phone_call`, `phone_hangup`, and `phone_status` send `X-Jarvis-Key` from `JARVIS_API_KEY`
- those same routes also send `x-operator-secret` from `OPERATOR_API_SECRET`
- `GET /health` is only a reachability check; it does not validate either secret

Local developer convenience:

- when the Preferences fields are blank, the app will seed them from the repo-root `.env` on launch if it can find one
- that fallback is for local builds only; the persisted Preferences values remain the real source of truth after seeding

Optional local call shortcuts:

- Bob now also checks repo-local destination hints before handing a call to the daemon:
  - `ZACK_PERSONAL_NUMBER`
  - `GLENNEL_PERSONAL_NUMBER`
  - `jarvis-address-book.local.json`
- `jarvis-address-book.local.json` is gitignored and intended for personal aliases such as `me`, `wife`, or household contacts.
- Start from the checked-in template:
  - [jarvis-address-book.example.json](jarvis-address-book.example.json)

Canonical public-site HTML location:

- canonical live file:
  - `/home/zackj26/public_html/ollamabob/index.html`
- synced secondary copy:
  - `/home/zackj26/public_html/cleardeskshop.com/ollamabob/index.html`

## Jarvis Calling Rules

This is the live prompt/operator policy Bob follows for phone calls:

### Current live OllamaBob phone tools

- `phone_call`
- `phone_hangup`
- `phone_status`

The Jarvis daemon exposes more call-related features than OllamaBob currently uses, including:

- active/recent call listing
- mid-call message injection
- mid-call supervision
- approval-request queues
- contacts APIs
- follow-up APIs
- memory search APIs

Those are daemon capabilities, not yet first-class OllamaBob tools.

### Caller identity

Supported caller identities today:

- `bob`
- `buddy`
- `zack`
- `glennel`
- `glennel_naggy`

Prompt policy:

- if the user does not specify a caller persona, Bob should default to `bob`
- `jarvis` is not a real daemon caller identity; it is not valid on the wire
- if the user asks for an unsupported caller identity, Bob should ask for clarification rather than silently substituting another persona
- `buddy` is a caller persona, not automatically a person to dial

### Destination resolution

The daemon accepts `to` as either:

- a raw E.164 number
- a known contact name

Behavior:

- explicit E.164 numbers win and bypass contact lookup
- bare 10-digit or 11-digit North American numbers are normalized client-side to E.164 before the request is sent
- contact-name lookup is daemon-side, case-insensitive, and exact-match
- `call me` is now resolved client-side from local config/address-book before the request is sent
- Bob checks local aliases in this order before falling back to daemon contact lookup:
  - embedded or bare phone number in the destination text
  - local env shortcuts (`ZACK_PERSONAL_NUMBER`, `GLENNEL_PERSONAL_NUMBER`)
  - `jarvis-address-book.local.json`
- prompt policy in the app now explicitly tells Bob to pass `to='me'` for `call me` requests instead of asking for the operator number again
- if the user says something ambiguous like `call buddy`, Bob should clarify whether `buddy` is the caller persona or the callee
- if the user says a relationship label such as `my wife`, Bob should not invent a new contact; he should map it only if that alias is a known client-side policy or ask a clarifying question

### How to ask Bob to place calls

Best prompt shape:

- `Call <person or number> [as <caller>] and <purpose>.`

Examples:

- `Call Glennel and tell her the pickup is at 5.`
- `Call me and tell me dinner is ready.`
- `Call +18082925669 and ask how the day is going.`
- `Call Glennel as zack and tell her I'm running late.`
- `Call me as buddy and tell me to get back to work.`
- `Call +18082925669 as glennel_naggy and remind me about the appointment.`

If the user omits the purpose and the task is not already obvious from context, Bob should ask 1-2 short follow-up questions before placing the call.

### Purpose / mission brief

- `purpose` is the one-line objective Bob sends for the call
- it is required by OllamaBob's current `phone_call` tool contract
- if the user says only `call Glennel` and the mission is not already obvious from context, Bob should ask 1-2 short clarifying questions before placing the call
- Bob should not auto-fill a vague generic purpose when the human intent is underspecified

### Approval / execution expectations

- approval should clearly state the caller persona, destination, and reason for the call
- if a contact name resolves to a number, the confirmation UX should prefer showing the resolved number
- Bob should mention the returned `callSid` after a successful call so the user can ask for status or hang up
- status polling is user-driven in v1; Bob should use `phone_status` when asked, not auto-poll continuously

### Current limitations

- no inbound-call support
- no historical transcript endpoint in OllamaBob yet
- no first-class call supervision UI in OllamaBob yet
- no first-class contacts/follow-ups/memory-search UI in OllamaBob yet
- phone tools are disabled in uncensored mode on the OllamaBob side

## Troubleshooting

### Jarvis `401 Unauthorized`

- `Jarvis operator secret rejected (401 Unauthorized)` means the outer operator auth failed
- `Jarvis call API key rejected (401 unauthorized)` means the inner call auth failed
- if `/health` passes but calls still fail, the most likely problem is one of the two secrets is missing or mismatched

### Jarvis Tools Missing

If `phone_call`, `phone_hangup`, or `phone_status` do not appear:

1. make sure Jarvis phone is enabled in Preferences
2. make sure both secrets are present
3. make sure the base URL still points at the daemon
4. relaunch the app if you just added values to `.env` and expect the initial seeding path to pick them up

### Jarvis Contact Lookup Misses

If Bob says the contact was not found:

1. give Bob an explicit E.164 number such as `+18082925669`
2. or add the alias to `jarvis-address-book.local.json`
3. or make sure the daemon-side contact exists in the Jarvis address book

If you type a plain local number like `8082925669`, Bob now normalizes it to `+18082925669` before sending it to Jarvis.

### macOS File Opens Time Out

- first access to Desktop/Documents/Downloads can trigger a macOS privacy prompt
- approve that prompt, then retry
- a shell timeout during that first open often means Bob was blocked on TCC, not that the file-open path itself is broken

## Documentation Map

- [AGENTS.md](AGENTS.md): repo layout, commands, coding/testing conventions
- [CLAUDE.md](CLAUDE.md): project guide and operating context for coding-agent sessions
- [docs/CURRENT_HANDOFF.md](docs/CURRENT_HANDOFF.md): current technical handoff, model-switch guidance, and rollout state
- [docs/OPERATOR_QA.md](docs/OPERATOR_QA.md): manual QA checklist and operator gotchas for live app testing
- [docs/MULTIMEDIA_BOB.md](docs/MULTIMEDIA_BOB.md): rich presentation design/spec and implemented acceptance coverage
- [OllamaBob/NAUGHTYBOB_PLAN.md](OllamaBob/NAUGHTYBOB_PLAN.md): Naughty Bob v1 plan and shipped behavior

## Repository Layout

```text
ollamaBob/
├── README.md
├── AGENTS.md
├── CLAUDE.md
├── docs/
├── samples/
├── archive/
└── OllamaBob/
    ├── Package.swift
    ├── build.sh
    ├── OllamaBob/
    └── Tests/
```
