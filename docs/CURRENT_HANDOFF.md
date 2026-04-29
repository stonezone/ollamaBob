# OllamaBob - Current Handoff

**Date:** 2026-04-29
**Audience:** the next coding agent or operator picking the project up cold.

## Repository State

- Active working branch at handoff time: `feature/phase-c-deskview-decomp-20260429`.
- Local `main` has Phase A and Phase B integrated through local no-ff merges and tags `phase-a-hygiene-complete-20260429` and `phase-b-untrusted-taint-complete-20260429`; push/review state is still operator-owned.
- `docs/ACTIVE_EXECUTION_PLAN.md` is tracked and Phase C is implemented on this branch; keep using it as the execution authority until the owner retires or archives it.
- Active docs are intentionally small; historical plans, old peer-review notes, and superseded handoffs are in `archive/`.
- Current visible app version: `1.0.31`.

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
- Phase C Bob's Desk decomposition: the live desk surface now uses `DeskViewModel`, `DeskTranscriptView`, `DeskInputView`, and `DeskStatusStrip`, with `BobsDeskView.swift` reduced to 795 lines while preserving the existing scene, window chrome behavior, prompt injection path, transcript rendering, history overlay, and send sounds
- Clipboard Cortex and walkie-talkie prompts route through `DeskPromptInbox` so app-originated prompts are not lost if Bob's Desk is still mounting
- Clipboard Cortex stack-trace summaries open Bob's Desk and submit the full stack trace wrapped as untrusted data
- Daily Briefing has Preferences controls for enable/time/run-now plus a history window from the menu bar
- Daily Briefing synthesis prompts explicitly tell the model to treat `<untrusted>` tool-output blocks as data, not instructions
- Phase B untrusted-output taint protection tracks sessions after successful file/web/mail/clipboard/YouTube-search/screen-OCR/context source tools and blocks write/action tools before approval until the user sends a fresh message or types `/lift`; blocked actions include shell, file writes/moves, clipboard writes, downloads, AppleScript, phone actions, memory mutation, saved-skill execution, and `present(kind=file|url)`
- Bob's Desk shows an "Untrusted content in this turn" banner while taint protection is active for the current conversation
- authorized personal music collection workflow for resolving album tracks or pasted song lists, auto-picking high-confidence YouTube candidates by title/duration, confirming only ambiguous tracks, saving approved MP3 files under underscore-safe generated folders like `~/Music/Bob/<Artist>_<Album>`, and using a whole-album single-file workflow when explicitly requested
- local FLAC-to-MP3 batch conversion through `ffmpeg` via shell, with a larger batch-audio loop budget and no per-file continuation prompts
- agent-loop batch-continuation guard that rejects status-only final replies like "Next up..." during batch audio turns and internally nudges Bob to call the next tool
- agent-loop batch completion audit for pasted track lists: Bob compares requested track names with downloaded MP3 filenames before accepting a batch as complete and emits a visible downloaded/missing/unmatched summary
- Naughty Bob v1 as a per-conversation uncensored mode
- Jarvis phone tools gated by Preferences and both Jarvis secrets, with bounded recent OllamaBob session context plus earlier-work highlights attached to outbound recap calls when useful

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

Last verified during the 2026-04-29 Phase C desk decomposition pass:

- `swift build` passed
- `swift test` passed: 413 tests, 0 failures
- `./build.sh` passed and assembled `build/OllamaBob.app`
- generated bundle metadata reports `CFBundleShortVersionString = 1.0.31` and `CFBundleVersion = 131`
- `git diff --check` passed
- `BobsDeskView.swift` is 798 LOC, satisfying the Phase C ≤800 LOC gate
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

No active task is binding after this handoff unless the user explicitly asks to continue. Candidate next work, in priority order:

- Run a fresh Opus deep review/audit of this integrated branch before push/merge if another external check is desired.
- Push or PR the integrated branch after review.
- Expose more Jarvis daemon capabilities in OllamaBob: contacts, follow-ups, memory search, and richer live supervision controls.
- Add a Preferences contact manager: import VCF files into app storage, list/search aliases, and add/edit/delete local phone aliases without hand-editing JSON.
- Broaden rich HTML sanitization beyond the current regex/CSP/JS-disabled defense.
- Decide whether `ChatPanel.swift` should be removed or revived as a real secondary surface.
- Continue avatar polish only after security/correctness scope is explicitly resolved.
