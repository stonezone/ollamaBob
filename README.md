# OllamaBob

OllamaBob is a native macOS menu-bar assistant for local Ollama models. It is a SwiftUI/AppKit app that talks directly to `http://localhost:11434/api/chat`, owns its agent loop in Swift, runs first-party tools, and stores local data in SQLite through GRDB.

Current app version: `1.0.3`

## Quick Start

Requirements:

- macOS 14+
- Xcode command-line tools / SwiftPM
- Ollama running locally on `http://localhost:11434`

Recommended models:

```bash
ollama pull gemma4:e4b
ollama pull qwen3:14b
```

Optional uncensored-mode model:

```bash
ollama pull huihui_ai/qwen3-abliterated:8b
```

Build, test, and run from `OllamaBob/`:

```bash
swift build
swift test
./build.sh --run
```

Useful alternatives:

```bash
swift run OllamaBob
./build.sh
```

## Current Features

- Local Ollama chat over the native `/api/chat` endpoint with `stream: false`.
- Menu-bar app with Bob's desk/chat window, avatar-only mode, conversation history, and persistent local storage.
- Rich presentation through `present(kind=html|url|file)` and transcript artifact chips.
- First-party tool catalog for files, shell, git, web search, phone calls, presentation, OCR/media, utility commands, YouTube, clipboard, AppleScript automation, and memory.
- Naughty Bob v1 as a per-conversation uncensored mode. Tools and compaction are disabled while uncensored mode is active, and the app does not silently fall back to the standard model stack.
- Jarvis phone tools behind explicit Preferences gating and a modal approval for outbound calls.

## Safety Model

The app sandbox is off because Bob can run local tools. Safety depends on first-party tool boundaries, approval policy, path policy, and output caps.

- Read-only tools can run silently.
- Writes, file moves, clipboard writes, AppleScript, YouTube downloads, and phone calls require modal approval.
- Forbidden shell shapes such as `sudo`, destructive root deletes, and download-execute chains are blocked.
- Sensitive paths route through path policy before execution.
- Tool output is wrapped as untrusted text before it is sent back to the model.

## Optional Services

Set these through Preferences or a local gitignored `.env` file:

- `BRAVE_API_KEY` enables `web_search`.
- `JARVIS_API_KEY` and `OPERATOR_API_SECRET` enable Jarvis phone routes.
- `ZACK_PERSONAL_NUMBER`, `GLENNEL_PERSONAL_NUMBER`, and `jarvis-address-book.local.json` provide local phone aliases.
- `ELEVENLABS_API_KEY` and `OLLAMABOB_VOICE_ID` are only needed when regenerating bundled voice clips.

External CLI dependency:

```bash
brew install yt-dlp
```

`yt-dlp` is required for YouTube search/download tools. macOS-native helpers such as `sips`, `units`, and `osascript` do not need extra installs.

## Documentation Map

Start here for active project work:

- [AGENTS.md](AGENTS.md): agent rules, architecture guardrails, repo layout, and build commands.
- [CLAUDE.md](CLAUDE.md): Claude Code guide and sticky project decisions.
- [docs/CURRENT_HANDOFF.md](docs/CURRENT_HANDOFF.md): current state, local operator notes, verification commands, and backlog.
- [docs/OPERATOR_QA.md](docs/OPERATOR_QA.md): manual QA checklist for the shipped app.
- [docs/ARCHITECTURE_NOTES.md](docs/ARCHITECTURE_NOTES.md): current architecture notes that are still active.

Historical plans, superseded handoffs, and old review memos live in [archive/](archive/). They are kept for decision history, not as the starting point for new work.

## Troubleshooting

- `Ollama not running`: start Ollama or run `ollama serve`.
- Missing `web_search`: add `BRAVE_API_KEY`.
- Missing phone tools: enable Jarvis phone service and set both Jarvis secrets.
- Missing YouTube tools: install `yt-dlp` and restart the app.
- Missing uncensored model: pull the configured tag shown in the app banner.
- macOS blocks Desktop/Documents/Downloads access: approve the system privacy prompt and retry.
