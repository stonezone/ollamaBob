# OllamaBob — Agent Guide

> This file is for AI coding agents. Read it first when picking up the project cold.  
> For current project state, also read `docs/CURRENT_HANDOFF.md`.  
> When `docs/ACTIVE_EXECUTION_PLAN.md` exists, it is binding for the current task and must be read before any code changes.

## Required Read Order

For any non-trivial task, read in this order:

1. `AGENTS.md`
2. `docs/CURRENT_HANDOFF.md`
3. `docs/ACTIVE_EXECUTION_PLAN.md` (if present)

If `docs/ACTIVE_EXECUTION_PLAN.md` conflicts with a descriptive section of this file, the active execution plan wins for the current task.

## Project Overview

OllamaBob is a native macOS menu-bar AI assistant that runs entirely locally. It is a SwiftUI/AppKit app targeting macOS 14+, built with Swift Package Manager. The app talks directly to a local Ollama server over HTTP at `http://localhost:11434`, owns its own agent loop written in Swift, executes structured tools, and shows native approval dialogs before risky actions.

Key characteristics:
- **No external agent runtime** — the Swift agent loop owns everything.
- **No Python subprocess, no Electron, no Docker** in the runtime.
- **No MCP servers** — all tools are first-party direct implementations.
- **No streaming** — all Ollama requests use `stream: false` (Gemma 4 + streaming + tool calls is known broken).
- **Native `/api/chat` endpoint** — NOT the OpenAI-compatible `/v1/chat/completions` endpoint.

## Active Task Execution Protocol

This section is the no-drift contract for active work.

### Audit-First Rule

Before writing code for a non-trivial change, produce all of the following:

1. Concise architecture map
2. Ranked findings with exact file/class references
3. Minimal-change implementation plan
4. Explicit preserved-components list
5. Verification plan

Do not start coding until these exist.

### Scope Control

- Prefer **additive refactors** over architectural rewrites.
- Extend existing boundaries before inventing new ones.
- Do **not** introduce a new state container, event bus, reducer/store layer, parser/normalization layer, or animation framework unless the active plan explicitly allows it after evidence.
- If a new boundary is proposed, prove why with exact file/class references and compare it against the smallest in-place alternative.
- Do not use “while I’m here” edits.
- Do not do unrelated cleanup during a phase.

### File Ownership and Parallelism

- **One writing agent per file per phase.**
- Do not allow concurrent edits to the same file in different branches/tasks.
- Be especially strict with high-conflict files such as:
  - `OllamaBob/OllamaBob/Views/BobsDeskView.swift`
  - `OllamaBob/OllamaBob/Models/ChatSessionController.swift`
  - `OllamaBob/OllamaBob/Views/ConversationManagerView.swift`
  - any window coordinator/configurator logic
- If sub-agents are available, use them for **read-only audits** or narrowly scoped implementation tasks, not uncontrolled parallel coding.

### Supervisor Rule

When working on a multi-phase task, one supervising agent must own:
- phase order
- scope enforcement
- changed-files review
- preserved-feature review
- merge decisions
- phase advancement

Sub-agents may investigate or implement isolated, approved scope only.

### Phase Gate After Every Implementation Phase

Do all of the following before moving to the next phase:

- `swift build`
- `swift test`
- targeted verification for the active phase
- changed-files list
- rollback note
- preserved-components regression summary
- list of deferred items, if any

### Stop Conditions

Stop and report immediately if any of the following occur:

- failing tests
- edits outside assigned phase scope
- undocumented architectural additions
- attempts to change preserved components without approval
- attempts to change `stream: false`, scene structure, native drag path, or per-mode frame persistence without explicit approval in the active plan
- unclear ownership of active conversation/session state
- any fix that requires speculative rewrite rather than evidenced change

### Preserved Components Default List

Unless the active plan explicitly authorizes a change, preserve:

- current `AgentLoop -> ChatSessionController -> BobsDeskView` pipeline
- `stream: false`
- `PresentationService` / `present`
- Jarvis phone tools
- approvals / path policy
- uncensored mode behavior and constraints
- onboarding / preferences
- Tool Activity window
- avatar pack system and `bobMood`-driven avatar state
- per-mode window persistence / relaunch behavior
- native `performDrag(with:)` drag path
- current main desk window scene structure

## Technology Stack

| Layer | Technology |
|-------|------------|
| Language | Swift 5.9+ |
| Build System | Swift Package Manager (`Package.swift`) |
| UI Framework | SwiftUI + AppKit (hybrid) |
| Persistence | SQLite via GRDB.swift |
| HTTP Client | `URLSession` |
| macOS Target | 14.0+ |
| App Sandbox | OFF (required for `Process()` shell execution) |
| Dock Icon | None (`LSUIElement: true`) |

