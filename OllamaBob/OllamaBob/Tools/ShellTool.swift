import Foundation

enum ShellTool {
    /// Execute a shell command with idle + hard-cap timeouts and optional
    /// live streaming + cancellation.
    ///
    /// - Parameters:
    ///   - command: The shell command line (run via `/bin/zsh -lc` — login
    ///     shell so `.zprofile` runs and Homebrew's `/opt/homebrew/bin` is
    ///     on PATH even when OllamaBob is launched from Finder/Dock by
    ///     launchd, which hands the app a minimal env that excludes brew).
    ///     `.zshrc` does NOT run (that requires interactive `-i`), so heavy
    ///     plugin init (oh-my-zsh, etc.) does not pay per-call latency.
    ///   - idleTimeout: Kill if no stdout/stderr activity for this many
    ///     seconds. Defaults to `AppConfig.shellIdleTimeoutSeconds` (60).
    ///     Clamped to `[shellIdleTimeoutMin, shellIdleTimeoutMax]`.
    ///   - hardCap: Absolute wall-clock ceiling. Defaults to
    ///     `AppConfig.shellMaxTotalSeconds` (1800). Clamped to
    ///     `[shellMaxTotalMin, shellMaxTotalMax]`.
    ///   - executable: Shell binary. Defaults to `/bin/zsh`.
    ///   - cancelHandle: Optional caller-owned handle for external cancel.
    ///     Triggering it from the UI fires SIGTERM→SIGKILL on the child.
    ///   - onOutputChunk: Optional callback for live streaming. Fires on a
    ///     background queue for every chunk; consumers that bind to SwiftUI
    ///     should hop to `@MainActor` and throttle.
    static func execute(
        command: String,
        idleTimeout: TimeInterval = AppConfig.shellIdleTimeoutSeconds,
        hardCap: TimeInterval = AppConfig.shellMaxTotalSeconds,
        executable: String = "/bin/zsh",
        cancelHandle: ProcessRunner.CancelHandle? = nil,
        onOutputChunk: ProcessRunner.OutputChunkHandler? = nil
    ) async -> ToolResult {
        let start = Date()

        let clampedIdle = max(
            AppConfig.shellIdleTimeoutMin,
            min(idleTimeout, AppConfig.shellIdleTimeoutMax)
        )
        let clampedCap = max(
            AppConfig.shellMaxTotalMin,
            min(hardCap, AppConfig.shellMaxTotalMax)
        )

        let result = await ProcessRunner.run(
            executable: executable,
            // `-lc` — login shell so `.zprofile` runs (puts Homebrew on
            // PATH). Required when the app is launched via `open` from
            // Finder/Dock; launchd's env does not include `/opt/homebrew/bin`.
            // See ToolRuntime.runWhich for the same trick used by the probe.
            arguments: ["-lc", command],
            currentDirectoryURL: URL(fileURLWithPath: NSHomeDirectory()),
            idleTimeout: clampedIdle,
            hardCap: clampedCap,
            stdoutMaxBytes: AppConfig.processOutputMaxBytes,
            stderrMaxBytes: AppConfig.processOutputMaxBytes,
            onOutputChunk: onOutputChunk,
            cancelHandle: cancelHandle
        )

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        switch result.terminationCause {
        case .cancelled:
            return .failure(
                tool: "shell",
                error: "Cancelled by user.",
                durationMs: durationMs
            )
        case .idleTimeout:
            return .failure(
                tool: "shell",
                error: "Command idle for \(Int(clampedIdle))s — terminated.",
                durationMs: durationMs
            )
        case .hardCap:
            return .failure(
                tool: "shell",
                error: "Command exceeded hard cap of \(Int(clampedCap))s — terminated.",
                durationMs: durationMs
            )
        case .timedOut:
            // Should not occur on this code path (we don't pass `timeout`),
            // but kept for completeness.
            return .failure(
                tool: "shell",
                error: "Command timed out.",
                durationMs: durationMs
            )
        case .outputLimit, .none:
            break
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

        if result.outputLimitExceeded {
            output += "\n\n[output limit exceeded]"
            return .failure(
                tool: "shell",
                error: output.isEmpty ? "Command output exceeded limit." : output,
                durationMs: durationMs
            )
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
