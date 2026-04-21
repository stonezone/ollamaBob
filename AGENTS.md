# OllamaBob — Agent Guide

> This file is for AI coding agents. Read it first when picking up the project cold. For the most recent technical handoff (current models, switch-model instructions, verification commands), also read `docs/CURRENT_HANDOFF.md`.

## Project Overview

OllamaBob is a native macOS menu-bar AI assistant that runs entirely locally. It is a SwiftUI/AppKit app targeting macOS 14+, built with Swift Package Manager. The app talks directly to a local Ollama server over HTTP at `http://localhost:11434`, owns its own agent loop written in Swift, executes structured tools, and shows native approval dialogs before risky actions.

Key characteristics:
- **No external agent runtime** — the Swift agent loop owns everything.
- **No Python subprocess, no Electron, no Docker** in the runtime.
- **No MCP servers** — all tools are first-party direct implementations.
- **No streaming** — all Ollama requests use `stream: false` (Gemma 4 + streaming + tool calls is known broken).
- **Native `/api/chat` endpoint** — NOT the OpenAI-compatible `/v1/chat/completions` endpoint.

## Technology Stack

| Layer | Technology |
|-------|------------|
| Language | Swift 5.9+ |
| Build System | Swift Package Manager (`Package.swift`) |
| UI Framework | SwiftUI + AppKit (hybrid) |
| Persistence | SQLite via GRDB.swift |
| HTTP Client | `URLSession` (in `OllamaClient.swift`) |
| macOS Target | 14.0+ |
| App Sandbox | OFF (required for `Process()` shell execution) |
| Dock Icon | None (`LSUIElement: true`) |

Single SPM dependency:
- `GRDB.swift` (from: "6.24.0") — SQLite wrapper.

## Project Structure

The active application lives under `OllamaBob/`. The repo root also contains docs, samples, images, and tooling scripts.

```
ollamaBob/
├── AGENTS.md                     # This file
├── CLAUDE.md                     # Project guide and decision log for Claude Code
├── README.md                     # Human-facing overview
├── .env                          # Local secrets (gitignored)
├── .env.example                  # Template for new clones
├── OllamaBob/
│   ├── Package.swift             # SPM manifest
│   ├── build.sh                  # Assembles build/OllamaBob.app
│   ├── OllamaBob/                # Swift sources
│   │   ├── OllamaBobApp.swift    # @main, MenuBarExtra, window scenes
│   │   ├── AppConfig.swift       # Compile-time defaults (models, limits, URLs)
│   │   ├── Agent/                # Loop, approvals, routing, prompt budgeting
│   │   ├── Tools/                # Structured tools + shell execution
│   │   ├── Views/                # SwiftUI UI
│   │   ├── Models/               # Shared state and controllers
│   │   ├── Services/             # App-level infrastructure (not model-callable)
│   │   ├── Personality/          # Prompt / persona logic
│   │   ├── Sound/                # Audio playback
│   │   ├── Persistence/          # GRDB-backed storage
│   │   └── Resources/            # Bundled assets (avatars, audio, ToolCatalog.json)
│   └── Tests/OllamaBobTests/     # XCTest suite
├── docs/                         # Plans, architecture notes, operator QA
├── samples/                      # Real Ollama wire-format JSON samples
├── images/                       # Avatar/icon source assets
├── tools/                        # Helper scripts (voice rendering)
└── archive/                      # Historical docs and phase artifacts
```

### Source Folder Responsibilities

- **`Agent/`** — `AgentLoop` (core turn processing), `ApprovalPolicy`, `PathPolicy`, `ToolRegistry`, `OllamaClient`, `Preflight`, `ConversationCompactor`, `OutputLimits`, `UntrustedWrapper`.
- **`Tools/`** — Individual tool implementations (`ShellTool`, `FileReadTool`, `FileWriteTool`, `DirectoryListTool`, `DirectoryCreateTool`, `FileMoveTool`, `FileSearchTool`, `GitStatusTool`, `GitDiffTool`, `WebSearchTool`, `PresentTool`, `AppleScriptTool`, `ClipboardTool`, `OCRTool`, `SayTool`, `WeatherTool`, `UnitsTool`, `SipsTool`, `YouTubeTool`, `PhoneTool`), plus `ToolCatalog`, `ToolRuntime`, `ToolOutputStore`, `BuiltinToolsCatalog`, `SearchProvider`.
- **`Views/`** — `BobsDeskView` (live chat surface), `ChatPanel`, `ChatBubble`, `ConversationManagerView`, `PreferencesView`, `OnboardingView`, `ToolActivityView`, `RichHTMLView`, `ApprovalAlert`, `ArtifactChip`, `ArtifactDetector`, `MemoryIOPanel`, `PreflightErrorView`, `PersonaQuickSwapMenu`, `ConversationSearchBar`.
- **`Models/`** — `ChatSessionController`, `ConversationStoreController`, `AppSettings`, `Conversation`, `Message`, `ToolCall`, `ToolResult`, `ApprovalLevel`, `AvatarStore`, `AvatarPack`, `RichHTMLState`, `JSONValue`, `ProcessMemorySampler`.
- **`Services/`** — `PresentationService`, `AutomationProbe`, `PromptComposerMemoryStore`.
- **`Personality/`** — `PromptComposer`, `BobOperatingRules`, `Persona`, `PersonaStore`, `BuiltinPersonas`, `GreetingLines`.
- **`Sound/`** — `BobSayings`, `BobSounds`, `Heartbeat`.
- **`Persistence/`** — `Database` (GRDB queue + record types), `Schema` (table creation).

