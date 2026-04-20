# OllamaBob — Claude Code Project Guide

## What This Is

OllamaBob is a native macOS menu bar AI assistant that runs entirely locally on an M1 Mac (32GB). It talks to Ollama over HTTP, owns its own agent loop in Swift, executes tools (shell, file read, file search, web search), and shows native approval dialogs before risky actions. Think: a persistent little buddy living on your Mac.

## Current State

- **Phase:** Shipping incremental V2.x releases. V1 feature set is complete; V2.0–V2.10 layered on voice, personas, tools, onboarding, UI polish, native tool expansion, rich presentation, and Naughty Bob v1.
- **Latest committed features:** V2.10 rich presentation pipeline plus Naughty Bob v1. Rich presentation adds the `present` tool, `PresentationService`, the rich HTML companion window, and assistant artifact chips that reopen URLs/files/rich views through the same pipeline. Naughty Bob v1 adds a master uncensored-mode setting, per-conversation `UNCENSORED` toggle/badge, forced tools-off behavior in uncensored mode, explicit missing-model messaging, and no silent fallback to the standard stack.
- **Current handoff:** `docs/CURRENT_HANDOFF.md` is the authoritative starting point for new sessions and current model-switch guidance. `docs/OLLAMABOB_V2.9.2_HANDOFF.md` is historical context for the older AppleScript/avatar-only pass.
- **V1.1 plan** (`docs/OLLAMABOB_V1.1_PLAN.md`) remains the architectural source of truth for the core agent loop and wire format. Features layered on top live in the V2 plan docs.
- **V2 plans:** `docs/OLLAMABOB_V2_PLAN_FINAL.md` (committed V2 scope). The earlier V2 draft, Phase-0 results write-up, and V2.9 Phase A plan are archived under `archive/`.
- **Historical docs** (original V1 kickoff prompt, V2.5 orchestration plan, phase-0 investigations) are preserved under `archive/`.

## Key Files

| File | Purpose |
|------|---------|
| `CLAUDE.md` | **This file** — operating rules and current state for Claude Code sessions. |
| `AGENTS.md` | Repo layout, commands, style conventions — keep this in sync with structure changes. |
| `README.md` | Human-facing project overview, setup, and uncensored-mode enable flow. |
| `docs/CURRENT_HANDOFF.md` | **Most recent handoff brief** — current state, current models, model-switch instructions, verification commands, and outstanding backlog. Read first in a fresh session. |
| `docs/OLLAMABOB_V1.1_PLAN.md` | Core architecture, wire format, schema, acceptance tests. Still authoritative for the agent loop. |
| `docs/OLLAMABOB_V2_PLAN_FINAL.md` | V2 scope that shipped on top of V1 (voice, personas, tools, memory, onboarding). |
| `docs/OLLAMABOB_V2.9.2_HANDOFF.md` | Historical handoff for the V2.9.2 AppleScript/avatar-only pass. |
| `docs/MULTIMEDIA_BOB.md` | Rich presentation design/spec, acceptance matrix, and current implementation notes. |
| `OllamaBob/NAUGHTYBOB_PLAN.md` | Naughty Bob v1 product plan and shipped constraints. |
| `docs/ARCHITECTURE_NOTES.md` | Running notes on architectural decisions as they're made. |
| `docs/personas.txt` | 14 voice personas for Bob's personality. |
| `images/` | Avatar/icon assets and source prompts. |
| `archive/` | Historical artifacts (V1 kickoff prompt, V2.5 plan, V2 draft, V2.9 Phase A plan, phase-0 investigations). See `archive/README.md`. |

---

## Non-Negotiable Architecture Rules

These are final. Do not change without explicit user approval AND documented evidence of a blocker.

