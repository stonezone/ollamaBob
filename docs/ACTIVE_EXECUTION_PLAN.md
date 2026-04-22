# ACTIVE_EXECUTION_PLAN.md

## Task

Avatar-mode hardening and no-drift execution plan for OllamaBob.

This file is binding for the current task. Read after `AGENTS.md` and `docs/CURRENT_HANDOFF.md`.

## Mission

Audit first, then implement the smallest highest-leverage changes needed to make Avatar Mode robust, maintainable, and production-worthy without regressing Full / developer view.

## Non-Negotiable Constraints

- Use the real files/classes in the repo.
- Prefer extending existing boundaries (`ChatSessionController`, `AgentLoop`, `AppState`, `AppSettings`, `BobsDeskView`, existing window coordinator/configurator) over introducing new ones.
- Do not introduce a new state container, event bus, reducer/store layer, parsing/normalization layer, or animation framework unless the audit proves the current boundaries create duplicated truth, unsafe coupling, mode drift, or brittle behavior that cannot be fixed more cleanly in place.
- If a new boundary is recommended, prove why with exact file/class references and compare it against the smallest in-place alternative.
- Do not invent Rive or any new animation system unless it already exists in the repo.
- Preserve native macOS feel and performance.
- Prefer additive refactors over destructive rewrites.
- No code until the audit and plan are complete.

## Supported Modes That Must Remain

### 1. Full / developer view
- hacker/developer surface
- tool activity, debug data, execution flow, logs, developer-facing detail

### 2. Avatar-only mode
- immersive desktop companion overlay
- animated avatar or avatar-state presentation
- comic-book style speech bubble
- short user-facing responses only
- no raw tool trace / debug chatter in the main avatar UI

## Preserved Components

Unless this plan is explicitly amended after evidence, do **not** change:

- current `AgentLoop -> ChatSessionController -> BobsDeskView` pipeline
- `stream: false`
- `PresentationService` / `present`
- Jarvis phone tools
- approvals / path policy
- uncensored mode behavior and constraints
- onboarding / preferences
- Tool Activity window
- avatar pack system and `bobMood`
- native `performDrag(with:)` drag path
- per-mode window persistence / relaunch behavior
- current main desk window scene structure
- current rich HTML companion window behavior

## Known Hypotheses To Verify

These are hypotheses, not pre-approved conclusions.

### Engineering hypotheses
- Active conversation ownership may be split between `ChatSessionController` and a separate conversation store/controller, creating a risk that an in-flight turn can complete into the wrong conversation after a switch/new chat.
- Avatar mode may be able to get stuck in a thinking/pending state if completion occurs without transcript delta or without the exact state change the bubble currently watches.
- Avatar-only speech may still be a truncated projection of the full assistant transcript, which may need stronger projection rules to feel speech-like rather than transcript-like.

### UX / window hypotheses
- Bubble geometry may be slot-first instead of content-first, causing oversized frosted-glass space for short replies.
- Bubble tail anchoring may be fixed instead of following actual avatar/head geometry.
- Accessibility display settings (`Reduce Motion`, `Reduce Transparency`) may not be honored.
- Multi-monitor restore / hotplug behavior may be under-hardened.
- Avatar window presence may still feel like a normal app window rather than a companion overlay, but any change to floating/all-spaces behavior is a product decision, not an automatic fix.

### Markup / tag hypothesis
- If transcript artifacts like `<speech>` / `<debug>` were discussed previously, verify whether the app actually parses or depends on those tags anywhere in code.
- Do **not** assume a tag-based parser exists.
- Do **not** propose a parser-removal project unless the audit finds a real parser or real UI dependence on model-emitted tags.

## Required Audit Output Before Any Code

Produce all of the following:

1. concise architecture map
2. ranked findings list
3. minimal-change implementation plan
4. explicit list of what should **not** be changed
5. verification notes

For each ranked finding include:
- exact file/class references
- smallest plausible fix
- expected blast radius
- quick verification step

## Audit Questions

### A. Current architecture
1. How is mode state represented and toggled today?
2. What files/classes own windowing and overlay behavior today?
3. How is assistant output delivered to the UI today?
4. How are tool events surfaced today?
5. How is avatar state driven today?
6. How is drag/move behavior implemented today?
7. Where is logic duplicated between Full view and Avatar-only mode?
8. What parts are clean enough to keep?
9. What parts are brittle and why?

