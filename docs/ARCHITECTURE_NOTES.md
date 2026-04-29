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
