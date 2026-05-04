# OllamaBob - Agent Guide

This file is for AI coding agents. Read it first when picking up the project cold.

## Required Read Order

For any non-trivial task, read in this order:

1. `AGENTS.md`
2. `docs/CURRENT_HANDOFF.md`
3. `docs/ACTIVE_EXECUTION_PLAN.md` if it exists

If an active execution plan exists, it wins over general guidance in this file.

## Claude OS / Codex OS Workflow

Claude OS is project-specific development RAG, not part of the OllamaBob runtime. Do not add MCP, Python, watcher, or Claude OS dependencies to the shipped app.

For this repository, the Claude OS project is:

- Project name: `ollamaBob`
- Project path: `/Users/zack/ollamaBob`
- KB filter: `ollamaBob-`
- Expected KBs: `ollamaBob-project_memories`, `ollamaBob-project_profile`, `ollamaBob-project_index`, `ollamaBob-knowledge_docs`

Before any non-trivial code or architecture work:

1. Use the `mcp__code-forge__` tools if they are exposed in the session.
2. If those tools are not exposed, use the local API at `http://localhost:8051`.
3. Search with `kb_filter: "ollamaBob-"` for relevant prior decisions, project profile, and code index entries.
4. Treat fresh repo files and active docs as authoritative when they conflict with stale RAG content.

After code or active-doc changes:

1. Add or update a concise memory in `ollamaBob-project_memories` describing the shipped change and verification.
2. Refresh `ollamaBob-knowledge_docs` when README, AGENTS, CLAUDE, or `docs/` change.
3. Refresh `ollamaBob-project_profile` when architecture, workflow, or constraints change.
4. Refresh `ollamaBob-project_index` when Swift source, tests, or tool contracts change.
5. Run `kb_lifecycle_health` or the equivalent `/api/kb/{name}/lifecycle/health` check when available and report stale or failed indexing.

## Project Overview

OllamaBob is a native macOS menu-bar AI assistant that runs locally. It is a SwiftUI/AppKit app targeting macOS 14+, built with Swift Package Manager. The app talks directly to the local Ollama native `/api/chat` endpoint, owns its agent loop in Swift, executes first-party tools, and shows native approval dialogs before risky actions.

Key constraints:

- No external agent runtime.
- No Python subprocess, Electron, or Docker in the runtime.
- No MCP client/server in the app runtime.
- No streaming; Ollama requests use `stream: false`.
- Use the native Ollama `/api/chat` endpoint, not `/v1/chat/completions`.

## Current State

Current visible app version: `1.0.53`

Current model defaults:

- Primary: `gemma4:e4b`
- Fallback: `qwen3:14b`
- Compaction: `qwen3:14b`
- Uncensored default: `huihui_ai/qwen3-abliterated:8b`

Current shipped surface:

- Bob's desk/chat window and avatar-only mode.
- Conversation persistence and history management.
- Rich presentation via `present(kind=html|url|file)`.
- First-party tools for files, shell, git, web, Apple Mail inbox checks and triage previews, phone, presentation, media, utility, YouTube, clipboard, AppleScript, and memory.
- Batch audio workflows use the larger `batchAudioAgentLoopMaxIterations` / `batchAudioAgentLoopTimeoutSeconds` budget and the batch-continuation guard so album downloads and FLAC-to-MP3 conversions can complete without per-item check-ins.
- Preferences tool badges support persisted per-tool `Auto` / `Ask` / `Deny` overrides, with path policy and forbidden shell-command blocks preserved as non-bypassable floors.
- Naughty Bob v1 as a per-conversation uncensored mode with tools and compaction disabled.
- Jarvis phone tools gated by Preferences and both Jarvis secrets, with bounded recent OllamaBob session context and earlier-work highlights attached to outbound recap calls when useful.
- Jarvis call supervision tools for listing active calls, reading active-call transcripts, and modal-gated mid-call message injection (`phone_inject` requires `modal` approval per injection).
- Live Call view (rebuilt) surfaces the active call; post-call action items are extracted from the transcript and rendered as tappable chips that dispatch a fresh prompt to `AgentLoop`.
- Mumbai Bob image avatar; avatar-only mode behavior unchanged.
- Bob's Desk status strip surfaces Mac context, Code Companion mode, walkie-talkie state, and Focus Guardian state when active.
- Clipboard Cortex stack traces and walkie-talkie transcripts can be submitted into Bob's Desk.
- Untrusted-output taint protection disables write/action tools after file, web, mail, clipboard, YouTube-search, or screen-OCR data enters a turn until the user sends a fresh message or types `/lift`.
- Local Jarvis address book resolves env aliases, JSON alias maps, and VCF exports such as `~/Downloads/bobs_contacts.vcf`.
- Long-running shell: idle timer (default 60s, clamped 5–600s) + hard cap (default 1800s/30min, clamped 10–7200s). SIGTERM→SIGKILL ladder with grace period (default 2s). Optional shell args `idle_timeout_seconds` and `max_total_seconds` tune limits per call.
- Live stdout/stderr streaming via `FileHandle.availableData` (fixes macOS pipe buffering); `ToolActivityRow` live-updates as output arrives.
- Tool wall time excluded from the 120s agent-loop budget; a 30-minute `brew upgrade` does not race the model timeout.
- Cancel/Stop: `Cmd-.` shortcut; Send button toggles to Stop while a turn is in flight; `ToolRegistry` kills in-flight `ProcessRunner`s via SIGTERM→SIGKILL on cancel.
- Tool-call-only assistant turns (no body text) render inline in the full-chat transcript instead of being hidden; `thinking` field renders as a collapsible inline strip when non-empty. Avatar-only mode is unchanged.
- Shell runs via `/bin/zsh -lc` (login shell) so `/opt/homebrew/bin` is on PATH for Finder/Dock launches.
- `build.sh` hard-fails when the signing identity is missing rather than silently falling back to ad-hoc, preserving Keychain "Always Allow" grants across rebuilds.