### What We Build
- **Native SwiftUI/AppKit macOS app** — menu bar + floating avatar + chat panel
- **Direct HTTP to Ollama** at `localhost:11434` using the **native `/api/chat` endpoint** (NOT `/v1/chat/completions`)
- **Agent loop in Swift** — no external agent runtime
- **4 tools in v1:** `shell`, `read_file`, `search_files`, `web_search`
- **SQLite via GRDB.swift** for persistence
- **Native NSAlert** for approval dialogs
- **`stream: false`** for all Ollama requests
- **Flat tool parameter schemas only** (single-level properties)

### What's Still Out Of Scope
The original V1 "do not build" list has partially dissolved — voice clips, structured write tools, multi-conversation UI, cartoon avatars, the rich HTML companion window, and per-conversation uncensored mode all shipped in V2.x. These remain out of scope:

- No Python subprocess or external IPC (the Swift agent loop owns everything)
- No Hermes Agent, Open Interpreter, LangChain, LangGraph
- No MCP servers or MCP client (direct tool implementations only)
- No Electron, Node.js, Docker in the runtime
- No streaming responses (Gemma 4 + streaming + tool calls is still broken)
- No screenshot/vision analysis, no browser automation
- No plugin/extension system (all tools are first-party)
- No App Store distribution (user-run builds only, signed via build.sh)
- No nested/complex tool parameter schemas (all flat, single-level)

### If You're Tempted to Add Something Not Listed Above
Check the Decision Log and the current V2 plan first. If it's not covered and the user hasn't asked for it in the current session, ask before building.

---

## Ollama API Contract (CRITICAL)

Use **`/api/chat`** (Ollama native), NOT `/v1/chat/completions` (OpenAI-compatible).

### Why
- Native endpoint returns tool call `arguments` as a **JSON object** (not a string)
- Native endpoint supports `options.num_ctx` directly in the request body
- Tool results use `tool_name` field (not `tool_call_id`)

### Known Wire-Format Gotchas
1. **Multi-turn arguments bug:** In multi-turn conversations, Ollama may return `arguments` as a STRING on the second tool call even though the first was an object. Your Codable MUST handle both formats. See `JSONValue.swift` in the plan.
2. **Gemma 4 special characters:** Backticks, braces, and regex in tool arguments can crash the parser. Keep tool schemas flat and simple.
3. **Gemma 4 thinking mode:** Breaks streaming tool recognition. Irrelevant for v1 since we use `stream: false`, but do NOT enable streaming without addressing this.
4. **No `id` field on tool_calls** in native `/api/chat` responses. That's only in the OpenAI-compatible endpoint.
5. **Tool result messages** use `role: "tool"` with `tool_name: "shell"` — NOT `tool_call_id`.

### Before Writing Codable Models
**Capture real JSON samples from the local Ollama instance first.** Save them to a `samples/` directory. Code against reality, not documentation. This is step 1 of the build order.

---

## Model Configuration

| Setting | Value |
|---------|-------|
| Primary model | `gemma4:e4b` |
| Fallback model | `qwen3:14b` |
| Uncensored default | `huihui_ai/qwen3-abliterated:8b` |
| Minimum Ollama version | 0.20.2 |
| Context size | `num_ctx: 32768` default, user-configurable snap points `8192/16384/24576/32768` |
| Stream | `false` (always) |
| Fallback trigger | 3 consecutive tool parse failures |
| Fallback scope | Per-session (resets on restart) |
| User notification | Always notify when model switches |

Standard-mode fallback is `qwen3:14b`. Uncensored-mode conversations do **not** silently fall back to the standard stack.

---

## Approval Policy

**No auto-approve. Ever.** All writes require explicit user action.

| Level | Behavior | When |
|-------|----------|------|
| `none` | Execute silently, log only | Read-only: ls, cat, find, ping, df, ps, read_file, search_files, web_search |
| `modal` | NSAlert blocks until user approves or denies | Any write: rm, mv, cp, mkdir, chmod, brew install, kill, etc. |
| `forbidden` | Never execute, tell model "not allowed" | sudo, su, mkfs, dd, curl\|sh, rm -rf / |

