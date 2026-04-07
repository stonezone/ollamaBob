import Foundation

/// Mutable byte accumulator used by background pipe readers.
/// Reference type so the DispatchGroup completion handler observes the mutations.
/// `@unchecked Sendable` is safe here: the writer thread mutates exclusively before
/// `group.leave()`, and the reader only touches `data` after `group.wait()` returns,
/// which establishes a happens-before edge.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum ShellTool {
    /// Execute a shell command with timeout and output caps.
    static func execute(command: String, timeout: TimeInterval = AppConfig.toolTimeoutSeconds) async -> ToolResult {
        let start = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Run with timeout
        let result: ToolResult = await withCheckedContinuation { continuation in
            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            do {
                try process.run()

                // Drain pipes concurrently to avoid the 64 KB buffer deadlock that
                // occurs when the child writes more than the pipe can hold while
                // the parent is blocked in waitUntilExit().
                let stdoutBox = DataBox()
                let stderrBox = DataBox()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                process.waitUntilExit()
                group.wait()
                timeoutItem.cancel()

                let durationMs = Int(Date().timeIntervalSince(start) * 1000)

                // Check if terminated by timeout
                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(returning: .failure(
                        tool: "shell",
                        error: "Command timed out after \(Int(timeout))s",
                        durationMs: durationMs
                    ))
                    return
                }

                let stdout = String(data: stdoutBox.data, encoding: .utf8) ?? ""
                let stderr = String(data: stderrBox.data, encoding: .utf8) ?? ""

                let truncatedStdout = OutputLimits.truncateShellStdout(stdout)
                let truncatedStderr = OutputLimits.truncateShellStderr(stderr)

                var output = truncatedStdout
                if !truncatedStderr.isEmpty {
                    output += "\n\nSTDERR:\n\(truncatedStderr)"
                }

                if process.terminationStatus != 0 {
                    output += "\n\n[exit code: \(process.terminationStatus)]"
                }

                continuation.resume(returning: .success(
                    tool: "shell",
                    content: output.isEmpty ? "(no output)" : output,
                    durationMs: durationMs
                ))
            } catch {
                timeoutItem.cancel()
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                continuation.resume(returning: .failure(
                    tool: "shell",
                    error: error.localizedDescription,
                    durationMs: durationMs
                ))
            }
        }
        return result
    }
}
