import Foundation

// MARK: - AgentLoop / Phone Call Context
//
// Phase 2a (peer-review plan, 2026-04-28): extracted from AgentLoop.swift.
// All entry points remain `nonisolated static` methods on `AgentLoop` so
// `PhoneTool`, `ChatSessionServices`, and tests keep using
// `AgentLoop.phoneCallContext(...)`, `AgentLoop.mergedPhoneCallContext(...)`,
// `AgentLoop.shouldAttachAutomaticPhoneContext(...)`, and
// `AgentLoop.phoneCallApprovalDescription(...)` unchanged.
//
// Scope of this file:
//   - Builds bounded session-context summaries to attach to outbound
//     Jarvis recap calls.
//   - Decides whether the current request is a "what did we do" recap
//     that should auto-attach session context vs. a normal destination
//     call that should not.
//   - Renders the operator-facing approval-modal description for an
//     outbound phone call.
extension AgentLoop {

    nonisolated static func phoneCallContext(
        from messages: [OllamaMessage],
        conversationId: String,
        maxCharacters: Int = 1500
    ) -> String? {
        guard maxCharacters > 80 else { return nil }
        let header = "OllamaBob conversation context (\(conversationId)). Use naturally; do not read this verbatim."
        let highlightLines = phoneCallHighlightLine(from: messages).map { [$0] } ?? []
        let prefixLines = [header] + highlightLines
        let prefixText = prefixLines.joined(separator: "\n")
        guard prefixText.count < maxCharacters else {
            return phoneContextTruncated(prefixText, maxCharacters: maxCharacters)
        }

        let lines = messages.compactMap(phoneCallContextLine(from:))
        guard lines.isEmpty == false else { return nil }

        var selected: [String] = []
        var used = prefixText.count
        for line in lines.reversed() {
            let separatorCost = selected.isEmpty ? 2 : 1
            let remaining = maxCharacters - used - separatorCost
            guard remaining > 0 else { break }

            if line.count <= remaining {
                selected.insert(line, at: 0)
                used += separatorCost + line.count
            } else if remaining >= 48 {
                selected.insert(phoneContextTruncated(line, maxCharacters: remaining), at: 0)
                break
            } else {
                break
            }
        }

        guard selected.isEmpty == false else {
            return phoneContextTruncated(prefixText, maxCharacters: maxCharacters)
        }
        return (prefixLines + selected).joined(separator: "\n")
    }

    nonisolated static func mergedPhoneCallContext(
        explicit: String?,
        automatic: String?,
        maxCharacters: Int = 1500
    ) -> String? {
        let explicit = cleanedPhoneContextText(explicit ?? "")
        let automatic = cleanedPhoneContextText(automatic ?? "")
        let parts: [String]
        if explicit.isEmpty == false, automatic.isEmpty == false {
            parts = [
                "Requested call context: \(explicit)",
                "Recent OllamaBob session:\n\(automatic)"
            ]
        } else if explicit.isEmpty == false {
            parts = [explicit]
        } else if automatic.isEmpty == false {
            parts = [automatic]
        } else {
            return nil
        }
        return phoneContextTruncated(parts.joined(separator: "\n\n"), maxCharacters: maxCharacters)
    }

    nonisolated static func shouldAttachAutomaticPhoneContext(
        purpose: String,
        userMessage: String
    ) -> Bool {
        let haystack = cleanedPhoneContextText("\(purpose) \(userMessage)")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let sessionContextPhrases = [
            "what you did",
            "what bob did",
            "what we did",
            "what we've done",
            "what we have done",
            "what we talked",
            "current ollamabob session",
            "current session",
            "current conversation",
            "this conversation",
            "this chat",
            "recent session",
            "session context",
            "status update",
            "progress update",
            "quick recap",
            "recap of",
            "summarize our",
            "summary of our",
            "working on",
            "we worked on"
        ]
        return sessionContextPhrases.contains { haystack.contains($0) }
    }

