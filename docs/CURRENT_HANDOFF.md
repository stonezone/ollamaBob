# OllamaBob — Current Handoff

**Date:** 2026-04-20  
**Audience:** the next coding agent or operator picking the project up cold.

Current visible app version:

- `1.0.3`

## Current State

The app is live as a single macOS menu-bar product with:

- core local agent loop over Ollama `/api/chat`
- V2.9.2 AppleScript/TCC permissions flow and avatar-only mode
- V2.10 rich presentation
- Naughty Bob v1 as a feature inside the current app, not a separate app
- complete first-party tool set (20+ tools across files, shell, git, web, phone, presentation, media, utility, YouTube, clipboard, automation, memory)

Runtime UI note:

- the shipped chat surface is `BobsDeskView`
- `ChatPanel.swift` currently exists in the repo but is not wired into the live app scene graph

Latest polish after the main release commits:

- `open ~/Desktop/...` / `open ~/Documents/...` fallback failures now normalize to a macOS-permission-prompt explanation instead of a generic shell-timeout sentence
- deprecated `onChange` usage in `ConversationManagerView` was modernized to keep the build warning-free in that area
- `ChatPanel` now tracks transcript growth by a refresh token instead of message-count only, so edits to the latest message keep the secondary transcript pinned correctly
- per-row time-format allocations were removed from conversation search and tool-activity UI to reduce avoidable redraw work in those surfaces
- `BobsDeskView` now resets conversation-scoped notice/tool cursor state on conversation switch
- `ChatSessionController` now publishes `transcriptRevision`, and `BobsDeskView` consumes it to avoid the old turn-completion bubble timing race
- avatar-only mode now shows the same model-switch and error banners as the full transcript layout
- avatar-only speech-bubble previews now use constrained rendered blocks, so markdown-image syntax and raw HTML payloads no longer leak directly into Bob's top bubble
- `BobsDeskView` now caches context-budget estimates instead of recomputing them from full history on every body render
- `BobsDeskView` now uses one `toolActivity` observer instead of separate count/change watchers
- `ChatBubbleRendering` now uses digest-backed cache keys, stable block-entry ids, and memoized assistant metadata / HTML reopen artifacts to reduce avoidable transcript recomputation
- `ChatSessionControllerTests` now waits deterministically for async tool-output clearing, so the suite no longer flakes on `startFreshConversation`
- `ChatBubble` now strips `<untrusted>` wrapper tags with a tag-aware helper instead of brittle literal substring replacement
- `ArtifactChip` tooltips no longer expose raw artifact payloads such as full local file paths
- `RichHTMLView` now opens safe clicked `mailto:` and `tel:` links externally
- active icon-only send controls now expose accessibility labels and hints in both input surfaces
- `ToolActivityView` now uses an explicit details toggle, selectable preview text, and clearer expanded input/output panels
- `phone_call` now defaults unsupported or omitted caller personas to `bob` instead of failing locally, so Bob no longer invents labels like `friend` and then trips the tool contract
- Jarvis phone tools now honor the daemon's real double-auth contract: `/call/*` requests send both `X-Jarvis-Key` and `x-operator-secret`
- the app now seeds Jarvis secrets from the repo-root `.env` on first launch when the Preferences values are still blank, which makes Finder-launched debug builds less brittle during local setup
- Jarvis 401 handling now distinguishes outer operator-auth failures from inner call-auth failures so the user sees which secret to fix
- `ShellTool` now returns a real failure when the shell executable cannot launch, instead of surfacing a fake success with `[exit code: -1]`
- `ToolRuntime` now probes external CLI tools sequentially; the earlier unbounded fan-out could stall the full Swift test suite because `ProcessRunner` still blocks worker threads internally

The current app bundle should be built from `OllamaBob/` with:

```bash
swift build
swift test
./build.sh --run
```

## Current Model Routing

Standard mode:

- primary: `gemma4:e4b`
- fallback: `qwen3:14b`
- compaction model: `qwen3:14b`

Uncensored mode:

