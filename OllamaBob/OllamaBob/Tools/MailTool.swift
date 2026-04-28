import Foundation
import AppKit

/// First-class Apple Mail helpers for common inbox checks.
/// This avoids asking the model to author ad hoc Mail AppleScript for
/// routine mail requests.
enum MailTool {
    private static let maxQueryChars = 120
    private static let maxOutputChars = 12_000
    private static let defaultLimit = 10
    private static let maxLimit = 20
    private static let defaultTriageLimit = 10
    private static let maxTriageLimit = 10
    private static let defaultPreviewChars = 400
    private static let maxPreviewChars = 500

    /// Metadata-only inbox summary: received date, read state, sender, and subject.
    static func checkInbox(query: String?, unreadOnly: Bool?, limit: Int?) async -> ToolResult {
        let start = Date()
        let normalizedQuery = normalizedQuery(query)
        let effectiveUnreadOnly = unreadOnly ?? true
        let effectiveLimit = clampedLimit(limit)
        let script = buildInboxScript(
            query: normalizedQuery,
            unreadOnly: effectiveUnreadOnly,
            limit: effectiveLimit
        )
        return await runOnMain(toolName: "mail_check", script: script, start: start)
    }

    /// Read short message previews for explicit triage requests such as
    /// "read my unread mail and tell me what needs attention".
    static func triageInbox(query: String?, unreadOnly: Bool?, limit: Int?, previewChars: Int?) async -> ToolResult {
        let start = Date()
        let normalizedQuery = normalizedQuery(query)
        let effectiveUnreadOnly = unreadOnly ?? true
        let effectiveLimit = clampedTriageLimit(limit)
        let effectivePreviewChars = clampedPreviewChars(previewChars)
        let script = buildTriageScript(
            query: normalizedQuery,
            unreadOnly: effectiveUnreadOnly,
            limit: effectiveLimit,
            previewChars: effectivePreviewChars
        )
        return await runOnMain(toolName: "mail_triage", script: script, start: start)
    }

    static func buildInboxScript(query: String, unreadOnly: Bool, limit: Int) -> String {
        let safeQuery = appleScriptStringLiteral(normalizedQuery(query))
        let safeLimit = clampedLimit(limit)
        let unreadLiteral = unreadOnly ? "true" : "false"
        return """
        tell application "Mail"
            if (count of accounts) is 0 then return "Mail is available, but no accounts are configured."
            set maxItems to \(safeLimit)
            set searchText to \(safeQuery)
            set unreadOnly to \(unreadLiteral)
            set collected to {}
            set inboxMessages to messages of inbox
            repeat with msg in inboxMessages
                try
                    set shouldInclude to true
                    set senderText to sender of msg as text
                    set subjectText to subject of msg as text
                    set readStatus to read status of msg
                    if unreadOnly is true and readStatus is true then set shouldInclude to false
                    if searchText is not "" then
                        if senderText does not contain searchText and subjectText does not contain searchText then set shouldInclude to false
                    end if
                    if shouldInclude is true then
                        set receivedText to date received of msg as string
                        set readText to "read"
                        if readStatus is false then set readText to "unread"
                        set end of collected to receivedText & " | " & readText & " | " & senderText & " | " & subjectText
                        if (count of collected) is greater than or equal to maxItems then exit repeat
                    end if
                end try
            end repeat
            if (count of collected) is 0 then return "No matching Mail messages found."
            set oldDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to linefeed
            set outputText to collected as text
            set AppleScript's text item delimiters to oldDelimiters
            return "Showing " & (count of collected) & " Mail message(s)." & linefeed & outputText
        end tell
        """
    }

