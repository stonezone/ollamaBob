# OllamaBob - Current Handoff

**Date:** 2026-05-02
**Audience:** the next coding agent or operator picking the project up cold.

## Wake-Up Summary (v1.0.46, 2026-05-02 overnight pass)

Zack went to sleep mid-debug at v1.0.45 with three production failures: (1) `nmap on the router` failed because Bob picked `netstat -ri` (BSD interface stats with routes) instead of `-nr` (routing table) and gave up after exit 1; (2) batch `youtube_download` of 14 songs died with "Ollama request timed out" mid-loop after youtube_search succeeded; (3) no debug-logging mode existed so failure root-cause was invisible. v1.0.46 ships fixes for all three plus structural debt the audit surfaced.

**4 bugs found in audit, all fixed:**

1. **OllamaClient HTTP idle timeout was hardwired to 120s** ([OllamaClient.swift:28](OllamaBob/Agent/OllamaClient.swift) used `agentLoopTimeoutSeconds`). With `stream: false` the URLSession idle timer fires when no bytes arrive for 120s, which is normal generation time for `qwen3.6:27b`/`gemma4:26b`/`gpt-oss:20b` and catastrophic for batch-audio loops with 3600s logical budget. Fixed by adding `AppConfig.ollamaHTTPRequestTimeoutSeconds = 600` (10 min) decoupled from the loop budget. The agent-loop iteration check + ⌘. Cancel button remain the actual escape hatch for stuck requests.

2. **YouTubeTool used the legacy `timeout: 300` ProcessRunner API.** Migrated `youtube_search` to `idleTimeout=30, hardCap=120` and `youtube_download` to `idleTimeout=120, hardCap=1800`. yt-dlp emits progress lines during download — idle reset on each line means a slow-but-progressing download isn't killed mid-fetch. Failure messages now distinguish idle-kill vs hard-cap-kill.

3. **No shell-failure recovery.** Bob ran `netstat -ri` → exit 1 → "I couldn't find the gateway, you can run it manually." The operating rules nudged Bob to *surface* failures, which is the right instinct for permission errors but the wrong instinct for syntax errors. New `AgentLoopShellRecoveryGuard.swift` (mirror of `AgentLoopContinuationGuard` from v1.0.45) detects shell exit non-zero + retryable stderr (`usage:` / `command not found` / `invalid option`) + assistant give-up language, and injects a system nudge: *"Diagnose the actual error and retry with a corrected command in the same turn… `netstat -nr` not `-ri`."* Cap=1, skips permission errors. 11 unit tests cover positive/negative cases. BobOperatingRules now distinguishes PERMISSION/POLICY (surface to user) from SYNTAX/USAGE (diagnose+retry) failure classes with macOS-specific BSD-vs-GNU examples.

4. **No debug visibility.** New `DebugLog.swift` service writes session logs to `~/Library/Logs/OllamaBob/debug-YYYYMMDD-HHmmss.log`. Default OFF; new Preferences checkbox "Debug logging" enables it. Captures every Ollama request/response (model, msgs, tools, numCtx, content length, tool_calls, elapsed ms), every tool dispatch (name, args, success, output preview), every shell spawn/exit/SIGTERM/SIGKILL, every guard fire (continuation + shell-recovery), and every timeout with elapsed-ms vs configured-cap.

**Tests:** 531 pass (was 520; +11 ShellRecoveryGuard tests). Existing batch-audio + continuation + version-consistency tests all green.

