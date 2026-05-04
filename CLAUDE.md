# OllamaBob - Claude Code Guide

This is the Claude-facing project guide. For task execution, read it with `AGENTS.md` and `docs/CURRENT_HANDOFF.md`.

## What This Is

OllamaBob is a native macOS menu-bar assistant that runs locally. It talks directly to Ollama over the native `/api/chat` endpoint, owns its agent loop in Swift, executes first-party tools, persists local state in SQLite through GRDB, and uses native approval dialogs before risky actions.

Current app version: `1.0.56`

## Current Product State

Shipped capabilities:

- SwiftUI/AppKit menu-bar app with Bob's desk window and avatar-only mode.
- Local Ollama chat with `stream: false`.
- Conversation persistence, conversation manager, search, pinning, rename, and delete.
- First-party tools for files, shell, git, web search, Apple Mail checks and triage previews, phone calls, rich presentation, OCR/media, utilities, YouTube, clipboard, AppleScript, and memory.
- Rich presentation through one `present` tool and `PresentationService`.
- Naughty Bob v1 as a per-conversation uncensored mode.
- Jarvis phone tools gated by Preferences, `JARVIS_API_KEY`, and `OPERATOR_API_SECRET`; outbound recap calls can include recent OllamaBob session context plus earlier-work highlights for the phone persona.
- Jarvis call supervision tools (`phone_list_calls`, `phone_get_transcript`, `phone_inject`) use the local daemon's authenticated HTTP routes; `phone_inject` requires modal approval per injection.
- Live Call view (rebuilt) shows the active Jarvis call; post-call action items are extracted from the transcript and rendered as tappable chips that hand off to Bob's agent loop.
- Local Jarvis webhook receiver registers `call.ended` and `call.action-items.ready` callbacks with the daemon, refreshes Live Call state through notifications, and deregisters best-effort on quit.
- Mumbai Bob image avatar.
- Bob's Desk status strip surfaces Mac context, Code Companion mode, walkie-talkie state, and Focus Guardian state when active.
- Clipboard Cortex stack-trace summaries and walkie-talkie transcripts can submit directly into the active chat.
- Untrusted-output taint protection disables write/action tools after file, web, mail, clipboard, YouTube-search, or screen-OCR data enters a turn until the user sends a fresh message or types `/lift`.
- Local Jarvis address book aliases from env vars, JSON maps, and VCF exports such as `~/Downloads/bobs_contacts.vcf`.
- Bundled Bob voice clips and persona-aware avatar behavior.
- Long-running shell: idle timer (default 60s, clamped 5–600s) + hard cap (default 1800s/30min, clamped 10–7200s); SIGTERM→SIGKILL ladder with configurable grace period (default 2s).
- Shell optional args `idle_timeout_seconds` and `max_total_seconds` allow per-call timeout tuning.
- Live stdout/stderr streaming via `availableData` (fixes silent macOS pipe buffering regression); ToolActivityRow updates in real time.
- Tool wall time excluded from the 120s agent-loop budget.
- Cancel button (`Cmd-.`) and Stop toggle on the Send button; cancel kills in-flight ProcessRunners via the active-tool registry.
- Tool-call-only assistant turns render inline in the full-chat transcript; `thinking` field renders as a collapsible inline strip.
- Shell runs via `/bin/zsh -lc` (login shell) so Homebrew and user PATH entries are available when launched from Finder/Dock.
- `build.sh` refuses silent fallback to ad-hoc signing, preserving Keychain "Always Allow" grants across builds.

Authoritative current handoff: `docs/CURRENT_HANDOFF.md`

Historical implementation plans and old handoffs are in `archive/`.

## Non-Negotiable Architecture Rules

Do not change these without explicit user approval and evidence:

- Native SwiftUI/AppKit macOS app.
- Direct HTTP to Ollama at `localhost:11434`.
- Native `/api/chat`, not `/v1/chat/completions`.
- Agent loop in Swift, no external agent runtime.
- No Python subprocess, LangChain/LangGraph, Hermes, MCP runtime, Electron, Node, or Docker in the app runtime.
- `stream: false` for all Ollama requests.
- Flat tool parameter schemas.
- SQLite via GRDB for persistence.
- Native approval dialogs for side effects.
- App Store distribution remains out of scope.

## Current Model Configuration

| Setting | Value |
|---------|-------|
| Primary model | `gemma4:e4b` |
| Fallback model | `qwen3:14b` |
| Compaction model | `qwen3:14b` |
| Uncensored default | `huihui_ai/qwen3-abliterated:8b` |
| Context size | user-configurable `num_ctx` snap points |
| Stream | `false` |

Uncensored mode does not silently fall back to the normal model stack.

## Approval Policy

Read-only tools may run silently. Writes and real-world side effects require modal approval unless the user has explicitly changed that tool badge in Preferences.

Examples that require approval:

