import Foundation

/// Shared process runner with concurrent pipe draining.
///
/// macOS pipe buffers are ~64 KB. If a child process writes more than that
/// while the parent is blocked in `waitUntilExit()`, the child deadlocks.
/// This helper spawns background readers for stdout and stderr before
/// waiting, eliminating that class of bug.
enum ProcessRunner {

    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    /// Run an executable with optional timeout and working directory.
    /// - Parameters:
    ///   - executable: Absolute path to the binary.
    ///   - arguments: Command-line arguments.
    ///   - currentDirectoryURL: Working directory for the child process.
    ///   - timeout: Seconds before the process is terminated. `nil` means no timeout.
    /// - Returns: Exit code, stdout, stderr, and whether the process was killed by timeout.
    static func run(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) async -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd = currentDirectoryURL {
            process.currentDirectoryURL = cwd
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var timedOut = false
        let timeoutItem: DispatchWorkItem?
        if let t = timeout {
            timeoutItem = DispatchWorkItem {
                timedOut = true
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + t, execute: timeoutItem!)
        } else {
            timeoutItem = nil
        }

        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let group = DispatchGroup()

        do {
            try process.run()

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
            timeoutItem?.cancel()
        } catch {
            timeoutItem?.cancel()
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        let stdout = String(data: stdoutBox.data, encoding: .utf8) ?? ""
        let stderr = String(data: stderrBox.data, encoding: .utf8) ?? ""
        return Result(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut
        )
    }

    private final class DataBox {
        var data = Data()
    }
}
