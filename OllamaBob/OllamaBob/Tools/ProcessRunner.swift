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
///
/// Long-running shell hardening: in addition to the legacy single `timeout`,
/// callers can supply `idleTimeout` (resets on each output byte) and
/// `hardCap` (absolute wall-clock ceiling). All kill paths use a two-stage
/// SIGTERM → grace → SIGKILL ladder so commands that ignore SIGTERM
/// (`trap '' TERM`, certain brew cleanup paths) still die.
enum ProcessRunner {

    // MARK: - Public types

    enum StreamKind: Sendable {
        case stdout
        case stderr
    }

    enum TerminationCause: String, Sendable {
        /// Legacy single-shot wall-clock `timeout` parameter expired.
        case timedOut
        /// `idleTimeout` expired with no output activity.
        case idleTimeout
        /// `hardCap` absolute ceiling expired.
        case hardCap
        /// External cancel via `CancelHandle`.
        case cancelled
        /// Output buffer cap (`stdout/stderrMaxBytes`) was exceeded.
        case outputLimit
    }

    typealias OutputChunkHandler = @Sendable (StreamKind, String) -> Void

    /// Caller-owned handle for externally cancelling a running process.
    /// Pass an instance into `run`, hold a reference, and call `.cancel()`
    /// to terminate the underlying process. Safe to call before, during,
    /// or after the run completes.
    final class CancelHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelAction: (() -> Void)?
        private var didCancel = false

        public init() {}