## Build, Test, and Development Commands

Run all commands from the `OllamaBob/` directory.

```bash
# Build the debug executable
swift build

# Run the app directly from SwiftPM
swift run OllamaBob

# Run the test suite
swift test

# Assemble the .app bundle (build/OllamaBob.app)
./build.sh

# Build and launch the .app bundle
./build.sh --run
```

The app expects a local Ollama server at `http://localhost:11434`.

### Model Defaults

Configured in `AppConfig.swift`:
- **Primary:** `gemma4:e4b`
- **Fallback:** `qwen3:14b`
- **Compaction:** `qwen3:14b`
- **Uncensored default:** `huihui_ai/qwen3-abliterated:8b`

### Secrets

Runtime secrets are read from environment variables or `UserDefaults`:
- `BRAVE_API_KEY` — enables the `web_search` tool (optional).
- `JARVIS_API_KEY` — inner Jarvis call API key for `/call/*`.
- `OPERATOR_API_SECRET` — outer Jarvis operator secret; the current daemon contract requires this as well as `JARVIS_API_KEY` for `phone_call`, `phone_hangup`, and `phone_status`.
- `ELEVENLABS_API_KEY` + `OLLAMABOB_VOICE_ID` — only needed to re-render voice clips via `tools/render-bob-sayings.py`; the shipping app reads pre-rendered audio from `Resources/Audio/`.

Store secrets in a gitignored `.env` at the repo root. Use `.env.example` as the template.

## Code Style Guidelines

- **Indentation:** 4 spaces.
- **Naming:** `UpperCamelCase` for types, `lowerCamelCase` for properties and methods.
- **File organization:** One primary type per file. Keep files focused and grouped by feature folder.
- **Clarity:** Prefer clear Swift over clever abstractions.
- **Safety:** Avoid force unwraps in production paths.
- **Navigation:** Use `// MARK:` sections where they improve navigation.
- **Comments:** Add comments only where intent is not obvious from the code.
- **No formatter or linter** is configured — match surrounding code before introducing new patterns.

## Architecture Details

### Agent Loop

`AgentLoop.process(userMessage:history:conversationId:uncensoredMode:)` is the core turn processor:

1. **Preflight** — checks Ollama reachability and model availability on launch (`Preflight.run()`).
2. **System prompt injection** — `PromptComposer` assembles the system prompt from `BobOperatingRules`, active persona, optional user profile, and a live tool cheat sheet. The system prompt is re-injected at position 0 on every request so it can never be evicted by context truncation.
3. **Compaction** — if the conversation approaches 75% of `num_ctx`, `ConversationCompactor` summarizes older turns (skipped in uncensored mode).
4. **Ollama request** — `OllamaClient.chat()` with `stream: false`, flat tool schemas, and `options.num_ctx`.
5. **Tool execution** — for each tool call: validate existence, validate args, check `ApprovalPolicy`, execute, spillout large results to `ToolOutputStore`, wrap in `<untrusted>` tags, append to message history.
6. **Iteration cap** — max 10 tool-call iterations per turn; total timeout 120s.

### Approval Policy

Three levels (defined in `ApprovalLevel.swift`):
- `none` — execute silently (read-only tools: `read_file`, `list_directory`, `search_files`, `web_search`, `git_status`, `git_diff`, `weather`, `unit_convert`, `ocr`, `speak`, `clipboard_read`, `remember`, `list_facts`, `phone_status`, etc.).
- `modal` — show NSAlert blocking until user approves or denies (`write_file`, `move_file`, `create_directory`, `image_convert`, `clipboard_write`, `forget`, `applescript`, `phone_call`, `youtube_download`, etc.).
- `forbidden` — never execute, return "not allowed" to the model (`sudo`, `rm -rf /`, download-and-execute chains, etc.).

Path policy (`PathPolicy.swift`) adds filesystem restrictions:
- Allowed without approval: `~/`, `/tmp`, `/var/tmp`, `/Applications`, `/usr/local`
- Requires approval: `/System`, `/Library`, `/private`, `/etc`, `/var`
- Always denied: `/dev`, `/Volumes`

### Conversation & Persistence