## Active Task Protocol

Before writing code for a non-trivial change, produce:

1. Concise architecture map
2. Ranked findings with exact file/class references
3. Minimal-change implementation plan
4. Preserved-components list
5. Verification plan

Stay scoped. Prefer additive changes and existing boundaries. Do not introduce new state containers, event buses, parser layers, animation systems, or broad rewrites unless the active plan explicitly allows it.

Stop and report immediately if:

- tests fail and the failure is not understood
- the change requires touching preserved components outside scope
- an implementation needs a speculative rewrite
- a task would change `stream: false`, the agent pipeline, window scene structure, native drag behavior, or per-mode frame persistence without explicit approval

Preserve by default:

- `AgentLoop -> ChatSessionController -> BobsDeskView`
- `stream: false`
- `PresentationService` / `present`
- Jarvis phone tools and auth contract
- approval policy and path policy
- uncensored mode behavior and constraints
- onboarding and Preferences
- Tool Activity window
- avatar pack system and `bobMood`-driven avatar state
- per-mode window persistence and relaunch behavior
- native `performDrag(with:)` drag path
- current main desk window scene structure

## Build And Test

Run from `OllamaBob/`:

```bash
swift build
swift test
swift run OllamaBob
./build.sh
./build.sh --run
```

The app expects Ollama at `http://localhost:11434`.

## Version Policy

Every user-visible Bob change must bump the visible version before handoff. Keep these files synchronized:

- `OllamaBob/OllamaBob/AppConfig.swift` (`appVersion`, `appBuild`)
- `OllamaBob/build.sh` (`CFBundleShortVersionString`, `CFBundleVersion`)
- `README.md`
- `CLAUDE.md`
- `AGENTS.md`
- `docs/CURRENT_HANDOFF.md`

Use patch bumps for normal fixes/features unless the user requests a larger release bump. Run the version consistency test with the normal test suite.

## Project Structure

```text
ollamaBob/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── MEMORY.md
├── .env.example
├── archive/                 # historical plans, old handoffs, review memos
├── docs/                    # active docs only
│   ├── ARCHITECTURE_NOTES.md
│   ├── CURRENT_HANDOFF.md
│   ├── OPERATOR_QA.md
│   └── personas.txt
├── images/
├── samples/
├── tools/
└── OllamaBob/
    ├── Package.swift
    ├── build.sh
    ├── OllamaBob/
    │   ├── Agent/
    │   ├── Tools/
    │   ├── Views/
    │   ├── Models/
    │   ├── Services/
    │   ├── Personality/
    │   ├── Sound/
    │   ├── Persistence/
    │   └── Resources/
    └── Tests/OllamaBobTests/
```

## Folder Responsibilities

- `Agent/`: `AgentLoop`, approval/path policy, Ollama client, tool registry, compaction, output limits, untrusted wrapper.
- `Tools/`: structured model-callable tools plus runtime/catalog/output-store helpers.
- `Views/`: SwiftUI/AppKit UI surfaces, Preferences, approval alerts, rich HTML view, tool activity, conversation manager.
- `Models/`: session state, settings, conversations, messages, tool calls/results, avatar state, rich HTML state.
- `Services/`: app infrastructure that is not model-callable, including presentation and automation probing.
- `Personality/`: prompt composition, operating rules, personas, greetings.
- `Sound/`: bundled audio playback and heartbeat.
- `Persistence/`: GRDB-backed database and schema.

## Approval And Tool Safety

Approval levels:

- `none`: silent execution for read-only operations.
- `modal`: explicit user approval required.
- `forbidden`: never execute.
- User-facing tool permission overrides are `Auto`, `Ask`, and `Deny`; `Auto` may only reduce approval when the path/shell safety floor allows it.

Path policy:

- Allowed without approval: `~/`, `/tmp`, `/var/tmp`, `/Applications`, `/usr/local`
- Requires approval: `/System`, `/Library`, `/private`, `/etc`, `/var`
- Always denied: `/dev`, `/Volumes`

Prefer first-class tools over broad shell commands when an existing structured tool fits.

## Docs Policy

Active docs stay small and current:

- `README.md`
- `AGENTS.md`
- `CLAUDE.md`
- `docs/CURRENT_HANDOFF.md`
- `docs/OPERATOR_QA.md`
- `docs/ARCHITECTURE_NOTES.md`

Superseded plans, completed implementation handoffs, old review notes, and historical prompts belong in `archive/`. If a doc describes what shipped rather than what to do next, archive it and point active docs at `archive/README.md`.

## Git Policy

- Commit in small logical units with short Conventional Commit subjects.
- Do not discard user changes unless explicitly asked.
- Keep root-level project docs intentional. New temporary handoffs and local notes should go under ignored `.local-docs/` or into `archive/` if they need to be committed.
