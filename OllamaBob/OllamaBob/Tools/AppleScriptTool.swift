import Foundation
import AppKit

/// Run an AppleScript via NSAppleScript. Modal-gated in ApprovalPolicy —
/// AppleScript can drive any scriptable Mac app (Messages, Mail, Finder,
/// Calendar, Safari tabs, Music, etc.), so every run needs explicit
/// user approval.
///
/// Forbidden patterns block the script before it ever runs. The list is
/// deliberately conservative: any path that shells out, synthesizes
/// keystrokes/clicks, or asks for admin privileges is rejected so Bob
/// cannot use AppleScript to escape the normal approval rails.
enum AppleScriptTool {

    /// Max script body length Bob can submit in a single call. Keeps
    /// runaway code generation from DOSing the OSA runtime.
    private static let maxScriptChars = 4_000

    /// Max characters of osascript output we return to the model. Long
    /// outputs still get captured, just truncated on the wire.
    private static let maxOutputChars = 10_000

    /// Patterns that are always rejected, case-insensitive. Each matches
    /// anywhere in the script body.
    private static let forbiddenPatterns: [String] = [
        "do shell script",               // arbitrary shell escape
        "with administrator privileges", // sudo-equivalent
        "key code",                      // synthetic keystroke
        "keystroke",                     // synthetic keystroke
        "key down",                      // synthetic keystroke
        "key up",                        // synthetic keystroke
        "click at",                      // synthetic click
        "mount volume",                  // filesystem mount
        "system attribute \"sudo\"",     // sudo probing
        "set volume",                    // irritating; not obviously useful
    ]

    static func execute(script: String) async -> ToolResult {
        let start = Date()
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .failure(tool: "applescript", error: "Script is empty.", durationMs: 0)
        }
        if trimmed.count > maxScriptChars {
            return .failure(
                tool: "applescript",
                error: "Script too long: \(trimmed.count) chars (max \(maxScriptChars)).",
                durationMs: 0
            )
        }

        let lower = trimmed.lowercased()
        for pattern in forbiddenPatterns {
            if lower.contains(pattern) {
                return .failure(
                    tool: "applescript",
                    error: "Forbidden AppleScript construct: '\(pattern)'. Use a dedicated tool instead.",
                    durationMs: 0
                )
            }
        }

        return await runOnMain(script: trimmed, start: start)
    }

    @MainActor
    private static func runOnMain(script: String, start: Date) async -> ToolResult {
        guard let apple = NSAppleScript(source: script) else {
            return .failure(tool: "applescript", error: "Could not parse script.", durationMs: 0)
        }
        var errorInfo: NSDictionary?
        let descriptor = apple.executeAndReturnError(&errorInfo)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if let err = errorInfo as? [String: Any] {
            let message = (err["NSAppleScriptErrorMessage"] as? String)
                ?? (err["NSAppleScriptErrorBriefMessage"] as? String)
                ?? "AppleScript error."
            let number = (err["NSAppleScriptErrorNumber"] as? Int).map { " (\($0))" } ?? ""
            return .failure(tool: "applescript", error: "\(message)\(number)", durationMs: durationMs)
        }

        let output = descriptor.stringValue ?? ""
        if output.isEmpty {
            return .success(tool: "applescript", content: "(no output)", durationMs: durationMs)
        }
        if output.count > maxOutputChars {
            let truncated = String(output.prefix(maxOutputChars))
            let note = "\n\n... [TRUNCATED: \(output.count) total chars, showing first \(maxOutputChars)] ..."
            return .success(tool: "applescript", content: truncated + note, durationMs: durationMs)
        }
        return .success(tool: "applescript", content: output, durationMs: durationMs)
    }
}
