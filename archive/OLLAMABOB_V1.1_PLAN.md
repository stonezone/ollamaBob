# OllamaBob v1.1 — Implementation Plan (Revised)

**Date:** April 6, 2026
**Revision:** V1.1 — incorporates GPT review feedback, wire-format verification, pricing corrections, and guardrail tightening
**Target:** Native macOS menu bar + floating avatar AI assistant
**Platform:** M1 Mac, 32GB unified memory, macOS 14+
**Model:** Gemma 4 E4B via Ollama (Qwen 2.5 14B fallback)

> **Current-state note (2026-04-20):** This doc describes the original V1 architecture. The shipped app now runs 20+ first-party tools, includes Naughty Bob v1 (uncensored mode), rich presentation, and Jarvis phone integration. See `AGENTS.md`, `docs/CURRENT_HANDOFF.md`, and `README.md` for the current tool set and feature list.

---

## Changes from V1.0

| Issue | V1.0 | V1.1 (Corrected) |
|-------|------|-------------------|
| API endpoint | `/v1/chat/completions` | **`/api/chat`** (native) — supports `options.num_ctx` directly, returns arguments as JSON objects not strings |
| Brave pricing | "Free 2,000/month" | **$5/month credit (~1,000 requests)**. SearXNG as free fallback option |
| Context size | Not addressed | **Explicit `num_ctx` in options**, or pin via Modelfile |
| `confirm` auto-approve | 3-second auto-approve | **Removed. All writes require explicit approval** |
| Output limits | Not specified | **Hard caps on all tool outputs** |
| Path policy | Unrestricted | **Allowed/denied path zones** |
| Launch health checks | Only Ollama check | **Full preflight checklist** |
| Model fallback | "Switch if flaky" | **Deterministic fallback config** |
| Wire format | Assumed from docs | **Verified from real Ollama responses with known gotchas documented** |
| Arguments parsing | Assumed consistent | **Must handle both object and string arguments (multi-turn bug)** |
| Tool result format | `tool_call_id` field | **`tool_name` field on native /api/chat** |

---

## Executive Summary

A native Swift menu bar app that talks directly to Ollama's native `/api/chat` endpoint over HTTP, owns the agent loop itself, runs 4 tools (shell, file read, file search, web search), and puts approvals in native macOS dialogs before any write action. No Python. No subprocess. No MCP. No Hermes.

**Feasibility: 9/10** — Confirmed by both independent analyses.

---

## Architecture

```
+-----------------------------------------------+
|           OllamaBob.app (Pure Swift)           |
|                                                |
|  +----------+  +----------+  +--------------+  |
|  | MenuBar  |  |  Avatar   |  |    Chat      |  |
|  |  Extra   |  |  Window   |  |    Panel     |  |
|  +----------+  +----------+  +--------------+  |
|  +--------------------------------------------+ |
|  |         Tool Activity Log View              | |
|  +--------------------------------------------+ |
|                                                |
|  +--------------------------------------------+ |
|  |           AgentLoop (Swift)                 | |
|  |                                             | |
|  |  1. Send messages + tool defs to Ollama     | |
|  |  2. Parse tool_calls from response          | |
|  |  3. Normalize arguments (object or string)  | |
|  |  4. Check approval policy + path policy     | |
|  |  5. Show NSAlert if needed                  | |
|  |  6. Execute tool (with output caps)         | |
|  |  7. Feed tool result back to Ollama         | |
|  |  8. Repeat until no tool_calls (max 10)     | |
|  |  9. Display final response                  | |
|  +--------------------------------------------+ |
|                                                |
|  +---------+  +----------+  +--------------+   |
|  |ToolExec |  | Approval |  |   SQLite     |   |
|  | Engine  |  |   Gate   |  |   Store      |   |
|  +---------+  +----------+  +--------------+   |
|       |                                        |
+-------|-----------------------------------------+
        | HTTP (localhost:11434)
+-------v-----------------------------------------+
|              Ollama Server                       |
|          gemma4:e4b / qwen2.5:14b               |
+-------------------------------------------------+
```

---

## Ollama API Contract

### Decision: Use `/api/chat` (native), NOT `/v1/chat/completions`

| Factor | `/api/chat` | `/v1/chat/completions` |
|--------|-------------|------------------------|
| Context size control | `options.num_ctx` — direct | Requires `extra_body` hack |
| Arguments format | JSON **object** (easier to parse) | JSON **string** (needs extra decode) |
| Tool result field | `tool_name` | `tool_call_id` |
| Portability | Ollama-only | OpenAI-compatible |

