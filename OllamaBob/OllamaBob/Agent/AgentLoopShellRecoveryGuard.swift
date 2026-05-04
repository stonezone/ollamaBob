import Foundation

// MARK: - AgentLoop / Shell Recovery Guard
//
// v1.0.46. Catches the "shell-failed-and-gave-up" pattern: Bob runs a
// shell command with a wrong macOS flag (`netstat -ri` instead of
// `-nr`), gets exit 1, then surfaces the failure to the user instead
// of diagnosing the stderr and retrying with corrected syntax.
//
// Symmetric to AgentLoopContinuationGuard. Both guards mirror the
// AgentLoopBatchGuard pattern: pure static helpers; the loop wires
// them in series after the per-iteration Ollama response is checked.
//
// Distinguishes failure classes so we don't push Bob to retry
// permission errors (which won't get better):
//   - SYNTAX/USAGE failures (`usage:`, `command not found`,
//     `invalid option`, `unknown flag`, `no such file`) → guard
//     fires, model is nudged to diagnose stderr and retry once.
//   - PERMISSION/POLICY failures (`Permission denied`, `Operation
//     not permitted`, app-level `path not allowed` / `Denied:`
//     ToolResult states) → guard skips; surfacing to the user is
//     correct.
//
// Cap: AppConfig.shellRecoveryNudgeMax = 1. After one nudge, give up
// and let the user intervene rather than spin.
extension AgentLoop {

    /// True when (a) last tool was shell, (b) it failed with a
    /// retryable syntax/usage error, (c) the assistant's reply
    /// contains give-up language and emitted no tool calls, (d) cap
    /// not reached. Caller is responsible for only invoking this when
    /// there are no tool_calls in the assistant message.
    static func shouldForceShellRecovery(
        assistantContent: String,
        lastToolResult: ToolResult?,
        nudgeCount: Int
    ) -> Bool {
        guard nudgeCount < AppConfig.shellRecoveryNudgeMax else { return false }
        guard let last = lastToolResult else { return false }
        guard last.toolName == "shell" else { return false }
        guard last.success == false else { return false }

        // App-level path-policy or forbidden-command denials surface
        // as ToolResult.denied (success=false, content describes the
        // denial). Don't try to recover — those are policy choices.
        if isPolicyDenial(last) { return false }

        // Stderr-driven classification: only retry on syntax/usage
        // patterns, not permission errors.
        guard isRetryableShellFailure(last) else { return false }

        // Only fire when the model is GIVING UP — otherwise it might
        // already be trying a different command in the same message
        // or moving on.
        guard contentExpressesGiveUp(assistantContent) else { return false }

        return true
    }

    /// Synthetic system message injected when the guard fires. Echoes
    /// a slice of the actual stderr so the nudge is concrete, then
    /// directs the model to diagnose and retry.
    static func shellRecoveryNudge(for lastToolResult: ToolResult) -> String {
        let stderr = extractStderrPreview(from: lastToolResult.content).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrSlice = stderr.isEmpty
            ? lastToolResult.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)
            : stderr.prefix(300)
        return """
        The previous shell command failed but the failure looks recoverable. Stderr/output:
        "\(stderrSlice)"
        Diagnose the actual error and retry with a corrected command in the SAME turn before surfacing this to the user. Common fixes: BSD vs GNU flag differences (use `netstat -nr` not `-ri` for routing table on macOS; use `find … -size +1G` not `--size`); typos in command names; missing quotes around paths with spaces. Only ask the user if you genuinely cannot fix the command.
        """
    }

    // MARK: - Private classification

    /// Heuristic: does the stderr/output pattern look like a recoverable
    /// shell error (wrong flag, typo, command not found, etc.) vs a
    /// permission/policy error?
    private static func isRetryableShellFailure(_ result: ToolResult) -> Bool {
        let text = result.content.lowercased()
        let retryablePatterns = [
            "usage:",                  // standard BSD/GNU help-on-error line
            "command not found",       // typo'd command name
            "invalid option",          // bad short flag
            "unrecognized option",     // bad long flag
            "unknown option",
            "no such file or directory",  // path typo OR missing file (often retryable with a search)
            "illegal option",
            "syntax error",
            "missing argument"
        ]
        return retryablePatterns.contains { text.contains($0) }
    }

    /// Heuristic: is this a permission/policy denial (NOT retryable)?
    private static func isPolicyDenial(_ result: ToolResult) -> Bool {
        let text = result.content.lowercased()
        let blockingPatterns = [
            "permission denied",
            "operation not permitted",
            "path not allowed",
            "denied:",
            "forbidden:",
            "rich presentation disabled",
            "user denied this action",
            "approval required"
        ]
        return blockingPatterns.contains { text.contains($0) }
    }

    /// Heuristic: does the assistant's reply contain give-up language?
    /// We only nudge when Bob is throwing in the towel, not when he's
    /// already trying a different approach.
    private static func contentExpressesGiveUp(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let giveUpMarkers = [
            "i couldn't",
            "i could not",
            "i was unable",
            "i can't",
            "i cannot",
            "you can run",
            "you can try",
            "please run",
            "please install",
            "please provide",
            "please tell me",
            "if you can provide",
            "command failed",      // matches "the find command failed", "netstat command failed", etc.
            "looks like",
            "is not installed",
            "was not found",
            "manually",
            "in your terminal"
        ]
        return giveUpMarkers.contains { lower.contains($0) }
    }

    /// Extract the part of the ToolResult.content after "STDERR:" if
    /// present (ShellTool conventionally appends `STDERR:\n<text>`
    /// when the command produced stderr). Falls back to the full
    /// content. Used to give the nudge concrete stderr text without
    /// echoing the entire stdout.
    private static func extractStderrPreview(from content: String) -> String {
        guard let range = content.range(of: "STDERR:", options: .caseInsensitive) else {
            return content
        }
        return String(content[range.upperBound...])
    }
}
