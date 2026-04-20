# Chat Review Remediation Plan

**Date:** 2026-04-20  
**Status:** Active implementation plan  
**Execution mode:** phased, verified, parallel where scopes are disjoint

## Goal

Address the validated blind-review findings that are still relevant in the current codebase without reopening already-stable behavior.

## Guardrails

- Use parallel worker agents only on bounded, disjoint scopes.
- Stop any worker immediately if it drifts outside the assigned scope.
- Verify every phase locally with `swift test` and `swift build`.
- Update [CURRENT_HANDOFF.md](/Users/zack/ollamaBob/docs/CURRENT_HANDOFF.md) at each major phase.
- Commit and push each major phase separately.

## Phase 0 — Resolve ChatPanel Scope

Before implementing the shared-session recommendation, decide whether [ChatPanel.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/ChatPanel.swift) is:

- a retained secondary surface that must share the same `ChatSessionController` as `BobsDeskView`, or
- dead code that should be removed instead of refactored.

This decision gates whether the “two controllers” finding is a shipped-app bug or only maintenance debt.

### Phase 0 Decision

Resolved on 2026-04-20:

- `ChatPanel` is not wired into the shipped app scene graph.
- The active chat window in [OllamaBobApp.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/OllamaBobApp.swift) mounts `BobsDeskView`, not `ChatPanel`.
- Shared-session refactoring for `ChatPanel` is therefore deferred as dead-surface maintenance work, not included in the immediate shipped-app remediation path.

Immediate consequence:

- `V-1` is de-scoped from the current shipped-path fixes.
- Phase 1 will target `BobsDeskView` + `ChatSessionController` + `AgentLoop` correctness issues only.

## Phase 1 — Conversation-Scoped Correctness

Target findings:

- reset `lastSeenToolActivityIndex` on conversation switch
- remove the turn-completion race behind the avatar bubble sync workaround
- if `ChatPanel` is retained, unify session ownership instead of duplicating `ChatSessionController`

Why first:

- These are the highest-value correctness issues.
- They affect visible behavior and state integrity.

### Phase 1 Status

Completed on 2026-04-20:

- `BobsDeskView` now resets conversation-scoped notice/tool-activity cursor state when the active conversation changes.
- `ChatSessionController` now publishes a narrow `transcriptRevision` signal whenever the transcript actually changes.
- `BobsDeskView` now uses that transcript signal to clear the turn-completion race instead of relying on the old post-processing timing workaround.

## Phase 2 — Avatar-Only Parity

Target findings:

- bring model-switch and error banners into avatar-only mode
- improve avatar-only bubble rendering so it does not regress to raw markdown/HTML-ish text

Why second:

- These are user-visible and isolated once the turn-order issue is fixed.

## Phase 3 — Render Hot-Path Cleanup

Target findings:

- cache `contextTokensUsed`
- replace full-content cache keys with stable digests
- collapse duplicate tool-activity observers
- replace offset-based parsed-block ids with stable ids
- memoize repeated HTML/body checks where profitable

Why third:

- Safe performance work after correctness issues are settled.

## Phase 4 — Trust-Boundary and UI Polish

Target findings:

- remove brittle `<untrusted>` string stripping from the display path
- make reopen-rich-view behavior resilient to settings changes
- reduce tooltip/path leakage in artifact chips
- improve icon-only accessibility and tool-activity readability
- review non-HTTP rich-view link handling and sanitizer follow-up scope

Why fourth:

- Important, but lower urgency than state correctness and avatar-only parity.

## Verification Strategy

For each phase:

1. implement the bounded change
2. run `swift test`
3. run `swift build`
4. if the phase affects the live app, run `./build.sh --run`
5. update [CURRENT_HANDOFF.md](/Users/zack/ollamaBob/docs/CURRENT_HANDOFF.md)
6. commit and push before moving on

## Immediate Next Step

Start with Phase 0:

- determine whether `ChatPanel` is still a real supported surface
- then choose the correct Phase 1 branch:
  - shared-session refactor if retained
  - removal/deferral if dead