We choose native because: context control matters, object arguments are cleaner, and we're not targeting OpenAI compatibility in v1. If we need portability later, switching is a contained change in `OllamaClient.swift`. VERIFIED.

### Request Format

```json
POST http://localhost:11434/api/chat
{
  "model": "gemma4:e4b",
  "messages": [
    {"role": "system", "content": "You are Bob..."},
    {"role": "user", "content": "Find files larger than 1GB"}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "shell",
        "description": "Run a shell command on macOS. Returns stdout and stderr.",
        "parameters": {
          "type": "object",
          "properties": {
            "command": {
              "type": "string",
              "description": "The shell command to execute"
            }
          },
          "required": ["command"]
        }
      }
    }
  ],
  "options": {
    "num_ctx": 8192
  },
  "stream": false
}
```

VERIFIED — `/api/chat` supports `tools` and `options.num_ctx` in the same request.

### Response (with tool call)

```json
{
  "model": "gemma4:e4b",
  "created_at": "2026-04-06T10:30:00Z",
  "message": {
    "role": "assistant",
    "content": "",
    "tool_calls": [
      {
        "function": {
          "name": "shell",
          "arguments": {
            "command": "find /Users -size +1G -type f 2>/dev/null"
          }
        }
      }
    ]
  },
  "done": true
}
```

