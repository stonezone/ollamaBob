# Project Memory

## Collaboration Preferences
- The user prefers delegated execution with explicit supervision: use sub-agents for bounded slices, keep a central plan, and stop work immediately on scope drift.
- The user values token efficiency as long as it does not reduce research quality or verification rigor.
- The user prefers direct execution over extended discussion once the plan is clear.
- The user wants docs kept current at each major phase, especially `README.md`, handoff docs, and plan docs.
- The user wants each major overnight phase committed and pushed instead of accumulating a large local delta.
- The user is comfortable with long autonomous overnight execution as long as progress is bounded, verified, and documented.

## Execution Guardrails
- For multi-phase work, define hard no-drift guardrails before implementation.
- Keep each worker on a disjoint write set.
- If a worker blocks, drifts, or fails to return a bounded result in time, shut it down and keep only locally verified changes.

## Verified Architecture Patterns
- `ChatSessionController` is the shared chat/session boundary for UI surfaces such as `BobsDeskView` and `ChatPanel`.
- `ConversationStoreController` owns conversation list/load/rename/delete behavior and should stay independent from view code.
- Structured local file actions should prefer first-class tools (`create_directory`, `list_directory`, `write_file`, `move_file`) over free-form shell commands when possible.
- `PromptComposer` memory access now flows through a narrow store seam rather than direct DB calls.
- Rich presentation is now a first-class pipeline centered on `PresentationService`, `RichHTMLState`, and transcript artifact chips that can reopen stored HTML snapshots after the window closes.
- Naughty Bob v1 is implemented inside the current app, not as a separate target: per-conversation uncensored mode, tools forced off, no silent fallback to the normal stack, and compaction skipped.

## Verification Norms
- Run `swift build` and `swift test` after integrating worker output; do not rely only on worker-reported results.
- Leave unrelated modified and untracked files alone unless the user explicitly asks otherwise.
- After code phases that affect the live app, rebuild and relaunch `OllamaBob.app` from `OllamaBob/build/OllamaBob.app`.
- After doc phases, keep `docs/CURRENT_HANDOFF.md` synchronized with the actual local operator state when that state materially changed.
- At major phase boundaries, run a `vibe_check` before choosing the next slice of work.
- Before compaction or a hard session stop, run reflection and persist the durable learnings into `MEMORY.md`.

## Known Operational Failure Mode
- Multiple active Codex/SwiftPM processes in this repo can cause lock contention or "too many open files" behavior. Check running processes and terminate stale repo-local Codex sessions before retrying builds or agent work.
- For `open ~/Desktop/...` and similar file-open fallbacks, a `shell` timeout can mean macOS TCC is waiting on a Desktop/Documents/Downloads permission prompt, not that the open path is fundamentally broken.
- Secondary UI surfaces can lag behind the main desk view if they use message-count-only transcript refresh logic; use a refresh token that includes last-message growth when pinning transcript scroll.
- When rich presentation is disabled, simple local file-open requests should route to `shell open ...` fallback rather than lingering on `present` or Preview-specific AppleScript attempts.

## Public Site Notes
- Confirmed public OllamaBob page URL: `https://cleardeskshop.com/ollamabob/` with section anchor `#bobs`.
- Confirmed live page title on 2026-04-20: `OllamaBob — Your Mac's new best mate.`
- Confirmed live page description on 2026-04-20 mentions a native macOS menu-bar AI agent and `25 built-in tools`.
- The exact local source file for the public `cleardeskshop.com/ollamabob` page is still not verified inside `/Users/zack/ollamaBob`; a quick check of `/Users/zack/ollama-chat` did not confirm ownership of that page.
