# Naughty Bob — Feature V1 Plan

**Status:** Implemented in the current app (`OllamaBob.app`)
**Current default uncensored tag:** `huihui_ai/qwen3-abliterated:8b`
**Current backup recommendation:** `dolphin3:8b`

## Product Decision

This ships as a feature inside `OllamaBob.app`, not as a separate app.

Reasoning:
- One app keeps persistence, settings, onboarding, tests, and release flow unified.
- The problem is mode/routing, not product separation.
- We should not fork the app surface until there is a hard distribution, branding, or UX reason to do that.

## V1 Goals

Add an **uncensored per-conversation mode** for chats where the default model stack refuses or moralizes unnecessarily.

V1 must be:
- explicit
- visible
- reversible
- safe at the tool/policy layer
- trustworthy about which model actually answered

## Non-Negotiables

These stay enforced in uncensored mode:
- approval policy
- forbidden command list
- path policy
- timeout/output caps
- conversation persistence
- local safety rails in `BobOperatingRules`

What changes in uncensored mode:
- model selection
- tool availability to the model
- prompt tone override

## Exact V1 Decisions

### 1. Single app, feature gated

Add a master feature flag in settings:
- `uncensoredModeAvailable: Bool = false`

If master flag is off:
- no uncensored toggle in chat UI
- behavior is identical to current app

### 2. Per-conversation sticky mode

Each conversation stores:
- `uncensoredMode: Bool = false`

Behavior:
- toggling affects only the current conversation
- reopening that conversation restores the mode
- new conversations start with uncensored mode OFF

### 3. Model choice

### Default configured uncensored model
- `huihui_ai/qwen3-abliterated:8b`

### Recommended backup model
- `dolphin3:8b`

### Why this choice
- V1 is chat-first, not tool-first.
- We are deliberately disabling tools in uncensored mode, so tool-template quality matters less than conversational quality.
- `qwen3-abliterated:8b` is the preferred default because it is likely to produce the behavior the feature is actually for.
- `dolphin3:8b` is the safer backup if the qwen abliterated model proves unstable or unavailable.

### Important local state right now
V1 was intentionally designed to handle a missing uncensored model without guessing:
- if the configured uncensored model is absent, the app shows a banner with the exact `ollama pull ...` command
- it does **not** silently fall back to the standard model stack

Operator note as of 2026-04-20:
- the default uncensored model was pulled locally
- the user confirmed uncensored-mode conversations are working on this machine

## Settings Surface

Add to `AppSettings`:
- `uncensoredModeAvailable: Bool = false`
- `uncensoredModelName: String = "huihui_ai/qwen3-abliterated:8b"`

Do **not** add a user-facing "disable tools in uncensored mode" toggle in V1.
In V1, tools are forced OFF in uncensored mode.

Preferences UI under Models:
- Toggle: `Enable Uncensored Mode`
- Text field: `Uncensored model tag`
- Inline note: `Tools are disabled in uncensored mode in V1. Approval and path safety still apply.`
- Inline note when model is missing: `Model not installed. Pull it with: ollama pull <tag>`

## Chat UI

### Input control
Add a small toggle/pill near the input/send area.

Behavior:
- visible only when `uncensoredModeAvailable == true`
- toggles current conversation's `uncensoredMode`

### Persistent mode visibility
Input-only indication is not enough.
V1 should also show a persistent visible mode marker in the active conversation surface.

Required:
- conversation header badge or transcript badge showing `Uncensored`

Optional later:
- sidebar row tint or badge

## Agent Routing

### Standard mode
Use current behavior:
- model: `AppConfig.primaryModel`
- fallback: `AppConfig.fallbackModel`
- tools: normal live registry
- compaction: current behavior

### Uncensored mode
Use:
- model: `AppSettings.shared.uncensoredModelName`
- tools: `[]`
- fallback to normal model stack: **disallowed**

If the uncensored model is missing:
- fail explicitly
- show a clear error
- do not silently answer with `gemma4:e4b`
- do not silently answer with `qwen3:14b`

### Compaction behavior in uncensored mode
Current compaction uses a normal model (`qwen3:14b`).
That is wrong for uncensored conversations because it silently routes content through a different model family.

V1 decision:
- disable conversation compaction while uncensored mode is ON

That keeps the mode semantically honest and avoids hidden model substitution.

## Prompt / Persona Behavior

Do **not** create a separate `BobUncensoredPersona.swift` in V1.

V1 approach:
- keep the current Bob identity/persona selection
- add a small uncensored-mode prompt override at compose time
- strip moralizing/refusal-style framing from the assistant's conversational behavior
- keep system safety/tool rules in `BobOperatingRules`

Why:
- less maintenance
- less prompt drift
- easier to compare standard vs uncensored behavior
- avoids duplicating the persona layer too early

Implementation direction:
- add a prompt-composer mode or optional uncensored override block
- do not fork the persona system unless later evidence justifies it

