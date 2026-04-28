# OllamaBob — Peer-Review Implementation Plan

**Source of truth for the work:** `docs/PEER_REVIEW.md`.
**Authoring agent (supervisor):** Claude (this session).
**Coding agents:** Task subagents dispatched **one phase at a time**, never overlapping.
**Status:** APPROVED for execution — owner answers locked in §9 (2026-04-28). Awaiting explicit "start Phase 0a" signal before any branch/tag/code work begins.

---

## 0. How this plan is executed

### Roles

- **Supervisor (me).** Owns this plan, dispatches subagents, validates each return, stops the line on drift, writes/lands commits.
- **Coding subagent (per-phase).** Receives a tightly scoped prompt containing only: (1) the phase scope box, (2) the preserved-components list, (3) the success-gate checks, (4) the STOP triggers, (5) the success report template. Returns: changed files list, test results, scope-box compliance check, preserved-component touch report, LOC delta on protected files. **Never sees this whole plan.**
- **Owner.** Approves the start of each phase, reviews each phase's bundled commit, decides whether to proceed.

### Cadence

1. Owner says "start phase N."
2. Supervisor runs the **Branch & Tag protocol** (§1.5): tag `pre-phase-N`, create branch `feature/phase-N-<slug>`, push branch, switch to it.
3. Supervisor dispatches a single subagent with the per-phase prompt.
4. **Compliance Check-in (§6.5):** subagent restates the 3 most critical STOP triggers and the primary file it is NOT allowed to modify, BEFORE writing any code. Supervisor verifies the restatement is accurate. If wrong: terminate and re-dispatch.
5. Subagent works on the feature branch and returns the success report (no commit yet).
6. Supervisor verifies: (a) scope box honored, (b) preserved components untouched, (c) no STOP trigger fired, (d) `swift build` clean, (e) `swift test` count ≥ 132 and 0 failures, (f) LOC deltas reported, (g) version bump applied.
7. Supervisor lands ONE bundled commit on the feature branch, runs the test suite one final time, then merges `feature/phase-N-<slug>` into `main`, tags `phase-N-complete`, and deletes the feature branch.
8. Owner approves; loop to next phase. **Or:** STOP and report (see §7).

### Multi-agent supervision rule

**Never run more than one coding subagent at once.** Phases are sequential. Parallelism is reserved for *research* subagents (read-only Explore) inside a single phase, never for code-writing subagents. This is a deliberate choice: the project's own `AGENTS.md` says "stay scoped," and parallel writers across god-classes (`AgentLoop`, `BobsDeskView`, `PreferencesView`) would race on the same files.

---

## 1.5 Branch & Tag protocol (non-negotiable)

`main` must remain green and shippable at all times. Each phase runs on its own feature branch, with a tag at start and at completion:

**Tag naming.** Tags are unique per dispatch — never reused, never overwritten. Format:

- Pre-phase anchor: `pre-phase-{slug}-{YYYYMMDD}` (e.g., `pre-phase-0b-20260428`).
- Completion marker: `phase-{slug}-complete-{YYYYMMDD}`.

If a phase is dispatched twice on the same day (e.g., after a STOP), append `-r2`, `-r3`. No mutable tags.

```bash
# Before subagent dispatch:
DATE=$(date +%Y%m%d)
git tag pre-phase-${SLUG}-${DATE}                       # immutable recovery anchor
git switch -c feature/phase-${SLUG}-${DATE}             # phase branch
git push -u origin feature/phase-${SLUG}-${DATE}        # only if remote exists; otherwise skip

# After phase success (supervisor lands one bundled commit on the feature branch):
swift build && swift test && ./build.sh                 # final pre-merge verification
git switch main
git merge --no-ff feature/phase-${SLUG}-${DATE}         # preserve phase boundary in history
git tag phase-${SLUG}-complete-${DATE}
git branch -d feature/phase-${SLUG}-${DATE}             # local delete

# On STOP:
git switch main                                         # leave the dirty branch alone for inspection
# Owner decides: abandon (delete branch + tag), refine (re-dispatch on same branch),
# or hard-revert (git reset --hard pre-phase-${SLUG}-${DATE} on main, only if main was somehow touched).
```

**Rules:**

- Never commit directly to `main` during a phase.
- Never delete a feature branch until merge succeeded and tests pass on `main`.
- Tags are immutable: `pre-phase-{slug}-{YYYYMMDD}` is the recovery anchor for that specific dispatch and is never moved, deleted, or reused. Re-dispatches get a new tag with `-r2`/`-r3` suffix.
- A `--no-ff` merge ensures the phase boundary stays visible in `git log`.
- If the owner has not configured a remote, the `git push` step is skipped; tags and branches stay local.

---

## 1. Non-negotiable architecture rules (carried into every phase)

These are repeated verbatim from `CLAUDE.md` / `AGENTS.md`. **Any subagent change that touches them is an automatic STOP:**

