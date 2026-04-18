# OllamaBob V2 — Implementation Plan (DRAFT for review)

## Context for reviewers

OllamaBob is a **native macOS menu bar AI assistant** written in Swift/AppKit/SwiftUI. V1 ships today: chrome-less chat window, SQLite persistence, custom Swift agent loop, 4 tools (shell, read_file, search_files, web_search), talks to local Ollama at `/api/chat` (native, not OpenAI-compatible), `num_ctx=8192`, stream=false. Primary model `gemma4:e4b`, fallback `qwen3:14b`.

Constraints from project CLAUDE.md that still apply:
- Flat tool parameter schemas only (Gemma4 special-character fragility)
- No streaming
- No write_file in v1
- App sandbox OFF (required for `Process()` shell execution)
- All destructive ops behind NSAlert approval; forbidden ops never execute
- SQLite via GRDB.swift

## V2 goals

Turn Bob from "shell-runner" into "complete personal assistant" without exceeding the 8K context window budget and without hardcoding a persona.

1. Bundle ~20 high-value tools (PDF, OCR, media, data) so Bob works on a Mac with zero external dependencies
2. Add a **tool discovery layer** that lets Bob pick the right tool from natural language without bloating the system prompt
3. Add **persistent memory** that survives conversation resets and app restarts (sticky facts + semantic)
4. Add a **user-configurable persona system** (no hardcoded character)
5. Add **memory view/edit/import UI** in Preferences
6. Add **beta tools** category for anything that may break the model or has safety implications
7. Keep v1 architecture; extend don't replace

## Pre-flight investigations (MUST complete before Phase 1)

Block all implementation until these three tests resolve. Each is 1-3 hours of work.

### Investigation A: `num_ctx` ceiling
Test Gemma4:e4b and Qwen3:14b at `num_ctx = 8192, 16384, 32768, 65536` (if supported). Measure:
- Does the model load?
- First-token latency on a 2K-token prompt
- Total latency for a 50-message conversation replay
- VRAM/RAM use on M1 32GB

**Decision impact:** If we can run at 32K+ at reasonable latency, 70% of the compaction work in this plan becomes unnecessary.

### Investigation B: Shell-quoting reliability
50 realistic tool-call scenarios fed to Gemma4:e4b via the current agent loop, measuring how often it emits a broken shell invocation. Cases must include:
- Filenames with spaces, unicode, parens, brackets, quotes
- Regex patterns for ripgrep
- URLs with query strings and ampersands
- JSON strings for jq
- Paths with tildes and env vars

**Decision impact:** If >5% fail, primary model becomes Qwen3:14b (slower but better at escaping), OR we add a pre-execution shell validator that re-parses before `Process.launch()`.

### Investigation C: Vector store + GRDB compatibility
Can GRDB.swift load the `sqlite-vec` extension against macOS system SQLite? Or do we need to:
- Bundle a custom SQLite build with extension loading enabled, OR
- Switch from GRDB to a direct SQLite bridge, OR
- Skip sqlite-vec and use a flat JSON-on-disk vector store (fine for <10K embeddings), OR
- Use a separate vector store like faiss via a Python helper

**Decision impact:** Determines Phase 6 memory architecture. If sqlite-vec doesn't work, fallback is the flat-file vector store — simpler, slightly slower, same UX.

---

## Phase 1 — Context-first foundation

Goal: make Bob's context architecture sound before layering anything new. No new features; structural cleanup only.

**1.1 Raise `num_ctx`** to whatever Investigation A validates (target: 32K).

**1.2 Remove the Mumbai persona entirely.** Strip the `CHARACTER — NEVER BREAK THIS` block from `BobPersonality.swift`. Replace with a neutral default: *"You are a helpful assistant running on Zack's Mac. Be concise and useful."*

**1.3 Introduce `PersonaStore`.**
- New SQLite table `personas (id TEXT PK, name TEXT, system_prompt TEXT, is_default INTEGER, created_at, updated_at)`
- Ships with one seed row: a neutral default, not deletable
- New `BobPersonality.systemPrompt` becomes dynamic: reads active persona from DB, concatenates with the stable rules block (tool rules, macOS env, approval rules) that should apply to every persona
- Active persona is stored on the `conversations` table as `personaId`

**1.4 Tool output spillout.**
- Any tool result with `content.count > 2048` gets saved to `~/Library/Application Support/OllamaBob/tool_outputs/<conversation_id>/<turn_id>.txt`
- In-context content is replaced with a preview: `[Tool output saved — first 400 chars: "...". Call read_tool_output("<turn_id>") for the full result.]`
- New tool: `read_tool_output(turn_id: String)` — reads and returns the saved output, subject to the same 100KB cap
- ShellTool, FileReadTool, and FileSearchTool all respect this