## Fallback Rules

### Standard mode
Keep current fallback logic.

### Uncensored mode
Do not silently fall back to:
- `AppConfig.primaryModel`
- `AppConfig.fallbackModel`
- any censored/normal model

If you want a future fallback, it must be:
- explicit
- configured separately
- also uncensored

Not part of V1.

## Failure Handling

If uncensored mode is ON and the configured model is unavailable:
- show a user-visible error
- include exact pull command
- do not continue with a normal answer

Example:
- `Uncensored mode is enabled for this conversation, but model 'huihui_ai/qwen3-abliterated:8b' is not installed. Run: ollama pull huihui_ai/qwen3-abliterated:8b`

## Files Likely Touched

Core:
- `OllamaBob/OllamaBob/Models/AppSettings.swift`
- `OllamaBob/OllamaBob/Models/Conversation.swift`
- `OllamaBob/OllamaBob/Persistence/Schema.swift`
- `OllamaBob/OllamaBob/Persistence/Database.swift`
- `OllamaBob/OllamaBob/Models/ChatSessionController.swift`
- `OllamaBob/OllamaBob/Agent/AgentLoop.swift`
- `OllamaBob/OllamaBob/Personality/PromptComposer.swift`
- `OllamaBob/OllamaBob/Views/ChatPanel.swift`
- `OllamaBob/OllamaBob/Views/BobsDeskView.swift`
- `OllamaBob/OllamaBob/Views/PreferencesView.swift`

Tests:
- `OllamaBob/Tests/OllamaBobTests/...`

## Implementation Phases

### Phase 1 — Data and settings
- add settings keys
- add conversation field
- add schema migration
- wire DB load/save for `uncensoredMode`

### Phase 2 — UI controls
- add master settings UI
- add per-conversation toggle pill
- add persistent visible badge in active conversation UI

### Phase 3 — Agent routing
- pass conversation mode into `AgentLoop.process(...)`
- select uncensored model when mode is ON
- force tools empty when mode is ON
- disable compaction in uncensored mode
- block fallback-to-normal-model behavior in uncensored mode

### Phase 4 — Prompt override
- add uncensored override path in prompt composition
- keep Bob identity, remove preachy/refusal framing

### Phase 5 — Validation
- missing-model UX
- persistence checks
- regression tests
- manual acceptance pass

## Acceptance Tests

### Mode availability
- `U1` master toggle OFF -> no uncensored toggle in chat UI
- `U2` master toggle ON, conversation mode OFF -> current app behavior unchanged

### Routing
- `U3` conversation mode ON -> request goes to uncensored model
- `U4` conversation mode ON -> no tools are sent to Ollama
- `U5` conversation mode ON -> no silent fallback to standard model stack
- `U6` conversation mode ON + model missing -> explicit error, no answer from normal models
- `U7` conversation mode ON -> compaction path is skipped

### Persistence
- `U8` reopen same conversation -> uncensored mode restored
- `U9` new conversation -> uncensored mode defaults OFF
- `U10` app relaunch -> conversation uncensored state persists

### Safety invariants
- `U11` uncensored mode ON + dangerous shell request -> approval policy still applies
- `U12` uncensored mode ON + forbidden command -> still forbidden
- `U13` uncensored mode ON + sensitive path request -> path policy still enforced

### UI clarity
- `U14` active uncensored conversation clearly shows mode badge
- `U15` master toggle turned OFF while an uncensored conversation is open -> conversation returns to normal mode cleanly

## Explicit Non-Goals For V1

Not in V1:
- separate app target
- automatic model download
- separate uncensored persona file
- user-configurable tools-on uncensored mode
- uncensored fallback chain
- onboarding modal
- per-session global uncensored mode

## Build Recommendation

Build this as a feature V1 inside the current app with this exact shape:
- one app
- master enable in settings
- sticky per-conversation uncensored mode
- default uncensored model: `huihui_ai/qwen3-abliterated:8b`
- backup recommendation: `dolphin3:8b`
- tools forced OFF in uncensored mode
- no silent fallback to normal models
- no compaction in uncensored mode
- persistent visible mode badge
- prompt override, not a separate persona file

## Implemented V1 Status

Shipped in the current app:
- master settings toggle for uncensored mode availability
- per-conversation sticky `UNCENSORED` mode
- visible `UNCENSORED` badge/toggle in chat UI
- configurable uncensored model tag
- explicit missing-model banner with `ollama pull ...` guidance
- tools forced OFF while uncensored mode is on
- no silent fallback to the standard model stack
- compaction skipped while uncensored mode is on

## Follow-On Work After V1

Potential V1.1 / V2 items:
- optional uncensored backup model setting
- onboarding confirmation modal
- better model validation UI against `ollama list`
- sidebar indicators
- model-specific tuning if `qwen3-abliterated:8b` underperforms
- only if needed: dedicated uncensored persona artifact
