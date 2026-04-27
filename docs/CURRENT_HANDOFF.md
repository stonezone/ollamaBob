# OllamaBob - Current Handoff

**Date:** 2026-04-27
**Audience:** the next coding agent or operator picking the project up cold.

## Repository State

- Active branch should be `main`.
- No active execution plan is tracked in `docs/`.
- Active docs are intentionally small; historical plans and old handoffs are in `archive/`.
- Current visible app version: `1.0.3`.

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
- first-party tool set across files, shell, git, web, phone, presentation, media, utility, YouTube, clipboard, AppleScript, and memory
- Naughty Bob v1 as a per-conversation uncensored mode
- Jarvis phone tools gated by Preferences and both Jarvis secrets

Runtime UI note:

- The shipped chat surface is `BobsDeskView`.
- `ChatPanel.swift` remains in the repo but is not the live app scene graph entrypoint.

## Model Routing

Standard mode:

- primary: `gemma4:e4b`
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
```

Optional tool dependencies:

```bash
brew install yt-dlp
```

Optional secrets:

- `BRAVE_API_KEY` enables `web_search`.
- `JARVIS_API_KEY` and `OPERATOR_API_SECRET` enable Jarvis phone tools.
- `ZACK_PERSONAL_NUMBER`, `GLENNEL_PERSONAL_NUMBER`, and `jarvis-address-book.local.json` support local call aliases.

## Verification Commands

Run from `OllamaBob/`:

```bash
swift build
swift test
./build.sh --run
```

Last verified during the 2026-04-27 docs cleanup:

- `swift build` passed
- `swift test` passed: 100 tests, 0 failures

Known warning note:

- `swift build` still emits pre-existing Swift 6 concurrency warnings in `Tools/ProcessRunner.swift`. They are not from this docs cleanup.

For doc-only cleanup, at minimum run:

```bash
swift build
swift test
```

## Remaining Backlog

No active task is binding right now. Candidate next work, in priority order only if the user asks:

- Decide whether to resume and land the parked peer-review security/correctness stash.
- Expose more Jarvis daemon capabilities in OllamaBob: call list, mid-call injection, supervision, contacts, follow-ups, and memory search.
- Broaden rich HTML sanitization beyond the current regex/CSP/JS-disabled defense.
- Decide whether `ChatPanel.swift` should be removed or revived as a real secondary surface.
- Continue avatar polish only after security/correctness scope is explicitly resolved.