**1.5 Per-tool approval categories.**
- Expand `ApprovalLevel` enum from `{none, modal, forbidden}` to include `{network, destructive, exfiltration}`
- Each tool declares its category
- Preferences has per-category toggles for whether modal vs automatic

**1.6 Tests:**
- Spill a 50KB shell output, verify it's stored on disk and the in-context version is ≤500 chars
- Create a new conversation with a custom persona, confirm the agent loop uses it
- Delete default persona — should fail
- 8 new unit tests covering PersonaStore CRUD

## Phase 2 — Tool bundling infrastructure

Goal: Bundle Tier-1 tools into the .app so Bob works on a clean Mac with nothing installed.

**2.1 Build script `scripts/bundle_tools.sh`** that:
- Takes a manifest file `tools/manifest.json` listing every tool + source path + target name
- For each tool: copies binary, runs `dylibbundler -b -x <binary> -d <app_frameworks> -p @executable_path/../Frameworks`
- Codesigns each bundled binary with ad-hoc or Developer ID cert
- Writes a `Tools/tools.json` inventory into the .app for runtime discovery

**2.2 Tier 1 tools to bundle:**

| Tool | Category | Purpose |
|------|----------|---------|
| pdftotext, pdftoppm, pdfinfo (poppler-utils) | docs | PDF text/image extraction |
| qpdf | docs | PDF split/merge/decrypt |
| tesseract + eng traineddata | docs | OCR |
| pandoc | docs | Universal doc conversion |
| ffmpeg | media | Audio/video Swiss army |
| jq | data | JSON query |
| yq | data | YAML query |
| miller (mlr) | data | CSV/TSV wrangling |
| ripgrep (rg) | search | Fast recursive search |
| fd | search | Fast file find |
| bat | view | Cat with syntax highlighting |
| tree | view | Directory rendering |
| zbar | image | QR/barcode scan |
| qrencode | image | QR generate |
| age | security | Simple encryption |
| exiftool | image | Metadata reader |
| (bundled Python venv) yt-dlp | media | Video download |
| whisper.cpp binary + small.en CoreML model | media | Local speech-to-text |

**2.3 PATH injection.** `ShellTool.execute()` prepends `${AppBundle}/Contents/Tools/bin` to `$PATH` before spawning bash. Bundled tools take precedence over system versions.

**2.4 First-run extraction for heavy assets.** Whisper model + tesseract traineddata copied from the .app into `~/Library/Application Support/OllamaBob/models/` on first launch so the .app itself stays portable and the data survives updates.

**2.5 Codesigning + notarization pipeline** (can be deferred to Phase 8 for dev builds; required for distribution). `scripts/notarize.sh` that submits the signed bundle to Apple's notarization service.

**2.6 Tests:**
- Clean Mac (VM or test account) runs the .app with no Homebrew, all bundled tools work
- Verify PATH injection doesn't shadow user-installed tools for non-bundled binaries
- Verify all bundled binaries pass `spctl --assess` after signing

## Phase 3 — Tool discovery layer

Goal: Bob picks the right tool from natural language without burning more than ~1K tokens on tool awareness.

**3.1 `ToolCatalog.json` manifest.** One line per tool with `{name, category, short_desc, one_line_example, help_file}`. Single source of truth.

**3.2 Cheat sheet generation.** Build step generates a compact Markdown cheat sheet from `ToolCatalog.json`. Beta-only tools included only when their category is enabled at runtime. Cheat sheet is injected into the system prompt each turn; dynamic content, hard capped at 1000 tokens.

**3.3 `tool_help(tool_name: String)` meta-tool.**
- Reads `~/Library/Application Support/OllamaBob/tools/help/<tool_name>.md`
- Returns content up to 4KB
- Help files are hand-authored for each Tier-1 tool, stored in the .app and copied on first run
- Bob calls this when the cheat sheet alone isn't enough

**3.4 `tool_search(intent: String)` semantic lookup.**
- Embeds `intent` via Ollama's `nomic-embed-text` model (need to pull this; ~270MB)
- Searches a pre-built local vector index of all tool descriptions (`~/Library/Application Support/OllamaBob/tools/index.vec` or the sqlite-vec table)
- Returns top 3 candidates with `{name, short_desc, confidence}`
- Fallback when Bob doesn't see an obvious match in the cheat sheet

**3.5 Beta tools toggle.**
- New Preferences section: "Advanced Tools"
- Per-category toggles with warning copy:
  - "CTF / Pentesting tools (nmap, hydra, etc.)" — disabled by default, first-enable confirmation
  - "Experimental tools (may produce unreliable output)" — disabled by default
  - "Network tools requiring internet access" — enabled by default
- Disabled categories are stripped from cheat sheet, tool_help, tool_search results, and the tool registry entirely