    static func buildTriageScript(query: String, unreadOnly: Bool, limit: Int, previewChars: Int) -> String {
        let safeQuery = appleScriptStringLiteral(normalizedQuery(query))
        let safeLimit = clampedTriageLimit(limit)
        let safePreviewChars = clampedPreviewChars(previewChars)
        let unreadLiteral = unreadOnly ? "true" : "false"
        return """
        on replaceText(findText, replaceText, sourceText)
            set oldDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to findText
            set textParts to text items of sourceText
            set AppleScript's text item delimiters to replaceText
            set newText to textParts as text
            set AppleScript's text item delimiters to oldDelimiters
            return newText
        end replaceText

        on compactPreview(rawText, maxChars)
            set previewText to rawText as text
            set previewText to my replaceText(return, " ", previewText)
            set previewText to my replaceText(linefeed, " ", previewText)
            set previewText to my replaceText(tab, " ", previewText)
            if (length of previewText) is greater than maxChars then
                set previewText to (text 1 thru maxChars of previewText) & "..."
            end if
            return previewText
        end compactPreview

        tell application "Mail"
            if (count of accounts) is 0 then return "Mail is available, but no accounts are configured."
            set maxItems to \(safeLimit)
            set maxPreviewChars to \(safePreviewChars)
            set searchText to \(safeQuery)
            set unreadOnly to \(unreadLiteral)
            set collected to {}
            set inboxMessages to messages of inbox
            repeat with msg in inboxMessages
                try
                    set shouldInclude to true
                    set senderText to sender of msg as text
                    set subjectText to subject of msg as text
                    set readStatus to read status of msg
                    if unreadOnly is true and readStatus is true then set shouldInclude to false
                    if searchText is not "" then
                        if senderText does not contain searchText and subjectText does not contain searchText then set shouldInclude to false
                    end if
                    if shouldInclude is true then
                        set receivedText to date received of msg as string
                        set readText to "read"
                        if readStatus is false then set readText to "unread"
                        set previewText to "(preview unavailable)"
                        try
                            set previewText to my compactPreview(content of msg as text, maxPreviewChars)
                        end try
                        set end of collected to "Date: " & receivedText & linefeed & "Status: " & readText & linefeed & "Sender: " & senderText & linefeed & "Subject: " & subjectText & linefeed & "Preview: " & previewText
                        if (count of collected) is greater than or equal to maxItems then exit repeat
                    end if
                end try
            end repeat
            if (count of collected) is 0 then return "No matching Mail messages found."
            set oldDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to linefeed & "---" & linefeed
            set outputText to collected as text
            set AppleScript's text item delimiters to oldDelimiters
            return "Showing " & (count of collected) & " Mail triage preview(s)." & linefeed & outputText
        end tell
        """
    }

    static func normalizedQuery(_ query: String?) -> String {
        guard let query else { return "" }
        let compact = query
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > maxQueryChars else { return compact }
        return String(compact.prefix(maxQueryChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clampedLimit(_ limit: Int?) -> Int {
        min(max(limit ?? defaultLimit, 1), maxLimit)
    }

    static func clampedTriageLimit(_ limit: Int?) -> Int {
        min(max(limit ?? defaultTriageLimit, 1), maxTriageLimit)
    }

    static func clampedPreviewChars(_ previewChars: Int?) -> Int {
        min(max(previewChars ?? defaultPreviewChars, 80), maxPreviewChars)
    }

    static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    @MainActor
    private static func runOnMain(toolName: String, script: String, start: Date) async -> ToolResult {
        guard let apple = NSAppleScript(source: script) else {
            return .failure(tool: toolName, error: "Could not parse Mail AppleScript.", durationMs: 0)
        }
        var errorInfo: NSDictionary?
        let descriptor = apple.executeAndReturnError(&errorInfo)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if let err = errorInfo as? [String: Any] {
            let number = err["NSAppleScriptErrorNumber"] as? Int ?? 0
            if number == -1743 {
                return .failure(
                    tool: toolName,
                    error: "macOS Automation denied Mail access. Open Preferences > Tools > Mac App Permissions, grant Mail, then retry.",
                    durationMs: durationMs
                )
            }
            let message = (err["NSAppleScriptErrorMessage"] as? String)
                ?? (err["NSAppleScriptErrorBriefMessage"] as? String)
                ?? "Mail AppleScript error."
            return .failure(tool: toolName, error: "\(message) (\(number))", durationMs: durationMs)
        }

        let output = descriptor.stringValue ?? ""
        if output.isEmpty {
            return .success(tool: toolName, content: "(no Mail output)", durationMs: durationMs)
        }
        if output.count > maxOutputChars {
            let truncated = String(output.prefix(maxOutputChars))
            let note = "\n\n... [TRUNCATED: \(output.count) total chars, showing first \(maxOutputChars)] ..."
            return .success(tool: toolName, content: truncated + note, durationMs: durationMs)
        }
        return .success(tool: toolName, content: output, durationMs: durationMs)
    }
}
