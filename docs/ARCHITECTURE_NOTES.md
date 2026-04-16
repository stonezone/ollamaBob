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

## Testing Focus

When adding new behavior, prefer fast XCTest coverage at the controller/tool layer:

- `ChatSessionControllerTests` for session-state flow
- `ConversationStoreControllerTests` for metadata actions and filtering
- `DatabaseManagerTests` for persistence ordering and metadata storage
- `StructuredFileToolTests` and `StructuredGitToolTests` for tool approval and execution paths