- Native SwiftUI/AppKit macOS app. No Electron, no web app, no cross-platform rewrite.
- Direct HTTP to Ollama at `localhost:11434`. Native `/api/chat`, **NOT** `/v1/chat/completions`.
- Agent loop in Swift. No external agent runtime.
- No Python subprocess, LangChain/LangGraph, Hermes, MCP runtime, Electron, Node, or Docker in the **app runtime**.
- `stream: false` for all Ollama requests.
- Flat tool parameter schemas.
- SQLite via GRDB for persistence.
- Native approval dialogs for side effects.
- App Store distribution out of scope.

**Preserved-by-default components (from AGENTS.md):**

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

A subagent **may** modify a preserved component only when the phase scope box explicitly names it. Otherwise: STOP.

---

## 2. Universal STOP triggers

The supervisor halts the line and reports to the owner if **any** of these fire during or after a subagent run:

| # | Trigger | Why |
|---|---|---|
| S1 | Any change to a non-negotiable architecture rule (§1) | Project contract violation. |
| S2 | New SPM/CocoaPods dependency not pre-approved in the phase scope box | Owner controls the dep surface. |
| S3 | Test count drops below the prior baseline | Coverage regression. |
| S4 | Any test failure in `swift test` | Unconditional. |
| S5 | LOC growth on a protected file (`AgentLoop.swift`, `BobsDeskView.swift`, `PreferencesView.swift`) without an explicit "this phase touches X" entry in scope box | God-class concern (R1). |
| S6 | Touch to a preserved-by-default component not named in scope box | Out-of-scope work. |
| S7 | Subagent proposed work outside the scope box ("while I was here I also fixed…") | Drift. |
| S8 | More than one phase in progress at the same time | Sequencing rule. |
| S9 | Any speculative rewrite, new state container, new event bus, new parser layer, new animation system, or broad refactor | AGENTS.md explicit prohibition. |
| S10 | Subagent's success report cannot cite real changed files (hallucinated diff) | Trust failure. |
| S11 | Visible app version not bumped per the version policy | Project rule. |
| S12 | Changes to `stream: false`, `/api/chat`, agent pipeline, window scene structure, native drag, or per-mode frame persistence not explicitly approved | AGENTS.md explicit stop list. |
| S13 | Any drift toward MCP runtime, `/v1/chat/completions`, streaming, or external Python/Node | Architecture rule violation. |
| S14 | Compliance Check-in (§6.5) failed — subagent could not accurately restate the phase's top STOP triggers and the primary forbidden file | Attention failure → drift risk. |
| S15 | Any commit landed on `main` during a phase (must be on the feature branch) | Branch protocol violation. |
| S16 | `pre-phase-N` tag missing at the start of the phase | Recovery anchor missing. |

When STOP fires: the supervisor (a) does not commit the subagent's work, (b) writes a STOP report citing which trigger fired with file/line evidence, (c) returns control to the owner.

---

## 3. Per-phase success gate (universal)

Every phase must pass all of these before commit:

```
[ ] swift build clean (warnings tolerated only if pre-existing)
[ ] swift test passes; test count >= prior baseline; 0 failures
[ ] ./build.sh produces build/OllamaBob.app
[ ] CFBundleShortVersionString and CFBundleVersion bumped per project rule
[ ] AppConfig.swift appVersion/appBuild bumped to match
[ ] README.md, CLAUDE.md, AGENTS.md, docs/CURRENT_HANDOFF.md version refs consistent
[ ] No STOP trigger fired
[ ] Subagent success report attached to commit message
```

Owner-side acceptance gate: `./build.sh --run` and a manual sanity click of the new feature path.

---

## 4. Phases (ranked by importance)

Phases are sequential. Each lists scope (in/out), success gate, sub-agent dispatch prompt skeleton, and STOP triggers specific to that phase **on top of** the universal §2 list.

---

### Phase 0 — Trust floor (ground-clearing)

**Why first.** Every later phase widens blast radius. Land trust infrastructure before piping screen pixels, FSEvents, or auto-approved repo writes into the agent.

**0a. Refresh the parked peer-review security/correctness stash as a reference backlog.**

**Owner decision (2026-04-28):** REFRESH, don't land wholesale, don't drop yet.

The stash is `stash@{2}: On avatar-overhaul-exec: peer-review security correctness pass`, ~1276 lines of patch. `git apply --check` does NOT apply cleanly on current `main` — it conflicts in `AgentLoop`, `ApprovalPolicy`, docs, Preferences, tests, and references files that no longer exist.

**Approach:** the stash is treated as a **reference backlog**, not an implementation branch.

- Extract its contents to `.local-docs/STASH_REFERENCE_BACKLOG.md` (gitignored): a digest of the security/correctness ideas, grouped by which later phase should consume them (0b sanitization, 0c keychain, 1 trust UI, 2a AgentLoop decomp).
- Keep the stash itself in `git stash` for the duration of Phases 0–2. Do NOT drop it.
- After Phase 2a lands, owner re-evaluates whether anything is still un-consumed; only then drop the stash.

**This is a supervisor task, not a coding subagent task.** No branch/tag protocol needed for 0a; nothing on `main` changes.

**0b. Resolve R4 — broaden HTML sanitization in `present(kind=html)`.**

