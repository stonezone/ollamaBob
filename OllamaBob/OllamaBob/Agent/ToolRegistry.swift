import Foundation

/// Manages tool definitions and validation.
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
            description: "Read the contents of a file at the given path.",
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

        // web_search (only if Brave key available)
        if braveKeyAvailable {
            defs["web_search"] = .tool(
                name: "web_search",
                description: "Search the web. Returns top 5 results with titles, URLs, and snippets.",
                properties: ["query": ("string", "Search query")],
                required: ["query"]
            )
            reqs["web_search"] = ["query"]
        }

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

        self.tools = defs
        self.requiredArgs = reqs
    }

    /// All tool definitions for the Ollama request
    var toolDefs: [OllamaToolDef] {
        Array(tools.values)
    }

    /// Check if a tool name is registered
    func has(_ name: String) -> Bool {
        tools[name] != nil
    }

    /// Validate that required arguments are present
    func validateArgs(_ name: String, _ args: [String: Any]) -> Bool {
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
        Array(tools.keys).sorted()
    }
}
