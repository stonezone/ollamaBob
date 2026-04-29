import Foundation

/// Pure-Swift clipboard cleanup transforms.
///
/// None of these invoke Ollama. All transforms run synchronously on the string
/// passed in and return `nil` when the result would be unchanged or invalid.
enum ClipboardCleaners {

    // MARK: - URL Cleaner

    /// Strip known tracking/analytics query parameters from a URL.
    ///
    /// Preserves all query params whose names are NOT in the tracking list.
    /// Returns `nil` when the input isn't a valid URL or has nothing to strip.
    static func cleanURL(_ raw: String) -> String? {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return nil
        }
        let filtered = queryItems.filter { !isTrackingParam($0.name) }
        // Nothing was stripped — don't return a "cleaned" URL identical to input.
        guard filtered.count < queryItems.count else { return nil }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url?.absoluteString
    }

    // MARK: - JSON Pretty-Printer

    /// Parse and re-format JSON with 2-space indentation and sorted keys.
    ///
    /// Returns `nil` when the input is not valid JSON.
    static func prettyJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return result
    }

    // MARK: - Base64 Decoder

    /// Decode a base64 string to its UTF-8 representation.
    ///
    /// Returns `nil` when the input is not valid base64 or the decoded bytes
    /// are not valid UTF-8 (binary blobs are not displayable).
    static func decodeBase64(_ raw: String) -> String? {
        let stripped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept standard and URL-safe base64 alphabets
        let normalized = stripped
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: normalized, options: .ignoreUnknownCharacters),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }

    // MARK: - Private

    private static let trackingParamNames: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_reader", "utm_referrer",
        "fbclid", "gclid", "msclkid", "dclid", "mc_cid", "mc_eid",
        "igshid", "twclid", "_ga", "_hsenc", "_hsmi", "yclid",
        "s_kwcid"
    ]

    private static func isTrackingParam(_ name: String) -> Bool {
        trackingParamNames.contains(name.lowercased())
    }
}