The approval classifier also checks a **path policy**:
- `~/`, `/tmp`, `/var/tmp`, `/Applications`, `/usr/local` — allowed
- `/System`, `/Library`, `/private`, `/etc`, `/var` — requires approval even for reads
- `/dev`, `/Volumes` — always denied

---

## Hard Limits

| Limit | Value |
|-------|-------|
| Shell stdout max | 10,000 chars |
| Shell stderr max | 2,000 chars |
| File read max | 100 KB |
| Search results max | 5 results, 200 chars per snippet |
| Tool loop max iterations | 10 |
| Per-tool timeout | 30 seconds |
| Total agent loop timeout | 120 seconds |

All outputs truncated with format: `[first N chars]\n\n... [TRUNCATED: X total chars, showing first N] ...`

---

## Web Search

Brave Search API at `https://api.search.brave.com/res/v1/web/search`.

**Pricing (April 2026):** $5/month credit (~1,000 requests). NOT free 2,000/month (that's stale).

If no Brave API key is configured, disable `web_search` tool gracefully — don't crash, just remove it from the tool registry for that session.

Web search is behind a `SearchProvider` protocol so SearXNG (free, self-hosted) can be swapped in for v2.

---

## Xcode Project Settings

| Setting | Value | Why |
|---------|-------|-----|
| App Sandbox | **OFF** | Required for `Process()` shell execution |
| LSUIElement | `true` in Info.plist | No Dock icon, menu-bar-only |
| Hardened Runtime | ON (with exceptions if needed) | For eventual distribution |
| Deployment Target | macOS 14.0 | MenuBarExtra available since macOS 13 |
| SPM Dependencies | GRDB.swift | SQLite |

---

## Build Order

The V1.1 plan has a detailed weekend build order with gates. The short version:

1. **Pre-kickoff:** Pull models, capture real JSON samples, create Brave key
2. **Saturday AM:** OllamaClient + Codable models + ShellTool + ToolRegistry (prove the core)
3. **Saturday PM:** Remaining tools + ApprovalPolicy + PathPolicy + AgentLoop (prove the loop)
4. **Saturday EVE:** MenuBarExtra + ChatPanel + ApprovalAlert (minimal UI)
5. **Sunday AM:** GRDB + persistence + preflight checks (survive restart)
6. **Sunday PM:** Avatar window + personality + acceptance tests (ship it)

**Gates:** Each phase has a gate. Do not proceed to the next phase until the gate passes. Especially: do NOT build UI until the agent loop completes a real tool-calling round trip with Ollama.

---

## Acceptance Tests

All 10 must pass before v1 is done:

| # | Test |
|---|------|
| A1 | "List files in my home directory" → shell tool → results shown |
| A2 | "Find files larger than 1GB" → shell tool → results or "none found" |
| A3 | "Read ~/.zshrc" → read_file → contents displayed |
| A4 | "Search the web for macOS M1 tips" → web_search → 5 results with snippets |
| A5 | "Delete ~/test.txt" → approval dialog → deny → model told "denied" |
| A6 | "Run sudo rm -rf /" → forbidden → model told "not allowed" |
| A7 | "Install htop with homebrew" → approval → approve → runs |
| A8 | Close chat, reopen → conversation loads |
| A9 | Quit app, relaunch → conversation persists, preflight passes |
| A10 | Stop Ollama, launch app → preflight error view shown |

---

## Coding Standards

- Prefer clear Swift over clever Swift
- Every file has a single clear responsibility
- Handle errors deliberately — no force unwraps in production paths
- Keep files small and composable (target: most files under 100 lines)
- Add comments only where intent is not obvious from the code
- No TODO placeholders in core paths — either implement it or defer it explicitly
- Produce runnable code, not scaffolding
- No premature abstractions — three similar lines > one speculative helper

---

## Personality

Bob's system prompt is defined in `Personality/BobPersonality.swift`. He is:
- Helpful and slightly cheeky
- Concise — doesn't over-explain
- Occasionally witty but never at the expense of usefulness
- Honest about limitations
- Respects denied commands (doesn't try to work around them)

The `docs/personas.txt` file has 14 voice personas for future voice features. These are **v2 material only** — do not implement voice or persona switching in v1.

---

## Project Structure

```
ollamaBob/                        # repo root
├── CLAUDE.md                     # This file (operating rules)
├── AGENTS.md                     # Repo layout + commands (keep in sync)
├── MEMORY.md                     # Long-running notes across sessions
├── LICENSE
├── .env                          # local secrets (gitignored)
├── .env.example                  # public template for new clones
├── archive/                      # historical docs + phase-0 artifacts
├── docs/                         # plans, architecture notes, persona text
├── images/                       # avatar/icon source assets
├── samples/                      # real Ollama wire-format samples
├── tools/                        # helper scripts (voice render, etc.)
└── OllamaBob/                    # Swift Package / Xcode project
    ├── Package.swift
    ├── build.sh                  # assembles build/OllamaBob.app
    └── OllamaBob/                # Swift sources
        ├── OllamaBobApp.swift
        ├── AppConfig.swift
        ├── Agent/                # loop, approvals, prompt budgeting
        ├── Tools/                # structured tools + shell
        ├── Views/                # SwiftUI screens
        ├── Models/               # state + controllers
        ├── Personality/          # persona prompts + operating rules
        ├── Persistence/          # GRDB schema + database
        └── Resources/            # avatars, audio, tool catalog
```

---

## Decision Log

| Date | Decision | Reason |
|------|----------|--------|
| 2026-04-06 | Use `/api/chat` not `/v1/chat/completions` | Native endpoint gives object arguments, supports num_ctx directly |
| 2026-04-06 | No Hermes Agent in v1 | No RPC mode, no programmatic approval injection, gateway bugs |
| 2026-04-06 | No MCP in v1 | Direct Brave API call is simpler for web search |
| 2026-04-06 | No Python subprocess | Eliminates IPC complexity, agent loop is ~400 lines of Swift |
| 2026-04-06 | No auto-approve | All write operations require explicit modal approval |
| 2026-04-06 | No streaming in v1 | Gemma 4 + streaming + tool calls = known broken |
| 2026-04-06 | No write_file in v1 | Too risky without proven approval/logging pipeline |
| 2026-04-06 | Brave pricing is $5/mo credit, not free 2K/mo | Verified April 2026 — old free tier is stale |
| 2026-04-06 | SearchProvider protocol for web search | Allows SearXNG swap in v2 without touching agent loop |
| 2026-04-06 | NonnaClaw does not exist | Verified — it's a blog post, not a repo |
| 2026-04-06 | Fallback model is `qwen3:14b`, not `qwen2.5:14b` | `qwen2.5:14b` not present locally; `qwen3:14b` already pulled. Same `/api/chat` contract, same flat-schema tool calling — drop-in. AppConfig.fallbackModel reflects this. |
| 2026-04-09 | V2 scope finalized (plans in `docs/OLLAMABOB_V2_PLAN_FINAL.md`) | Covers personas, persistent memory, onboarding, extended tool set, voice. Shipped in phases V2.0 → V2.8. |
| 2026-04-16 | V2.5 — Bob speaks (50 ElevenLabs voice clips bundled as resources) | Offline playback; no runtime TTS call. `tools/render-bob-sayings.py` regenerates clips from `.env` key. |
| 2026-04-16 | V2.6 — clipboard + AppleScript tools added | Keeps "executor of small tasks on this Mac" posture while respecting the approval policy. |
| 2026-04-16 | V2.7 — swappable avatar packs (classic robot + Mumbai cartoon) | Pack-prefix naming under `Resources/Avatars/`. Avatar store chooses per persona. |
| 2026-04-17 | V2.8 — chromeless chat window + thinking/answer split | Tool traces stream as transparent "invisible thoughts" above Bob; chat transcript keeps user messages, tool output (df -h), and final reply only. |
| 2026-04-17 | Transparent sprites via `rembg[cpu,cli]`, not a gen model | Gen models (nano-banana / Gemini 2.5 Flash Image) can't output true alpha — they paint a background. Generate art, then mask with rembg. |
| 2026-04-17 | Chromeless SwiftUI windows need three pieces | Explicit `WindowDragHandle` NSView for dragging, `.resizable` styleMask + `hasShadow=true` for discoverable edges, `.windowResizability(.contentMinSize)` with min/ideal frame (no fixed `.frame`). |
| 2026-04-17 | Ollama memory must use `ps -axo rss=,command=` | The `comm=` field truncates to 16 chars on macOS, so `/Applications/Ollama.app/Contents/Resources/ollama` never matches a `== "ollama"` test. Use `command=` (full argv) and match the executable basename. |
| 2026-04-17 | V2.9 Phase A — seven native tools (OCR, speak, weather, unit_convert, image_convert, youtube_search, youtube_download) | Each is its own `enum`-namespaced `Tools/*.swift` file following the established pattern. No new SPM dependencies — Vision / CoreImage / sips / wttr.in / yt-dlp all satisfy the need without them. |
| 2026-04-17 | V2.9.1 — built-in tools promoted above external CLI tools in Preferences | The built-in set is the core product; the external CLI list is opt-in depth. Surface ordering now reflects that. |
| 2026-04-18 | V2.9.2 — `NSAppleEventsUsageDescription` is required for AppleScript to honor TCC grants | Without it, macOS accepts the user's "Allow" on the Automation prompt but the subsequent Apple-event send still fails with `-1743`. `build.sh` now inlines the Apple-events, Contacts, Calendar, and Reminders usage strings. |
| 2026-04-18 | V2.9.2 — Permissions are a dedicated onboarding step + a Preferences section | Discovery pattern for first-launch users: fire every TCC prompt up front via `AutomationProbe.probeAll()` rather than letting Bob stumble into each one mid-conversation. `AutomationProbe` lives in `Services/` (it's app infrastructure, not a model-callable tool). |
| 2026-04-19 | V2.10 — rich presentation shipped behind one `present` tool and one `PresentationService` | `html` opens Bob's rich HTML companion window, `url` opens the browser, `file` opens the default macOS app, and assistant artifact chips route through the same pipeline. |
| 2026-04-20 | Naughty Bob v1 ships inside the current app, not as a separate app | The feature is a mode/routing change, not a product split: per-conversation `UNCENSORED`, tools forced off, no silent fallback to censored models, and compaction skipped while uncensored mode is on. |

---

## Errata / Corrections to Other Docs

| Document | Issue | Correction |
|----------|-------|------------|
| Any doc saying "free 2,000 queries/month" for Brave | Stale pricing | **$5/month credit (~1,000 requests) for new signups** |
| Any doc/plan saying fallback is `qwen2.5:14b` | Model not installed locally | **Use `qwen3:14b`** — see Decision Log 2026-04-06. AppConfig.fallbackModel is the source of truth. |
| Archived `OLAMMABOB_PROMPT.md` | References `/v1/chat/completions` | Codebase uses `/api/chat` (native endpoint). The prompt is kept in `archive/` for historical context only. |

When CLAUDE.md and other docs conflict, **CLAUDE.md wins.**

---

## For Future Sessions

The V1 implementation is complete and V2.x features have been layering on top. When picking up a new task:

1. Read **`docs/CURRENT_HANDOFF.md`** first — it's the most recent snapshot (current state, current models, switch-model instructions, verification commands, backlog).
2. Read **AGENTS.md** for the current repo layout, build/test commands, and style conventions.
3. Read the **Decision Log** above — decisions are sticky and should not be revisited without documented cause.
4. Check `archive/` if you need to understand why something is the way it is.
5. Always follow the build order: `swift build` first, then `./build.sh --run` to verify changes live in the actual menu-bar app.
