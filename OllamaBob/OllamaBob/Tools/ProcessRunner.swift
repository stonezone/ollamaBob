import Foundation

/// Shared process runner with concurrent pipe draining.
///
/// macOS pipe buffers are ~64 KB. If a child process writes more than that
/// while the parent is blocked in `waitUntilExit()`, the child deadlocks.
/// This helper spawns background readers for stdout and stderr before
/// waiting, eliminating that class of bug.
///
/// Phase A hardening: output is capped stream-side so unbounded child output
/// is never buffered in memory. Timeout and limit state are thread-safe.
/// Execution is dispatched on a detached task to avoid blocking the caller's
/// actor.
enum ProcessRunner {

    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
        let outputLimitExceeded: Bool
    }

    /// Run an executable with optional timeout and working directory.
    /// - Parameters:
    ///   - executable: Absolute path to the binary.
    ///   - arguments: Command-line arguments.
    ///   - currentDirectoryURL: Working directory for the child process.
    ///   - timeout: Seconds before the process is terminated. `nil` means no timeout.
    ///   - stdoutMaxBytes: Maximum stdout bytes to buffer before terminating the child.
    ///   - stderrMaxBytes: Maximum stderr bytes to buffer before terminating the child.
    /// - Returns: Exit code, stdout, stderr, and whether the process was killed by timeout
    ///   or exceeded its output limit.
    static func run(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil,
        stdoutMaxBytes: Int = AppConfig.processOutputMaxBytes,
        stderrMaxBytes: Int = AppConfig.processOutputMaxBytes
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            runSync(
                executable: executable,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                timeout: timeout,
                stdoutMaxBytes: stdoutMaxBytes,
                stderrMaxBytes: stderrMaxBytes
            )
        }.value
    }

    private static func runSync(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeout: TimeInterval?,
        stdoutMaxBytes: Int,
        stderrMaxBytes: Int
    ) -> Result {
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

        let state = ProcessState()
        let timeoutItem: DispatchWorkItem?
        if let t = timeout {
            timeoutItem = DispatchWorkItem {
                state.markTimedOut()
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + t, execute: timeoutItem!)
        } else {
            timeoutItem = nil
        }

        let stdoutBox = DataBox(limit: stdoutMaxBytes)
        let stderrBox = DataBox(limit: stderrMaxBytes)
        let group = DispatchGroup()

        do {
            try process.run()

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                drain(stdoutPipe.fileHandleForReading, into: stdoutBox, state: state, process: process)
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                drain(stderrPipe.fileHandleForReading, into: stderrBox, state: state, process: process)
                group.leave()
            }

            process.waitUntilExit()
            group.wait()
            timeoutItem?.cancel()
        } catch {
            timeoutItem?.cancel()
            return Result(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false,
                outputLimitExceeded: false
            )
        }

        let stdout = String(data: stdoutBox.snapshot(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBox.snapshot(), encoding: .utf8) ?? ""
        return Result(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            timedOut: state.timedOut,
            outputLimitExceeded: state.outputLimitExceeded || stdoutBox.truncated || stderrBox.truncated
        )
    }

    private static func drain(_ handle: FileHandle, into box: DataBox, state: ProcessState, process: Process) {
        while true {
            let chunk = handle.readData(ofLength: 4096)
            if chunk.isEmpty {
                break
            }
            if box.append(chunk) == false {
                state.markOutputLimitExceeded()
                if process.isRunning {
                    process.terminate()
                }
                break
            }
        }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var data = Data()
        private var didTruncate = false

        var truncated: Bool {
            lock.lock()
            defer { lock.unlock() }
            return didTruncate
        }

        init(limit: Int) {
            self.limit = max(0, limit)
        }

        func append(_ chunk: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard didTruncate == false else { return false }
            let remaining = limit - data.count
            if remaining <= 0 {
                didTruncate = true
                return false
            }
            if chunk.count > remaining {
                data.append(chunk.prefix(remaining))
                didTruncate = true
                return false
            }

            data.append(chunk)
            return true
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private final class ProcessState: @unchecked Sendable {
        private let lock = NSLock()
        private var didTimeOut = false
        private var didExceedOutputLimit = false

        var timedOut: Bool {
            lock.lock()
            defer { lock.unlock() }
            return didTimeOut
        }

        var outputLimitExceeded: Bool {
            lock.lock()
            defer { lock.unlock() }
            return didExceedOutputLimit
        }

        func markTimedOut() {
            lock.lock()
            didTimeOut = true
            lock.unlock()
        }

        func markOutputLimitExceeded() {
            lock.lock()
            didExceedOutputLimit = true
            lock.unlock()
        }
    }
}
