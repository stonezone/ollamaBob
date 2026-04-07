# OllamaBob — Claude Code Project Guide

## What This Is

OllamaBob is a native macOS menu bar AI assistant that runs entirely locally on an M1 Mac (32GB). It talks to Ollama over HTTP, owns its own agent loop in Swift, executes tools (shell, file read, file search, web search), and shows native approval dialogs before risky actions. Think: a persistent little buddy living on your Mac.

## Current State

- **Phase:** Pre-implementation. Architecture finalized, plan reviewed and revised.
- **No code written yet.** The Xcode project does not exist.
- **The V1.1 plan is the source of truth:** `docs/OLLAMABOB_V1.1_PLAN.md`
- **The kickoff prompt for implementation:** `OLAMMABOB_PROMPT.md` — NOTE: this references `/v1/chat/completions` but V1.1 plan corrected this to `/api/chat` (native endpoint). The CLAUDE.md rules below take precedence over any stale references in the prompt.

## Key Files

| File | Purpose |
|------|---------|
| `docs/OLLAMABOB_V1.1_PLAN.md` | **Authoritative implementation plan.** All architecture, API contracts, schemas, build order, acceptance tests. Read this FIRST. |
| `OLAMMABOB_PROMPT.md` | Kickoff prompt for the implementation agent. Good structure but has one stale API endpoint reference (see above). |
| `docs/personas.txt` | 14 voice personas for Bob's personality. These are for v2 voice features — do NOT implement voice in v1. |
| `images/image_prompts.txt` | AI image generation prompts for Bob's avatar/icon. Assets in `images/`. |
| `images/ollaaBob_icons.png` | Generated icon concepts. |
| `images/ollamaBob_avatars.png` | Generated avatar concepts. |

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

### What We Do NOT Build in v1
- No Python subprocess, no IPC protocol
- No Hermes Agent, Open Interpreter, LangChain, LangGraph
- No MCP servers or MCP client
- No Electron, web views, Node.js, Docker
- No streaming responses
- No `write_file` tool (add in v2 after approvals are proven)
- No voice input/output (whisper.cpp, AVSpeechSynthesizer)
- No screenshot/vision analysis
- No browser automation
- No scheduled background tasks
- No multi-conversation UI
- No plugin/extension system
- No App Store distribution work
- No nested/complex tool parameter schemas

### If You're Tempted to Add Something Not Listed Above
**Don't.** If it's not in the v1 tool set or the v1 feature list in V1.1_PLAN.md, it does not ship in v1. No exceptions unless the user explicitly asks for it in this session.

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
| Fallback model | `qwen2.5:14b` |
| Minimum Ollama version | 0.20.2 |
| Context size | `num_ctx: 8192` (passed in `options`) |
| Stream | `false` (always) |
| Fallback trigger | 3 consecutive tool parse failures |
| Fallback scope | Per-session (resets on restart) |
| User notification | Always notify when model switches |

If Gemma 4 E4B fails tool calling during initial testing (Saturday morning gate), switch to `qwen2.5:14b` immediately. Same API, same tool format, one config value change.

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

See V1.1 plan for the full file tree. Key directories:

```
OllamaBob/
├── CLAUDE.md                 # This file
├── OLAMMABOB_PROMPT.md       # Kickoff prompt (stale on API endpoint — CLAUDE.md overrides)
├── docs/
│   ├── OLLAMABOB_V1.1_PLAN.md  # Authoritative plan
│   └── personas.txt            # Voice personas (v2)
├── images/                     # Avatar/icon assets and prompts
└── OllamaBob/                  # Xcode project (to be created)
    ├── OllamaBobApp.swift
    ├── AppConfig.swift
    ├── Models/
    ├── Agent/
    ├── Tools/
    ├── Views/
    ├── Persistence/
    ├── Personality/
    └── Assets.xcassets/
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

---

## Errata / Corrections to Other Docs

| Document | Issue | Correction |
|----------|-------|------------|
| `OLAMMABOB_PROMPT.md` line 279 | Says "Use /v1/chat/completions" | **Use /api/chat instead.** V1.1 plan corrected this. |
| `OLAMMABOB_PROMPT.md` line 18 | Mission says `/v1/chat/completions` | **Use /api/chat.** |
| Any doc saying "free 2,000 queries/month" for Brave | Stale pricing | **$5/month credit (~1,000 requests) for new signups** |
| Any doc/plan saying fallback is `qwen2.5:14b` | Model not installed locally | **Use `qwen3:14b`** — see Decision Log 2026-04-06. AppConfig.fallbackModel is the source of truth. |

When CLAUDE.md and other docs conflict, **CLAUDE.md wins.**

---

## For the Implementation Agent

When you start building:

1. **Read `docs/OLLAMABOB_V1.1_PLAN.md` first.** It has the complete architecture, wire format, schema, file tree, build order, and acceptance tests.
2. **Read `OLAMMABOB_PROMPT.md` second** for the execution strategy, subagent plan, enforcement checks, and coding standards. But remember the `/api/chat` correction above.
3. **Capture real Ollama JSON samples before writing any Codable models.** Save to `samples/`. This is non-negotiable.
4. **Test Gemma 4 E4B tool calling with curl before writing Swift.** If it fails 3+ times on flat schemas, switch to `qwen2.5:14b`.
5. **Follow the build order and gates.** Core before UI. Prove the loop before polishing the avatar.
6. **Run all 10 acceptance tests before declaring v1 done.**
7. **Do not add deferred features.** If it's in the "Do Not Build Yet" list, it stays deferred.