VERIFIED — native `/api/chat` returns `arguments` as a JSON **object**, not a string. No `id` field on tool_calls (that's OpenAI-compat only).

### Tool Result Fed Back

```json
POST http://localhost:11434/api/chat
{
  "model": "gemma4:e4b",
  "messages": [
    {"role": "system", "content": "You are Bob..."},
    {"role": "user", "content": "Find files larger than 1GB"},
    {
      "role": "assistant",
      "content": "",
      "tool_calls": [
        {
          "function": {
            "name": "shell",
            "arguments": {"command": "find /Users -size +1G -type f 2>/dev/null"}
          }
        }
      ]
    },
    {
      "role": "tool",
      "tool_name": "shell",
      "content": "/Users/zack/bigfile.iso 4.2GB\n/Users/zack/vm.qcow2 8.1GB"
    }
  ],
  "tools": [...same tools...],
  "options": {"num_ctx": 8192},
  "stream": false
}
```

VERIFIED — tool results use `role: "tool"` with **`tool_name`** (NOT `tool_call_id`). This is specific to the native `/api/chat` endpoint.

### Critical Wire-Format Gotcha: Arguments Normalization

VERIFIED BUG: In multi-turn conversations, Ollama may return `arguments` as a **string** on the second tool call even though the first was an object. Your Swift Codable must handle both:

```swift
// In ToolCall.swift — handle both formats
struct FunctionCall: Codable {
    let name: String
    let arguments: JSONValue // custom enum: .object([String: JSONValue]) or .string(String)
    
    var parsedArguments: [String: Any] {
        switch arguments {
        case .object(let dict):
            return dict  // already an object
        case .string(let str):
            // Parse the string as JSON
            guard let data = str.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return obj
        }
    }
}
```

This is not theoretical — it's a documented multi-turn bug across multiple Ollama GitHub issues. VERIFIED.

---

## Gemma 4 E4B Tool Calling Status

| Fact | Status |
|------|--------|
| Supports tool calling via Ollama | VERIFIED |
| Requires Ollama >= v0.20.2 (April 4, 2026) | VERIFIED |
| Tool call parsing was broken in v0.20.0-v0.20.1 | VERIFIED |
| ~89% tool calling accuracy | VERIFIED |
| Known: hallucinated tool calls (calls tools not in schema) | VERIFIED |
| Known: sometimes flattens nested parameters | VERIFIED |
| Known: special characters in arguments (backticks, braces) can crash parser | VERIFIED |
| Known: thinking mode breaks streaming tool recognition | VERIFIED |
| `reasoning_effort: none` fixes streaming (not needed with stream:false) | VERIFIED |
| Qwen 2.5 14B/32B is more reliable for tool calling | VERIFIED |

### Gemma 4 Specific Defenses

```swift
// In AgentLoop.swift — validate tool calls before execution
func validateToolCall(_ call: ToolCall) -> Bool {
    // 1. Reject hallucinated tools (not in our registry)
    guard toolRegistry.has(call.function.name) else {
        log("Rejected hallucinated tool call: \(call.function.name)")
        return false
    }
    // 2. Reject if required arguments are missing
    guard toolRegistry.validateArgs(call.function.name, call.function.parsedArguments) else {
        log("Rejected tool call with invalid arguments: \(call.function.name)")
        return false
    }
    return true
}
```

---

## Model Fallback Configuration

Deterministic, not improvised. Stored in a single config struct:

```swift
struct ModelConfig {
    static let primary = "gemma4:e4b"
    static let fallback = "qwen2.5:14b"
    static let maxConsecutiveFailures = 3  // trigger fallback after 3 failed tool parses
    static let fallbackScope = FallbackScope.session  // revert on next app launch
    static let notifyUser = true  // show banner: "Switched to Qwen 2.5 (Gemma 4 was unreliable)"
}
```

| Setting | Value | Rationale |
|---------|-------|-----------|
| Primary model | `gemma4:e4b` | Newest, multimodal, 9.6GB |
| Fallback model | `qwen2.5:14b` | More reliable tool calling, 9GB |
| Fallback trigger | 3 consecutive tool parse failures | Avoids flapping on single bad response |
| Fallback scope | Per-session | Resets on app restart so Gemma 4 gets another chance |
| User notification | Yes | Always tell the user the model changed |

---

## Context Size Strategy

**Decision:** Accept model default for v1, pass `num_ctx: 8192` in options for safety.

Gemma 4 E4B default context is 8192 tokens. For a chat assistant with tool calls, this is sufficient for v1 (system prompt + ~20 messages + tool results).

If context becomes an issue, create a pinned model:

```
# Modelfile.ollamabob
FROM gemma4:e4b
PARAMETER num_ctx 16384
```

```bash
ollama create ollamabob -f Modelfile.ollamabob
```

This is a v2 optimization. For v1, `options.num_ctx: 8192` in the request is correct. VERIFIED that `/api/chat` accepts this.

---

## Web Search: Brave API (Corrected Pricing)

### Pricing (April 2026) — VERIFIED

| Plan | Cost | Notes |
|------|------|-------|
| Search | $5 per 1,000 requests | Includes $5/month automatic credit (~1,000 free requests) |
| Free tier | ~1,000 requests/month | Requires credit card for verification. Attribution required. |

**V1.0 was wrong:** "Free 2,000/month" is stale. New signups get $5/month credit = ~1,000 requests. VERIFIED.

### Fallback: SearXNG (Self-Hosted, Completely Free)

If you want zero cost and no API key:

```bash
docker run -d -p 8888:8888 searxng/searxng
# Query: http://localhost:8888/search?q=your+query&format=json
```

**V1 decision:** Use Brave for now (1,000/month is plenty for personal use). Stub `WebSearchTool` behind a `SearchProvider` protocol so SearXNG can be swapped in later without changing the agent loop.

```swift
protocol SearchProvider {
    func search(query: String) async throws -> [SearchResult]
}

struct BraveSearchProvider: SearchProvider { ... }
struct SearXNGProvider: SearchProvider { ... }  // v2
```

---

## v1 Tool Set (4 Tools)

| Tool Name | Description for Model | Implementation |
|-----------|----------------------|----------------|
| `shell` | Run a shell command on macOS. Returns stdout and stderr. | `Process()` with `/bin/zsh -c` |
| `read_file` | Read the contents of a file at the given path. | `FileManager` |
| `search_files` | Find files matching a name pattern or size threshold. | `mdfind` / `find` via `Process()` |
| `web_search` | Search the web. Returns top 5 results with titles, URLs, and snippets. | Brave Search REST API |

**No `write_file` in v1.** Add after logging and approvals are solid.

---

## Hard Output Limits (NEW in V1.1)

Every tool output is capped before the model sees it:

| Limit | Value | Rationale |
|-------|-------|-----------|
| Shell stdout max | 10,000 chars | Prevents `cat hugefile` from wrecking context |
| Shell stderr max | 2,000 chars | Errors are usually short |
| File read max | 100 KB | ~100K chars is already a lot of context |
| Search results max | 5 results | More is noise for the model |
| Search snippet max | 200 chars each | Keep context lean |
| Tool loop max iterations | 10 | Prevents infinite loops |
| Per-tool timeout | 30 seconds | Prevents hung processes |
| Total agent loop timeout | 120 seconds | Hard ceiling on any single user request |

### Truncation Format

When output exceeds the cap:

```
[first 10000 chars of output]

... [TRUNCATED: 45,231 total chars, showing first 10,000] ...
```

This tells the model (and the user) that output was cut.

```swift
func truncate(_ output: String, max: Int) -> String {
    guard output.count > max else { return output }
    let truncated = String(output.prefix(max))
    return "\(truncated)\n\n... [TRUNCATED: \(output.count) total chars, showing first \(max)] ..."
}
```

---

## Path Policy (NEW in V1.1)

Even for personal use, restrict where tools can roam:

```swift
struct PathPolicy {
    // Allowed without any approval
    static let allowed: [String] = [
        NSHomeDirectory(),          // ~/
        "/tmp",
        "/var/tmp",
        "/Applications",
        "/usr/local"
    ]
    
    // Require modal approval even for read-only
    static let sensitive: [String] = [
        "/System",
        "/Library",
        "/private",
        "/etc",
        "/var"  // (except /var/tmp)
    ]
    
    // Always denied
    static let forbidden: [String] = [
        "/dev",
        "/Volumes"  // external drives — too risky for v1
    ]
    
    static func check(_ path: String) -> PathAccess {
        if forbidden.contains(where: { path.hasPrefix($0) }) { return .denied }
        if sensitive.contains(where: { path.hasPrefix($0) }) { return .requiresApproval }
        if allowed.contains(where: { path.hasPrefix($0) }) { return .allowed }
        return .requiresApproval  // unknown paths need approval
    }
}
```

This applies to `read_file`, `search_files`, and shell commands that reference paths. For shell commands, this is best-effort (the model could construct a path indirectly), but it catches the common cases.

---

## Approval Policy (Revised — No Auto-Approve)

V1.0 had `confirm` with 3-second auto-approve. **Removed.** All writes require explicit user action.

```swift
enum ApprovalLevel {
    case none       // Execute silently, log only
    case modal      // NSAlert, blocks until user explicitly approves
    case forbidden  // Never execute, tell model "not allowed"
}

func approvalLevel(for toolName: String, arguments: [String: Any]) -> ApprovalLevel {
    // Non-shell tools
    switch toolName {
    case "read_file":
        let path = arguments["path"] as? String ?? ""
        return PathPolicy.check(path) == .denied ? .forbidden :
               PathPolicy.check(path) == .requiresApproval ? .modal : .none
    case "search_files":
        let path = arguments["path"] as? String ?? NSHomeDirectory()
        return PathPolicy.check(path) == .denied ? .forbidden :
               PathPolicy.check(path) == .requiresApproval ? .modal : .none
    case "web_search":
        return .none
    case "shell":
        break  // fall through to shell-specific logic
    default:
        return .modal  // unknown tool = always ask
    }
    
    // Shell command analysis
    let cmd = (arguments["command"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    let lower = cmd.lowercased()
    
    // Forbidden — never allow
    let forbidden = ["sudo ", "su ", "mkfs", "dd if=", "> /dev/",
                     "curl|sh", "curl | sh", "wget|sh", "wget -O - |",
                     "rm -rf /", "chmod -R 777 /"]
    if forbidden.contains(where: { lower.contains($0) }) { return .forbidden }
    
    // Modal — destructive or write operations (ALL of them, no auto-approve)
    let writes = ["rm ", "rm -", "rmdir", "mv ", "cp ", "mkdir",
                  "touch ", "chmod", "chown", "kill ", "killall", "pkill",
                  "brew install", "brew uninstall", "pip install", "pip uninstall",
                  "npm install", "launchctl", "defaults write", "defaults delete",
                  "networksetup", "scutil", "pmset", "dscl", "hdiutil",
                  "tee ", ">>", "> "]
    if writes.contains(where: { lower.contains($0) }) { return .modal }
    
    // None — read-only: ls, cat, find, ping, df, ps, top, sw_vers, etc.
    return .none
}
```

**Key change from V1.0:** The `confirm` level is gone. Everything is either `none` (safe, just log it) or `modal` (explicit approval required). No grey zone.

---

## Launch Preflight Checklist (NEW in V1.1)

Before the UI says "Bob is ready," verify:

```swift
struct Preflight {
    struct Status {
        var ollamaReachable: Bool = false
        var modelInstalled: Bool = false
        var braveKeyPresent: Bool = false
        var databaseWritable: Bool = false
        var sandboxDisabled: Bool = false
    }
    
    static func run() async -> Status {
        var s = Status()
        
        // 1. Ollama reachable
        s.ollamaReachable = await checkURL("http://localhost:11434/api/tags")
        
        // 2. Selected model installed
        if s.ollamaReachable {
            let models = await fetchModels()
            s.modelInstalled = models.contains(ModelConfig.primary)
                            || models.contains(ModelConfig.fallback)
        }
        
        // 3. Brave API key present (optional — web search degrades gracefully)
        s.braveKeyPresent = !AppConfig.braveAPIKey.isEmpty
        
        // 4. Database writable
        s.databaseWritable = Database.shared.canWrite()
        
        // 5. Sandbox disabled (check at runtime)
        s.sandboxDisabled = !ProcessInfo.processInfo.environment.keys.contains("APP_SANDBOX_CONTAINER_ID")
        
        return s
    }
}
```

If Ollama is unreachable or no model is installed, show an error view instead of the chat panel. If Brave key is missing, disable web_search tool but keep everything else working.

---

## SQLite Schema (Unchanged from V1.0)

```sql
CREATE TABLE conversations (
    id         TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    title      TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE messages (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role            TEXT NOT NULL CHECK(role IN ('system','user','assistant','tool')),
    content         TEXT,
    tool_calls_json TEXT,
    tool_call_id    TEXT,
    created_at      TEXT DEFAULT (datetime('now'))
);
CREATE INDEX idx_messages_conv ON messages(conversation_id, created_at);

CREATE TABLE tool_log (
    id              TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    conversation_id TEXT NOT NULL REFERENCES conversations(id),
    tool_name       TEXT NOT NULL,
    input_json      TEXT NOT NULL,
    output_text     TEXT,
    approval_level  TEXT CHECK(approval_level IN ('none','modal','forbidden')),
    approved        INTEGER,
    duration_ms     INTEGER,
    executed_at     TEXT DEFAULT (datetime('now'))
);

CREATE TABLE memory (
    id         TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    key        TEXT NOT NULL UNIQUE,
    value      TEXT NOT NULL,
    category   TEXT DEFAULT 'general',
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);
```

Note: `approval_level` CHECK updated to remove `'confirm'` (no longer exists in V1.1).

---

## Project Structure (Updated)

```
OllamaBob/
├── OllamaBob.xcodeproj
├── OllamaBob/
│   ├── OllamaBobApp.swift              # @main, MenuBarExtra, window management
│   ├── AppConfig.swift                  # Model config, API keys, limits (NEW)
│   ├── Info.plist                       # LSUIElement = true (no dock icon)
│   │
│   ├── Models/
│   │   ├── Message.swift                # Chat message Codable struct
│   │   ├── Conversation.swift           # Conversation container
│   │   ├── ToolCall.swift               # Parsed tool call — handles object AND string arguments
│   │   ├── ToolResult.swift             # Execution result
│   │   ├── ApprovalLevel.swift          # enum: none, modal, forbidden
│   │   └── JSONValue.swift              # Custom enum for flexible JSON parsing (NEW)
│   │
│   ├── Agent/
│   │   ├── AgentLoop.swift              # THE CORE: prompt -> ollama -> validate -> approve -> execute -> repeat
│   │   ├── OllamaClient.swift           # HTTP client for /api/chat (native endpoint)
│   │   ├── ToolRegistry.swift           # Tool schemas + name-to-executor mapping + validation
│   │   ├── ApprovalPolicy.swift         # Command + path -> approval level
│   │   ├── PathPolicy.swift             # Allowed/sensitive/forbidden path zones (NEW)
│   │   ├── OutputLimits.swift           # Truncation and caps for tool outputs (NEW)
│   │   └── Preflight.swift              # Launch health checks (NEW)
│   │
│   ├── Tools/
│   │   ├── ShellTool.swift              # Process() wrapper, stdout/stderr, 30s timeout
│   │   ├── FileReadTool.swift           # FileManager read, 100KB max
│   │   ├── FileSearchTool.swift         # mdfind/find wrapper
│   │   ├── WebSearchTool.swift          # SearchProvider protocol + BraveSearchProvider
│   │   └── SearchProvider.swift         # Protocol for swappable search backends (NEW)
│   │
│   ├── Views/
│   │   ├── MenuBarView.swift            # MenuBarExtra dropdown content
│   │   ├── AvatarWindow.swift           # Floating NSPanel, borderless, draggable
│   │   ├── ChatPanel.swift              # Main conversation view
│   │   ├── ChatBubble.swift             # Message bubble (user/assistant styles)
│   │   ├── ToolActivityView.swift       # Log of tool executions
│   │   ├── ApprovalAlert.swift          # NSAlert wrapper for dangerous commands
│   │   └── PreflightErrorView.swift     # Shown when Ollama/model not available (NEW)
│   │
│   ├── Persistence/
│   │   ├── Database.swift               # GRDB connection, setup, migrations
│   │   └── Schema.swift                 # Table definitions
│   │
│   ├── Personality/
│   │   └── BobPersonality.swift         # System prompt, personality config
│   │
│   └── Assets.xcassets/
│       ├── BobIcon.imageset/            # Menu bar icon (16x16, 32x32)
│       └── BobAvatar.imageset/          # Floating avatar image
│
└── OllamaBobTests/
    ├── AgentLoopTests.swift
    ├── OllamaClientTests.swift
    ├── ApprovalPolicyTests.swift
    ├── PathPolicyTests.swift             # NEW
    ├── OutputLimitsTests.swift           # NEW
    └── ToolTests.swift
```

### New Files in V1.1

| File | Purpose |
|------|---------|
| `AppConfig.swift` | Central config: model names, API keys, limits, fallback behavior |
| `JSONValue.swift` | Custom Codable enum to handle arguments as object OR string |
| `PathPolicy.swift` | Allowed/sensitive/forbidden path classification |
| `OutputLimits.swift` | Truncation functions and constants |
| `Preflight.swift` | Launch-time health checks |
| `SearchProvider.swift` | Protocol for swappable search backends |
| `PreflightErrorView.swift` | Error UI when Ollama/model not available |

---

## Weekend Build Order (Revised)

### Pre-Kickoff Checklist (Before Saturday — 30 minutes)

Do this the night before:

```bash
# 1. Pin Ollama version
ollama --version  # must be >= 0.20.2

# 2. Pull models
ollama pull gemma4:e4b
ollama pull qwen2.5:14b  # fallback ready

# 3. Capture real wire format samples (save these!)
# Plain response:
curl -s http://localhost:11434/api/chat -d '{
  "model": "gemma4:e4b",
  "messages": [{"role": "user", "content": "Say hello"}],
  "stream": false
}' | python3 -m json.tool > ~/ollamaBob/samples/plain_response.json

# Tool call response:
curl -s http://localhost:11434/api/chat -d '{
  "model": "gemma4:e4b",
  "messages": [{"role": "user", "content": "List files in /tmp"}],
  "tools": [{"type": "function", "function": {"name": "shell", "description": "Run a shell command", "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}}],
  "stream": false
}' | python3 -m json.tool > ~/ollamaBob/samples/tool_call_response.json

# Multi-turn tool response (feed the result back):
# [use the tool_call response above to construct the next request with a tool result]

# 4. Create Brave Search API key at brave.com/search/api
# Save key — do NOT commit to repo

# 5. Verify Brave billing: check your dashboard shows $5/month credit
```

**Code your Swift Codable models against these saved JSON files, not against documentation examples.** VERIFIED that this prevents wire-format surprises.

### Saturday Morning — Prove the Core (4 hours)

| # | File / Action | What You're Proving | Time |
|---|---------------|---------------------|------|
| 1 | `AppConfig.swift` | Central config struct with model names, API keys, all limits from this doc | 20m |
| 2 | `Models/JSONValue.swift` | Custom Codable enum handling object AND string arguments | 20m |
| 3 | `Models/Message.swift` | Codable structs for Ollama native `/api/chat` request/response — code against your saved JSON samples | 25m |
| 4 | `Models/ToolCall.swift` | Parsed tool call with `parsedArguments` that normalizes both formats | 20m |
| 5 | `Agent/OllamaClient.swift` | URLSession POST to `/api/chat`. Parse response. Include `options.num_ctx`. Unit test against real Ollama | 45m |
| 6 | `Agent/ToolRegistry.swift` | Tool JSON schemas for 4 tools. Validation: reject unknown tools, check required args | 30m |
| 7 | `Tools/ShellTool.swift` | `Process()` wrapper. stdout/stderr capture. 30s timeout. Test: `ls /tmp` | 30m |
| 8 | `Agent/OutputLimits.swift` | Truncation functions with format from this doc | 15m |

**GATE:** If Gemma 4 produces invalid tool_calls in your saved samples OR in the unit test, switch `AppConfig.primary` to `qwen2.5:14b` before proceeding.

### Saturday Afternoon — Agent Loop + Remaining Tools (4 hours)

| # | File / Action | What | Time |
|---|---------------|------|------|
| 9 | `Tools/FileReadTool.swift` | Read file, 100KB max, truncation format | 15m |
| 10 | `Tools/FileSearchTool.swift` | `mdfind` wrapper, max 20 results | 20m |
| 11 | `Tools/SearchProvider.swift` | Protocol: `func search(query:) async throws -> [SearchResult]` | 10m |
| 12 | `Tools/WebSearchTool.swift` | BraveSearchProvider implementing protocol. Parse top 5 results, 200-char snippets | 30m |
| 13 | `Agent/PathPolicy.swift` | Allowed/sensitive/forbidden zones from this doc | 15m |
| 14 | `Agent/ApprovalPolicy.swift` | Full policy: tool + command + path analysis. No auto-approve. | 25m |
| 15 | `Agent/AgentLoop.swift` | Core loop: send → parse → validate → approve → execute (with caps) → feed back → repeat. Max 10 iterations. 120s total timeout. | 90m |
| 16 | Tests | AgentLoop end-to-end: "list files in /tmp" → shell → result. Also test: hallucinated tool rejection, approval for `rm`, forbidden for `sudo` | 30m |

**GATE:** AgentLoop must complete a full tool-calling round trip AND correctly reject a hallucinated tool before touching UI.

### Saturday Evening — Chat UI (2 hours)

| # | File / Action | What | Time |
|---|---------------|------|------|
| 17 | `OllamaBobApp.swift` | MenuBarExtra with Bob icon. Click → open chat window | 30m |
| 18 | `Views/ChatBubble.swift` | User = right/blue, assistant = left/gray, tool = monospace/dark | 15m |
| 19 | `Views/ChatPanel.swift` | ScrollView + TextField + send button. Wire to AgentLoop. Show inline tool activity | 45m |
| 20 | `Views/ApprovalAlert.swift` | NSAlert: shows command, path, risk level. Approve/Deny only. No auto-approve | 30m |

**GATE:** Type a message → see tool call → see result → get approval dialog for `rm` → denial works.

### Sunday Morning — Persistence + Preflight (3 hours)

| # | File / Action | What | Time |
|---|---------------|------|------|
| 21 | `Persistence/Schema.swift` | SQL from this doc | 15m |
| 22 | `Persistence/Database.swift` | GRDB setup, create tables, CRUD helpers | 45m |
| 23 | Wire persistence | ChatPanel saves messages, loads on open | 30m |
| 24 | `Agent/Preflight.swift` | Launch checks: Ollama, model, Brave key, database, sandbox | 20m |
| 25 | `Views/PreflightErrorView.swift` | Error UI: "Ollama not running" / "Model not installed" / "Start Ollama and relaunch" | 15m |
| 26 | `Views/ToolActivityView.swift` | List of tool_log entries. Expandable | 25m |

**GATE:** Quit → reopen → conversation loads. Launch without Ollama → error view shown.

### Sunday Afternoon — Avatar + Personality + Acceptance Tests (3 hours)

| # | File / Action | What | Time |
|---|---------------|------|------|
| 27 | `Personality/BobPersonality.swift` | System prompt from this doc | 10m |
| 28 | `Views/AvatarWindow.swift` | NSPanel: borderless, floating, 64x64, click toggles chat | 45m |
| 29 | Avatar states | Idle / thinking / working — SF Symbol or opacity | 15m |
| 30 | `Views/MenuBarView.swift` | Dropdown: Open Chat, Tool Activity, Quit | 15m |

**Acceptance tests (must all pass before calling v1 done):**

| # | Test | Expected |
|---|------|----------|
| A1 | "List files in my home directory" | Shell tool, `ls ~`, results shown |
| A2 | "Find files larger than 1GB" | Shell tool, `find`, results (or "none found") |
| A3 | "Read the contents of ~/.zshrc" | read_file tool, contents displayed |
| A4 | "Search the web for macOS M1 optimization tips" | web_search, 5 results with snippets |
| A5 | "Delete ~/ollamaBob/samples/test.txt" | Approval dialog → deny → model told "denied" |
| A6 | "Run sudo rm -rf /" | Forbidden → model told "not allowed, never" |
| A7 | "Install htop with homebrew" | Approval dialog → approve → `brew install htop` runs |
| A8 | Close chat, reopen | Previous conversation loads |
| A9 | Quit app, relaunch | Conversation persists. Preflight passes. |
| A10 | Stop Ollama, launch app | Preflight error view shown |

---

## Bob's Personality (System Prompt)

```
You are Bob, a helpful and slightly cheeky AI assistant living on Zack's M1 Mac.

You have access to these tools:
- shell: Run shell commands on macOS
- read_file: Read file contents
- search_files: Find files by name or size
- web_search: Search the web

Guidelines:
- Be concise and useful. Don't over-explain.
- When using tools, briefly say what you're doing and why.
- If a task needs multiple steps, think through them before acting.
- If you're unsure about a destructive action, say so.
- Be occasionally witty but never at the expense of usefulness.
- You run locally on this Mac. You are private. No data leaves this machine (except web searches).
- If you can't do something, say so honestly.
- When a command is denied or forbidden, do not try to work around it.
- Truncated output means the full result was too large. Summarize what you see and offer to narrow the search.
```

---

## Verified Facts (Updated)

| Claim | Status |
|-------|--------|
| Ollama `/api/chat` supports tools + `options.num_ctx` | VERIFIED |
| `/api/chat` returns arguments as JSON **object** | VERIFIED |
| `/v1/chat/completions` returns arguments as JSON **string** | VERIFIED |
| Multi-turn bug: arguments may flip between object and string | VERIFIED |
| Tool results use `role: "tool"` with `tool_name` on native API | VERIFIED |
| Gemma 4 E4B tool calling requires Ollama >= 0.20.2 | VERIFIED |
| Gemma 4 ~89% reliable, hallucinated calls documented | VERIFIED |
| Gemma 4 special chars in arguments can crash parser | VERIFIED |
| Qwen 2.5 is more reliable fallback (same API format) | VERIFIED |
| Brave Search: $5/month credit (~1,000 requests) for new signups | VERIFIED |
| Brave Search: old "free 2,000/month" is stale for new users | VERIFIED |
| SearXNG is completely free self-hosted alternative | VERIFIED |
| `Process()` works if App Sandbox OFF | VERIFIED |
| `MenuBarExtra` available since macOS 13 | VERIFIED |
| `NSPanel.floating` creates always-on-top window | VERIFIED |
| `LSUIElement = true` hides from Dock | VERIFIED |
| GRDB.swift is actively maintained | VERIFIED |
| Hermes has no programmatic approval injection | VERIFIED |
| Hermes RPC mode is feature request, not code | VERIFIED |
| NonnaClaw does not exist as a repo | VERIFIED |

---

## Do Not Build Yet (v2/v3)

### Deferred to v2
- Voice input (whisper.cpp) / output (AVSpeechSynthesizer)
- MCP integration (replace direct Brave call with MCP servers)
- Streaming responses (use `stream: false` until Gemma 4 stabilizes)
- Multi-model routing (E4B quick / 26B hard)
- Screenshot/vision analysis
- `write_file` tool
- Animated avatar
- Hermes Agent integration (after RPC mode ships)
- Drag-and-drop files onto avatar
- Background scheduled tasks (launchd)
- SearXNG as alternative search provider
- Extended context via Modelfile

### Deferred to v3
- Self-improving memory / preference learning
- Browser automation
- Messaging platform integration (Telegram, etc.)
- Entertainment mode / games
- Plugin/extension system
- Multi-conversation support

### Dependencies to Avoid
| Dependency | Why |
|------------|-----|
| Hermes Agent | No clean Swift integration path |
| Open Interpreter | AGPL, Python-only |
| Any Python subprocess | Eliminates IPC complexity |
| Electron / web views | Native Swift |
| LangChain / LangGraph | Agent loop is Swift |
| Docker (for v1) | Not needed until SearXNG |
| Node.js / npm | Direct HTTP calls |
| MCP for v1 | Adds bridge complexity |

### Time Traps
| Trap | Why |
|------|-----|
| Streaming + tool calls | Known broken with Gemma 4. `stream: false`. |
| Complex/nested tool params | Gemma 4 flattens them. Keep flat. |
| OpenAI-compatible endpoint | Use native `/api/chat` — simpler, more control |
| Auto-approve behavior | Just... don't. Explicit approval only. |
| Perfect avatar animation | Static + 3 states is fine |
| Optimizing SQLite schema | It works. Migrate later. |

---

## Success Criteria (Unchanged + Acceptance Tests)

End of weekend, OllamaBob v1 can:

1. Sit in the menu bar with a Bob icon (no Dock presence)
2. Show a floating avatar window (64x64, draggable, always-on-top)
3. Click avatar or menu bar → open chat panel
4. Accept user messages and send to Ollama
5. Parse tool calls (handling both argument formats)
6. Validate tool calls (reject hallucinated tools)
7. Execute shell commands (with modal approval for writes, forbidden for sudo)
8. Enforce path policy (deny /dev, require approval for /System)
9. Truncate oversized tool output before sending to model
10. Read files and search for files
11. Search the web via Brave API (graceful degradation if no key)
12. Show tool activity in a log view
13. Persist conversations and tool history in SQLite
14. Survive quit/reopen with conversation intact
15. Show preflight error if Ollama not running or model not installed
16. Fall back to Qwen 2.5 after 3 consecutive tool parse failures
17. Pass all 10 acceptance tests (A1-A10)

**Ship it. Iterate later.**