### B. Ranked findings
Rank issues high / medium / low with exact file/class references, especially around:
- duplicated active-conversation ownership or duplicated derived truth
- in-flight turn integrity / wrong-chat completion risk
- output projection / formatting assumptions
- pending/thinking state clearing
- window/input handling
- drag reliability
- bubble layout / sizing
- bubble/avatar attachment
- stale or orphaned UI on mode switch
- asset loading / fallback behavior
- multi-monitor behavior
- accessibility / reduce motion / reduce transparency

### C. Evidence standard
- Distinguish observed fact from inference.
- If you claim something is brittle, cite the file/class and explain the concrete failure mode.
- If you cannot verify a claim from code, say so.
- If you cannot build/run the app in this environment, say so explicitly.
- Use code evidence first.
- Use screenshot-based or UI-based measurements only as labeled estimates.
- Do not imply runtime verification you did not actually perform.

## Hard Rules

- Audit first.
- No speculative architecture rewrite.
- No new state container, event bus, reducer/store layer, parsing layer, or animation framework unless the audit proves they are necessary and the smallest in-place fix is insufficient.
- Propose the smallest fix per verified problem.
- Preserve native macOS feel and performance.
- Prefer additive refactors over destructive rewrites.
- Stay phase-locked.
- No unrelated cleanup.

## Implementation Priority Order

### Priority 1 — Session integrity and completion correctness

**Goal:** ensure a turn always lands in the originating conversation and never mutates the wrong live session.

**Requirements**
- Verify whether active conversation ownership is split across more than one controller/store.
- If confirmed, make `ChatSessionController` the single active-conversation owner or otherwise guarantee a single authoritative live conversation boundary without a large rewrite.
- Add an originating conversation-id + turn-token guard before applying async completion results.
- Review whether UI should allow conversation switching/new chat while a turn is in flight:
  - preferred default: keep switching enabled if completion guard fully solves correctness
  - only disable switching if a real remaining corruption/race risk still exists after the guard
- Preserve conversation load/rename/delete flows and current UX unless a change is necessary.

**Deliverables**
- exact failure mode
- file/class targets
- smallest fix
- verification steps:
  - submit prompt
  - switch conversations immediately
  - create new chat immediately
  - ensure reply/history/tool state land only in originating conversation

### Priority 2 — Pending / thinking state correctness

**Goal:** Avatar Mode must never remain in thinking state after a valid turn completion.

**Requirements**
- Audit how pending/thinking state is set and cleared.
- Verify whether the bubble currently depends on transcript revision, error changes, or other indirect signals.
- Fix no-message / no-delta completion paths so the avatar reliably returns to idle, last speech, or final status.
- Add focused regression coverage for the verified failure path.

**Deliverables**
- exact trigger path that can leave the bubble stuck
- smallest fix
- regression test or equivalent verification step

### Priority 3 — Stronger avatar-only speech projection

**Goal:** Avatar Mode should feel like spoken output, not a mini transcript.

**Requirements**
- Keep one message model unless the audit proves it is insufficient.
- Do not add a new parser.
- Do not depend on model-emitted tags.
- Tighten the existing avatar-only preview/projection rules so avatar mode:
  - shows concise speech-like output
  - collapses code / tool-heavy / transcript-like content harder
  - keeps full transcript untouched in Full mode
- Preserve any existing HTML/image/rich-view placeholder behavior if already present.

**Suggested target behavior**
- 1 to 3 short spoken lines for normal avatar-only replies
- no raw code block rendering in primary avatar speech unless explicitly intended
- minimal developer-noise leakage even when assistant content is verbose

**Verification**
- long prose reply
- prose + list
- prose + code
- tool-heavy reply
- ensure Full mode remains unchanged while Avatar Mode becomes more speech-like

### Priority 4 — Bubble geometry and bubble/avatar attachment

**Goal:** Avatar Mode should look like a desktop companion, not a shrunk chat client.

**Requirements**
- Make bubble size to content first.
- Remove or reduce dead frosted-glass space for short replies.
- Keep a max-width clamp for longer replies.
- Keep scroll only for overflow/history, not as the default visual state.
- Rework tail anchoring so it follows actual avatar/head geometry rather than a fixed fraction if the audit confirms that issue.
- Keep current bubble system unless a smaller in-place refinement is clearly insufficient.

