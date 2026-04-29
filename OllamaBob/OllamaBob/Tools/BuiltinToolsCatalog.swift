import Foundation

/// Static catalog of first-class tools (implemented in Swift, not external CLI
/// binaries). Rendered in Preferences > Tools so the user can see what Bob
/// can do natively, separate from the external tool catalog (jq/rg/etc).
enum BuiltinToolsCatalog {

    /// Approval posture shown in the UI. The *actual* approval decision is
    /// made at call time by `ApprovalPolicy.check` based on arguments (e.g.
    /// `shell` with `rm -rf` jumps to `.forbidden`). This enum reports the
    /// baseline so the UI can show a sensible dot color.
    enum ApprovalPosture: String {
        case none = "auto"
        case modal = "ask"
        case dynamic = "dynamic"
    }

    struct Entry {
        let name: String
        let category: String
        let posture: ApprovalPosture
        let description: String
    }

    /// Every first-class tool registered in `ToolRegistry.swift`. Keep in
    /// sync when adding a new tool — there is no unit test that cross-checks
    /// this list, but the Tools tab will silently miss new tools otherwise.
    static let entries: [Entry] = [
        // MARK: Files
        Entry(name: "read_file",        category: "files", posture: .none,  description: "Read a file's contents into chat by absolute path"),
        Entry(name: "write_file",       category: "files", posture: .modal, description: "Write UTF-8 text to a file (overwrites)"),
        Entry(name: "move_file",        category: "files", posture: .modal, description: "Move or rename a file or directory"),
        Entry(name: "create_directory", category: "files", posture: .modal, description: "Create a directory (parents included)"),
        Entry(name: "list_directory",   category: "files", posture: .none,  description: "List folder contents (depth up to 3)"),
        Entry(name: "search_files",     category: "files", posture: .none,  description: "Find files by name pattern"),

        // MARK: Shell
        Entry(name: "shell", category: "shell", posture: .dynamic, description: "Run a shell command (approval depends on the command)"),

        // MARK: Git
        Entry(name: "git_status", category: "git", posture: .none, description: "Show `git status --short --branch`"),
        Entry(name: "git_diff",   category: "git", posture: .none, description: "Show working-tree or staged diff"),

        // MARK: Web
        Entry(name: "web_search", category: "web", posture: .none, description: "Brave web search, top 5 results"),

        // MARK: Timeline
        Entry(name: "timeline_search", category: "timeline", posture: .none, description: "Search Bob's local Activity Timeline"),

        // MARK: Mail
        Entry(name: "mail_check", category: "mail", posture: .modal, description: "Check Apple Mail inbox summaries"),
        Entry(name: "mail_triage", category: "mail", posture: .modal, description: "Read short Apple Mail previews for attention triage"),

        // MARK: Phone
        Entry(name: "phone_call", category: "phone", posture: .modal, description: "Place a real phone call through the Jarvis phone service (defaults to Bob as caller; requires both Jarvis secrets)"),
        Entry(name: "phone_hangup", category: "phone", posture: .none, description: "End an active Jarvis phone call"),
        Entry(name: "phone_status",          category: "phone", posture: .none,  description: "Check the current status of a Jarvis phone call"),
        Entry(name: "phone_list_calls",      category: "phone", posture: .none,  description: "List active Jarvis phone calls being supervised"),
        Entry(name: "phone_get_transcript",  category: "phone", posture: .none,  description: "Fetch the latest transcript chunk for a supervised call"),
        Entry(name: "phone_inject",          category: "phone", posture: .modal, description: "Inject text into an active Jarvis call (requires approval per injection)"),

        // MARK: Presentation
        Entry(name: "present", category: "presentation", posture: .none, description: "Open rich HTML, URLs, or local files in the user's apps"),

        // MARK: Media
        Entry(name: "ocr",           category: "media", posture: .none,  description: "Extract text from an image or clipboard screenshot"),
        Entry(name: "speak",         category: "media", posture: .none,  description: "Speak text aloud via macOS TTS"),
        Entry(name: "image_convert", category: "media", posture: .modal, description: "Convert/resize images via `sips`"),

        // MARK: Utility
        Entry(name: "weather",      category: "utility", posture: .none, description: "Current weather via wttr.in"),
        Entry(name: "unit_convert", category: "utility", posture: .none, description: "Convert between units via `units`"),

        // MARK: YouTube
        Entry(name: "youtube_search",   category: "youtube", posture: .none,  description: "Search YouTube via yt-dlp (top 10)"),
        Entry(name: "youtube_download", category: "youtube", posture: .modal, description: "Download confirmed audio/video via yt-dlp"),

        // MARK: Clipboard
        Entry(name: "clipboard_read",  category: "clipboard", posture: .none,  description: "Read current clipboard as text"),
        Entry(name: "clipboard_write", category: "clipboard", posture: .modal, description: "Replace clipboard contents"),

        // MARK: Automation
        Entry(name: "applescript", category: "automation", posture: .modal, description: "Run an AppleScript (Mail, Calendar, Music, …)"),

        // MARK: Memory
        Entry(name: "remember",   category: "memory", posture: .none,  description: "Store a fact to Bob's long-term memory"),
        Entry(name: "list_facts", category: "memory", posture: .none,  description: "List remembered facts"),
        Entry(name: "forget",     category: "memory", posture: .modal, description: "Delete a remembered fact by id"),

        // MARK: Meta
        Entry(name: "tool_help",        category: "meta", posture: .none, description: "Look up help for an external CLI tool"),
        Entry(name: "read_tool_output", category: "meta", posture: .none, description: "Fetch a previously stored large tool output"),

        // MARK: Context (Phase 3 — Mac Context Lens)
        Entry(name: "active_window",   category: "context", posture: .none, description: "Return frontmost app name and window title"),
        Entry(name: "selected_items",  category: "context", posture: .none, description: "Return Finder-selected file paths (max 50)"),
        Entry(name: "screen_ocr",      category: "context", posture: .none, description: "Capture screen and extract text via Vision OCR"),
        Entry(name: "current_context", category: "context", posture: .none, description: "Composite: active app + Finder selection + clipboard metadata"),

        // MARK: Code (Phase 6 — Code Companion)
        Entry(name: "project_context",  category: "code", posture: .none,  description: "Walk to .git root, identify language, return manifest head + recent log + diff --stat"),
        Entry(name: "enable_dev_mode",  category: "code", posture: .modal, description: "Enable dev mode: auto-approve write_file inside the repo root (shell stays gated)"),
        Entry(name: "disable_dev_mode", category: "code", posture: .none,  description: "Disable dev mode and restore modal approval for all file writes"),

        // MARK: Skills (Phase 7a — Skill Capsules)
        Entry(name: "create_skill",  category: "skills", posture: .modal, description: "Save a named recipe that replays a sequence of first-party tools (approval required)"),
        Entry(name: "list_skills",   category: "skills", posture: .none,  description: "List all saved skills with name, step count, and description"),
        Entry(name: "inspect_skill", category: "skills", posture: .none,  description: "Show the full step-by-step recipe for a saved skill"),
        Entry(name: "run_skill",     category: "skills", posture: .none,  description: "Run a saved skill; each step is gated by its own tool approval policy"),
        Entry(name: "delete_skill",  category: "skills", posture: .modal, description: "Permanently delete a saved skill (approval required)"),
    ]

    /// Rendering order for categories in the Preferences UI.
    static let categoryOrder: [String] = [
        "files", "shell", "git", "web", "mail", "phone", "presentation", "media", "utility",
        "timeline", "youtube", "clipboard", "automation", "memory", "meta", "context", "code", "skills"
    ]

    static func entries(for category: String) -> [Entry] {
        entries.filter { $0.category == category }
    }
}
