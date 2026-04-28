import Foundation

// MARK: - AgentLoop / Final-Assistant Output Normalizer
//
// Phase 2a (peer-review plan, 2026-04-28): extracted from AgentLoop.swift.
// All entry points remain `static` methods on `AgentLoop` so existing
// callers (`process()`, MultimediaBobTests) keep using
// `AgentLoop.normalizedFinalAssistantContent(...)` unchanged.
//
// Scope of this file:
//   - Last-pass shaping of the model's final reply for the chat surface.
//   - Honors user constraints in the prompt ("one sentence", "one line",
//     "fenced code block only", "markdown only ![alt](path)").
//   - Substitutes a concise success/failure phrase for an open-intent
//     turn whose final reply doesn't acknowledge the actual tool result.
//   - Supplies a fallback Mail summary when the model emits an empty
//     reply after a successful Mail tool result.
extension AgentLoop {
    static func normalizedFinalAssistantContent(
        _ content: String,
        for userMessage: String,
        turnHadToolFailure: Bool,
        lastFailedToolResult: ToolResult?,
        lastToolResult: ToolResult?
    ) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerUser = userMessage.lowercased()

        if let markdownImage = explicitMarkdownImageResponse(for: userMessage) {
            return markdownImage
        }

        if requestsOnlyFencedCodeBlock(lowerUser),
           let fencedBlock = firstFencedCodeBlock(in: trimmed) {
            return fencedBlock
        }

        if let lastToolResult,
           lastToolResult.success,
           finalSuccessfulOpenShouldOverride(content: trimmed, userMessage: userMessage, result: lastToolResult) {
            return conciseSuccessReply(for: userMessage, from: lastToolResult)
        }

        if trimmed.isEmpty,
           let lastToolResult,
           lastToolResult.success,
           let mailReply = fallbackMailReply(from: lastToolResult) {
            return mailReply
        }

        if turnHadToolFailure,
           let lastFailedToolResult,
           (contentAcknowledgesFailure(trimmed) == false || finalFailureReplyShouldOverride(content: trimmed, userMessage: userMessage, result: lastFailedToolResult)) {
            return conciseFailureReply(for: userMessage, from: lastFailedToolResult)
        }

        if requestsSingleLine(lowerUser) {
            return firstNonEmptyLine(in: trimmed)
        }

        if requestsSingleSentence(lowerUser) {
            return bestSentence(in: trimmed, userMessage: userMessage)
        }