**3.6 Tests:**
- Ask Bob "download me this YouTube video" — he calls shell with `yt-dlp ...`, not a placeholder
- Ask Bob "transcribe this audio file" — he uses whisper
- Enable CTF category, ask Bob "port scan 127.0.0.1" — he calls nmap
- Disable CTF category, same question — Bob replies "that tool isn't enabled" (does not attempt to use nmap)

## Phase 4 — Sticky facts memory (Layer A)

Goal: Bob remembers simple user profile across sessions. Cheap and reliable.

**4.1 SQLite `facts` table** `(key TEXT PK, value TEXT, category TEXT, source_conversation_id TEXT, created_at, updated_at)`.

**4.2 Two new tools:**
- `remember(key: String, value: String)` — upsert
- `forget(key: String)` — delete

**4.3 System prompt injection.** At the start of each turn, facts are serialized into a compact `USER PROFILE:` block, capped at 200 tokens. Oldest facts truncated first if over budget.

**4.4 Memory view UI in Preferences.**
- New "Memory" tab
- Table: `key | value | category | last updated`
- Row actions: edit, delete
- Bulk: export to JSON, import from JSON, clear all (with confirmation)
- JSON schema versioned: `{"schema_version": 1, "facts": [{...}], "episodic": [{...}]}`

**4.5 Tests:**
- User says "my name is Zack and I prefer terse responses" → facts written, visible in UI
- Close app, reopen, new conversation, Bob knows the name without being told
- Edit fact in UI, Bob uses the edited value in next turn
- Export → clear → import → all facts restored

## Phase 5 — Conversation compaction

Goal: Handle long-running conversations without losing the thread or the persona.

**5.1 Compaction trigger.** When `estimated_tokens_used / num_ctx > 0.75`, run compaction.

**5.2 Compaction algorithm.**
1. Identify keepable range: system prompt, facts block, last 5 user-assistant pairs
2. Everything else is the "compaction target"
3. Build a reviewer prompt (persona-neutral, hardcoded): *"Summarize this conversation slice in 200 words. Preserve: decisions, tool findings, user preferences, open questions. Omit: pleasantries, rephrasing, tool invocation plumbing."*
4. Send the target to a dedicated summarization model — **always Qwen3:14b regardless of primary**, because summarization quality is the single highest-risk operation in this system
5. Replace the target range with a single synthetic `system` message: `[Earlier in this conversation (auto-summarized): <summary>]`
6. Continue normally

**5.3 Background episodic extraction.** While we have the summary, also extract any new facts or episodic memories and write them to the memory tables (Phase 4 + Phase 6).

**5.4 UI.**
- Status line shows `⚡ compacted Nx` counter
- Clicking opens a side panel with the full compaction history for the current conversation
- At 90% utilization, non-blocking banner: "Conversation is heavy. /clear recommended."
- At 98%, block new sends with: "Context full. Compact, /clear, or export and restart."

**5.5 Tests:**
- Replay a 40-turn fixture conversation, compaction fires, output resembles original intent
- Verify compaction summary is persona-neutral regardless of active persona
- Verify compaction does not lose any facts (before/after fact count equal or greater)

## Phase 6 — Semantic / episodic memory (Layer B)

Goal: Long-term memory that survives conversation clears.

**6.1 Depends on Investigation C.** If sqlite-vec works, use it. Otherwise, flat-file index.

**6.2 Embedding pipeline.**
- Use Ollama `nomic-embed-text` (pulled in Phase 3 for tool_search)
- After each assistant turn that is "learnable" (heuristic: turn contains a decision, a tool success, or a factual statement), background task extracts a one-sentence summary via a small LLM call, embeds it, stores
- `memories` table: `(id, summary TEXT, embedding BLOB, timestamp, conversation_id, tags TEXT)`

**6.3 Retrieval injection.**
- Before each user message hits Ollama, embed it, find top 5 similar memories with `similarity > 0.65`
- Inject as `[Relevant prior context: ...]` block in the user message, capped at 400 tokens
- Configurable per-user in Preferences (on/off, top-k, threshold)

**6.4 Memory encryption.**
- Database key stored in macOS Keychain under `com.ollamabob.memory-key`
- GRDB.swift with SQLCipher variant encrypts the `memories.sqlite` file at rest
- First launch generates key; if Keychain is wiped, memories are unrecoverable (this is correct behavior)

**6.5 Memory view UI.**
- Extends the Phase 4 "Memory" tab with a second subsection: "Episodic Memories"
- Searchable list, sortable by time/relevance
- Row actions: edit summary, delete, export
- Bulk import supports the same versioned JSON schema

**6.6 Tests:**
- 10 prior conversations, ask something related to conversation #3, verify retrieval surfaces the relevant memory
- Wipe Keychain, verify DB becomes unreadable (correct failure mode)
- Import 100 memories from JSON export

## Phase 7 — Persona system UI

Goal: User-defined personas with a clean editor.

