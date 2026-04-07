import Foundation

enum FileSearchTool {
    static func execute(pattern: String, path: String? = nil) async -> ToolResult {
        let start = Date()
        let searchPath = path.map { NSString(string: $0).expandingTildeInPath } ?? NSHomeDirectory()

        // Use mdfind for Spotlight-indexed searches, fall back to find
        let command: String
        if pattern.contains("*") || pattern.contains("?") {
            // Glob pattern — use find
            command = "find \(shellEscape(searchPath)) -name \(shellEscape(pattern)) -maxdepth 5 2>/dev/null | head -\(AppConfig.fileSearchResultsMax)"
        } else {
            // Name search — use mdfind for speed
            command = "mdfind -onlyin \(shellEscape(searchPath)) 'kMDItemFSName == \"*\(pattern)*\"' 2>/dev/null | head -\(AppConfig.fileSearchResultsMax)"
        }

        let result = await ShellTool.execute(command: command, timeout: AppConfig.toolTimeoutSeconds)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if result.content.isEmpty || result.content == "(no output)" {
            return .success(tool: "search_files", content: "No files found matching '\(pattern)' in \(searchPath)", durationMs: durationMs)
        }

        return .success(tool: "search_files", content: result.content, durationMs: durationMs)
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
