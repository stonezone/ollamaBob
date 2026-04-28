import Foundation

/// Manages tool definitions and validation.
@MainActor
struct ToolRegistry {
    private let tools: [String: OllamaToolDef]
    private let requiredArgs: [String: Set<String>]

    init(braveKeyAvailable: Bool) {
        var defs: [String: OllamaToolDef] = [:]
        var reqs: [String: Set<String>] = [:]

        // shell
        defs["shell"] = .tool(
            name: "shell",
            description: "Run a shell command on macOS. Returns stdout and stderr.",
            properties: ["command": ("string", "The shell command to execute")],
            required: ["command"]
        )
        reqs["shell"] = ["command"]

        // read_file
        defs["read_file"] = .tool(
            name: "read_file",
            description: "Read the contents of a file into chat. Do not use this to open a file in Preview, the browser, or another app.",
            properties: ["path": ("string", "Absolute path to the file to read")],
            required: ["path"]
        )
        reqs["read_file"] = ["path"]

        // create_directory
        defs["create_directory"] = .tool(
            name: "create_directory",
            description: "Create a local directory path. Intermediate directories are created if needed, and existing directories are left unchanged.",
            properties: ["path": ("string", "Directory path to create")],
            required: ["path"]
        )
        reqs["create_directory"] = ["path"]

        // list_directory
        defs["list_directory"] = .tool(
            name: "list_directory",
            description: "List the contents of a local directory. Optional depth is capped at 3.",
            properties: [
                "path": ("string", "Directory path to inspect"),
                "depth": ("integer", "Optional recursion depth from 1 to 3")
            ],
            required: ["path"]
        )
        reqs["list_directory"] = ["path"]

        // write_file
        defs["write_file"] = .tool(
            name: "write_file",
            description: "Write UTF-8 text to a local file, overwriting the file if it already exists.",
            properties: [
                "path": ("string", "File path to write"),
                "content": ("string", "UTF-8 text content to write")
            ],
            required: ["path", "content"]
        )
        reqs["write_file"] = ["path", "content"]

        // move_file
        defs["move_file"] = .tool(
            name: "move_file",
            description: "Move or rename a local file or directory.",
            properties: [
                "source": ("string", "Source path to move"),
                "destination": ("string", "Destination path")
            ],
            required: ["source", "destination"]
        )
        reqs["move_file"] = ["source", "destination"]

        // git_status
        defs["git_status"] = .tool(
            name: "git_status",
            description: "Show `git status --short --branch` for a local repository.",
            properties: [
                "repo_path": ("string", "Path to the local git repository")
            ],
            required: ["repo_path"]
        )
        reqs["git_status"] = ["repo_path"]

        // git_diff
        defs["git_diff"] = .tool(
            name: "git_diff",
            description: "Show the current working-tree diff for a local repository. Optionally limit to staged changes or one relative path.",
            properties: [
                "repo_path": ("string", "Path to the local git repository"),
                "relative_path": ("string", "Optional relative path inside the repo"),
                "staged": ("boolean", "Optional: true to show staged diff")
            ],
            required: ["repo_path"]
        )
        reqs["git_diff"] = ["repo_path"]

        // search_files
        defs["search_files"] = .tool(
            name: "search_files",
            description: "Find files matching a name pattern. Returns up to 20 results.",
            properties: [
                "pattern": ("string", "File name pattern to search for"),
                "path": ("string", "Directory to search in. Defaults to home directory.")
            ],
            required: ["pattern"]
        )
        reqs["search_files"] = ["pattern"]

        // phone_call / phone_hangup / phone_status
        if PhoneTool.isConfigured {
            defs["phone_call"] = .tool(
                name: "phone_call",
                description: "Place a real phone call through the Jarvis phone service daemon. Requires destination and purpose. If persona is omitted or unsupported, Bob calls as 'bob'. `to` may be a contact name, `me`, or an explicit phone number. The Jarvis phone service must be enabled and both its API key and operator secret must be configured.",
                properties: [
                    "persona": ("string", "Optional caller label. Supported values: bob, jarvis, buddy, zack, glennel, glennel_naggy. Defaults to bob."),
                    "to": ("string", "Address-book name, `me`, or an explicit phone number/E.164 destination."),
                    "purpose": ("string", "Short reason for the call."),
                    "context": ("string", "Optional concise background from the current OllamaBob session for the phone persona to use naturally. Do not include secrets."),
                    "max_minutes": ("integer", "Optional call length cap in minutes.")
                ],
                required: ["to", "purpose"]
            )
            reqs["phone_call"] = ["to", "purpose"]

            defs["phone_hangup"] = .tool(
                name: "phone_hangup",
                description: "End an active Jarvis phone call by call id.",
                properties: [
                    "call_id": ("string", "The callSid returned by phone_call.")
                ],
                required: ["call_id"]
            )
            reqs["phone_hangup"] = ["call_id"]

            defs["phone_status"] = .tool(
                name: "phone_status",
                description: "Fetch the current status for a Jarvis phone call by call id.",
                properties: [
                    "call_id": ("string", "The callSid returned by phone_call.")
                ],
                required: ["call_id"]
            )
            reqs["phone_status"] = ["call_id"]
        }

        // web_search (only if Brave key available)
        if braveKeyAvailable {
            defs["web_search"] = .tool(
                name: "web_search",
                description: "Search the web. Returns top 5 results with titles, URLs, and snippets. For music album workflows, use this for album metadata and official track lists, not YouTube candidate picking when youtube_search is available.",
                properties: ["query": ("string", "Search query")],
                required: ["query"]
            )
            reqs["web_search"] = ["query"]
        }

        defs["mail_check"] = .tool(
            name: "mail_check",
            description: "Check Apple Mail inbox summaries through a first-class read-only tool. Use for unread-mail checks and simple sender/subject searches before falling back to generic AppleScript. Returns date, read state, sender, and subject only; no message bodies. Requires approval.",
            properties: [
                "query": ("string", "Optional sender or subject text to search for."),
                "unread_only": ("boolean", "Optional; true to return only unread messages. Defaults to true."),
                "limit": ("integer", "Optional result limit from 1 to 20. Defaults to 10.")
            ],
            required: []
        )
        reqs["mail_check"] = []

        defs["mail_triage"] = .tool(
            name: "mail_triage",
            description: "Read short Apple Mail message previews for explicit triage requests such as 'read my unread mail and tell me what needs attention'. Returns date, read state, sender, subject, and a truncated preview only. Does not send, delete, archive, or mark messages read. Requires approval.",
            properties: [
                "query": ("string", "Optional sender or subject text to search for."),
                "unread_only": ("boolean", "Optional; true to return only unread messages. Defaults to true."),
                "limit": ("integer", "Optional result limit from 1 to 10. Defaults to 10."),
                "preview_chars": ("integer", "Optional preview length from 80 to 500 characters per message. Defaults to 400.")
            ],
            required: []
        )
        reqs["mail_triage"] = []

        defs["present"] = .tool(
            name: "present",
            description: "Open content for the user. Use this when they say open, launch, or show something in Bob's window, the browser, Preview, or another default app. `kind=html` opens Bob's companion window and should contain real clickable anchors when source URLs are available. `kind=url` opens the browser, `kind=file` opens a local file in its default app.",
            properties: [
                "kind": ("string", "One of: html, url, file."),
                "content": ("string", "HTML source, URL, or absolute file path depending on kind."),
                "title": ("string", "Optional label for the rich view or logs.")
            ],
            required: ["kind", "content"]
        )
        reqs["present"] = ["kind", "content"]

        // read_tool_output — meta-tool for fetching spillover outputs.
        // Registered unconditionally; no approval needed (it only reads
        // files Bob himself wrote during this conversation).
        defs["read_tool_output"] = .tool(
            name: "read_tool_output",
            description: "Read back a previously-stored large tool output by its integer id. Use this when an earlier tool result was replaced with a pointer like '[output too large to inline — stored with id=7]'. Optionally pass a range (e.g. '0-2000' or '500-') to read only a slice.",
            properties: [
                "id":    ("integer", "The integer id returned in the inline pointer."),
                "range": ("string",  "Optional character range like '0-2000' or '500-'. Omit to read the whole stored output.")
            ],
            required: ["id"]
        )
        reqs["read_tool_output"] = ["id"]

        // tool_help — meta-tool Bob calls when he's uncertain which
        // external CLI tool to use for a task. Reads straight from the
        // in-memory ToolCatalog via ToolRuntime, no LLM, no approval.
        // `tool_help("list")` returns all live tools grouped by category;
        // `tool_help("<name>")` returns the full catalog entry for that
        // tool (description, whenToUse, example, commonFlags).
        defs["tool_help"] = .tool(
            name: "tool_help",
            description: "Look up help for an external CLI tool. Pass name='list' to see every tool available in this session grouped by category, or name='<tool>' (e.g. 'yt-dlp', 'ffmpeg', 'jq') for the full description, whenToUse guidance, example command, and common flags. Use this BEFORE calling shell with an unfamiliar tool.",
            properties: [
                "name": ("string", "Either 'list' or an exact tool name like 'jq', 'rg', 'yt-dlp'.")
            ],
            required: ["name"]
        )
        reqs["tool_help"] = ["name"]

        // remember — save a fact to Bob's sticky memory.
        defs["remember"] = .tool(
            name: "remember",
            description: "Store a fact the user wants you to remember across sessions. Categories: 'identity' (who the user is), 'preference' (how they like things), 'project' (current work context), 'reference' (useful links/paths), 'other'.",
            properties: [
                "category": ("string", "One of: identity, preference, project, reference, other"),
                "content":  ("string", "The fact to remember, max 400 characters")
            ],
            required: ["category", "content"]
        )
        reqs["remember"] = ["category", "content"]

        // forget — delete a remembered fact by id.
        defs["forget"] = .tool(
            name: "forget",
            description: "Delete a fact from Bob's memory by its id. Get the id from list_facts first.",
            properties: [
                "id": ("string", "The fact id to delete")
            ],
            required: ["id"]
        )
        reqs["forget"] = ["id"]

        // clipboard_read — pull the current pasteboard contents.
        defs["clipboard_read"] = .tool(
            name: "clipboard_read",
            description: "Read the current macOS clipboard (pasteboard) as text. Use when the user says things like 'summarize what I just copied' or 'what's on my clipboard'.",
            properties: [:],
            required: []
        )
        reqs["clipboard_read"] = []

        // clipboard_write — put text onto the pasteboard (modal-gated).
        defs["clipboard_write"] = .tool(
            name: "clipboard_write",
            description: "Replace the macOS clipboard contents with the given text. Overwrites whatever was there, so requires user approval.",
            properties: [
                "content": ("string", "Text to copy to the clipboard.")
            ],
            required: ["content"]
        )
        reqs["clipboard_write"] = ["content"]

        // applescript — run an AppleScript through NSAppleScript (modal).
        defs["applescript"] = .tool(
            name: "applescript",
            description: "Run an AppleScript to drive scriptable macOS apps (Messages, Mail, Calendar, Reminders, Notes, Finder, Safari tabs, Music, etc.). No shell escape, no keystrokes, no admin privileges. Each call requires user approval.",
            properties: [
                "script": ("string", "The AppleScript source to execute.")
            ],
            required: ["script"]
        )
        reqs["applescript"] = ["script"]

        // list_facts — list all remembered facts, optionally filtered.
        defs["list_facts"] = .tool(
            name: "list_facts",
            description: "List all facts Bob remembers about the user. Optionally filter by category (identity, preference, project, reference, other). Returns id + category + content for each.",
            properties: [
                "category": ("string", "Optional: filter to a specific category")
            ],
            required: []
        )
        reqs["list_facts"] = []

        // ocr — extract text from image path or clipboard image.
        defs["ocr"] = .tool(
            name: "ocr",
            description: "Extract text from an image using Apple's Vision framework. If `path` is provided, OCR that file. If omitted, OCR the current clipboard image (works with screenshots). Returns the recognized text.",
            properties: [
                "path": ("string", "Optional absolute path to a local image file. If omitted, reads clipboard image.")
            ],
            required: []
        )
        reqs["ocr"] = []

        defs["speak"] = .tool(
            name: "speak",
            description: "Speak the given text aloud using macOS built-in text-to-speech. Optional `voice` parameter picks a named macOS voice (e.g. 'Samantha'). Returns immediately once playback starts.",
            properties: [
                "text": ("string", "Text to speak aloud."),
                "voice": ("string", "Optional macOS voice name.")
            ],
            required: ["text"]
        )
        reqs["speak"] = ["text"]

        defs["weather"] = .tool(
            name: "weather",
            description: "Get the current weather for a location. Pass a city ('Honolulu'), airport code ('HNL'), postal code, or 'lat,lon'. Returns a one-line summary.",
            properties: [
                "location": ("string", "City, airport code, postal code, or lat,lon pair.")
            ],
            required: ["location"]
        )
        reqs["weather"] = ["location"]

        defs["unit_convert"] = .tool(
            name: "unit_convert",
            description: "Convert between units using the macOS `units` tool. Works for length, mass, temperature, volume, currency (with stale rates), and many more. Pass `from` as a value+unit ('5 miles') and `to` as a unit name ('kilometers').",
            properties: [
                "from": ("string", "Value plus source unit (for example '5 miles')."),
                "to": ("string", "Target unit (for example 'kilometers').")
            ],
            required: ["from", "to"]
        )
        reqs["unit_convert"] = ["from", "to"]

        defs["image_convert"] = .tool(
            name: "image_convert",
            description: "Convert or resize an image using the native macOS `sips` tool. `format` is jpeg/png/tiff/heic/gif/bmp. Optional `max_dimension` proportionally shrinks so neither side exceeds that many pixels. Requires approval (writes a file).",
            properties: [
                "input_path": ("string", "Absolute source image path."),
                "output_path": ("string", "Absolute destination image path."),
                "format": ("string", "Output format: jpeg/png/tiff/heic/gif/bmp."),
                "max_dimension": ("integer", "Optional max dimension in pixels.")
            ],
            required: ["input_path", "output_path", "format"]
        )
        reqs["image_convert"] = ["input_path", "output_path", "format"]

        defs["youtube_search"] = .tool(
            name: "youtube_search",
            description: "Search YouTube and return up to 10 candidate videos with title, uploader, duration, and URL. For owned-album workflows, use this to find per-track candidate URLs yourself; do not ask the user to provide YouTube URLs. Auto-select the best high-confidence match by artist/title and duration; ask the user only when candidates are genuinely ambiguous. Requires yt-dlp to be installed (brew install yt-dlp).",
            properties: [
                "query": ("string", "Free-text YouTube search query."),
                "limit": ("integer", "Optional result count from 1 to 10 (default 5).")
            ],
            required: ["query"]
        )
        reqs["youtube_search"] = ["query"]

        defs["youtube_download"] = .tool(
            name: "youtube_download",
            description: "Download audio or video from a confirmed, authorized YouTube URL using yt-dlp. `format` is mp3/m4a/mp4/bestaudio/bestvideo. Default output dirs: ~/Music/Bob/ for audio, ~/Downloads/Bob/ for video. For Bob-created album workflows, pass `output_dir` like ~/Music/Bob/<Artist>_<Album>. Requires approval.",
            properties: [
                "url": ("string", "Full YouTube URL."),
                "format": ("string", "One of: mp3, m4a, mp4, bestaudio, bestvideo."),
                "output_dir": ("string", "Optional output directory, absolute or tilde-expanded. For new albums use ~/Music/Bob/<Artist>_<Album>; existing user folders with spaces are accepted."),
                "filename": ("string", "Optional output filename stem. For albums use a clean no-space track name like '01_Track_Title'. Do not include path separators.")
            ],
            required: ["url", "format"]
        )
        reqs["youtube_download"] = ["url", "format"]

        // MARK: - Mac Context (Phase 3)
        // All four tools are read-only (approval: .none). They capture data
        // from the user's current Mac environment on explicit model request only.

        defs["active_window"] = .tool(
            name: "active_window",
            description: "Return the frontmost app bundle ID, display name, and window title (when accessible via Accessibility). Use this when the user asks what app they're looking at, what file they have open, or what the current window title is.",
            properties: [:],
            required: []
        )
        reqs["active_window"] = []

        defs["selected_items"] = .tool(
            name: "selected_items",
            description: "Return the list of paths currently selected in Finder (max 50). Use this when the user says 'these files', 'what I have selected', or wants Bob to work on whatever is highlighted in Finder. Returns empty if Finder is not frontmost or nothing is selected.",
            properties: [:],
            required: []
        )
        reqs["selected_items"] = []

        defs["screen_ocr"] = .tool(
            name: "screen_ocr",
            description: "Capture the frontmost screen and extract its text via Apple Vision OCR. Use when the user says 'look at my screen', 'read what's on my screen', 'what does this say', or wants Bob to see what's visible. Returns text prefixed with '(captured at HH:MM:SS)'. Caps at ~10KB. Requires Screen Recording permission.",
            properties: [:],
            required: []
        )
        reqs["screen_ocr"] = []

        defs["current_context"] = .tool(
            name: "current_context",
            description: "Return a composite snapshot: frontmost app + window title, Finder selection (paths), and clipboard metadata (length/preview). Does NOT capture the screen — call screen_ocr explicitly for that. Use this when the user says 'what am I working on', 'what's on my clipboard', or wants Bob to orient to the current Mac environment.",
            properties: [:],
            required: []
        )
        reqs["current_context"] = []

        self.tools = defs
        self.requiredArgs = reqs
    }

    /// All tool definitions for the Ollama request
    var toolDefs: [OllamaToolDef] {
        toolNames.compactMap { tools[$0] }
    }

    /// Check if a tool name is registered
    func has(_ name: String) -> Bool {
        tools[name] != nil && isEnabled(name)
    }

    /// Validate that required arguments are present
    func validateArgs(_ name: String, _ args: [String: Any]) -> Bool {
        guard has(name) else { return false }
        guard let required = requiredArgs[name] else { return false }
        for key in required {
            guard let val = args[key] else { return false }
            if let s = val as? String, s.isEmpty, !allowsEmptyString(toolName: name, key: key) {
                return false
            }
        }
        return true
    }

    private func allowsEmptyString(toolName: String, key: String) -> Bool {
        toolName == "write_file" && key == "content"
    }

    var toolNames: [String] {
        tools.keys.filter(isEnabled(_:)).sorted()
    }

    private func isEnabled(_ name: String) -> Bool {
        switch name {
        case "present":
            return AppSettings.shared.richPresentationEnabled
        case "phone_call", "phone_hangup", "phone_status":
            return PhoneTool.isConfigured
        default:
            return true
        }
    }
}