- `write_file`
- `move_file`
- `create_directory`
- `clipboard_write`
- `applescript`
- `mail_check`
- `mail_triage`
- `phone_call`
- `youtube_download`
- image conversion or other file-writing tools

Examples that are silent:

- `read_file`
- `list_directory`
- `search_files`
- `git_status`
- `git_diff`
- `web_search`
- `weather`
- `unit_convert`
- `ocr`
- `speak`
- `clipboard_read`
- `remember`
- `list_facts`
- `phone_status`

Always preserve forbidden-command handling and path policy.
Preferences tool badges are persisted per-tool `Auto` / `Ask` / `Deny` overrides. `Deny` maps to forbidden, `Ask` maps to modal approval, and `Auto` may only run silently when path policy and forbidden shell-command checks also allow it.

## Ollama API Notes

Use real captured behavior from `samples/` and current source over old docs.

Important points:

- Tool call arguments can arrive as either JSON objects or strings, depending on turn/model behavior.
- `options.num_ctx` belongs in the native `/api/chat` request body.
- Tool results use native Ollama message shapes, not OpenAI-compatible `tool_call_id` assumptions.
- Do not enable streaming without first proving Gemma tool calls work correctly under streaming.

## Build And Test

Run from `OllamaBob/`:

```bash
swift build
swift test
./build.sh --run
```

`build.sh` assembles `build/OllamaBob.app`, copies the SPM resource bundle, writes the app plist, and ad-hoc signs the bundle so local launches work after framework changes.

## Version And RAG Gates

For every user-visible Bob change, bump the visible app version before handoff. Keep these in sync:

- `OllamaBob/OllamaBob/AppConfig.swift` (`appVersion`, `appBuild`)
- `OllamaBob/build.sh` (`CFBundleShortVersionString`, `CFBundleVersion`)
- `README.md`
- `CLAUDE.md`
- `AGENTS.md`
- `docs/CURRENT_HANDOFF.md`

Before non-trivial work, search the Claude OS project KBs with the `ollamaBob-` filter when the tools or local API are available. After code or active-doc changes, update Claude OS with the new project memory/docs and refresh `ollamaBob-project_index` when code changed. Claude OS is development tooling only; do not add MCP, watcher, Python, or other Claude OS dependencies to the OllamaBob app runtime.

## Decision Log

| Date | Decision | Reason |
|------|----------|--------|
| 2026-04-06 | Use `/api/chat` instead of `/v1/chat/completions` | Native endpoint better matches Ollama tool calling and `num_ctx`. |
| 2026-04-06 | Keep the agent loop in Swift | Avoids IPC and external runtime complexity. |
| 2026-04-06 | Keep `stream: false` | Gemma tool calls were unreliable with streaming. |
| 2026-04-06 | Use `qwen3:14b` as fallback | It is available locally and matches the flat-schema tool contract. |
| 2026-04-09 | V2 scope shipped incrementally | Personas, memory, onboarding, tools, voice, and UI polish landed over V2.x. |
| 2026-04-17 | Native tool expansion shipped | OCR, speak, weather, units, image conversion, and YouTube tools were added without new SPM dependencies. |
| 2026-04-18 | AppleScript/TCC requires usage strings | macOS accepts but then denies Apple events without `NSAppleEventsUsageDescription`. |
| 2026-04-19 | Rich presentation uses one `present` pipeline | HTML, URL, file, and transcript artifact chips share `PresentationService`. |
| 2026-04-20 | Naughty Bob v1 is a mode inside the current app | It keeps persistence/settings unified and disables tools/compaction while active. |
| 2026-04-20 | Jarvis phone calls require two secrets | App-side `/call/*` requests send both `X-Jarvis-Key` and `x-operator-secret`. |
| 2026-05-01 | Shell idle timer + hard cap replace fixed 30s timeout | Allows long builds/installs to complete; `idle_timeout_seconds` and `max_total_seconds` args give per-call control. |
| 2026-05-01 | Tool wall time excluded from agent-loop budget | Prevents long shell commands from racing the 120s model timeout. |
| 2026-05-01 | `availableData` for shell pipe reads | `readData(ofLength:)` silently buffered on macOS pipes; `availableData` delivers incremental output correctly. |
| 2026-05-01 | Login shell for ShellTool | `/bin/zsh -lc` ensures `/opt/homebrew/bin` is on PATH for Finder/Dock launches. |

## Active Docs

- `README.md`: human-facing setup and overview.
- `AGENTS.md`: general agent workflow, structure, and guardrails.
- `docs/CURRENT_HANDOFF.md`: current state and next-session handoff.
- `docs/OPERATOR_QA.md`: manual QA checklist.
- `docs/ARCHITECTURE_NOTES.md`: active architecture notes.
- `archive/README.md`: index of historical docs.

When docs conflict, prefer this order:

1. `docs/ACTIVE_EXECUTION_PLAN.md` if present
2. `docs/CURRENT_HANDOFF.md`
3. `AGENTS.md`
4. `CLAUDE.md`
5. archived historical docs
