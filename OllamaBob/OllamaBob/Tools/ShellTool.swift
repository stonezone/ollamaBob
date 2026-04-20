import Foundation

enum ShellTool {
    /// Execute a shell command with timeout and output caps.
    static func execute(
        command: String,
        timeout: TimeInterval = AppConfig.toolTimeoutSeconds,
        executable: String = "/bin/zsh"
    ) async -> ToolResult {
        let start = Date()

        let result = await ProcessRunner.run(
            executable: executable,
            arguments: ["-c", command],
            currentDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()),
            timeout: timeout
        )

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if result.timedOut {
            return .failure(
                tool: "shell",
                error: "Command timed out after \(Int(timeout))s",
                durationMs: durationMs
            )
        }

        if result.exitCode == -1 {
            return .failure(
                tool: "shell",
                error: result.stderr.isEmpty ? "Failed to launch shell." : result.stderr,
                durationMs: durationMs
            )
        }

        let truncatedStdout = OutputLimits.truncateShellStdout(result.stdout)
        let truncatedStderr = OutputLimits.truncateShellStderr(result.stderr)

        var output = truncatedStdout
        if !truncatedStderr.isEmpty {
            output += "\n\nSTDERR:\n\(truncatedStderr)"
        }

        if result.exitCode != 0 {
            output += "\n\n[exit code: \(result.exitCode)]"
        }

        return .success(
            tool: "shell",
            content: output.isEmpty ? "(no output)" : output,
            durationMs: durationMs
        )
    }
}
