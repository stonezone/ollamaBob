# OllamaBob - Agent Guide

This file is for AI coding agents. Read it first when picking up the project cold.

## Required Read Order

For any non-trivial task, read in this order:

1. `AGENTS.md`
2. `docs/CURRENT_HANDOFF.md`
3. `docs/ACTIVE_EXECUTION_PLAN.md` if it exists

If an active execution plan exists, it wins over general guidance in this file.

## Project Overview

OllamaBob is a native macOS menu-bar AI assistant that runs locally. It is a SwiftUI/AppKit app targeting macOS 14+, built with Swift Package Manager. The app talks directly to the local Ollama native `/api/chat` endpoint, owns its agent loop in Swift, executes first-party tools, and shows native approval dialogs before risky actions.

Key constraints:

- No external agent runtime.
- No Python subprocess, Electron, or Docker in the runtime.
- No MCP client/server in the app runtime.
- No streaming; Ollama requests use `stream: false`.
- Use the native Ollama `/api/chat` endpoint, not `/v1/chat/completions`.

## Current State

Current visible app version: `1.0.3`

Current model defaults:

- Primary: `gemma4:e4b`
- Fallback: `qwen3:14b`
- Compaction: `qwen3:14b`
- Uncensored default: `huihui_ai/qwen3-abliterated:8b`

Current shipped surface:

- Bob's desk/chat window and avatar-only mode.
- Conversation persistence and history management.
- Rich presentation via `present(kind=html|url|file)`.
- First-party tools for files, shell, git, web, phone, presentation, media, utility, YouTube, clipboard, AppleScript, and memory.
- Naughty Bob v1 as a per-conversation uncensored mode with tools and compaction disabled.
- Jarvis phone tools gated by Preferences and both Jarvis secrets.

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
