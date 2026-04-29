import Foundation

/// Stateless regex-based classifier for clipboard text payloads.
///
/// All work here is CPU-only, no model invocation. The regexes are compiled
/// once as static properties so repeated calls are cheap.
///
/// Classification order (first match wins):
///   1. messyURL  — URL with at least one known tracking param
///   2. messyJSON — content that parses as JSON (or looks like it)
///   3. base64Blob — dense base64 with no whitespace, length >= 64
///   4. stackTrace — multiple lines matching `at Foo (file:line)` or `at file:line`
///   5. nil       — plain text, no suggestion needed
enum ClipboardClassifier {

    // MARK: - Compiled patterns (static, compiled once)

    /// Tracking query parameter names that warrant a "Clean URL" chip.
    private static let trackingParamNames: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_reader", "utm_referrer",
        "fbclid", "gclid", "msclkid", "dclid", "mc_cid", "mc_eid",
        "igshid", "twclid", "_ga", "_hsenc", "_hsmi", "yclid",
        "ref", "source", "s_kwcid"
    ]

    /// Matches a URL-like string (starts with http/https).
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"^https?://"#,
        options: [.caseInsensitive]
    )

    /// Matches JSON object or array start.
    private static let jsonStartPattern = try! NSRegularExpression(
        pattern: #"^\s*[\[\{]"#,
        options: []
    )

    /// Base64: only contains [A-Za-z0-9+/=], length >= 64, no whitespace.
    private static let base64Pattern = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9+/=]{64,}$"#,
        options: []
    )

    /// Stack-trace line patterns:
    ///  - JS/Node: "    at FooBar (file.js:10:3)"
    ///  - JVM: "    at com.foo.Bar.method(File.java:42)"
    ///  - Swift/macOS: "0  OllamaBob  0x000001234 SomeFunc + 100"
    ///  - Python: "  File \"foo.py\", line 42, in bar"
    private static let stackLinePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"^\s+at\s+\S+\s*\("#, options: []),        // JS/JVM
        try! NSRegularExpression(pattern: #"^\s+at\s+\S+:\d+"#, options: []),          // bare at
        try! NSRegularExpression(pattern: #"^\s*\d+\s+\S+\s+0x[0-9a-fA-F]+"#, options: []),  // symbolicated
        try! NSRegularExpression(pattern: #"^\s*File\s+".+",\s*line\s+\d+"#, options: [])      // Python
    ]

    // MARK: - Public API

    /// Classify a clipboard payload. Returns `nil` when no action is useful.
    ///
    /// - Parameter text: Raw clipboard text. Caller should already have size-
    ///   gated this to <= 32 KB.
    static func classify(_ text: String) -> ClipboardSuggestion.Kind? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Messy URL check — cheapest string operation first
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        if urlPattern.firstMatch(in: trimmed, range: nsRange) != nil {
            if hasTrackingParams(in: trimmed) {
                return .messyURL
            }
            // A plain URL without tracking params doesn't warrant a chip.
            return nil
        }

        // 2. JSON check
        let jsonRange = NSRange(trimmed.startIndex..., in: trimmed)
        if jsonStartPattern.firstMatch(in: trimmed, range: jsonRange) != nil {
            if looksLikeJSON(trimmed) {
                return .messyJSON
            }
        }

        // 3. Base64 blob — single-line, no whitespace, min length 64
        if !trimmed.contains("\n") && !trimmed.contains(" ") {
            let b64Range = NSRange(trimmed.startIndex..., in: trimmed)
            if base64Pattern.firstMatch(in: trimmed, range: b64Range) != nil {
                return .base64Blob
            }
        }

        // 4. Stack trace — at least 3 matching lines
        if hasStackTrace(trimmed) {
            return .stackTrace
        }

        return nil
    }

    // MARK: - Private helpers

    private static func hasTrackingParams(in urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString),
              let queryItems = components.queryItems else { return false }
        return queryItems.contains { trackingParamNames.contains($0.name.lowercased()) }
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func hasStackTrace(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 3 else { return false }
        var matchCount = 0
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            for pattern in stackLinePatterns {
                if pattern.firstMatch(in: line, range: range) != nil {
                    matchCount += 1
                    break
                }
            }
            if matchCount >= 3 { return true }
        }
        return false
    }
}
