# Phase 5 — Local Knowledge Layer (Re-Scope)

**Status:** DRAFT — owner approves before any 5x dispatch.
**Source:** §4 Phase 5 of `docs/PEER_REVIEW_TODO.md` (owner directive: "Phase 5 is huge; split it harder when we get there.").

The original Phase 5 listed two sub-phases (5a Activity Timeline, 5b Document Vault). Per owner directive, that's still too coarse. This document re-scopes Phase 5 into six smaller sub-phases, each independently shippable, each with its own success gate and feature-branch tag.

Each sub-phase ≤ 600 LOC of new code. Each lands behind a Preferences toggle defaulting OFF — no surprise indexing on first launch. The owner toggles features on individually as they're tested.

## Sub-phase ordering (owner-decision: pick one)

**Order A — Timeline first, then Vault.** Activity-event capture is cheap (no embeddings, no large index). Ships incremental value fast. Recommended default.

**Order B — Vault first, then Timeline.** Document semantic search is the more obvious "killer feature." Higher effort up front, slower first ship.

This plan defaults to **Order A**.

---

## 5.1 — Schema + ActivityEvent value type

**Scope IN:**
- `OllamaBob/OllamaBob/Persistence/Schema.swift` — additive `activity_event` table:
  ```sql
  CREATE TABLE activity_event (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL NOT NULL,
    source TEXT NOT NULL,        -- "tool" | "chat" | "fsevents"
    kind TEXT NOT NULL,          -- e.g. "tool_call", "user_message", "file_changed"
    detail TEXT NOT NULL,        -- short summary, capped 500 chars
    conversation_id TEXT,
    metadata_json TEXT           -- optional JSON blob (≤ 1KB)
  );
  CREATE INDEX idx_activity_event_timestamp ON activity_event (timestamp);
  CREATE INDEX idx_activity_event_source_kind ON activity_event (source, kind);
  ```
- `OllamaBob/OllamaBob/Persistence/Database.swift` — `appendActivityEvent(...)` and `fetchActivityEvents(since:until:source:limit:)`.
- NEW `OllamaBob/OllamaBob/Models/ActivityEvent.swift`.
- Tests: `Tests/OllamaBobTests/ActivityEventDatabaseTests.swift` (≥ 6 tests).

**Scope OUT:** all consumers — none yet, just the data layer.

**Success gate:** existing tests pass; new round-trip + filter + index tests pass.

**Estimated:** ≤ 250 LOC.

---

## 5.2 — ActivityIndexer: capture from ToolRuntime + ChatSessionController

**Scope IN:**
- NEW `OllamaBob/OllamaBob/Services/ActivityIndexer.swift` — `@MainActor` singleton subscribing to:
  - `AgentLoop+ToolDispatch.executeToolCall` post-execution hook (after `executeTool` returns; whether successful or not).
  - `ChatSessionController` user-message and assistant-message persistence hook.
- NEW `OllamaBob/OllamaBob/Models/AppSettings.swift` toggle: `activityTimelineEnabled: Bool` (default OFF).
- Adapter changes: 1 line each in `AgentLoopToolDispatch.swift` and `ChatSessionController.swift` to call `ActivityIndexer.shared.record(...)` when the toggle is ON.

**Scope OUT:** FSEvents, embeddings, search tools.

**Success gate:** toggle OFF → no rows written. Toggle ON → tool calls and chat messages append rows. Existing test suite green.

**Estimated:** ≤ 200 LOC.

---

## 5.3 — FSEvents source (opt-in per folder)

**Scope IN:**
- NEW `OllamaBob/OllamaBob/Services/FSEventsActivitySource.swift` — `FSEventStreamCreate` wrapper. User opts in per folder.
- AppSettings: `activityTimelineFolders: [String]` (paths) + Preferences UI to add/remove.
- Throttle: at most 1 event per 30s per folder. Coalesce burst writes.
- Per-folder mute toggle.

**Scope OUT:** content reading (FSEvents only logs the path + change type, never the file body).