Single SPM dependency:
- `GRDB.swift` (from: `6.24.0`) — SQLite wrapper.

## Project Structure

The active application lives under `OllamaBob/`. The repo root also contains docs, samples, images, and tooling scripts.

```text
ollamaBob/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── .env
├── .env.example
├── OllamaBob/
│   ├── Package.swift
│   ├── build.sh
│   ├── OllamaBob/
│   │   ├── OllamaBobApp.swift
│   │   ├── AppConfig.swift
│   │   ├── Agent/
│   │   ├── Tools/
│   │   ├── Views/
│   │   ├── Models/
│   │   ├── Services/
│   │   ├── Personality/
│   │   ├── Sound/
│   │   ├── Persistence/
│   │   └── Resources/
│   └── Tests/OllamaBobTests/
├── docs/
├── samples/
├── images/
├── tools/
└── archive/
```

### Source Folder Responsibilities

- **`Agent/`** — `AgentLoop`, `ApprovalPolicy`, `PathPolicy`, `ToolRegistry`, `OllamaClient`, `Preflight`, `ConversationCompactor`, `OutputLimits`, `UntrustedWrapper`.
- **`Tools/`** — structured tools plus tool runtime/catalog/output-store/search support.
- **`Views/`** — `BobsDeskView`, `ChatPanel`, `ChatBubble`, `ConversationManagerView`, `PreferencesView`, `OnboardingView`, `ToolActivityView`, `RichHTMLView`, `ApprovalAlert`, `ArtifactChip`, `ArtifactDetector`, `MemoryIOPanel`, `PreflightErrorView`, `PersonaQuickSwapMenu`, `ConversationSearchBar`.
- **`Models/`** — `ChatSessionController`, `ConversationStoreController`, `AppSettings`, `Conversation`, `Message`, `ToolCall`, `ToolResult`, `ApprovalLevel`, `AvatarStore`, `AvatarPack`, `RichHTMLState`, `JSONValue`, `ProcessMemorySampler`.
- **`Services/`** — `PresentationService`, `AutomationProbe`, `PromptComposerMemoryStore`.
- **`Personality/`** — prompt/persona composition and persona storage.
- **`Sound/`** — audio playback and sayings.
- **`Persistence/`** — GRDB-backed database and schema.

## Build, Test, and Development Commands

Run all commands from the `OllamaBob/` directory.

```bash
swift build
swift run OllamaBob
swift test
./build.sh
./build.sh --run
```

The app expects a local Ollama server at `http://localhost:11434`.

## Model Defaults

Configured in `AppConfig.swift`:
- **Primary:** `gemma4:e4b`
- **Fallback:** `qwen3:14b`
- **Compaction:** `qwen3:14b`
- **Uncensored default:** `huihui_ai/qwen3-abliterated:8b`

## Secrets

Runtime secrets are read from environment variables or `UserDefaults`:

- `BRAVE_API_KEY` — enables the `web_search` tool (optional)
- `JARVIS_API_KEY` — inner Jarvis call API key for `/call/*`
- `OPERATOR_API_SECRET` — outer Jarvis operator secret required alongside `JARVIS_API_KEY` for phone operations
- `ELEVENLABS_API_KEY` + `OLLAMABOB_VOICE_ID` — only needed to re-render voice clips via tooling; shipping app reads pre-rendered audio from resources

Store secrets in a gitignored `.env` at the repo root. Use `.env.example` as the template.

## Code Style Guidelines

- **Indentation:** 4 spaces
- **Naming:** `UpperCamelCase` for types, `lowerCamelCase` for properties and methods
- **File organization:** one primary type per file where practical
- **Clarity:** prefer clear Swift over clever abstractions
- **Safety:** avoid force unwraps in production paths
- **Navigation:** use `// MARK:` where it improves navigation
- **Comments:** add comments only where intent is not obvious from code
- **Formatting:** no formatter/linter is configured; match surrounding style

## Architecture Details

### Agent Loop

`AgentLoop.process(userMessage:history:conversationId:uncensoredMode:)` is the core turn processor:

1. **Preflight** — checks Ollama reachability and model availability on launch
2. **System prompt injection** — `PromptComposer` assembles the system prompt from operating rules, persona, optional user profile, and a live tool cheat sheet
3. **Compaction** — older turns are summarized when the conversation approaches context limits (skipped in uncensored mode)
4. **Ollama request** — `OllamaClient.chat()` with `stream: false`, flat tool schemas, and configured context limits
5. **Tool execution** — validates tool existence/args, applies approval policy, executes, spills large outputs to `ToolOutputStore`, wraps in `<untrusted>` tags, and appends results to history
6. **Iteration cap** — max 10 tool-call iterations per turn; total timeout 120s