**Owner decision (2026-04-28):** SwiftSoup approved. Use SwiftSoup as a pre-WebView allowlist sanitizer + retain CSP, JS-disabled, and navigation blocking as defense-in-depth (DO NOT remove existing WebView hardening when adding SwiftSoup).

- Scope IN: `Tools/PresentTool.swift`, `Services/PresentationService.swift`, `Views/RichHTMLView.swift` — sanitization layer only. **Plus:** `OllamaBob/Package.swift` and `OllamaBob/Package.resolved` to add the SwiftSoup dependency. New `Tests/OllamaBobTests/PresentationSanitizerTests.swift`.
- Scope OUT: any other tool, any other view, any change to existing CSP / JS-disabled / navigation-blocking configuration except to document it (must remain ON).
- New dep: `SwiftSoup` (MIT, pure Swift, SPM). Pin to a recent stable tag — subagent picks, supervisor verifies.
- Specific work:
  1. Add SwiftSoup as an SPM dep.
  2. Build a strict allowlist parser (tags, attributes, URL schemes) that runs BEFORE content reaches `WKWebView`.
  3. Persist sanitizer rule version in `AppConfig` (e.g., `htmlSanitizerVersion = 1`) so future hardening can be tracked.
  4. **Retain** existing `WKWebView` defense-in-depth: CSP header, JS disabled, navigation blocking. Document what each layer protects against in `Views/RichHTMLView.swift` header comment.
  5. Add ≥6 prompt-injection regression tests covering: `<script>`, `<iframe>`, `<object>`, `<form>` action, `javascript:` URLs, `data:` URLs, on-event handlers (`onclick=`, `onerror=`), CSS expression hacks, SVG-borne JS, base-tag hijacking.