- default uncensored tag: `huihui_ai/qwen3-abliterated:8b`
- tools: disabled
- compaction: disabled
- fallback to the normal stack: disallowed
- current operator note: the default uncensored model was pulled locally and the user reported the mode is working as intended on this machine

## How To Enable Uncensored Bob

Two switches must be on:

1. Preferences -> Models -> `Enable Uncensored Mode`
2. In the active conversation, click the `UNCENSORED` pill

If the configured uncensored model is missing, the app shows a banner with the exact pull command.

Install the default uncensored model:

```bash
ollama pull huihui_ai/qwen3-abliterated:8b
```

Optional backup candidate:

```bash
ollama pull dolphin3:8b
```

## How To Switch Models

### Change the standard app models in code

Edit [AppConfig.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/AppConfig.swift):

- `primaryModel`
- `fallbackModel`
- `compactionModel`

Then run:

```bash
swift test
swift build
./build.sh --run
```

### Change the uncensored default in code

Edit [AppSettings.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Models/AppSettings.swift):

- `defaultUncensoredModelName`

This changes the default value for new installs / blank settings.

### Change the uncensored model locally without a code change

Use Preferences -> Models -> `Uncensored model tag`

The effective value is:

- `AppSettings.shared.effectiveUncensoredModelName`

## Rich Presentation

Rich presentation is now first-class:

- `present(kind=html)` -> Bob's rich HTML window
- `present(kind=url)` -> default browser
- `present(kind=file)` -> default app

Assistant transcript chips route through the same `PresentationService`.
Rich HTML snapshots can be reopened after the window is closed.

## Jarvis Phone Tools

Current local app behavior:

- tools: `phone_call`, `phone_hangup`, `phone_status`
- gating: Jarvis phone enabled, valid base URL, non-empty Jarvis API key, non-empty operator secret
- auth on `/call/*`:
  - `X-Jarvis-Key` from `JARVIS_API_KEY`
  - `x-operator-secret` from `OPERATOR_API_SECRET`
- `/health` remains open and is only a reachability check

Preference fields:

- `Jarvis API key`
- `Operator secret`

Local setup note:

- on local developer machines, if those preference fields are blank, the app will try to seed them from the repo-root `.env`
- after that first seeding, the persisted Preferences values remain authoritative
- local phone shortcuts now also seed from repo-local config:
  - `ZACK_PERSONAL_NUMBER`
  - `GLENNEL_PERSONAL_NUMBER`
  - `jarvis-address-book.local.json`
- Bob's prompt/tool guidance now explicitly tells the model:
  - `call me` -> pass `to='me'`
  - plain local numbers like `8082925669` are acceptable and normalized client-side

Troubleshooting:

- `401 Unauthorized` with capital `U` -> operator secret rejected by the outer gate
- `401 unauthorized` with lowercase `u` -> Jarvis API key rejected by the inner `/call/*` gate
- if `/health` is healthy but call routes still fail, assume a secret mismatch before assuming the daemon is down

Live prompt/policy guidance from `JARVIS_KNOWS.md`:

- supported caller identities are exactly:
  - `bob`
  - `buddy`
  - `zack`
  - `glennel`
  - `glennel_naggy`
- `bob` is the right default caller when the user does not specify one
- `jarvis` is not a real daemon-side caller identity
- explicit unsupported caller requests should ideally trigger a clarification question, not a silent substitution
- `to` accepts either raw E.164 numbers or contact names
- contact-name resolution is daemon-side
- explicit E.164 numbers win over contact-name lookup
- bare 10-digit and 11-digit North American numbers are normalized client-side to E.164
- `call me` now resolves to the operator's own configured number client-side
- local alias lookup checks env shortcuts and `jarvis-address-book.local.json` before falling back to daemon contact lookup
- ambiguous phrases like `call buddy` should trigger clarification
- if the user gives no clear mission brief and the purpose is not obvious from context, Bob should ask 1-2 short clarifying questions before placing the call

Live daemon features not yet first-class in OllamaBob:

- active/recent call listing
- mid-call message injection
- mid-call supervision
- approval request queues
- contacts APIs
- follow-up APIs
- memory search

These are available in `jarvis-phone-service` but not yet wired into the OllamaBob tool surface.

