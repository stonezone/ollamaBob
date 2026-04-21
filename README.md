# OllamaBob

Native macOS menu-bar AI assistant for local Ollama models.

OllamaBob runs as a SwiftUI/AppKit app, talks directly to Ollama over `http://localhost:11434`, owns its own Swift agent loop, and keeps local persistence in SQLite via GRDB.

## Current Highlights

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
