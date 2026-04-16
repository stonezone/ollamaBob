# Project Memory

## Collaboration Preferences
- The user prefers delegated execution with explicit supervision: use sub-agents for bounded slices, keep a central plan, and stop work immediately on scope drift.
- The user values token efficiency as long as it does not reduce research quality or verification rigor.
- The user prefers direct execution over extended discussion once the plan is clear.

## Execution Guardrails
- For multi-phase work, define hard no-drift guardrails before implementation.
- Keep each worker on a disjoint write set.
- If a worker blocks, drifts, or fails to return a bounded result in time, shut it down and keep only locally verified changes.

## Verified Architecture Patterns
- `ChatSessionController` is the shared chat/session boundary for UI surfaces such as `BobsDeskView` and `ChatPanel`.
- `ConversationStoreController` owns conversation list/load/rename/delete behavior and should stay independent from view code.
- Structured local file actions should prefer first-class tools (`create_directory`, `list_directory`, `write_file`, `move_file`) over free-form shell commands when possible.
- `PromptComposer` memory access now flows through a narrow store seam rather than direct DB calls.

## Verification Norms
- Run `swift build` and `swift test` after integrating worker output; do not rely only on worker-reported results.
- Leave unrelated modified and untracked files alone unless the user explicitly asks otherwise.

## Known Operational Failure Mode
- Multiple active Codex/SwiftPM processes in this repo can cause lock contention or "too many open files" behavior. Check running processes and terminate stale repo-local Codex sessions before retrying builds or agent work.
