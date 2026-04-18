# Architecture Notes

## Chat and Conversation Boundaries

- `ChatSessionController` owns the active transcript, Ollama history, message persistence, tool-log persistence, and command handling for `/new` and `/clear`.
- `ConversationStoreController` owns conversation discovery and metadata actions: list, title search, pin/unpin, load, rename, and delete.
- `ConversationManagerView` is intentionally narrow. It is a popover for conversation management, not a second navigation system.

## Structured Tools

Prefer first-class tools before falling back to `shell`:

- File and directory work: `read_file`, `list_directory`, `create_directory`, `write_file`, `move_file`
- Git inspection: `git_status`, `git_diff`

These tools exist to keep approvals predictable, reduce shell-quoting failure modes, and make regression testing possible.

## Persistence Rules

- Conversation persistence is additive-only. New metadata such as pinning should be introduced with backward-compatible schema changes.
- Message insert and conversation `updatedAt` maintenance should stay in the same write path so ordering remains stable.

## Services vs Tools

`Tools/` hosts types the model can call. `Services/` hosts app-level infrastructure the user or the app itself invokes — not the model. Two examples:

- `PromptComposerMemoryStore` — the narrow seam `PromptComposer` reads facts through, keeping direct DB calls out of prompt assembly.
- `AutomationProbe` (added V2.9.2) — a `@MainActor ObservableObject` singleton that fires trivial `tell application "X" to return name` probes against Mail/Calendar/Reminders/Contacts/Music/Finder/System Events. Drives the onboarding Permissions step and the Preferences → Tools → Mac App Permissions section. The probe is never reachable from the agent loop; keeping it in `Services/` makes that separation explicit.

## TCC / Automation

`build.sh` inlines every usage string macOS needs before granting Bob access to protected surfaces. Specifically: `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSAppleEventsUsageDescription`, `NSContactsUsageDescription`, `NSCalendarsUsageDescription`, `NSRemindersUsageDescription`. Removing any of these silently breaks the corresponding grant flow — the user clicks "Allow" and the subsequent access still fails with a TCC denial code (`-1743` for Apple events).

## Testing Focus

When adding new behavior, prefer fast XCTest coverage at the controller/tool layer:

- `ChatSessionControllerTests` for session-state flow
- `ConversationStoreControllerTests` for metadata actions and filtering
- `DatabaseManagerTests` for persistence ordering and metadata storage
- `StructuredFileToolTests` and `StructuredGitToolTests` for tool approval and execution paths
- `Phase2_9ToolTests` for the V2.9 Phase A native tools (OCR, say, weather, units, sips, yt-dlp)
