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

Optional web search:

- set `BRAVE_API_KEY` in the repo-root `.env`

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
