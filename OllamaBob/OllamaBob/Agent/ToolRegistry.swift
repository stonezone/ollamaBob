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
            if let s = val as? String, s.isEmpty { return false }
        }
        return true
    }

    var toolNames: [String] {
        Array(tools.keys).sorted()
    }
}