    nonisolated static func phoneCallApprovalDescription(args: [String: Any]) -> String {
        let rawPersona = args["persona"] as? String ?? ""
        let persona = PhoneTool.resolvedCallerLabel(rawPersona)
        let to = args["to"] as? String ?? "unknown"
        let purpose = cleanedPhoneContextText(args["purpose"] as? String ?? "")
        let context = cleanedPhoneContextText(args["context"] as? String ?? "")
        let shortPurpose = phoneContextTruncated(purpose, maxCharacters: 200)

        var lines = [
            "Bob wants to place a phone call to \(to) as \(persona).",
            "Purpose: \(shortPurpose)"
        ]
        if context.isEmpty == false {
            lines.append("Context: \(phoneContextTruncated(context, maxCharacters: 500))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private helpers

    private nonisolated static func phoneCallContextLine(from message: OllamaMessage) -> String? {
        switch message.role {
        case "user":
            return labeledPhoneContextLine(label: "User", text: message.content)
        case "assistant":
            if let line = labeledPhoneContextLine(label: "Bob", text: message.content) {
                return line
            }
            guard let names = message.toolCalls?.map(\.function.name), names.isEmpty == false else {
                return nil
            }
            return "Bob requested tools: \(names.joined(separator: ", "))"
        case "tool":
            let name = message.toolName ?? "unknown"
            return labeledPhoneContextLine(label: "Tool \(name)", text: message.content)
        default:
            return nil
        }
    }

    private nonisolated static func phoneCallHighlightLine(from messages: [OllamaMessage]) -> String? {
        let haystack = messages
            .filter { $0.role != "system" }
            .map { cleanedPhoneContextText($0.content) }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        guard haystack.isEmpty == false else { return nil }

        var highlights: [String] = []
        appendHighlight(
            "music/download work",
            to: &highlights,
            if: haystackContainsAny(haystack, [
                "download", "album", "song", "songs", "track", "tracks",
                "mp3", "flac", "youtube", "yt-dlp", "music", "audio"
            ])
        )
        appendHighlight(
            "mail triage",
            to: &highlights,
            if: haystackContainsAny(haystack, ["mail", "email", "inbox", "unread"])
        )
        appendHighlight(
            "contacts/address book",
            to: &highlights,
            if: haystackContainsAny(haystack, ["contact", "contacts", "address book", "vcf", "vcard"])
        )
        appendHighlight(
            "tool permissions/approvals",
            to: &highlights,
            if: haystackContainsAny(haystack, ["permission", "permissions", "approval", "approved", "auto", "ask", "deny"])
        )
        appendHighlight(
            "phone/Jarvis call work",
            to: &highlights,
            if: haystackContainsAny(haystack, ["phone", "call", "calls", "jarvis"])
        )
        appendHighlight(
            "build/version/git work",
            to: &highlights,
            if: haystackContainsAny(haystack, ["build", "test", "version", "commit", "push", "git"])
        )

        guard highlights.isEmpty == false else { return nil }
        return "Earlier highlights: \(highlights.prefix(5).joined(separator: "; "))"
    }

    private nonisolated static func appendHighlight(_ highlight: String, to highlights: inout [String], if condition: Bool) {
        if condition {
            highlights.append(highlight)
        }
    }

    private nonisolated static func haystackContainsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private nonisolated static func labeledPhoneContextLine(label: String, text: String) -> String? {
        let cleaned = cleanedPhoneContextText(text)
        guard cleaned.isEmpty == false else { return nil }
        return "\(label): \(phoneContextTruncated(cleaned, maxCharacters: 260))"
    }

    private nonisolated static func cleanedPhoneContextText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<untrusted>", with: "")
            .replacingOccurrences(of: "</untrusted>", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extension-private truncator. Renamed from the original `truncated`
    /// to avoid colliding with similar helpers in other extracted files.
    private nonisolated static func phoneContextTruncated(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 1, text.count > maxCharacters else { return text }
        return "\(text.prefix(maxCharacters - 1))…"
    }
}
