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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoURL.path] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: toolName, error: error.localizedDescription, durationMs: durationMs)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        let output = OutputLimits.truncateShellStdout(stdout.isEmpty ? "(no output)" : stdout)
        let trimmedError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus == 0 {
            if trimmedError.isEmpty {
                return .success(tool: toolName, content: output, durationMs: durationMs)
            }

            let combined = "\(output)\n\nSTDERR:\n\(OutputLimits.truncateShellStderr(trimmedError))"
            return .success(tool: toolName, content: combined, durationMs: durationMs)
        }

        let errorText = trimmedError.isEmpty ? "git command failed with exit code \(process.terminationStatus)." : trimmedError
        return .failure(tool: toolName, error: errorText, durationMs: durationMs)
    }
}
