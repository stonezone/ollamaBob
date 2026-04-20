# OllamaBob — Current Handoff

**Date:** 2026-04-20  
**Audience:** the next coding agent or operator picking the project up cold.

## Current State

The app is live as a single macOS menu-bar product with:

- core local agent loop over Ollama `/api/chat`
- V2.9.2 AppleScript/TCC permissions flow and avatar-only mode
- V2.10 rich presentation
- Naughty Bob v1 as a feature inside the current app, not a separate app

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

Primary files:

- [PresentationService.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Services/PresentationService.swift)
- [RichHTMLState.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Models/RichHTMLState.swift)
- [RichHTMLView.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/RichHTMLView.swift)
- [ChatBubble.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/ChatBubble.swift)
- [ArtifactDetector.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/ArtifactDetector.swift)

## Key Files

- [AGENTS.md](/Users/zack/ollamaBob/AGENTS.md): repo layout and commands
- [CLAUDE.md](/Users/zack/ollamaBob/CLAUDE.md): project guide and decision log
- [README.md](/Users/zack/ollamaBob/README.md): human-facing overview
- [MULTIMEDIA_BOB.md](/Users/zack/ollamaBob/docs/MULTIMEDIA_BOB.md): rich presentation plan/spec
- [NAUGHTYBOB_PLAN.md](/Users/zack/ollamaBob/OllamaBob/NAUGHTYBOB_PLAN.md): uncensored-mode plan/spec
- [CHAT_REVIEW_REMEDIATION_PLAN.md](/Users/zack/ollamaBob/docs/CHAT_REVIEW_REMEDIATION_PLAN.md): active phased plan for the remaining validated chat/UI review findings

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