**7.1 Persona editor in Preferences.**
- New "Personas" tab
- Table: `name | is_default | created`
- Row actions: edit (name + system prompt textarea), delete (disabled for default), duplicate, export to JSON, import from JSON
- New persona button opens modal with name + multi-line prompt editor

**7.2 Per-conversation persona.**
- "New Chat" button opens a small dropdown to pick persona (defaults to the default)
- Active persona shown in status line: `>_ gemma4:e4b • idle • as: Default`

**7.3 Example/seed personas** shipped disabled by default: none. The default is genuinely neutral, no Mumbai, no voice.

**7.4 Tests:**
- Create persona "Terse Linus", switch to it, Bob replies tersely
- Delete default persona — should fail with error dialog
- Export persona, import on fresh install — restored

## Phase 8 — Polish, hardening, distribution

**8.1 Full notarization pipeline** (if deferred from Phase 2).

**8.2 Audit log.** Every tool execution appends to `~/Library/Application Support/OllamaBob/audit.log` with timestamp, tool, args, exit code, duration. Viewable in Tool Activity window.

**8.3 Onboarding flow.** First-run wizard:
- Welcome
- "I found these tools on your system: [list]"
- "I bundled these: [list]"
- "Enable beta/advanced tools? [off]"
- Memory preferences
- Default persona pick / create

**8.4 Update mechanism.** Sparkle framework or manual "Check for Updates" that downloads a signed delta.

**8.5 Crash reporting.** Basic local-only crash log, no telemetry off-box without explicit user consent.

---

## Acceptance tests (V2)

V1's 10 tests (A1-A10) still must pass. New V2 tests:

| # | Test |
|---|------|
| B1 | Load a 2MB PDF via read_file + pdftotext pipeline, Bob extracts text correctly |
| B2 | Ask Bob to transcribe a 2-min audio file via whisper, returns text in <60s on M1 |
| B3 | "Download this YouTube video" (no tool named) → Bob uses yt-dlp |
| B4 | Fill context to 80%, auto-compaction fires, conversation continues coherently |
| B5 | Tell Bob "my name is X, I prefer terse" → new conversation, he still knows |
| B6 | CTF mode disabled, "port scan 127.0.0.1" → Bob says tool is disabled; enable, retry → uses nmap |
| B7 | Create persona "Grumpy Linus", switch, Bob replies in that voice |
| B8 | Edit a memory in Preferences, Bob uses the edited value |
| B9 | Export memories to JSON, import on a clean install, Bob recalls them |
| B10 | No Mumbai persona present anywhere in default install |
| B11 | Tool help markdown for every Tier-1 tool exists and is <4KB |
| B12 | Clean-Mac bundle runs with zero Homebrew dependencies |
| B13 | Memory DB is encrypted at rest; wiping keychain breaks it |
| B14 | Shell-quoting stress test suite passes (50 edge cases) |

## Out of scope for V2 (explicitly deferred)

- Phone service integration (Jarvis Phone Service — separate future module)
- Multi-conversation UI beyond basic new-chat + picker
- write_file tool
- Streaming responses
- Voice input from microphone (whisper is for file transcription only)
- CTF tool bundling at the binary level (Phase 3 CTF toggle enables tools expected at system paths; bundling CTF binaries is V3)
- Metasploit bundling (never — Ruby stack is too big)
- App Store distribution

## Open questions for reviewers

1. **Is raising `num_ctx` to 32K safe on M1 32GB with the two models in rotation?** (Investigation A)
2. **Is the per-turn cost of semantic retrieval (embedding + search + injection) worth it, or should we make Layer B opt-in only?**
3. **Should compaction always use Qwen3:14b, or is a smaller model fine for the summarization task?**
4. **Should we tag tools with approval categories at the catalog level, or let the model infer from context?**
5. **Should Tier-1 tools be downloaded on first launch instead of bundled, to keep the .app download small?** (Alt distribution model)
6. **Is there a better vector store than sqlite-vec / flat-file for a <10K memory DB?**
7. **How do we handle the user running their OWN Ollama instance with different models? Fall back gracefully?**

## Phase dependencies

```
Investigations A, B, C (parallel, must all pass)
         ↓
    Phase 1 (context foundation)
         ↓
    Phase 2 (tool bundling) ─┬→ Phase 3 (tool discovery)
         ↓                    │
    Phase 4 (sticky facts) ───┤
         ↓                    │
    Phase 5 (compaction)      │
         ↓                    ↓
    Phase 6 (semantic memory) ← Phase 7 (personas UI)
         ↓
    Phase 8 (polish + distribution)
```

Phases 2 and 4 can run in parallel after Phase 1. Phase 7 can run any time after Phase 1 (it only depends on PersonaStore). Phase 6 must wait for both Phase 3 (nomic-embed-text pulled) and Phase 5 (compaction extracts memories).
