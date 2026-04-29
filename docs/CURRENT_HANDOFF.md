# OllamaBob - Current Handoff

**Date:** 2026-04-27
**Audience:** the next coding agent or operator picking the project up cold.

## Repository State

- Active branch should be `main`.
- No active execution plan is tracked in `docs/`.
- Active docs are intentionally small; historical plans and old handoffs are in `archive/`.
- Current visible app version: `1.0.26`.

Local-only note for Zack's workstation:

- Before this cleanup, a peer-review security/correctness implementation was parked in a local stash named `peer-review security correctness pass`.
- Treat that stash as unlanded work, not as part of `main`. Check `git stash list` before resuming that thread.

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
- local Jarvis phone address-book aliases from env vars, JSON maps, and VCF exports, including Zack's `~/Downloads/bobs_contacts.vcf`
- authorized personal music collection workflow for resolving album tracks or pasted song lists, auto-picking high-confidence YouTube candidates by title/duration, confirming only ambiguous tracks, saving approved MP3 files under underscore-safe generated folders like `~/Music/Bob/<Artist>_<Album>`, and using a whole-album single-file workflow when explicitly requested
- local FLAC-to-MP3 batch conversion through `ffmpeg` via shell, with a larger batch-audio loop budget and no per-file continuation prompts
- agent-loop batch-continuation guard that rejects status-only final replies like "Next up..." during batch audio turns and internally nudges Bob to call the next tool
- agent-loop batch completion audit for pasted track lists: Bob compares requested track names with downloaded MP3 filenames before accepting a batch as complete and emits a visible downloaded/missing/unmatched summary
- Naughty Bob v1 as a per-conversation uncensored mode
- Jarvis phone tools gated by Preferences and both Jarvis secrets, with bounded recent OllamaBob session context plus earlier-work highlights attached to outbound recap calls when useful

Runtime UI note:

- The shipped chat surface is `BobsDeskView`.
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

- Tools: `phone_call`, `phone_hangup`, `phone_status`
- Gating: Jarvis phone enabled, valid base URL, non-empty `JARVIS_API_KEY`, non-empty `OPERATOR_API_SECRET`
- `/call/*` requests send both `X-Jarvis-Key` and `x-operator-secret`
- `/health` is only a reachability check

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

- `BRAVE_API_KEY` enables `web_search`.
- `JARVIS_API_KEY` and `OPERATOR_API_SECRET` enable Jarvis phone tools.
- `ZACK_PERSONAL_NUMBER`, `GLENNEL_PERSONAL_NUMBER`, `jarvis-address-book.local.json`, and local VCF exports such as `~/Downloads/bobs_contacts.vcf` support local call aliases.

## Verification Commands

Run from `OllamaBob/`:

```bash
swift build
swift test
./build.sh --run
```

Last verified during the 2026-04-27 phone call context highlight pass:

- `swift build` passed
- `swift test` passed: 132 tests, 0 failures
- `./build.sh` passed and assembled `build/OllamaBob.app`
- generated bundle metadata reports `CFBundleShortVersionString = 1.0.26` and `CFBundleVersion = 126`
- `./build.sh --run` passed and launched the rebuilt app from `build/OllamaBob.app`

Known warning note:

- `Phase2_9ToolTests.testSipsConvertsPNGToJPEG` still emits pre-existing AppKit colorspace warnings during `swift test`; the test passes.

For doc-only cleanup, at minimum run:

```bash
swift build
swift test
```

## Remaining Backlog

No active task is binding right now. Candidate next work, in priority order only if the user asks:

- Decide whether to resume and land the parked peer-review security/correctness stash.
- Expose more Jarvis daemon capabilities in OllamaBob: call list, mid-call injection, supervision, contacts, follow-ups, and memory search.
- Add a Preferences contact manager: import VCF files into app storage, list/search aliases, and add/edit/delete local phone aliases without hand-editing JSON.
- Broaden rich HTML sanitization beyond the current regex/CSP/JS-disabled defense.
- Decide whether `ChatPanel.swift` should be removed or revived as a real secondary surface.
- Continue avatar polish only after security/correctness scope is explicitly resolved.