        public var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return didCancel
        }

        fileprivate func attach(_ action: @escaping () -> Void) {
            lock.lock()
            let alreadyCancelled = didCancel
            if !alreadyCancelled {
                cancelAction = action
            }
            lock.unlock()
            if alreadyCancelled {
                action()
            }
        }

        fileprivate func detach() {
            lock.lock()
            cancelAction = nil
            lock.unlock()
        }

        public func cancel() {
            lock.lock()
            guard !didCancel else { lock.unlock(); return }
            didCancel = true
            let action = cancelAction
            cancelAction = nil
            lock.unlock()
            action?()
        }
    }

    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        /// True for any time-based kill (legacy `timeout`, `idleTimeout`, or
        /// `hardCap`). Preserved for backward compatibility — new callers
        /// should inspect `terminationCause` for the precise reason.
        let timedOut: Bool
        let outputLimitExceeded: Bool
        let terminationCause: TerminationCause?

        var cancelled: Bool { terminationCause == .cancelled }
        var idleTimedOut: Bool { terminationCause == .idleTimeout }
        var hardCapped: Bool { terminationCause == .hardCap }
    }

    // MARK: - Run API

    /// Run an executable with optional timeout and working directory.
    /// - Parameters:
    ///   - executable: Absolute path to the binary.
    ///   - arguments: Command-line arguments.
    ///   - currentDirectoryURL: Working directory for the child process.
    ///   - timeout: Legacy single wall-clock timeout. Mutually exclusive with
    ///     `idleTimeout` / `hardCap` — if any of those are non-nil, `timeout`
    ///     is ignored. `nil` means no legacy timeout.
    ///   - idleTimeout: Kill if no stdout/stderr activity for this many
    ///     seconds. Resets on every output byte. `nil` disables.
    ///   - hardCap: Absolute wall-clock ceiling regardless of activity.
    ///     `nil` disables.
    ///   - killGrace: Seconds between SIGTERM and SIGKILL escalation.
    ///   - stdoutMaxBytes: Maximum stdout bytes to buffer before terminating.
    ///   - stderrMaxBytes: Maximum stderr bytes to buffer before terminating.
    ///   - onOutputChunk: Optional callback fired (on a background queue) for
    ///     every chunk read from stdout/stderr, decoded as UTF-8. Use this
    ///     for live streaming to UI. May be invoked rapidly — throttle on the
    ///     consumer side if you bind to SwiftUI.
    ///   - cancelHandle: Optional caller-owned handle. Calling `.cancel()`
    ///     on it triggers the same SIGTERM→SIGKILL ladder as the timeouts.
    /// - Returns: Exit code, stdout, stderr, time-based kill flag, output
    ///   limit flag, and the precise termination cause (if any).
    static func run(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil,
        idleTimeout: TimeInterval? = nil,
        hardCap: TimeInterval? = nil,
        killGrace: TimeInterval = AppConfig.processKillGraceSeconds,
        stdoutMaxBytes: Int = AppConfig.processOutputMaxBytes,
        stderrMaxBytes: Int = AppConfig.processOutputMaxBytes,
        onOutputChunk: OutputChunkHandler? = nil,
        cancelHandle: CancelHandle? = nil
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            runSync(
                executable: executable,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                timeout: timeout,
                idleTimeout: idleTimeout,
                hardCap: hardCap,
                killGrace: killGrace,
                stdoutMaxBytes: stdoutMaxBytes,
                stderrMaxBytes: stderrMaxBytes,
                onOutputChunk: onOutputChunk,
                cancelHandle: cancelHandle
            )
        }.value
    }

    // MARK: - Implementation

    private static func runSync(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeout: TimeInterval?,
        idleTimeout: TimeInterval?,
        hardCap: TimeInterval?,
        killGrace: TimeInterval,
        stdoutMaxBytes: Int,
        stderrMaxBytes: Int,
        onOutputChunk: OutputChunkHandler?,
        cancelHandle: CancelHandle?
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
        let useNewTimers = (idleTimeout != nil) || (hardCap != nil)

        // Legacy single-shot timeout (only when caller did not opt into the
        // new dual-timer setup).
        let legacyTimeoutItem: DispatchWorkItem?
        if !useNewTimers, let t = timeout {
            legacyTimeoutItem = DispatchWorkItem {
                state.markCause(.timedOut)
                terminateThenKill(process, grace: killGrace)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + t, execute: legacyTimeoutItem!)
        } else {
            legacyTimeoutItem = nil
        }

        // Idle timer (rescheduled on each chunk via generation counter).
        let idleTimer: IdleTimer?
        if let i = idleTimeout {
            idleTimer = IdleTimer(interval: i) {
                state.markCause(.idleTimeout)
                terminateThenKill(process, grace: killGrace)
            }
        } else {
            idleTimer = nil
        }

        // Hard-cap timer (single shot).
        let hardCapItem: DispatchWorkItem?
        if let cap = hardCap {
            hardCapItem = DispatchWorkItem {
                state.markCause(.hardCap)
                terminateThenKill(process, grace: killGrace)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + cap, execute: hardCapItem!)
        } else {
            hardCapItem = nil
        }

        // Wire external cancel.
        if let handle = cancelHandle {
            handle.attach {
                state.markCause(.cancelled)
                terminateThenKill(process, grace: killGrace)
            }
        }

        let stdoutBox = DataBox(limit: stdoutMaxBytes)
        let stderrBox = DataBox(limit: stderrMaxBytes)
        let group = DispatchGroup()

        do {
            try process.run()
            DebugLog.log(.shell, "spawn", [
                "pid": "\(process.processIdentifier)",
                "executable": executable,
                "args": arguments.joined(separator: " "),
                "idleTimeoutSec": idleTimeout.map { "\(Int($0))" } ?? "-",
                "hardCapSec": hardCap.map { "\(Int($0))" } ?? "-",
                "legacyTimeoutSec": timeout.map { "\(Int($0))" } ?? "-"
            ])

            // Arm the idle timer once the process is actually running.
            idleTimer?.reset()

            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                drain(
                    stdoutPipe.fileHandleForReading,
                    kind: .stdout,
                    into: stdoutBox,
                    state: state,
                    process: process,
                    killGrace: killGrace,
                    idleTimer: idleTimer,
                    onChunk: onOutputChunk
                )
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                drain(
                    stderrPipe.fileHandleForReading,
                    kind: .stderr,
                    into: stderrBox,
                    state: state,
                    process: process,
                    killGrace: killGrace,
                    idleTimer: idleTimer,
                    onChunk: onOutputChunk
                )
                group.leave()
            }

            process.waitUntilExit()
            group.wait()
            legacyTimeoutItem?.cancel()
            hardCapItem?.cancel()
            idleTimer?.cancel()
            cancelHandle?.detach()
        } catch {
            legacyTimeoutItem?.cancel()
            hardCapItem?.cancel()
            idleTimer?.cancel()
            cancelHandle?.detach()
            return Result(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false,
                outputLimitExceeded: false,
                terminationCause: nil
            )
        }

        let stdout = String(data: stdoutBox.snapshot(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrBox.snapshot(), encoding: .utf8) ?? ""
        let cause = state.cause
        let outputLimitHit = (cause == .outputLimit) || stdoutBox.truncated || stderrBox.truncated
        let timeBased: Bool = {
            switch cause {
            case .timedOut, .idleTimeout, .hardCap: return true
            default: return false
            }
        }()
        // Promote a buffer-truncation that wasn't already classified into an
        // outputLimit cause.
        let resolvedCause: TerminationCause? = {
            if let c = cause { return c }
            if outputLimitHit { return .outputLimit }
            return nil
        }()
        let result = Result(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            timedOut: timeBased,
            outputLimitExceeded: outputLimitHit,
            terminationCause: resolvedCause
        )
        DebugLog.log(.shell, "exit", [
            "pid": "\(process.processIdentifier)",
            "exit": "\(result.exitCode)",
            "cause": resolvedCause.map { "\($0)" } ?? "normal",
            "stdoutLen": "\(stdout.count)",
            "stderrLen": "\(stderr.count)",
            "stderrPreview": String(stderr.prefix(300))
        ])
        return result
    }

    private static func drain(
        _ handle: FileHandle,
        kind: StreamKind,
        into box: DataBox,
        state: ProcessState,
        process: Process,
        killGrace: TimeInterval,
        idleTimer: IdleTimer?,
        onChunk: OutputChunkHandler?
    ) {
        while true {
            // `availableData` returns as soon as the kernel pipe has any bytes;
            // `readData(ofLength:)` was observed to block until the writer
            // closes despite an unbuffered producer (python -u, setvbuf=0),
            // which kills incremental streaming. Empty == EOF.
            let chunk = handle.availableData
            if chunk.isEmpty {
                break
            }
            if box.append(chunk) == false {
                state.markCause(.outputLimit)
                terminateThenKill(process, grace: killGrace)
                break
            }
            // Reset idle countdown on every byte of activity.
            idleTimer?.reset()
            if let onChunk {
                if let str = String(data: chunk, encoding: .utf8) {
                    onChunk(kind, str)
                } else {
                    // Fallback for non-UTF8 byte sequences; replace invalids
                    // so we never drop activity entirely.
                    let lossy = String(decoding: chunk, as: UTF8.self)
                    onChunk(kind, lossy)
                }
            }
        }
    }

    /// Two-stage kill ladder: SIGTERM, then SIGKILL after a grace period if
    /// the child is still alive. Idempotent — safe to call multiple times.
    private static func terminateThenKill(_ process: Process, grace: TimeInterval) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        DebugLog.log(.shell, "terminate-sigterm", ["pid": "\(pid)", "graceSec": "\(grace)"])
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
            if process.isRunning {
                DebugLog.log(.shell, "escalate-sigkill", ["pid": "\(pid)"])
                kill(pid, SIGKILL)
            }
        }
    }

    // MARK: - Internal types

    /// Idle timer with a generation counter so resets are race-free without
    /// needing to cancel a `DispatchWorkItem`. Each `reset()` bumps the
    /// generation; only the most-recent scheduled fire actually runs.
    private final class IdleTimer: @unchecked Sendable {
        private let lock = NSLock()
        private var generation: UInt64 = 0
        private var stopped = false
        private let interval: TimeInterval
        private let onFire: () -> Void

        init(interval: TimeInterval, onFire: @escaping () -> Void) {
            self.interval = interval
            self.onFire = onFire
        }

        func reset() {
            lock.lock()
            guard !stopped else { lock.unlock(); return }
            generation &+= 1
            let myGen = generation
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + interval) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let fire = (!self.stopped) && (self.generation == myGen)
                self.lock.unlock()
                if fire {
                    self.onFire()
                }
            }
        }

        func cancel() {
            lock.lock()
            stopped = true
            generation &+= 1
            lock.unlock()
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

    /// Tracks the first termination cause to win a race between
    /// idle/hardCap/cancel/outputLimit. Once set, additional `markCause`
    /// calls are ignored so the original reason is preserved.
    private final class ProcessState: @unchecked Sendable {
        private let lock = NSLock()
        private var firstCause: TerminationCause?

        var cause: TerminationCause? {
            lock.lock()
            defer { lock.unlock() }
            return firstCause
        }

        func markCause(_ c: TerminationCause) {
            lock.lock()
            if firstCause == nil {
                firstCause = c
            }
            lock.unlock()
        }
    }
}