**Bundle:** 1.0.46 / 146. App rebuilt + signed with stable Apple Development identity. Not auto-launched (you're sleeping).

**To verify on wake-up:**
1. Toggle Preferences → Debug logging ON.
2. Retry the nmap router scenario. Bob should now: try `-ri`, fail, see the shell-recovery nudge in Tool Activity, retry with `-nr`, get the gateway IP, then run nmap. (If he still picks `-ri` first, the new BobOperatingRules examples should improve future turns; the recovery guard catches the failure either way.)
3. Retry the batch song download. With `qwen3.6:27b` selected, Ollama responses can now take up to 10 minutes per turn; the batch shouldn't die mid-loop.
4. Open the log file at `~/Library/Logs/OllamaBob/debug-*.log` — every request, response, tool dispatch, and timeout is in there grep-able.

**Known limitations carried forward:**
- Integration test for `AgentLoop.process()` end-to-end still missing (would require protocolizing `OllamaClient` actor; tracked in Remaining Backlog). All four guards (batch continuation, batch audit, generic continuation, shell recovery) are unit-tested at the static-helper level only.
- System prompt is now ~6900 tokens vs 5000 budget at num_ctx=32768 (was 6889 before this pass; +14 tok from new failure-class examples). Not blocking but should be trimmed when convenient.
- The user reported `qwen3.6:27b` showed `ram 9.6G` then `143M` in the status strip — that's a status-strip display oddity, not investigated.

## Repository State

- Active branch: `feature/ui-modernization-on-main-20260429` (UI modernization stack rebased on top of codex's clean main).
- Codex's `main` has Phase A, Phase B, Phase C, Phase D.1, Phase D.2, Phase D.5, and Phase E integrated through local no-ff merges and completion tags; push/review state is still operator-owned.
- This branch adds the 2026 UI modernization (Phases 1–5 + 4.5 + 5.5 + visibility/UX fixes) as a single bundled commit on top of codex's main. Pre-rebase backup tagged at `backup/ui-phases-pre-rebase-20260429`.
- `docs/ACTIVE_EXECUTION_PLAN.md` is tracked. Next default phase after Phase E is F.1 (ArtifactStore + kinds); UI modernization runs in parallel and does not block F.1.
- Active docs are intentionally small; historical plans, old peer-review notes, and superseded handoffs are in `archive/`.
- Current visible app version: `1.0.54`.

Local-only notes for Zack's workstation:

- Kimi implemented Phase A security/correctness cleanup in a separate worktree: `/Users/zack/ollamaBob-kimi-phase-a` on branch `codex/kimi-phase-a-security`.
- Kimi's export is `/Users/zack/ollamaBob-kimi-phase-a/kimi-export-b7049281-20260428-221733.md`.
- Kimi's work is integrated into this branch through commit `c4fe548` and merge commit `2e8373e`. The export file remains local context only and is not part of the app.

## Current Product State

OllamaBob is live as a single local macOS menu-bar product with:

- Swift agent loop over Ollama native `/api/chat`
- `stream: false`
- Bob's desk/chat window and avatar-only mode
- conversation persistence and conversation manager
- rich presentation through `present(kind=html|url|file)` and transcript artifact chips
- first-party tool set across files, shell, git, web, Apple Mail inbox checks and triage previews, phone, presentation, media, utility, YouTube, clipboard, AppleScript, and memory
- `mail_check` is a modal-gated read-only Apple Mail inbox summary tool; it returns date/read state/sender/subject only and should be preferred over generic AppleScript for unread/search requests
- `mail_triage` is a modal-gated Apple Mail preview tool for explicit "read my mail and tell me what needs attention" requests; it returns date/read state/sender/subject plus short truncated previews only and does not mutate mail
- Preferences tool badges with persisted per-tool `Auto` / `Ask` / `Deny` overrides that still preserve path policy and forbidden shell-command safety floors
- Phase A security hardening for approval/path/shell execution: structured file tools compare execution-time resolved paths with approval-time resolved paths, forbidden paths beat generic write-modal classification, shell forbidden-command parsing handles quoted and escaped command names, and `ProcessRunner` enforces large stream-side caps without killing normal shell commands at display-truncation limits
- local Jarvis phone address-book aliases from env vars, JSON maps, and VCF exports, including Zack's `~/Downloads/bobs_contacts.vcf`
- live Jarvis call supervision tools: list active calls, fetch active-call transcripts, and inject a modal-approved mid-call message
- Jarvis supervision tools are hidden until Jarvis phone is enabled and both Jarvis secrets are configured
- DEBUG builds default to the real Jarvis HTTP supervision client; a Preferences-only DEBUG toggle can opt into the canned mock client
- Bob's Desk status strip for Mac context snapshots, Code Companion mode, walkie-talkie recording/speaking state, and Focus Guardian state
- Phase C Bob's Desk decomposition: the live desk surface now uses `DeskViewModel`, `DeskTranscriptView`, `DeskInputView`, and `DeskStatusStrip` while preserving the existing scene, window chrome behavior, prompt injection path, transcript rendering, history overlay, and send sounds
- Clipboard Cortex and walkie-talkie prompts route through `DeskPromptInbox` so app-originated prompts are not lost if Bob's Desk is still mounting
- Clipboard Cortex stack-trace summaries open Bob's Desk and submit the full stack trace wrapped as untrusted data
- Daily Briefing has Preferences controls for enable/time/run-now plus a history window from the menu bar
- Daily Briefing synthesis prompts explicitly tell the model to treat `<untrusted>` tool-output blocks as data, not instructions
- Phase D.1 Activity Timeline persistence: local `activity_event` SQLite table, timestamp and source/kind indexes, `ActivityEvent` value type, and bounded `appendActivityEvent` / `fetchActivityEvents` database APIs
- Phase D.2 ActivityIndexer: Preferences exposes `Activity Timeline (local)` as an opt-in toggle defaulting OFF; when enabled, tool calls and user/assistant chat messages are appended to the local activity timeline, with file-event indexing intentionally stubbed for D.3
- Phase D.5 `timeline_search`: read-only, approval-free local Activity Timeline search that stays gated behind the Activity Timeline toggle, caps results at 50 events, accepts ISO8601 date ranges, and wraps returned timeline rows as untrusted data
- Phase E Naughty Bob context budget banner: uncensored conversations show a visible warning above the input once the visible message stack reaches 85% of `num_ctx`; no automatic compaction or fallback is added
- Phase B untrusted-output taint protection tracks sessions after successful file/web/mail/clipboard/YouTube-search/screen-OCR/context source tools and blocks write/action tools before approval until the user sends a fresh message or types `/lift`; blocked actions include shell, file writes/moves, clipboard writes, downloads, AppleScript, phone actions, memory mutation, saved-skill execution, and `present(kind=file|url)`
- Bob's Desk shows an "Untrusted content in this turn" banner while taint protection is active for the current conversation
- authorized personal music collection workflow for resolving album tracks or pasted song lists, auto-picking high-confidence YouTube candidates by title/duration, confirming only ambiguous tracks, saving approved MP3 files under underscore-safe generated folders like `~/Music/Bob/<Artist>_<Album>`, and using a whole-album single-file workflow when explicitly requested
- local FLAC-to-MP3 batch conversion through `ffmpeg` via shell, with a larger batch-audio loop budget and no per-file continuation prompts
- agent-loop batch-continuation guard that rejects status-only final replies like "Next up..." during batch audio turns and internally nudges Bob to call the next tool
- agent-loop batch completion audit for pasted track lists: Bob compares requested track names with downloaded MP3 filenames before accepting a batch as complete and emits a visible downloaded/missing/unmatched summary
- Naughty Bob v1 as a per-conversation uncensored mode
- Jarvis phone tools gated by Preferences and both Jarvis secrets, with bounded recent OllamaBob session context plus earlier-work highlights attached to outbound recap calls when useful
- v1.0.42: image-based Mumbai Bob avatar; Live Call view rebuilt with a post-call action-items section populated by `JarvisCallClient.actionItems(callID:)` using `JarvisCallActionItems` model in `OllamaBob/Models/JarvisCallTypes.swift`
- v1.0.43: action items are clickable — tapping one injects it as a new user prompt into Bob's session via the existing `DeskPromptInbox` / `DeskPromptActions` path
- v1.0.44: long-running shell support with dual timers (`idleTimeout` resets on each output chunk; `hardCap` is a single-shot ceiling); both end via `terminateThenKill(grace:)` (SIGTERM then SIGKILL after 2 s); `ProcessRunner` gains `onOutputChunk` callback and `CancelHandle`; drain uses `handle.availableData` (not `readData(ofLength:)`) to prevent pipe-buffering stalls; `ShellTool` accepts optional `idle_timeout_seconds` and `max_total_seconds` and runs via `/bin/zsh -lc` so Homebrew is on PATH; `AgentLoop` exposes `cancel()` / `cancelToolEntry(id:)`, `activeCancelHandles` registry keyed by `ToolLogEntry.id`, and a loop-budget that excludes tool wall-time; `ToolLogEntry` promoted from struct to `final class ObservableObject` with `@Published output` so `ToolActivityRow` re-renders live chunks; `ChatBubble` and `DeskTranscriptView` accept a `fullChatMode` flag that unhides tool-only assistant turns and renders the thinking panel inline; `build.sh` hard-errors on signing-identity mismatch instead of silently falling back to ad-hoc

Runtime UI note:

- The shipped chat surface is `BobsDeskView`.
- `DeskViewModel` owns app-originated prompt notification sinks and drains `DeskPromptInbox`; `BobsDeskView` still bridges injected sends through `sendWithSound()` so sounds, heartbeat activity, autoscroll, and local-command behavior stay unchanged.
- `ChatPanel.swift` remains in the repo but is not the live app scene graph entrypoint.

Claude OS / Codex OS local RAG note:

- Project `ollamaBob` is registered in Claude OS with path `/Users/zack/ollamaBob`.
- Use KB filter `ollamaBob-`.
- Expected KBs are `ollamaBob-project_memories`, `ollamaBob-project_profile`, `ollamaBob-project_index`, and `ollamaBob-knowledge_docs`.
- Claude OS is development tooling only and must not be added to the app runtime.
- Before non-trivial work, search the KBs for relevant prior decisions. After code or active-doc changes, update memories/docs/profile and refresh the project index when source or tests changed.

## Model Routing

Standard mode:

- primary: `gemma4:e4b`
- selectable normal models: `gemma4:e4b`, `gemma4:26b`, `qwen3.6:27b`, `gpt-oss:20b`
- fallback: `qwen3:14b`
- compaction model: `qwen3:14b`

Uncensored mode:

- default tag: `huihui_ai/qwen3-abliterated:8b`
- tools: disabled
- compaction: disabled
- fallback to the normal model stack: disallowed

Install the default uncensored model:

```bash
ollama pull huihui_ai/qwen3-abliterated:8b
```

## Active Documentation

Start with these files only:

- `AGENTS.md`: agent workflow, guardrails, repo layout, and commands
- `CLAUDE.md`: Claude Code guide and sticky decisions
- `README.md`: human-facing overview and setup
- `docs/CURRENT_HANDOFF.md`: this file
- `docs/OPERATOR_QA.md`: manual QA checklist
- `docs/ARCHITECTURE_NOTES.md`: active architecture notes

Everything else that was an implementation plan, old handoff, or historical memo is under `archive/`. Use `archive/README.md` as the index.

Important archive note:

- `archive/HANDOFF_TO_CODEX_2026-04-28.md`, `archive/PEER_REVIEW_TODO_2026-04-28.md`, `archive/PEER_REVIEW_2026-04-27.md`, and `archive/PHASE_5_PLAN_2026-04-28.md` are historical context only. Some of them mention old blocked Jarvis routes (`/call/list`, `/call/transcript`, `/call/inject`) that are superseded by the current routes below.

## Important Runtime Contracts

Ollama:

- Use `http://localhost:11434/api/chat`.
- Do not switch to OpenAI-compatible `/v1/chat/completions`.
- Keep tool schemas flat.
- Keep `stream: false`.

Approvals:

- Read-only tools may run silently.
- Writes and real-world side effects require modal approval.
- Always preserve path policy and forbidden-command handling.
- Preferences can override each built-in tool to `Auto`, `Ask`, or `Deny`. `Auto` cannot bypass denied paths, approval-required paths, or forbidden shell-command shapes.

Jarvis phone:

- Tools: `phone_call`, `phone_hangup`, `phone_status`, `phone_list_calls`, `phone_get_transcript`, `phone_inject`
- Gating: Jarvis phone enabled, valid base URL, non-empty `JARVIS_API_KEY`, non-empty `OPERATOR_API_SECRET`
- `/call/*` and `/calls/*` requests send both `X-Jarvis-Key` and `x-operator-secret`
- Supervision HTTP routes are `/calls/active`, `/call/status/:id`, and `/call/:id/message`
- `/health` is only a reachability check
- `phone_inject` is modal-gated in the agent path. Live Call window suggested injections also check `ApprovalPolicy`, respect per-tool `Deny`, and log injection attempts to the Privacy Ledger.

Rich presentation:

- `present(kind=html)` opens Bob's rich HTML companion window.
- `present(kind=url)` opens the default browser.
- `present(kind=file)` opens the default macOS app after policy checks.
- Assistant transcript artifact chips route through the same presentation service.

## Useful Setup Notes

Required local models:

```bash
ollama pull gemma4:e4b
ollama pull qwen3:14b
ollama pull gpt-oss:20b
```

Optional tool dependencies:

```bash
brew install yt-dlp
```

Optional secrets:

- `BRAVE_API_KEY` enables `web_search`; Preferences can import it from `.env` into the Keychain.
- `JARVIS_API_KEY` and `OPERATOR_API_SECRET` enable Jarvis phone tools.
- `ZACK_PERSONAL_NUMBER`, `GLENNEL_PERSONAL_NUMBER`, `jarvis-address-book.local.json`, and local VCF exports such as `~/Downloads/bobs_contacts.vcf` support local call aliases.

## Verification Commands

Run from `OllamaBob/`:

```bash
swift build
swift test
./build.sh
./build.sh --run
```

Last verified on 2026-05-01 (v1.0.44):

- `swift build` passed
- `swift test` passed: 505 tests, 0 failures
- `./build.sh` passed and assembled `build/OllamaBob.app`
- bundle metadata reports `CFBundleShortVersionString = 1.0.44` and `CFBundleVersion = 144`
- new files since v1.0.40: `OllamaBob/Models/JarvisCallTypes.swift` (`JarvisCallActionItems`), `Views/LiveCallView.swift` (rebuilt with action-items section), `Tests/OllamaBobTests/ShellLongRunningTests.swift`
- key changes since v1.0.40: Mumbai Bob image avatar; clickable post-call action items via `DeskPromptInbox`; `ProcessRunner` dual-timer/streaming/cancel architecture; `ToolLogEntry` promoted to `ObservableObject`; `ShellTool` login-shell and timeout args; `AgentLoop` cancel registry and tool-time-excluded loop budget; `ChatBubble`/`DeskTranscriptView` `fullChatMode` flag; `build.sh` signing hard-error

Earlier verification on the 2026-04-29 UI modernization rebase pass (v1.0.40):

- `swift test` passed: 496 tests, 0 failures (441 inherited from codex's main + 55 new UI tests across `DesignSystemTests`, `BobPersonaTests`, `BubbleShapeTests`, `MenuBarMarkTests`, `HUDSettingsTests`, `MenuBarSummonHotkeyTests`, `HUDStateTests`)
- `./build.sh` passed and assembled `build/OllamaBob.app`
- new `OllamaBob/OllamaBob/DesignSystem/` (6 token files + 5 primitives + persona protocol/registry), `OllamaBob/OllamaBob/Personas/` (Mumbai Bob + Classic Robot live SwiftUI characters), `Views/Desk/DeskWindowChrome.swift`, `Views/MenuBar/{BobMenuBarMark,BobMenuBarPopover}.swift`, `Views/HUD/{BobHUDScene,HUDWindowChrome}.swift`, `Models/HUDState.swift`, `Services/MenuBarSummonHotkey.swift`. Avatar PNG sprites (12) and `AvatarPack`/`AvatarStore` retired in favor of live persona renderers. `WindowTransparencyConfigurator` extracted to `DeskWindowChrome`. `BobsDeskView.chatContainer` rebuilt on `GlassSurface(role: .deskWindow)`. `ChatBubble.textBubble` renders inside `BobBubble`. `MenuBarExtra` switched to `.menuBarExtraStyle(.window)` with custom mark + glass popover. Floating HUD scene with persona-tinted `GlassGlyph`, live transcript snippet, and ⌘⇧Space global summon hotkey.

Earlier verification on the Phase E pass:

- `swift test` passed: 441 tests, 0 failures
- bundle reported `CFBundleShortVersionString = 1.0.34` and `CFBundleVersion = 134`
- `git diff --check` passed
- `BobsDeskView.swift` is 819 LOC after Phase E; Phase E added 21 lines, within the authorized +30 line cap
- `AgentLoopToolDispatch.swift` changed by one D.2 line and five D.5 lines; `PreferencesView.swift` grew by six D.2 toggle-row lines
- Focused `ActivityIndexerTests` passed: 6 tests, 0 failures, covering toggle-off no-op, tool calls, user messages, assistant messages, detail capping, and settings persistence
- Focused `ActivityEventDatabaseTests` passed: 6 tests, 0 failures
- Focused `TimelineSearchToolTests` passed: 9 tests, 0 failures, covering recent events, limit cap, toggle-off denial, untrusted wrapping/sanitization, source filtering through the real DB path, invalid dates, registration/catalog visibility, disabled-toggle registry hiding, approval, prompt gating, and dispatch self-index prevention
- Focused `ContextBudgetTests` passed: 7 tests, 0 failures, covering empty stack, all-role counting, visible chat messages, known percentage math, default qwen-abliterated context, 85% warning threshold, and ignored decoded thinking
- Focused `DeskViewModelTests` passed: 7 tests, 0 failures, including the live external-send bridge used by `BobsDeskView` and multi-prompt queue preservation
- Focused `TaintPolicyTests` passed: 18 tests, 0 failures
- Focused `PolicyRegressionTests` passed: 12 tests, 0 failures
- Codex OS refresh for Phase C was attempted through `http://localhost:8051/openapi.json` and `/health`; both timed out locally with no response bytes while the server was busy.
- Jarvis daemon probe: `/health` returned `200`. Authenticated route smoke was skipped in the final integration shell because `JARVIS_API_KEY` / `OPERATOR_API_SECRET` were not exported there; the earlier Codex pass had already verified unauthenticated `/calls/active` as `401`, authenticated `/calls/active` as `200`, and nonexistent `/call/status/:id` plus `/call/:id/message` as `404`.
- Codex OS refreshed after final integration: project memory upload succeeded, project profile upload succeeded, active docs (`README.md`, `AGENTS.md`, `CLAUDE.md`, and `docs/`) were uploaded/imported into `ollamaBob-knowledge_docs`, and structural indexing succeeded with 878 symbols across 4447 files. Semantic indexing was started as background job `semantic-ollamaBob-project_index-337b900c`; job/status and project-index lifecycle health calls timed out while the local server was busy. Memories/docs/profile health returned 100% embedding coverage with dedup recommendations.

Kimi Phase A verification before integration:

- Branch/worktree: `/Users/zack/ollamaBob-kimi-phase-a`, `codex/kimi-phase-a-security`
- Files touched there: `AgentLoopToolDispatch.swift`, `ApprovalPolicy.swift`, `AppConfig.swift`, `DirectoryCreateTool.swift`, `FileMoveTool.swift`, `FileWriteTool.swift`, `ProcessRunner.swift`, `ShellTool.swift`, `PolicyRegressionTests.swift`, `StructuredFileToolTests.swift`
- Kimi K1 regression fix was applied before merge: `ShellTool` now uses `AppConfig.processOutputMaxBytes` for process kill limits while keeping display truncation at `shellStdoutMax` / `shellStderrMax`.
- Red/green regression evidence: `PolicyRegressionTests/testShellToolAllowsLongStdoutAndReturnsDisplayTruncation` failed before the fix with `[output limit exceeded]`, then passed after the fix.
- Verification in the Kimi worktree: focused long-output regression passed, `swift test` passed with 379 tests / 0 failures, `swift build` passed, `./build.sh` passed, and `git diff --check` passed.

Known warning note:

- `Phase2_9ToolTests.testSipsConvertsPNGToJPEG` still emits pre-existing AppKit colorspace warnings during `swift test`; the test passes.

For doc-only cleanup, at minimum run:

```bash
swift build
swift test
```

## Remaining Backlog

`docs/ACTIVE_EXECUTION_PLAN.md` remains active. Candidate next work, in priority order:

- Continue the active plan with Phase F.1 (ArtifactStore + kinds) from clean local `main`.
- Run a fresh Opus deep review/audit of this integrated branch before push if another external check is desired.
- Push or PR the integrated branch after review.
- Expose more Jarvis daemon capabilities in OllamaBob: contacts, follow-ups, memory search, and richer live supervision controls.
- Add a Preferences contact manager: import VCF files into app storage, list/search aliases, and add/edit/delete local phone aliases without hand-editing JSON.
- Broaden rich HTML sanitization beyond the current regex/CSP/JS-disabled defense.
- Decide whether `ChatPanel.swift` should be removed or revived as a real secondary surface.
- Continue avatar polish only after security/correctness scope is explicitly resolved.