**Success gate:** opt-in flow visible in Preferences. Removing a folder stops events for it. App relaunch preserves settings.

**Estimated:** ≤ 350 LOC.

---

## 5.4 — `timeline_search` and `summarize_recent_work` tools

**Scope IN:**
- NEW `OllamaBob/OllamaBob/Tools/TimelineSearchTool.swift` — args: `since`, `until`, `source`, `kind`, `query` (optional substring match), `limit`. Returns formatted lines bounded at 8KB, wrapped `<untrusted>`.
- NEW `OllamaBob/OllamaBob/Tools/SummarizeRecentWorkTool.swift` — args: `hours` (default 24), grouped by source/kind.
- ApprovalPolicy: both `.none` (read-only).
- ToolRegistry + BuiltinToolsCatalog + BobOperatingRules entries.

**Scope OUT:** semantic embedding search (5.6).

**Success gate:** Bob can answer "what did I do yesterday?" from the timeline.

**Estimated:** ≤ 250 LOC.

---

## 5.5 — Document Vault schema + IndexingService stub

**Scope IN:**
- `Persistence/Schema.swift` — additive `document_chunk` table:
  ```sql
  CREATE TABLE document_chunk (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_path TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,        -- chunk text, capped per-chunk
    embedding BLOB,                -- vector blob (nullable until 5.6)
    last_modified REAL NOT NULL,
    chunk_hash TEXT NOT NULL       -- to detect re-indexing need
  );
  CREATE INDEX idx_document_chunk_path ON document_chunk (document_path);
  CREATE INDEX idx_document_chunk_hash ON document_chunk (chunk_hash);
  ```
- NEW `Services/IndexingService.swift` — chunks documents (text/markdown/PDF) into 500-char chunks with 50-char overlap. Stores chunks WITHOUT embeddings yet (5.6 fills them in).
- AppSettings toggle: `documentVaultEnabled` (default OFF), `documentVaultFolders` (opt-in list).

**Scope OUT:** embeddings, search.

**Success gate:** opt-in folder produces chunk rows on demand. No embedding work.

**Estimated:** ≤ 350 LOC.

---

## 5.6 — Embeddings + `search_vault` tool

**Scope IN:**
- Use Apple's `NLContextualEmbedding` (no new SPM dep). Owner decision §9.6 still pending; if owner picks bundled CoreML MiniLM instead, this sub-phase scope grows.
- `IndexingService` fills `embedding` column for all chunks. Throttles on Low Power Mode.
- NEW `Tools/SearchVaultTool.swift` — args: `query`, `limit` (default 5). Returns top-K passages bounded at 8KB, wrapped `<untrusted>`.
- ApprovalPolicy: `.none` (read-only).
- "Forget everything between dates X and Y" path in Preferences.
- Per-folder visibility surface (what's currently indexed) in Preferences.

**Scope OUT:** UI tweaks beyond Preferences.

**Success gate:** Bob can answer "what did the contract say about X?" from indexed local docs. "Forget" wipes specified date range.

**Estimated:** ≤ 500 LOC.

---

## Cross-cutting STOP triggers (apply to every 5x sub-phase)

- Indexing folders the user did NOT explicitly opt into.
- Any vendor cloud call for embeddings.
- Any path that returns indexed content WITHOUT `<untrusted>` wrapping.
- Indexing chat messages outside the existing `messages` table (chats stay where they are, NEVER mirrored into `document_chunk`).
- Storage growth check: GRDB DB growth must be measurable. If a typical workload produces > 100 MB/day on the default index scope, scope must be reduced before that sub-phase ships.

---

## Owner decisions before any 5x dispatch

1. **Sub-phase order:** A (timeline first, recommended) or B (vault first)?
2. **5.6 embedding model:** Apple `NLContextualEmbedding` (no deps) or bundled CoreML MiniLM (better quality, larger asset)?
3. **5.3 default folders:** none (always opt-in) — confirm.
4. **5.5 PDF chunking:** PDF support out-of-scope for v1, or include?

Until these four are answered, no 5x branch is opened.
