# Architecture Notes

## Chat and Conversation Boundaries

- `ChatSessionController` owns the active transcript, Ollama history, message persistence, tool-log persistence, and command handling for `/new` and `/clear`.
- `ConversationStoreController` owns conversation discovery and metadata actions: list, title search, pin/unpin, load, rename, and delete.
- `ConversationManagerView` is intentionally narrow. It is a popover for conversation management, not a second navigation system.

## Structured Tools

Prefer first-class tools before falling back to `shell`:

- File and directory work: `read_file`, `list_directory`, `create_directory`, `write_file`, `move_file`
- Git inspection: `git_status`, `git_diff`
- Apple Mail reads: `mail_check` for inbox unread/search summaries and `mail_triage` for explicit short-preview attention triage before generic AppleScript

These tools exist to keep approvals predictable, reduce shell-quoting failure modes, and make regression testing possible.

## Persistence Rules

- Conversation persistence is additive-only. New metadata such as pinning should be introduced with backward-compatible schema changes.
- Message insert and conversation `updatedAt` maintenance should stay in the same write path so ordering remains stable.

## Services vs Tools

`Tools/` hosts types the model can call. `Services/` hosts app-level infrastructure the user or the app itself invokes — not the model. Two examples:

- `PromptComposerMemoryStore` — the narrow seam `PromptComposer` reads facts through, keeping direct DB calls out of prompt assembly.
- `AutomationProbe` (added V2.9.2) — a `@MainActor ObservableObject` singleton that fires cheap read-only probes against Mail/Calendar/Reminders/Contacts/Music/Finder/System Events. Mail counts accounts; the others return app names. Drives the onboarding Permissions step and the Preferences → Tools → Mac App Permissions section. The probe is never reachable from the agent loop; keeping it in `Services/` makes that separation explicit.
- `MailTool` — model-callable, modal-gated Apple Mail helpers. `mail_check` is metadata-only (date/read state/sender/subject). `mail_triage` is only for explicit attention-triage requests and adds short truncated previews without mutating Mail. Both use hardcoded AppleScript so common mail checks do not require the model to generate arbitrary Mail scripts.
- `LocalAddressBook` — runtime phone alias loader for Jarvis calls. It merges env aliases, local JSON maps, and VCF exports such as `~/Downloads/bobs_contacts.vcf`; it is not a full Contacts database.
- `JarvisCallClientHTTP` — production HTTP client for call supervision. It uses the daemon's two-header auth contract and maps `/calls/active`, `/call/status/:id`, and `/call/:id/message` into Bob's `phone_list_calls`, `phone_get_transcript`, and `phone_inject` tools.
- `DeskPromptActions` — pure adapter for app-originated prompts. Walkie-talkie transcripts are trimmed before submission; clipboard stack traces are wrapped with `UntrustedWrapper` before Bob sees them.

## TCC / Automation

`build.sh` inlines every usage string macOS needs before granting Bob access to protected surfaces. Specifically: `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSAppleEventsUsageDescription`, `NSContactsUsageDescription`, `NSCalendarsUsageDescription`, `NSRemindersUsageDescription`. Removing any of these silently breaks the corresponding grant flow — the user clicks "Allow" and the subsequent access still fails with a TCC denial code (`-1743` for Apple events).

## Testing Focus

When adding new behavior, prefer fast XCTest coverage at the controller/tool layer:

- `ChatSessionControllerTests` for session-state flow
- `ConversationStoreControllerTests` for metadata actions and filtering
- `DatabaseManagerTests` for persistence ordering and metadata storage
- `StructuredFileToolTests` and `StructuredGitToolTests` for tool approval and execution paths
- `Phase2_9ToolTests` for the V2.9 Phase A native tools (OCR, say, weather, units, sips, yt-dlp)
- `PhoneSupervisionToolsTests` for Jarvis supervision route/auth mapping
- `DeskPromptActionsTests` for notification-to-chat prompt adapters
- `ShellLongRunningTests` for dual-timer behavior, idle resets, hard-cap enforcement, and cancel

## Long-Running Shell and ProcessRunner Architecture (v1.0.44)

`ProcessRunner` uses two independent timers instead of a single fixed wall-clock timeout:

- **`idleTimeout`** (default 60 s): a generation-counter-based `IdleTimer` that resets every time `onOutputChunk` fires. If the process produces no output for 60 s the timer fires and the process is terminated. The generation counter makes the reset race-free — a reset that races a pending fire simply increments the generation and the stale closure is a no-op.
- **`hardCap`** (default 1800 s): a single `DispatchWorkItem` that fires unconditionally after the wall-clock ceiling regardless of output.

Both paths call `terminateThenKill(grace: 2.0)` — SIGTERM first, then SIGKILL if the child is still alive after a 2-second grace period.

`ShellTool` exposes both timers as optional flat parameters (`idle_timeout_seconds`, `max_total_seconds`, each clamped to a max). It runs via `/bin/zsh -lc` so `/opt/homebrew/bin` is on PATH even under launchd.

**Critical drain note:** `ProcessRunner.drain()` reads stdout/stderr via `handle.availableData`, not `readData(ofLength:)`. The `readData(ofLength:)` form blocks until the buffer is full, which starves both the live-output UI and tests even when the child writes unbuffered output. `availableData` returns whatever bytes are in the pipe right now, which is what makes live streaming work.

## Live Tool Output Data Flow (v1.0.44)

```
ProcessRunner.onOutputChunk  (called on output pipe queue)
  → DispatchQueue.main.async
      → ToolLogEntry.output += chunk   (@Published, final class ObservableObject)
          → SwiftUI diff detects change
              → ToolActivityRow re-renders   (@ObservedObject var entry: ToolLogEntry)
```

`ToolLogEntry` was a struct before v1.0.44. Promoting it to `final class ObservableObject` is required: SwiftUI's `@ObservedObject` only works with reference types, and the append-in-place mutation on `output` must be visible to all observers of the same instance. `ToolActivityRow` changed its binding from `let entry` to `@ObservedObject var entry`.

## AgentLoop Cancel Registry (v1.0.44)

`AgentLoop` maintains an `activeCancelHandles: [UUID: CancelHandle]` dictionary keyed by `ToolLogEntry.id`. While a tool is running:

1. `AgentLoopToolDispatch.executeShellWithLiveEntry` creates a `ToolLogEntry` up-front and registers a `CancelHandle` in `activeCancelHandles`.
2. `canCancel` (`@Published Bool`) reflects whether any handle is registered.
3. Calling `cancel()` on the agent loop, or `cancelToolEntry(id:)` with a specific entry ID, invokes the handle and removes it.
4. The handle is always deregistered on normal completion to prevent stale entries.

The 120-second agent-loop budget excludes tool wall-time: the guard is `Date().timeIntervalSince(loopStart) - toolTimeAccumulated > timeoutSeconds`. This prevents a legitimate long shell command (e.g., a brew upgrade) from consuming the model-turn budget while it runs.

`cancelRequested` is reset to `false` at the top of `process()` so a stale flag from a previous turn cannot abort a new turn immediately.
