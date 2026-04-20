import Foundation

enum GitToolRunner {
    static func run(toolName: String, repoPath: String, arguments: [String]) async -> ToolResult {
        let start = Date()

        guard let repoURL = FileToolPaths.resolvedURL(for: repoPath) else {
            return .failure(tool: toolName, error: "Invalid repository path.", durationMs: 0)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repoURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(tool: toolName, error: "Repository path does not exist: \(repoPath)", durationMs: 0)
        }

        let result = await ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoURL.path] + arguments
        )
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        let output = OutputLimits.truncateShellStdout(result.stdout.isEmpty ? "(no output)" : result.stdout)
        let trimmedError = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0 {
            if trimmedError.isEmpty {
                return .success(tool: toolName, content: output, durationMs: durationMs)
            }

            let combined = "\(output)\n\nSTDERR:\n\(OutputLimits.truncateShellStderr(trimmedError))"
            return .success(tool: toolName, content: combined, durationMs: durationMs)
        }

        let errorText = trimmedError.isEmpty ? "git command failed with exit code \(result.exitCode)." : trimmedError
        return .failure(tool: toolName, error: errorText, durationMs: durationMs)
    }
}