- `ChatSessionController` owns the active transcript, session flow, and message persistence.
- `ConversationStoreController` owns conversation list/search/pin/load/rename/delete behavior.
- `DatabaseManager` (singleton) wraps a `GRDB.DatabaseQueue` stored in `~/Library/Application Support/OllamaBob/ollamabob.sqlite`.
- Tables: `conversations`, `messages`, `toolLog`, `facts` (Phase 4 sticky memory), `memory` (v1 key/value reserved).

### Tool Output Spillout

If a tool result exceeds `AppConfig.toolInlineMax` (2,000 chars), `ToolOutputStore` writes it to disk and replaces the inline content with a short pointer. The model can read the full content via the `read_tool_output` meta-tool. This keeps the chat context clean.

### Uncensored Mode (Naughty Bob v1)

- Enabled globally in Preferences, then per-conversation via an `UNCENSORED` pill/badge.
- Uses a separate model stack (`AppSettings.effectiveUncensoredModelName`).
- **Tools are disabled** in uncensored mode.
- **Compaction is skipped**.
- **No silent fallback** to the standard model stack.

### Rich Presentation

The `present` tool and `PresentationService` support three kinds:
- `html` — opens Bob's in-app rich HTML companion window (`rich-html` window scene).
- `url` — opens the default browser.
- `file` — opens the default macOS app for that file.

Assistant transcript artifact chips route through the same `PresentationService`.

## Testing Strategy

Test target: `OllamaBob/Tests/OllamaBobTests/`.

Testing patterns observed:
- **Protocol-based fakes** — `ChatSessionControllerTests` uses `FakeDatabase`, `FakeAgentLoop`, and `FakeToolOutputStore` conforming to protocols like `ChatSessionDatabaseManaging`, `ChatSessionAgentLooping`, and `ChatSessionToolOutputStoring`.
- **Behavior-named tests** — e.g., `testPreflightFailsWhenOllamaIsUnavailable()`, `testSendCurrentInputUsesInjectedServices()`.
- **Async testing** — uses `expectation(description:)` and `await fulfillment(of:timeout:)` for async agent loop calls.
- **Deterministic waits** — `testStartFreshConversationClearsPreviousSpilloutAndResetsState` uses `Task.yield()` loops instead of `sleep` to avoid flakiness.

Priority areas for tests:
- Controller behavior (session flow, conversation management)
- Approval / path policy regressions
- Persistence ordering and CRUD
- Structured tool edge cases (file tools, git tools)

When adding a feature that replaces a shell path with a first-class tool, add **both** approval tests and an execution-path test.

## Security Considerations

- **No hardcoded secrets** — read runtime keys from environment variables or `UserDefaults`.
- **App Sandbox is OFF** — required for `Process()` shell execution. The app relies on the approval policy and path policy for safety.
- **Tool output isolation** — `UntrustedWrapper.wrap()` wraps tool results in `<untrusted>…</untrusted>` so a malicious file or web page cannot pretend to be a user instruction.
- **Sample payloads** in `samples/` must be scrubbed of private data before committing.
- **Prefer first-class tools** (`read_file`, `list_directory`, `write_file`, `move_file`, `git_status`, `git_diff`) over broad `shell` calls when the task fits an existing structured action.

## Deployment

The app is distributed as a user-built `.app` bundle, not via the App Store.

`build.sh` handles:
1. Killing any running instance.
2. `swift build -c debug`.
3. Copying the binary into `build/OllamaBob.app/Contents/MacOS/`.
4. Generating `Info.plist` inline (includes TCC usage strings for Desktop, Documents, Downloads, removable volumes, Apple Events, Contacts, Calendars, and Reminders).
5. Copying the SPM-generated resource bundle (`OllamaBob_OllamaBob.bundle`) into `Contents/Resources/`.
6. Ad-hoc re-signing with `codesign --force --deep --sign -` to avoid "Launchd job spawn failed" errors when new frameworks are linked.

## Commit & Pull Request Guidelines

- Use short Conventional Commit subjects: `feat:`, `fix:`, `test:`, `refactor:`.
- Write in the imperative mood.
- Scope each commit to one logical change.
- For UI changes to `Views/` or menu bar behavior, include screenshots or short recordings in PRs.
- Link the relevant planning doc from `docs/` when work follows a spec.

## Documentation Map

| File | Purpose |
|------|---------|
| `docs/CURRENT_HANDOFF.md` | Most recent state snapshot — read this first in a fresh session |
| `CLAUDE.md` | Operating rules, decision log, and architecture constraints |
| `docs/OLLAMABOB_V1.1_PLAN.md` | Core architecture, wire format, schema |
| `docs/OLLAMABOB_V2_PLAN_FINAL.md` | V2 scope (personas, memory, tools, onboarding) |
| `docs/MULTIMEDIA_BOB.md` | Rich presentation design/spec |
| `OllamaBob/NAUGHTYBOB_PLAN.md` | Uncensored-mode plan and shipped constraints |
| `docs/OPERATOR_QA.md` | Manual QA checklist and operator gotchas |
| `docs/ARCHITECTURE_NOTES.md` | Running architectural decision notes |
| `archive/` | Historical artifacts and superseded plans |