- Phase-specific STOPs:
  - Removing or weakening any existing `WKWebView` hardening (CSP / JS-disabled / nav-block).
  - Enabling JS in `present(kind=html)` (that's Gemini's E-07 — explicitly on the don't-build list).
  - Adding any dep beyond SwiftSoup.
  - Sanitizer running INSIDE the WebView instead of before content reaches it.

**0c. N3 — Keychain Vault (one-time prompt migration).**

**Owner decision (2026-04-28):** ONE-TIME PROMPT, not silent migration. `.env` and process env stay as fallback / import sources, NOT silently migrated. Only UserDefaults-resident keys get migrated automatically.

**Confirmed UserDefaults-resident today:** `braveAPIKey`, `jarvisAPIKey`, `jarvisOperatorSecret`. ElevenLabs is `.env`-only — no UserDefaults migration needed for it.

- Scope IN:
  - New `Services/KeychainService.swift` (wrapper around `SecItemAdd`/`SecItemCopyMatching` with explicit kSecAttrAccessibleAfterFirstUnlock).
  - New `Services/SecretMigration.swift` orchestrating the one-time prompt + migration sequence.
  - `Models/AppSettings.swift` API-key getters/setters route through `KeychainService` (UserDefaults code path becomes legacy-only, kept to enable detection on first launch then write-deletion-after-success).
  - `Services/LocalEnv.swift` retains `.env` reads as fallback/import sources only.
  - `Views/PreferencesView.swift` API-key text-field bindings updated, plus an "Import from .env" button per key. **No other Preferences sections touched.**
- Scope OUT: ElevenLabs auto-migration (no UserDefaults presence; user opts in via Import button). Any other secret. Any tool surface change. Any change to existing approval/path policy.
- Migration sequence (first launch after this version):
  1. Detect presence of any of: `braveAPIKey`, `jarvisAPIKey`, `jarvisOperatorSecret` in UserDefaults.
  2. If found: show one-time modal: "Bob is moving N API key(s) to the macOS Keychain for security. Approve?" with a "Show details" disclosure listing which keys.
  3. On approve: for each key, read from UserDefaults → write to Keychain → on Keychain-write success, delete UserDefaults entry. On Keychain-write failure, leave UserDefaults entry intact and surface the error.
  4. Append a migration log entry (timestamp, keys-migrated count, success/failure per key) to a new gitignored `~/Library/Application Support/OllamaBob/migration.log`.
  5. On deny: do nothing this launch; re-prompt next launch.
- `.env` import flow: when the user clicks "Import from .env" next to a key field in Preferences, read the value from `.env` / process env, write to Keychain, leave the `.env` file alone.
- Phase-specific STOPs:
  - Never log secret values.
  - Never include secrets in `<untrusted>` blocks.
  - Never expose Keychain access as a tool the model can call.
  - Never silently migrate `.env` values without an explicit user click.
  - Never delete UserDefaults entry before Keychain write confirms success.

**Success gate (Phase 0):**

- All universal gates green.
- HTML sanitizer has new tests (target: ≥ 6 prompt-injection regression cases).
- Keychain migration test passes; PreferencesView text fields read/write Keychain transparently.
- Owner manual test: paste a known-malicious HTML payload into a `present` call → confirm it's neutralized.

**Subagent dispatch (skeleton):**

```
You are implementing Phase 0b (HTML sanitization) of the OllamaBob peer-review plan. You may modify ONLY: Tools/PresentTool.swift, Services/PresentationService.swift, Views/RichHTMLView.swift. You may add Tests/OllamaBobTests/PresentationSanitizerTests.swift. You may NOT touch any other file. You may NOT add a dependency without explicit owner approval (ask the supervisor before adding). You may NOT enable JS in WKWebView. You MUST NOT touch AgentLoop.swift, BobsDeskView.swift, PreferencesView.swift, or any preserved component listed in §1. Run `swift build` and `swift test` after every change. Return: list of changed files, test count delta, LOC delta on protected files (must be 0), and the prompt-injection cases your tests cover.
```

---

### Phase 1 — V6 Approval Trust UI / Diff Guardian

**Why next.** Trust UX must precede the high-blast features (V1/V2/V3/N1). Diff preview makes write_file safe; execution log makes the privacy story visible.

**1a. Diff preview for `write_file`.**

- Scope IN: `Agent/ApprovalPolicy.swift`, `Tools/FileWriteTool.swift`, `Views/ApprovalAlert.swift`, `Tools/ToolRuntime.swift` (only the path that hands off the structured preview). New `Models/WriteDiff.swift`.
- Scope OUT: every other tool, every other view, schema changes (1b will own those).
- Specific work: when `write_file`'s target exists, read current content, compute unified diff, attach to the approval payload. `ApprovalAlert` renders the diff in a scrollable view with mono font.
- Phase-specific STOPs: the diff must be computed in Swift (no shelling out to `diff`); the existing `path policy` and `forbidden shell shapes` floors must remain unchanged.

**1b. Execution log + Privacy Ledger view.**

- Scope IN: `Persistence/Schema.swift` (additive `execution_log` table), `Persistence/Database.swift` (one new write path + one read query), new `Models/ExecutionLogEntry.swift`, new `Views/PrivacyLedgerView.swift` (a Preferences sub-tab). `Tools/ToolRuntime.swift` writes a row on every approved side-effect tool execution (write/move/clipboard-write/AppleScript/youtube_download/phone_call).
- Scope OUT: any other read-only tool's instrumentation (read_file/list_directory/etc are *not* logged — privacy posture: log mutations, not reads).
- Persistence rule: **additive only** (per `docs/ARCHITECTURE_NOTES.md`).

**Success gate (Phase 1):**

- All universal gates green.
- New tests cover: diff render of small/large/binary files, log row written on approval, log NOT written on denial, ledger view filters by date/tool.
- Owner manual test: write to a known existing config file → see diff → approve → verify ledger entry appears.

---

### Phase 2 — God-class decomposition (R1) — Owner-selected: 2a only, defer 2b

**Owner decision (2026-04-28):** Option C. Decompose `AgentLoop.swift` now (orchestration code is where silent correctness/security bugs get expensive). **Defer `BobsDeskView.swift` decomposition** until after Phase 3 (Mac Context Lens) and Phase 4a (Call Cockpit) — UI direction will be clearer once those features land. UI bloat is annoying but visible and fixable; orchestration bugs are not.

**2b is removed from Phase 2.** A new "Phase 8 — Deferred BobsDeskView decomposition" will be added after Phase 7 polish, scoped at that time.

**Strict rule: this phase is a refactor, not a feature.** No behavior changes. All existing tests must pass with the same assertions. New tests are allowed only for the extracted seams.

**2a. Decompose `AgentLoop.swift`.**

- Target end-state: `AgentLoop` ≤ 800 LOC, with extracted coordinators:
  - `Agent/AgentLoopOllamaPump.swift` — owns the Ollama call/retry/fallback logic.
  - `Agent/AgentLoopToolDispatch.swift` — owns the tool-name → registry → runtime → result pipeline.
  - `Agent/AgentLoopApprovalGate.swift` — owns the modal-approval await + per-tool badge resolution.
  - `Agent/AgentLoopBatchGuard.swift` — owns the batch audio continuation guard / completion audit logic that's currently inline.
- Scope OUT: any change to the public method signatures `ChatSessionController` calls. Any change to `<untrusted>` wrapping behavior. Any change to compaction trigger.

**2b — DEFERRED to Phase 8 (post-killer-features, owner re-scopes at that time).**

**Success gate (Phase 2a):**

- All universal gates green, including no LOC growth on `AgentLoop.swift` beyond the target ceiling. `AgentLoop.swift` ≤ 800 LOC after refactor.
- New extracted coordinator files: each ≤ 600 LOC.
- The same 132+ tests pass with no assertion changes.
- Owner manual test: feature parity sweep — open desk, type, get reply, see avatar mood update, run a tool, see approval, see Tool Activity, run a batch audio request, run a Jarvis recap call (mocked or real), confirm uncensored mode toggle works. **Nothing visibly different.**

**Phase-specific STOPs:**

- New extracted file > 600 LOC.
- `AgentLoop.swift` final size > 800 LOC.
- Any existing test had its assertions modified.
- A new state container or event bus was introduced.
- Any change to `BobsDeskView.swift` (deferred to Phase 8).
- Any change to public method signatures `ChatSessionController` calls.
- Any change to `<untrusted>` wrapping behavior.
- Any change to compaction trigger timing.

---

### Phase 3 — V1 Mac Context Lens (killer feature 1)

**Why ahead of V2/V3.** Unanimous 4/4 #1 across all peers. Composes well with Phase 1's trust UX. V2 (Call Cockpit) can reuse the live-state UI primitives V1 ships.

- Scope IN: new `Services/MacContextService.swift` (frontmost app, window title, selected Finder paths, clipboard metadata snapshot, optional ScreenCaptureKit + Vision OCR). New tools in `Tools/`: `current_context`, `screen_ocr`, `selected_items`, `active_window` (each registered in `BuiltinToolsCatalog`/`ToolRegistry`). Small "context chip" UI in the extracted desk subview from Phase 2 showing what Bob is grounded on this turn.
- Scope OUT: auto-attaching context on every prompt. Storing screenshots to disk. Any change to compaction. Any change to the persona system (V1 does not auto-swap personas — that's N2's job, not this phase's).
- TCC: add `NSScreenCaptureUsageDescription` to the build plist; surface a permissions step in onboarding.
- New deps: none (ScreenCaptureKit and Vision are system frameworks).

**Phase-specific STOPs:**

- Any path that sends OCR'd content back to the model **without** `<untrusted>` wrapping.
- Any code path that captures the screen without the user explicitly invoking the tool.
- ScreenCaptureKit running on a timer (must be call-only).
- Any context auto-injection into `PromptComposer` outside the explicit tool path.

**Success gate (Phase 3):**

- All universal gates green.
- Tests cover: tool returns sane payloads when permission denied, OCR text is `<untrusted>`-wrapped before composition, context chip surfaces in UI when a context tool fires.
- Owner manual test: ask "what's in the active window?" → Bob calls `screen_ocr` → returns bounded summary → context chip visible.

---

### Phase 4 — V2 Jarvis Call Cockpit (killer feature 2)

**Split into 4a (mocked client + UI) and 4b (real daemon integration)** so the UI/UX work can ship and be demoed to the owner regardless of daemon-side readiness.

#### Phase 4a — UI + mocked Jarvis client

- Scope IN: new `Services/JarvisCallClient.swift` protocol (`listCalls`, `inject`, `transcript`) with two implementations: `JarvisCallClientMock` (canned responses for development/testing) and a stub `JarvisCallClientHTTP` that returns "not implemented" for the real endpoints. Extend `Tools/PhoneTool.swift` with new tools (`phone_list_calls`, `phone_inject`, `phone_get_transcript`) routing through the protocol. New `Views/LiveCallView.swift` rendered through `PresentationService` as an artifact. Per-injection approval gate in `ApprovalPolicy`. New `AppSettings` toggle: "Use mocked Jarvis client" defaulting to `true` until 4b lands.
- Scope OUT: any real daemon-side endpoint work, any change to `LocalAddressBook`, any change to `phone_call` baseline behavior, any change to dual-secret auth contract.
- New deps: none.

**Success gate (4a):**

- Universal gates green.
- Mock-driven LiveCallView demo: owner can open a fake live call, see a (canned) transcript stream, see suggested injections, approve or reject one, see the mock call end with a recap artifact.
- Tests cover the per-injection approval gate against the mock client.
- Switch to real client returns clean "not implemented" responses (no crashes).

**Phase-specific STOPs (4a):**

- Any code path that talks to the real Jarvis daemon (4b owns that).
- Any auto-injection of model-generated text into a call without explicit per-injection user approval.
- Any change to the Jarvis dual-secret auth contract.
- Any code path that records call audio locally (out of scope; daemon owns that).
- Any change to `LocalEnv` ancestor walk (it has a known bound from `0c16d35` — leave it alone).
- Mock client must be DEV-ONLY, never reachable in a release build. Compile the mock implementation under `#if DEBUG` (or behind a `Debug` SPM trait) so the release binary cannot instantiate it. The `AppSettings` toggle is a dev-mode affordance only; release builds always use `JarvisCallClientHTTP`.

#### Phase 4b — Real Jarvis daemon integration

**Prereq:** owner confirms the Jarvis daemon exposes (or will expose) `/call/list`, `/call/inject`, `/call/transcript` with the dual-secret auth contract. If those endpoints don't exist yet, 4b waits — but 4a has already shipped value.

- Scope IN: implement `JarvisCallClientHTTP` against the real endpoints. Flip the default `AppSettings` toggle from mock to real. Smoke-test against a running daemon in dev. Add an inline preflight in `Preflight.swift` so the app warns when the daemon is reachable but the new endpoints 404.
- Scope OUT: anything UI (4a owns that). Any change to dual-secret auth contract.

**Success gate (4b):**

- Universal gates green.
- Owner places a real test call and successfully injects an approved suggestion mid-call.
- Preflight warns clearly when daemon is on an old version without the new endpoints.

---

### Phase 5 — V3 Local Knowledge Layer (killer feature 3)

This is the largest phase by far. The owner has flagged that **5a/5b is still too coarse — split harder when we get there.** The current sub-phase listing below is a placeholder. Before Phase 5 begins, the supervisor will produce a `docs/PHASE_5_PLAN.md` re-scoping into 4–6 smaller sub-phases (e.g.: 5a-schema, 5b-tool-runtime-event-source, 5c-chat-event-source, 5d-FSEvents-source, 5e-timeline-search-tool, 5f-summarize-tool for the timeline path; vault path gets its own breakout). Owner approves the re-scope before any 5x dispatch.

**5a. Activity Timeline.**

- Scope IN: `Persistence/Schema.swift` additive `activity_event` table; `Services/ActivityIndexer.swift` (subscribes to `ToolRuntime` execution events, `ChatSessionController` message events, optional FSEvents on opt-in folders); new `timeline_search` and `summarize_recent_work` tools.
- Scope OUT: anything semantic / embeddings (5b owns that).
- Per-source toggles in PreferencesView (subscribe to ToolRuntime / subscribe to ChatSession / subscribe to FSEvents per folder).

**5b. Document Vault.**

- Scope IN: `Persistence/Schema.swift` additive `document_chunk` table with vector blob; `Services/IndexingService.swift` running an opt-in CoreML / Apple `NLContextualEmbedding` embed pass over user-selected folders; `search_vault` tool returning top-K passages bounded and `<untrusted>`-wrapped.
- Scope OUT: any chat-history embed (chats stay in `Conversation` tables, not `document_chunk`).
- Embedding model: prefer Apple `NLContextualEmbedding` (no new deps) over CoreML-converted MiniLM (would require asset bundling). Owner approval needed if a custom CoreML model is bundled.

**Phase-specific STOPs (both 5a and 5b):**

- Indexing folders the user did not explicitly opt into.
- Any vendor cloud call for embeddings (must be on-device).
- Any path that returns indexed content without `<untrusted>` wrapping.
- Storage growth check: GRDB DB growth must be reported per-day; if >100 MB/day on a typical workload, reduce default index scope.

**Success gate (Phase 5, both subphases):**

- "Forget everything between dates X and Y" path works and is tested.
- Per-folder opt-in surface is visible in PreferencesView.
- Indexing throttles correctly on battery / Low Power Mode.

---

### Phase 6 — N1 Code Companion Mode (owner-fit feature)

- Scope IN: new `project_context` tool (walks up to `.git` root, reads `Package.swift`/`project.pbxproj`, returns repo structure + last-N commits + current diff bounded). New `dev_mode` toggle in `PreferencesView` (per-conversation, off by default). When dev_mode is on AND the conversation is anchored to a detected `.git` root, `write_file` inside that root auto-approves. Outside that root, all existing approval gates apply unchanged.
- Scope OUT: changes to `shell` approval (still always gated). Changes to `git` tools' read paths.
- New deps: none.

**Phase-specific STOPs:**

- `write_file` auto-approval applying outside the detected `.git` root.
- `shell` ever auto-approving in dev_mode.
- Dev_mode persisting across new conversations (must be per-conversation).
- Missing visible UI indicator when dev_mode is active.

---

### Phase 7 — Polish layer (sequential within phase)

Land in this order, one at a time:

- **7a. V4 Skill Capsules.** GRDB `skill` table; declarative recipes over existing tools only; `create_skill`, `list_skills`, `inspect_skill`, `run_skill` tools. **Hard rule:** a skill is a recipe over existing first-party tools, *not* an executable scripting layer. Approval policy applies per-step.
- **7b. V5 Walkie-Talkie.** `Services/SpeechService.swift` using `SFSpeechRecognizer` + `AVSpeechSynthesizer` + global hotkey via `NSEvent.addGlobalMonitor`. Push-to-talk only.
- **7c. N2 Focus Guardian.** `Services/FocusService.swift` observing `NSWorkspace.shared.runningApplications`; map bundle-id → context profile → optional persona swap (with manual override always visible). Subtle indicator in desk view.
- **7d. V8 Clipboard Cortex.** Passive `NSPasteboard` watcher with cheap regex-gated trigger before model invocation; results as a chip in the menu-bar dropdown, not auto-pasted.
- **7e. V7 Proactive / Daily Briefing.** `BackgroundTasks` + `SchedulerService` persisting cron-like expressions in `AppSettings`. Read-only auto-approval in headless mode only.

**Phase-specific STOPs:**

- 7a: any code path that lets a skill bypass `ApprovalPolicy`.
- 7c: persona thrashing (must debounce app-switch).
- 7d: model invocation on every clipboard write (must be regex-gated).
- 7e: any tool with `modal` approval running headless.

---

## 5. What is explicitly NOT in this plan

These are the don't-build items from the review. A subagent that proposes any of them must be redirected:

- JS support in `present(kind=html)` until R4 is closed (Gemini E-07).
- Web Companion / browser control (DeepSeek E-07) — TCC pain not justified pre-V1.
- MCP runtime, plugin SDK, LangChain/LangGraph, external Python/Node integration — architectural rule.
- Streaming Ollama (`stream:true`) — explicit owner decision.
- `/v1/chat/completions` — explicit owner decision.
- App Store distribution work.
- iOS/iPad companion (synthesizer-only idea, not yet validated by peers).

---

## 6.5 Compliance Check-in (mandatory before any code is written)

A long dispatch prompt is statistically likely to be skimmed. The Check-in is the antidote: the subagent must *prove* it parsed the rules before touching code. Programmatic attention check.

**Supervisor sends as the FIRST message in every subagent dispatch:**

> "Before you touch any file, restate in your own words: (1) the 3 most critical STOP triggers for this phase, (2) the primary file you are NOT allowed to modify, (3) the one bullet item from the Scope IN list you intend to start with, and (4) confirm you will NOT commit — the supervisor lands the bundled commit. Do nothing else until I confirm."

**Supervisor verifies all four items are present and accurate.** If any is wrong, vague, or hallucinated:

- Terminate the subagent.
- Re-dispatch with the same prompt — sometimes a second pass reads more carefully.
- If the second attempt also fails, STOP the phase and report to the owner. STOP trigger S14 fires.

This applies to every phase, every dispatch. No exceptions. Do not skip it because "this subagent already did Phase N-1 well" — different sessions, different attention budgets.

---

## 6. Subagent dispatch template (use verbatim per phase)

```
You are implementing Phase {N} ({title}) of the OllamaBob peer-review plan.

REPOSITORY: /Users/zack/ollamaBob
ACTIVE BRANCH: {branch}
BUILD VERIFY: cd OllamaBob && swift build && swift test && ./build.sh

SCOPE — files you MAY modify (and only these):
{list from phase}

SCOPE — files you MAY NOT touch:
- AgentLoop.swift, BobsDeskView.swift, PreferencesView.swift  (unless explicitly listed above)
- Anything in the preserved-by-default list (see CLAUDE.md / AGENTS.md)
- Anything not listed in this prompt

NON-NEGOTIABLE ARCHITECTURE RULES:
- Native /api/chat, NOT /v1/chat/completions
- stream: false
- No MCP / Python / Node / Electron / Docker in app runtime
- Flat tool parameter schemas
- GRDB for persistence, additive-only schema
- Native approval dialogs for side effects

STOP TRIGGERS (return immediately if any fires):
- Need to add a dependency not pre-approved
- Need to touch a file outside the SCOPE list
- A test fails or test count drops
- LOC of AgentLoop.swift / BobsDeskView.swift / PreferencesView.swift grows
- You discover scope creep ("while I'm here…")

COMPLIANCE CHECK-IN (do this FIRST, before any file edits):
Restate in your own words:
  1) The 3 most critical STOP triggers for this phase (from the list above and the universal STOPs in §2/§1.5).
  2) The primary file you are NOT allowed to modify.
  3) The one bullet item from the Scope IN list you intend to start with.
  4) Confirm you will NOT commit — the supervisor lands the bundled commit.
Wait for the supervisor's confirmation before touching any file.

DELIVER (after the work):
- Bullet list of changed files with LOC deltas
- swift test summary (count, pass/fail)
- LOC delta on AgentLoop.swift, BobsDeskView.swift, PreferencesView.swift (must be 0 unless scope says otherwise)
- Anything you wanted to do but DIDN'T because it was out of scope
- Confirmation that no preserved component was touched

DO NOT commit. The supervisor lands the bundled commit on the feature branch after verification.
```

---

## 7. Resumption rules

If a phase fails or a STOP fires:

1. Subagent leaves the working tree as-is. Supervisor `git status` to confirm scope.
2. Supervisor writes a `STOP-{phase}.md` note inside `.local-docs/` (gitignored) with: which trigger fired, file/line evidence, what the subagent attempted, what it was supposed to do.
3. Supervisor reports to owner with a one-paragraph summary and recommended next step (refine scope, split phase, abort feature).
4. Owner decides. No subagent re-dispatch without owner approval.

If a phase is half-finished and the session ends:

1. Supervisor writes a single `docs/ACTIVE_EXECUTION_PLAN.md` (per CLAUDE.md doc-priority order) describing exactly where work stopped and what the next phase action is.
2. Next session reads `ACTIVE_EXECUTION_PLAN.md` first, ahead of this file.
3. When the phase lands, `ACTIVE_EXECUTION_PLAN.md` is deleted and this file is the source of truth again.

---

## 8. Approval checkpoints summary

| Phase | What owner approves before start | What owner approves before commit |
|---|---|---|
| 0a stash | The stash decision (land/refresh/drop) | n/a (no code work) |
| 0b sanitization | New deps (if any), sanitizer approach | Diff + tests + injection-payload coverage |
| 0c keychain | Migration plan (which keys, in what order) | Migration log + Preferences manual test |
| 1 trust UI | Diff format choice (unified vs split) | Manual diff/approve/ledger walkthrough |
| 2 decompose | Target seam list | Feature-parity sweep result |
| 3 context lens | TCC strings, default tool visibility | Manual screen-OCR run on a non-sensitive page |
| 4a mock cockpit | Mock-client surface, default toggle state | Mock-driven LiveCallView demo |
| 4b real cockpit | Daemon endpoint inventory + dual-secret auth confirmation | Real test call with injection approval |
| 5a timeline | Per-source toggle defaults | "Forget between dates" demo |
| 5b vault | Embedding model choice | Per-folder opt-in walkthrough |
| 6 code companion | Default dev_mode = OFF confirmation | Repo-boundary write test |
| 7a–e polish | Order of sub-phases | Per-sub-phase manual test |

---

## 9. Owner answers (LOCKED 2026-04-28)

1. **Stash decision (0a):** REFRESH as reference backlog, do not land wholesale, do not drop yet. Conflicts in AgentLoop/ApprovalPolicy/docs/Preferences/tests; references files that no longer exist. → §4 Phase 0a updated.
2. **HTML sanitizer (0b):** APPROVED to add SwiftSoup as SPM dep. Use as pre-WebView allowlist sanitizer; retain CSP + JS-disabled + navigation blocking as defense-in-depth (DO NOT remove). → §4 Phase 0b updated.
3. **Keychain migration (0c):** ONE-TIME PROMPT. Auto-migrate `braveAPIKey` / `jarvisAPIKey` / `jarvisOperatorSecret` from UserDefaults (confirmed present). `.env` and process env stay as fallback / explicit-import sources only. ElevenLabs is `.env`-only — no UserDefaults migration. → §4 Phase 0c updated.
4. **Phase ordering:** Option C — AgentLoop decomp now (Phase 2a only), defer BobsDeskView decomp to Phase 8 after Phases 3, 4a, 6 land and the UI direction is clearer. → §4 Phase 2 updated; Phase 2b removed; Phase 8 placeholder created.
5. **Phase 4 split:** Confirmed (4a mock dev-only / 4b real daemon). 4a mock client must be `#if DEBUG`-gated; release builds always use HTTP client. → §4 Phase 4a updated.
6. **Phase 5 embedding model:** unanswered — irrelevant until Phase 5 re-scope (owner asked Phase 5 be split harder; supervisor will produce `docs/PHASE_5_PLAN.md` before any 5x dispatch). Defer.
7. **Branch / tag protocol:** Confirmed, with refinement — tags are unique per dispatch (`pre-phase-{slug}-{YYYYMMDD}`), never reused. → §1.5 updated.

---

## 10. Vibe-check notes (from `mcp__vibe-check__vibe_check`)

Two passes were run. First pass surfaced internal sanity issues; second pass (external Gemini-backed reviewer) surfaced four operational gaps. Both rounds of revisions are reflected throughout this document.

**Pass 1 (internal):**

- "Phase 0 mixes trust-floor code with a stash *decision* that isn't really a phase" → split 0a (decision) from 0b/0c (code).
- "Phase 2 refactor before killer features risks owner fatigue" → kept Phase 2 as default but escalated to an explicit owner question (§9.4).
- "Subagent dispatch prompt is long" → kept it long; the STOP list is the whole point. Short prompts produce drift.
- "No rollback story" → added §7 Resumption rules.
- "No way to land partial work safely" → added the `ACTIVE_EXECUTION_PLAN.md` handoff flow.

**Pass 2 (external review):**

- **"Branching / worktree strategy is the missing safety net."** → added §1.5 Branch & Tag protocol making per-phase feature branches and `pre-phase-N` / `phase-N-complete` tags non-negotiable; added STOP triggers S15 and S16 to enforce.
- **"Subagent dispatch is statistically likely to be skimmed"** → added §6.5 Compliance Check-in, requiring the subagent to restate the top STOPs and the forbidden file before any code is written; failure to comply triggers S14.
- **"Phase 4 risks long-blocked stall on Jarvis daemon"** → split into 4a (mock UI, ships immediately) and 4b (real-daemon swap) so the UI work is demoable regardless of daemon-side readiness.
- **"Refactor-vs-feature should be an explicit owner decision, not an implicit default"** → reworded §9.4 to put both options on the table with the trade-off documented and the recommended default flagged.

**Pass 3 (owner review, 2026-04-28):**

- **"Phase 0b scope must allow Package.swift / Package.resolved if SwiftSoup is approved"** → 0b scope IN extended to include those files.
- **"Keep WKWebView hardening even after SwiftSoup"** → 0b explicit Phase-specific STOP added against removing or weakening existing CSP / JS-disabled / navigation-blocking defenses; SwiftSoup is *additive* defense-in-depth, not a replacement.
- **"Treat the stash as reference backlog, not implementation branch"** → 0a rewritten as a reference-extraction task with output to `.local-docs/STASH_REFERENCE_BACKLOG.md`, stash retained until after Phase 2a.
- **"Use unique phase tags like `pre-phase-0b-20260428`, not reusable `pre-phase-N`"** → §1.5 tag naming changed to `pre-phase-{slug}-{YYYYMMDD}` with `-r2`/`-r3` for re-dispatches; immutability rule made explicit.
- **"Mock Jarvis client should be dev-only, not release default"** → 4a STOP added: mock implementation must be `#if DEBUG`-gated; release binary cannot instantiate the mock.
- **"Phase 5 is huge; split it harder when we get there"** → Phase 5 marked as placeholder; supervisor will produce `docs/PHASE_5_PLAN.md` re-scoping into 4–6 smaller sub-phases before any 5x dispatch.

---

## 11. STOP

This plan is now ready for owner review. **No phase begins until the owner answers §9 and explicitly says "start Phase 0."** The supervisor will not dispatch a subagent until that signal.