Current verified state:

- the app-side Jarvis double-auth patch is applied locally in this phase
- Preferences now expose both `Jarvis API key` and `Operator secret`
- local debug builds can seed those two values from the repo-root `.env` when the stored Preferences fields are still blank
- `ToolRuntime` now skips startup probing under XCTest so the full suite exits cleanly
- `JarvisPhoneV1Tests` no longer use the class-level `@MainActor` pattern that broke SwiftPM class filtering
- `swift test --filter JarvisPhoneV1Tests` now runs cleanly
- full-suite verification is green:
  - `swift build`
  - `swift test`
  - `./build.sh --run`
- current suite result on this machine: `100` tests, `0` failures

Operator note from the Jarvis daemon side:

- Claude reported the Codex-side `jarvis-phone` MCP config now includes both `OPERATOR_API_SECRET` and `JARVIS_API_KEY`
- those two values currently happen to match in the local `.env`
- Codex needs a restart for MCP-side `phone_call_initiate` to pick up that change

Primary files:

- [PresentationService.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Services/PresentationService.swift)
- [RichHTMLState.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Models/RichHTMLState.swift)
- [RichHTMLView.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/RichHTMLView.swift)
- [ChatBubble.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/ChatBubble.swift)
- [ArtifactDetector.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/ArtifactDetector.swift)

## Public Site Notes

- Confirmed live public page: `https://cleardeskshop.com/ollamabob/`
- Relevant section anchor used in discussion/testing: `https://cleardeskshop.com/ollamabob/#bobs`
- Confirmed live page title on 2026-04-20: `OllamaBob — Your Mac's new best mate.`
- Confirmed live description on 2026-04-20 advertises a native macOS menu-bar AI agent with `25 built-in tools`
- Confirmed live host files via SSH:
  - `/home/zackj26/public_html/ollamabob/index.html`
  - `/home/zackj26/public_html/cleardeskshop.com/ollamabob/index.html`
- Going forward, treat `/home/zackj26/public_html/ollamabob/index.html` as canonical and sync the second copy after edits

## Key Files

- [AGENTS.md](/Users/zack/ollamaBob/AGENTS.md): repo layout and commands
- [CLAUDE.md](/Users/zack/ollamaBob/CLAUDE.md): project guide and decision log
- [README.md](/Users/zack/ollamaBob/README.md): human-facing overview
- [MULTIMEDIA_BOB.md](/Users/zack/ollamaBob/docs/MULTIMEDIA_BOB.md): rich presentation plan/spec
- [NAUGHTYBOB_PLAN.md](/Users/zack/ollamaBob/OllamaBob/NAUGHTYBOB_PLAN.md): uncensored-mode plan/spec
- [CHAT_REVIEW_REMEDIATION_PLAN.md](/Users/zack/ollamaBob/docs/CHAT_REVIEW_REMEDIATION_PLAN.md): active phased plan for the remaining validated chat/UI review findings
- [OPERATOR_QA.md](/Users/zack/ollamaBob/docs/OPERATOR_QA.md): manual QA checklist and operator gotchas
- [JARVIS_BOB_CALLS.md](/Users/zack/ollamaBob/JARVIS_BOB_CALLS.md): Jarvis phone integration implementation plan
- [CODEX-JARVIS-CALL-HANDOFF.md](/Users/zack/ollamaBob/CODEX-JARVIS-CALL-HANDOFF.md): current Codex session handoff for phone tool tests

## Verification Commands

From `OllamaBob/`:

```bash
swift test
swift build
./build.sh --run
```

Check current Ollama models:

```bash
ollama list
```

## Remaining Backlog

These are not blockers for the current shipped state:

- fuller HTML sanitization if we want to move beyond the current regex + CSP + JS-disabled defense
- broader transcript/history UX for avatar-only mode
- further auto-scroll heuristics if long in-place transcript mutations become a real issue

## Superseded Docs

- [OLLAMABOB_V2.9.2_HANDOFF.md](/Users/zack/ollamaBob/docs/OLLAMABOB_V2.9.2_HANDOFF.md) is historical and no longer the primary handoff.