### Approval Policy

Three levels:

- `none` — silent execution for approved read-only operations
- `modal` — explicit user approval required
- `forbidden` — never execute

Path policy adds filesystem restrictions:
- Allowed without approval: `~/`, `/tmp`, `/var/tmp`, `/Applications`, `/usr/local`
- Requires approval: `/System`, `/Library`, `/private`, `/etc`, `/var`
- Always denied: `/dev`, `/Volumes`

### Conversation & Persistence

Current architecture describes:
- `ChatSessionController` owning the active transcript, session flow, and message persistence
- `ConversationStoreController` owning conversation list/search/pin/load/rename/delete behavior
- GRDB-backed persistence in `~/Library/Application Support/OllamaBob/ollamabob.sqlite`

When a task touches these boundaries, audit carefully before changing them.

### Tool Output Spillout

If a tool result exceeds `AppConfig.toolInlineMax`, `ToolOutputStore` writes it to disk and replaces the inline content with a short pointer. The model can read the full content via the meta-tool path.

### Uncensored Mode

- Enabled globally in Preferences, then per-conversation
- Uses a separate model stack
- Tools are disabled
- Compaction is skipped
- No silent fallback to the standard model stack

### Rich Presentation

The `present` tool and `PresentationService` support:
- `html` — opens Bob’s in-app rich HTML companion window
- `url` — opens the default browser
- `file` — opens the default macOS app for that file

Assistant transcript artifact chips route through the same `PresentationService`.

## Testing Strategy

Test target: `OllamaBob/Tests/OllamaBobTests/`

Patterns already used in the repo:
- protocol-based fakes
- behavior-named tests
- async tests using expectations / fulfillment
- deterministic waits using yields instead of `sleep`

Priority areas for tests:
- controller/session behavior
- approval/path policy regressions
- persistence ordering and CRUD
- structured tool edge cases

When a feature changes controller/session behavior, add or update focused regression tests.

## Security Considerations

- No hardcoded secrets
- App Sandbox is OFF; safety depends on approval and path policy
- Tool outputs are wrapped in `<untrusted>` tags to prevent prompt injection from tool content
- Sample payloads must be scrubbed before commit
- Prefer first-class tools over broad shell calls when an existing structured tool fits

## Deployment

The app is distributed as a user-built `.app` bundle, not via the App Store.

`build.sh` handles:
1. killing any running instance
2. `swift build -c debug`
3. copying the binary into the `.app`
4. generating `Info.plist`
5. copying the SPM-generated resource bundle
6. ad-hoc signing with `codesign --force --deep --sign -`

## Commit & Pull Request Guidelines

- Use short Conventional Commit subjects: `feat:`, `fix:`, `test:`, `refactor:`
- Write in the imperative mood
- Scope each commit to one logical change
- For UI changes, include screenshots or short recordings in PRs
- Link the relevant planning doc from `docs/` when work follows a spec

## Documentation Map

| File | Purpose |
|------|---------|
| `docs/CURRENT_HANDOFF.md` | Most recent state snapshot — read this first in a fresh session after `AGENTS.md` |
| `docs/ACTIVE_EXECUTION_PLAN.md` | Binding instructions for the current task, if present |
| `CLAUDE.md` | Project guide and decision log for Claude Code |
| `docs/OLLAMABOB_V1.1_PLAN.md` | Core architecture, wire format, schema |
| `docs/OLLAMABOB_V2_PLAN_FINAL.md` | V2 scope |
| `docs/MULTIMEDIA_BOB.md` | Rich presentation design/spec |
| `OllamaBob/NAUGHTYBOB_PLAN.md` | Uncensored-mode plan and constraints |
| `docs/OPERATOR_QA.md` | Manual QA checklist and operator gotchas |
| `docs/ARCHITECTURE_NOTES.md` | Running architectural decision notes |
| `archive/` | Historical artifacts and superseded plans |

## Multi-Agent Execution Pattern

When a tool/environment supports sub-agents or task fan-out, use this pattern:

1. **Prime supervisor** — owns phase order, scope, merge, and drift control
2. **Read-only audit swarm first**
   - session/state audit
   - avatar UI/projection audit
   - window/accessibility audit
   - preserved-features/regression audit
3. **Sequential implementation**
   - one phase at a time
   - one writing agent per file
   - no concurrent edits to core files
4. **Independent regression review**
   - compare against preserved components and phase scope before advancing

If sub-agents are unavailable, emulate the same pattern as separate audit passes before coding.

## Agent Output Expectations

For any meaningful task, responses should be:
- evidence-based
- explicit about observed fact vs inference
- honest about what was not verified
- phase-locked
- concise but complete enough to support safe execution

Do not claim runtime verification you did not perform.
