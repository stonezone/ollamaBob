import XCTest
@testable import OllamaBob

/// Coverage for the shell-recovery guard (v1.0.46).
///
/// Failure mode: Bob runs `netstat -ri` (wrong macOS flag), gets exit 1,
/// then says "I couldn't find the gateway, can you provide it?" and ends
/// the turn. The current operating-rules nudge Bob to *surface* failures
/// to the user — but for SYNTAX/USAGE failures (wrong flag, command not
/// found), the right move is for Bob to read stderr, diagnose, and retry
/// once with corrected syntax before bothering the user.
///
/// The guard fires when:
///   1. The previous shell tool exited non-zero (recoverable failure).
///   2. The model's reply contains "give-up" language ("I couldn't",
///      "you can run", "please provide", "the command failed", etc.)
///      AND emitted no tool_calls (so it's not already retrying).
///   3. The stderr suggests a SYNTAX/USAGE error (not permission/policy):
///      `usage:` line, "command not found", "invalid option", "no such
///      file" — these are all retryable. Permission failures
///      ("operation not permitted", "Denied:", "path not allowed") are
///      NOT retryable and the guard skips them.
///   4. Cap not reached.
@MainActor
final class ShellRecoveryGuardTests: XCTestCase {

    // MARK: - Positive: should fire

    func testFiresOnNetstatBadFlag() {
        // The real production failure pattern.
        let lastShell = ToolResult.failure(
            tool: "shell",
            error: "[exit code: 1]\n\nSTDERR:\nusage: netstat [-AaLlnW] [-f address_family]...",
            durationMs: 100
        )
        XCTAssertTrue(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "I couldn't find the default gateway. You can run `netstat -nr` in your terminal and provide the result.",
                lastToolResult: lastShell,
                nudgeCount: 0
            )
        )
    }

    func testFiresOnCommandNotFound() {
        let lastShell = ToolResult.failure(
            tool: "shell",
            error: "[exit code: 127]\n\nSTDERR:\nzsh:1: command not found: brewq",
            durationMs: 50
        )
        XCTAssertTrue(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "Looks like brewq is not installed sir. Please install it manually.",
                lastToolResult: lastShell,
                nudgeCount: 0
            )
        )
    }

    func testFiresOnInvalidOption() {
        let lastShell = ToolResult.failure(
            tool: "shell",
            error: "[exit code: 2]\n\nSTDERR:\nfind: invalid option -- 'Q'",
            durationMs: 30
        )
        XCTAssertTrue(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "The find command failed. The flag seems wrong. Sorry sir.",
                lastToolResult: lastShell,
                nudgeCount: 0
            )
        )
    }

    // MARK: - Negative: must NOT fire (different failure class or no give-up)

    func testDoesNotFireOnPermissionDenied() {
        // Permission errors are NOT retryable. Surface to user.
        let lastShell = ToolResult.failure(
            tool: "shell",
            error: "[exit code: 1]\n\nSTDERR:\nrm: /etc/hosts: Permission denied",
            durationMs: 10
        )
        XCTAssertFalse(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "I could not delete /etc/hosts because permission was denied.",
                lastToolResult: lastShell,
                nudgeCount: 0
            ),
            "permission errors must surface to user, not retry"
        )
    }

    func testDoesNotFireOnPathPolicyDenied() {
        // App-level path policy denial — not a stderr error, but a
        // ToolResult.denied. The guard must not interpret this as a
        // retryable failure.
        let lastShell = ToolResult.denied(tool: "shell", reason: "path not allowed")
        XCTAssertFalse(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "I couldn't run that — the path is not allowed.",
                lastToolResult: lastShell,
                nudgeCount: 0
            )
        )
    }

    func testDoesNotFireWhenLastToolWasNotShell() {
        // Other tools have their own failure semantics; this guard is
        // shell-specific.
        let lastWeb = ToolResult.failure(tool: "web_search", error: "rate limited", durationMs: 100)
        XCTAssertFalse(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "I couldn't search. Please try again later.",
                lastToolResult: lastWeb,
                nudgeCount: 0
            )
        )
    }

    func testDoesNotFireWhenLastToolSucceeded() {
        let lastShell = ToolResult.success(tool: "shell", content: "ok", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "I couldn't make sense of the result.",
                lastToolResult: lastShell,
                nudgeCount: 0
            )
        )
    }

    func testDoesNotFireWhenAssistantIsNotGivingUp() {
        // If the model is already calling another tool / has a real
        // answer, don't push.
        let lastShell = ToolResult.failure(
            tool: "shell",
            error: "[exit code: 1]\n\nSTDERR:\nusage: netstat ...",
            durationMs: 10
        )
        XCTAssertFalse(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "Got it. The routing table from `route -n get default` is...",
                lastToolResult: lastShell,
                nudgeCount: 0
            ),
            "must not fire when assistant is moving on"
        )
    }

    func testDoesNotFireAfterCap() {
        let lastShell = ToolResult.failure(
            tool: "shell",
            error: "[exit code: 1]\n\nSTDERR:\nusage: netstat ...",
            durationMs: 10
        )
        XCTAssertFalse(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "I couldn't find that.",
                lastToolResult: lastShell,
                nudgeCount: AppConfig.shellRecoveryNudgeMax
            )
        )
    }

    func testDoesNotFireWhenLastToolResultIsNil() {
        XCTAssertFalse(
            AgentLoop.shouldForceShellRecovery(
                assistantContent: "I couldn't do that.",
                lastToolResult: nil,
                nudgeCount: 0
            )
        )
    }

    // MARK: - Nudge text

    func testNudgeMentionsStderrAndDirectsRetry() {
        let lastShell = ToolResult.failure(
            tool: "shell",
            error: "[exit code: 1]\n\nSTDERR:\nusage: netstat [-AaLlnW] [-f address_family]...",
            durationMs: 10
        )
        let nudge = AgentLoop.shellRecoveryNudge(for: lastShell)
        XCTAssertTrue(
            nudge.lowercased().contains("usage") || nudge.contains("netstat"),
            "nudge should echo a slice of the failed stderr: \(nudge)"
        )
        XCTAssertTrue(
            nudge.lowercased().contains("retry") || nudge.lowercased().contains("corrected") || nudge.lowercased().contains("diagnose"),
            "nudge should explicitly direct Bob to diagnose+retry: \(nudge)"
        )
    }
}