**For every change here, report**
- current observed behavior
- approximate current measurement or estimate
- target behavior
- why it matters

**Suggested targets**
- short replies often land roughly in a ~140–280 pt content-hugging range
- max-width clamp around ~300–340 pt unless current layout constraints prove otherwise
- thinking state may keep a small fixed pill bubble if that reads better

**Verification**
- 1-line reply
- 2-line reply
- 5-line reply
- long overflow case
- compare both bundled avatar packs if more than one exists

### Priority 5 — Mode lifecycle and overlay cleanup

**Goal:** Avatar-only UI state should not resurrect stale surfaces or feel brittle across mode switches.

**Requirements**
- Verify whether history overlay or similar avatar-only local state persists unexpectedly across mode changes.
- Reset/close avatar-only transient surfaces when leaving avatar-only mode if the audit confirms stale resurrection.
- Preserve per-mode frame persistence and relaunch behavior.
- Do not break native drag/window behavior.

**Verification**
- open overlay/history if available
- switch to full
- switch back
- relaunch app
- confirm no stale or orphaned transient UI

### Priority 6 — Accessibility and fallback hardening

**Goal:** make the overlay production-worthy without architecture churn.

**Requirements**
- Audit and add `Reduce Motion` handling if missing.
- Audit and add `Reduce Transparency` handling if missing.
- Add/verify accessibility labels for avatar speech surface and avatar image where appropriate.
- Hide drag-only affordances from accessibility if appropriate.
- Audit missing-asset fallback behavior; avoid showing debug-ish internal filenames to end users if that currently happens.
- Keep the current avatar pack / `bobMood` pipeline.

**Verification**
- toggle macOS accessibility display settings
- validate avatar mode still reads clearly
- simulate asset fallback if feasible

### Priority 7 — Multi-monitor and window resilience

**Goal:** make the overlay recover sanely across monitor changes without changing the overall window model.

**Requirements**
- Audit current frame-restore logic.
- If current logic only tests weak intersection, clamp restored frames more aggressively into visible bounds.
- Add screen-parameter/hotplug handling if missing.
- Evaluate floating / all-Spaces / fullscreen-auxiliary behavior only as an explicit product decision:
  - do not enable by default unless requested and justified
  - if recommended, make it configurable or clearly isolated to Avatar Mode
- Preserve current scene structure unless proven insufficient.

**Verification**
- move window near edge
- relaunch
- change display arrangement or disconnect external display if testable
- confirm avatar stays recoverable and on-screen

## Optional Cleanup / Watchlist

Only act if low-risk and clearly valuable in this phase:

- dead/unused alternate chat surface or duplicate compiled UI that can attract drift
- minor input-width polish in Avatar Mode
- minor fallback polish

## Phase Gates

After each implementation phase, do all of the following before advancing:

- `swift build`
- `swift test`
- targeted verification for the active phase
- changed-files list
- rollback note
- preserved-components regression summary
- list of deferred items, if any

## Stop Conditions

Stop and report immediately if:

- tests fail
- scope expands beyond the active phase
- a fix requires a speculative rewrite
- a new architecture layer is added without explicit approval
- preserved components would be changed without explicit approval
- runtime verification cannot support a claimed behavioral conclusion

## Acceptance Criteria For Implementation

The work is not done unless all of the following are true:

- Both modes still exist and work.
- A turn cannot complete into the wrong conversation after a switch/new chat.
- Avatar Mode cannot remain stuck in thinking state after a valid completion.
- Avatar-only speech is visibly more speech-like and less transcript-like.
- Full mode still exposes developer-grade detail.
- Bubble no longer looks absurdly large for short messages.
- Bubble feels visually attached to the avatar.
- Mode switching does not resurrect stale avatar-only transient UI.
- Accessibility display settings are respected if supported by the platform.
- Window/frame persistence still works.
- Multi-monitor behavior is more recoverable and not worse than before.
- No preserved feature regresses.

## Final Response Format For The Audit Stage

Respond in this order:

1. Audit findings
2. Minimal-change plan
3. Risks / deferred items
4. Exact build/test/verification steps

Do not write code yet. Stop after the audit and plan.

## Final Response Format For Each Implementation Phase

Respond in this order:

1. Phase completed
2. Changed files
3. Why the change is the smallest viable fix
4. Verification performed
5. Preserved-feature regression check
6. Deferred risks / next phase recommendation