        return trimmed
    }

    private static func fallbackMailReply(from result: ToolResult) -> String? {
        let detail = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard detail.isEmpty == false else { return nil }

        switch result.toolName {
        case "mail_check":
            return "I found these Mail messages:\n\(detail)"
        case "mail_triage":
            return "I pulled these Mail previews for triage, but I could not finish the ranking in this turn. Here are the previews I found:\n\(detail)"
        default:
            return nil
        }
    }

    private static func explicitMarkdownImageResponse(for userMessage: String) -> String? {
        let lowerUser = userMessage.lowercased()
        guard lowerUser.contains("markdown only"),
              lowerUser.contains("![alt](path)") else {
            return nil
        }

        guard let path = extractAbsoluteOrTildePath(from: userMessage) else {
            return nil
        }

        let fileName = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).deletingPathExtension().lastPathComponent
        let alt = fileName.isEmpty ? "image" : fileName
        return "![\(alt)](\(path))"
    }

    private static func requestsOnlyFencedCodeBlock(_ lowerUser: String) -> Bool {
        lowerUser.contains("fenced code block") ||
        lowerUser.contains("only that fenced block") ||
        lowerUser.contains("just the code block")
    }

    private static func requestsSingleSentence(_ lowerUser: String) -> Bool {
        lowerUser.contains("one sentence")
    }

    private static func requestsSingleLine(_ lowerUser: String) -> Bool {
        lowerUser.contains("one line")
    }

    private static func firstFencedCodeBlock(in content: String) -> String? {
        guard let openRange = content.range(of: "```") else { return nil }
        guard let closeRange = content.range(of: "```", range: openRange.upperBound..<content.endIndex) else { return nil }
        return String(content[openRange.lowerBound..<closeRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contentAcknowledgesFailure(_ content: String) -> Bool {
        let lower = content.lowercased()
        let markers = ["couldn't", "could not", "failed", "error", "not allowed", "denied", "refused", "did not succeed", "can't", "cannot"]
        return markers.contains { lower.contains($0) }
    }

    private static func finalSuccessfulOpenShouldOverride(content: String, userMessage: String, result: ToolResult) -> Bool {
        guard result.toolName == "shell" || result.toolName == "present" else { return false }
        guard isOpenIntent(userMessage) else { return false }
        if contentAcknowledgesFailure(content) { return true }
        return contentAcknowledgesOpenSuccess(content) == false
    }

    private static func finalFailureReplyShouldOverride(content: String, userMessage: String, result: ToolResult) -> Bool {
        guard isOpenIntent(userMessage) else { return false }
        let lowerDetail = result.content.lowercased()
        let lowerContent = content.lowercased()

        if lowerDetail.contains("command timed out after"),
           lowerContent.contains("command timed out after") {
            return true
        }

        return false
    }

    private static func isOpenIntent(_ userMessage: String) -> Bool {
        let lower = userMessage.lowercased()
        return ["open ", "launch ", "show ", "in preview", "in browser", "in my browser", "default app", "proper window"]
            .contains { lower.contains($0) }
    }

    private static func contentAcknowledgesOpenSuccess(_ content: String) -> Bool {
        let lower = content.lowercased()
        let markers = [
            "opened",
            "open in preview",
            "in preview",
            "in your browser",
            "in my browser",
            "rich view",
            "shown",
            "showing"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func conciseFailureReply(for userMessage: String, from result: ToolResult) -> String {
        let detail = result.content
            .replacingOccurrences(of: "Error: ", with: "")
            .replacingOccurrences(of: "Denied: ", with: "")
            .replacingOccurrences(of: "Forbidden: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if detail.localizedCaseInsensitiveContains("path not allowed"),
           let path = extractAbsoluteOrTildePath(from: userMessage) {
            return "I couldn't open \(path) because that path is not allowed."
        }

        // `open ~/Desktop/...` and similar shell fallbacks can block on a macOS
        // TCC prompt instead of returning promptly. When that happens we want a
        // retry/approval explanation, not a misleading generic shell failure.
        if detail.localizedCaseInsensitiveContains("command timed out after"),
           isOpenIntent(userMessage) {
            if let path = extractAbsoluteOrTildePath(from: userMessage),
               likelyTriggersMacOSFilePrompt(path: path) {
                return "I hit a macOS file-access prompt while opening \(path). Approve it and retry."
            }
            return "I hit a macOS prompt while opening that. Approve it and retry."
        }

        if detail.isEmpty {
            return "I couldn't complete that request."
        }

        let sentence = firstSentence(in: detail)
        return sentence.hasPrefix("I ") ? sentence : "I couldn't complete that request: \(sentence.prefix(1).lowercased())\(sentence.dropFirst())"
    }

    private static func conciseSuccessReply(for userMessage: String, from result: ToolResult) -> String {
        let detail = result.content
            .replacingOccurrences(of: "Opened file: ", with: "")
            .replacingOccurrences(of: "Opened URL: ", with: "")
            .replacingOccurrences(of: "Opened rich view: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lowerUser = userMessage.lowercased()
        if lowerUser.contains("in preview"),
           let path = extractAbsoluteOrTildePath(from: userMessage) {
            return "I opened \(path) in Preview."
        }

        if lowerUser.contains("in browser") || lowerUser.contains("in my browser") {
            return "I opened it in your browser."
        }

        if detail.isEmpty == false, detail != "(no output)" {
            return result.content
        }

        if let path = extractAbsoluteOrTildePath(from: userMessage) {
            return "I opened \(path)."
        }

        return "I completed that request."
    }

    private static func extractAbsoluteOrTildePath(from text: String) -> String? {
        let patterns = [#"(~\/[^\s`]+)"#, #"((?:\/[^\s`]+)+)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let capture = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[capture]).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:)]}\"'"))
        }
        return nil
    }

    private static func likelyTriggersMacOSFilePrompt(path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        let protectedRoots = [
            "\(NSHomeDirectory())/Desktop",
            "\(NSHomeDirectory())/Documents",
            "\(NSHomeDirectory())/Downloads"
        ]
        return protectedRoots.contains { expanded == $0 || expanded.hasPrefix($0 + "/") }
    }

    private static func firstNonEmptyLine(in content: String) -> String {
        content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? content
    }

    private static func firstSentence(in content: String) -> String {
        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"(?i)\b(anything else sir\??|bob is done sir[^\.\!\?]*[\.\!\?]?|most welcome sir[^\.\!\?]*[\.\!\?]?)"#,
                                  with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return content.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let regex = try? NSRegularExpression(pattern: #"[.!?](?=\s|$)"#) {
            let nsRange = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, range: nsRange),
               let range = Range(match.range, in: cleaned) {
                return String(cleaned[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return cleaned
    }

    private static func bestSentence(in content: String, userMessage: String) -> String {
        let sentences = splitSentences(in: content)
        guard sentences.isEmpty == false else {
            return firstSentence(in: content)
        }

        let keywords = significantKeywords(from: userMessage)
        return sentences.max { scoreSentence($0, keywords: keywords) < scoreSentence($1, keywords: keywords) } ?? firstSentence(in: content)
    }

    private static func splitSentences(in content: String) -> [String] {
        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"(?i)\b(anything else sir\??|bob is done sir[^\.\!\?]*[\.\!\?]?|most welcome sir[^\.\!\?]*[\.\!\?]?)"#,
                                  with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return [] }

        guard let regex = try? NSRegularExpression(pattern: #"[.!?](?=\s|$)"#) else {
            return [cleaned]
        }

        let range = NSRange(cleaned.startIndex..., in: cleaned)
        let matches = regex.matches(in: cleaned, range: range)
        guard matches.isEmpty == false else { return [cleaned] }

        var sentences: [String] = []
        var sentenceStart = cleaned.startIndex

        for match in matches {
            guard let punctuationRange = Range(match.range, in: cleaned) else { continue }
            let sentence = String(cleaned[sentenceStart..<punctuationRange.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.isEmpty == false {
                sentences.append(sentence)
            }

            sentenceStart = punctuationRange.upperBound
            while sentenceStart < cleaned.endIndex, cleaned[sentenceStart].isWhitespace {
                sentenceStart = cleaned.index(after: sentenceStart)
            }
        }

        if sentenceStart < cleaned.endIndex {
            let tail = String(cleaned[sentenceStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty == false {
                sentences.append(tail)
            }
        }

        return sentences.isEmpty ? [cleaned] : sentences
    }

    private static func scoreSentence(_ sentence: String, keywords: [String]) -> Int {
        let lower = sentence.lowercased()
        var score = 0

        if lower.contains("~/") || lower.contains("/") { score += 12 }
        if lower.range(of: #"(~\/|\/[A-Za-z0-9._-]+)"#, options: .regularExpression) != nil { score += 6 }
        if lower.contains("located") || lower.contains("called") || lower.contains("use ") { score += 3 }
        if lower.contains(" is ") || lower.hasPrefix("is ") || lower.contains(" are ") { score += 1 }

        for keyword in keywords where lower.contains(keyword) {
            score += 3
        }

        let fillerPatterns = [
            "actually sir",
            "yes sir",
            "very simple matter",
            "simple matter",
            "one moment",
            "bob will",
            "no tension",
            "most welcome"
        ]
        if fillerPatterns.contains(where: { lower.contains($0) }) { score -= 8 }
        if lower.contains("anything else") { score -= 10 }

        score -= max(0, sentence.count - 120) / 12
        return score
    }

    private static func significantKeywords(from userMessage: String) -> [String] {
        let lower = userMessage.lowercased()
        let stopWords: Set<String> = [
            "the", "a", "an", "in", "on", "at", "for", "to", "my", "me", "is", "where", "what",
            "show", "give", "just", "only", "one", "sentence", "line", "code", "block", "no", "tool", "tools"
        ]

        return lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && stopWords.contains($0) == false }
    }
}
