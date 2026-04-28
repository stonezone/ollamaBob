import Foundation

enum PhoneTool {
    static let defaultCaller = "bob"

    static var isConfigured: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.jarvisPhoneEnabledKey) &&
        JarvisConfiguration.apiKey.isEmpty == false &&
        JarvisConfiguration.operatorSecret.isEmpty == false &&
        JarvisConfiguration.baseURL != nil
    }

    static func execute(
        persona: String,
        to: String,
        purpose: String,
        maxMinutes: Int?,
        context: String? = nil
    ) async -> ToolResult {
        let start = Date()
        let resolvedDestination = resolvedDestinationLabel(to)
        let cleanedContext = context?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = cleanedContext?.isEmpty == false ? cleanedContext : nil
        let request = PhoneCallRequest(
            caller: resolvedCallerLabel(persona),
            to: resolvedDestination,
            missionBrief: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
            context: trimmedContext,
            maxDurationSeconds: (maxMinutes ?? 10) * 60
        )

        guard request.to.isEmpty == false,
              request.missionBrief.isEmpty == false else {
            return .failure(tool: "phone_call", error: "Missing destination or purpose.", durationMs: 0)
        }

        let client = JarvisClient()
        do {
            let response = try await client.postJSON(
                toolName: "phone_call",
                paths: ["/call/initiate"],
                body: request
            )
            return summarizeCallResponse(
                action: .call,
                request: request,
                response: response,
                start: start
            )
        } catch let error as JarvisClientError {
            return toolResult(from: error, start: start)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_call", error: error.localizedDescription, durationMs: durationMs)
        }
    }

    static func hangup(callID: String) async -> ToolResult {
        let start = Date()
        let trimmed = callID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .failure(tool: "phone_hangup", error: "Missing call_id.", durationMs: 0)
        }

        let client = JarvisClient()
        do {
            let response = try await client.postEmpty(
                toolName: "phone_hangup",
                paths: [
                    "/call/hangup/\(trimmed)"
                ]
            )
            return summarizeCallResponse(
                action: .hangup,
                callID: trimmed,
                response: response,
                start: start
            )
        } catch let error as JarvisClientError {
            return toolResult(from: error, start: start)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_hangup", error: error.localizedDescription, durationMs: durationMs)
        }
    }

    static func status(callID: String) async -> ToolResult {
        let start = Date()
        let trimmed = callID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .failure(tool: "phone_status", error: "Missing call_id.", durationMs: 0)
        }

        let client = JarvisClient()
        do {
            let response = try await client.getJSON(
                toolName: "phone_status",
                paths: [
                    "/call/status/\(trimmed)"
                ]
            )
            return summarizeCallResponse(
                action: .status,
                callID: trimmed,
                response: response,
                start: start
            )
        } catch let error as JarvisClientError {
            return toolResult(from: error, start: start)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_status", error: error.localizedDescription, durationMs: durationMs)
        }
    }

    // MARK: - Response Formatting

    private static func summarizeCallResponse(
        action: CallAction,
        request: PhoneCallRequest? = nil,
        callID: String? = nil,
        response: JarvisHTTPResponse,
        start: Date
    ) -> ToolResult {
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        guard (200...299).contains(response.statusCode) else {
            return failureResult(action: action, response: response, durationMs: durationMs)
        }

        let rawText = response.bodyTextTruncated
        let envelope = JarvisResponseEnvelope(data: response.data)

        var lines: [String] = []
        switch action {
        case .call:
            let callSid = envelope.string(for: ["callSid", "call_id", "callId", "id"]) ?? "unknown"
            let status = envelope.string(for: ["status", "state"]) ?? "queued"
            let persona = request?.caller ?? envelope.string(for: ["caller", "persona"]) ?? "unknown"
            let target = request?.to ?? envelope.string(for: ["to", "destination", "target"]) ?? "unknown"
            lines.append("Call started: callSid=\(callSid), persona=\(persona), to=\(target), status=\(status)")
            if let maxDurationSeconds = request?.maxDurationSeconds {
                lines.append("maxMinutes=\(formatNumber(Double(maxDurationSeconds) / 60.0))")
            }
            if let message = firstMeaningfulText(envelope: envelope, fallback: rawText) {
                lines.append(message)
            }

        case .hangup:
            let sid = callID ?? envelope.string(for: ["callSid", "call_id", "callId", "id"]) ?? "unknown"
            let status = envelope.string(for: ["status", "state"]) ?? "hangup requested"
            lines.append("Hangup sent: callSid=\(sid), status=\(status)")
            if let message = firstMeaningfulText(envelope: envelope, fallback: rawText) {
                lines.append(message)
            }

        case .status:
            let sid = callID ?? envelope.string(for: ["callSid", "call_id", "callId", "id"]) ?? "unknown"
            let status = envelope.string(for: ["status", "state"]) ?? "unknown"
            lines.append("Call status: callSid=\(sid), status=\(status)")
            if let duration = envelope.double(for: ["durationSeconds", "duration"]) {
                lines.append("duration=\(formatNumber(duration))s")
            }
            if let cost = envelope.double(for: ["costUsd", "cost", "price"]) {
                lines.append("cost=$\(formatNumber(cost))")
            }
            if let message = firstMeaningfulText(envelope: envelope, fallback: rawText) {
                lines.append(message)
            }
        }

        let content = lines.joined(separator: "\n")
        return ToolResult(
            toolName: toolName(for: action),
            content: content.isEmpty ? rawText : content,
            success: true,
            durationMs: durationMs
        )
    }

    private static func failureResult(action: CallAction, response: JarvisHTTPResponse, durationMs: Int) -> ToolResult {
        let rawText = String(response.bodyText.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
        if response.statusCode == 401 {
            let message: String
            if rawText.contains("Unauthorized") {
                message = "Jarvis operator secret rejected (401 Unauthorized). Update the Operator secret in Preferences."
            } else if rawText.lowercased().contains("unauthorized") {
                message = "Jarvis call API key rejected (401 unauthorized). Update the Jarvis API key in Preferences."
            } else {
                message = "Jarvis authentication failed (401). Check the Operator secret and Jarvis API key in Preferences."
            }
            return ToolResult(
                toolName: toolName(for: action),
                content: message,
                success: false,
                durationMs: durationMs
            )
        }
        let suffix = rawText.isEmpty ? "" : ": \(rawText)"
        return ToolResult(
            toolName: toolName(for: action),
            content: "Jarvis error: \(response.statusCode)\(suffix)",
            success: false,
            durationMs: durationMs
        )
    }

    private static func toolResult(from error: JarvisClientError, start: Date) -> ToolResult {
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        switch error {
        case .unreachable:
            return ToolResult(
                toolName: error.toolName,
                content: "Jarvis unreachable at \(JarvisConfiguration.baseURLString)",
                success: false,
                durationMs: durationMs
            )
        case .invalidURL:
            return .failure(tool: error.toolName, error: "Invalid Jarvis base URL.", durationMs: durationMs)
        }
    }

    private static func firstMeaningfulText(envelope: JarvisResponseEnvelope, fallback: String) -> String? {
        if let message = envelope.string(for: ["message", "detail"]) {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed.count > 500 ? String(trimmed.prefix(500)) : trimmed
            }
        }

        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFallback.isEmpty == false else { return nil }
        return trimmedFallback.count > 500 ? String(trimmedFallback.prefix(500)) : trimmedFallback
    }

    static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    static func resolvedCallerLabel(_ persona: String) -> String {
        switch persona.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "jarvis", "bob":
            return "bob"
        case "buddy":
            return "buddy"
        case "zack":
            return "zack"
        case "glennel":
            return "glennel"
        case "glennel_naggy", "glennel naggy", "naggy":
            return "glennel_naggy"
        default:
            return defaultCaller
        }
    }

    static func resolvedDestinationLabel(
        _ destination: String,
        addressBookLookup: (String) -> String? = LocalAddressBook.value(for:)
    ) -> String {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        if let e164 = firstE164Candidate(in: trimmed) {
            return e164
        }

        if let normalized = firstNorthAmericanNumberCandidate(in: trimmed) {
            return normalized
        }

        if let alias = resolvedLocalContactAlias(trimmed, addressBookLookup: addressBookLookup) {
            return alias
        }

        return trimmed
    }

    private static func firstE164Candidate(in text: String) -> String? {
        firstRegexMatch(in: text, pattern: #"(?<!\d)\+[1-9]\d{7,14}(?!\d)"#)
    }

    private static func firstNorthAmericanNumberCandidate(in text: String) -> String? {
        let patterns = [
            #"(?:\+?1[\s.\-]*)?(?:\(\d{3}\)|\d{3})[\s.\-]*\d{3}[\s.\-]*\d{4}"#,
            #"(?<!\d)\d{10}(?!\d)"#,
            #"(?<!\d)1\d{10}(?!\d)"#
        ]

        for pattern in patterns {
            guard let candidate = firstRegexMatch(in: text, pattern: pattern) else { continue }
            if let normalized = normalizeNorthAmericanNumber(candidate) {
                return normalized
            }
        }

        return nil
    }

    private static func resolvedLocalContactAlias(
        _ text: String,
        addressBookLookup: (String) -> String?
    ) -> String? {
        let normalizedAlias = canonicalDestinationAlias(text)
        guard normalizedAlias.isEmpty == false else { return nil }

        if let direct = addressBookLookup(normalizedAlias),
           let normalized = normalizeNorthAmericanNumber(direct) ?? firstE164Candidate(in: direct) {
            return normalized
        }

        return nil
    }

    private static func canonicalDestinationAlias(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func normalizeNorthAmericanNumber(_ text: String) -> String? {
        let digits = text.filter(\.isWholeNumber)
        switch digits.count {
        case 10:
            return "+1\(digits)"
        case 11 where digits.hasPrefix("1"):
            return "+\(digits)"
        default:
            return nil
        }
    }

    private static func firstRegexMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    private static func toolName(for action: CallAction) -> String {
        switch action {
        case .call: return "phone_call"
        case .hangup: return "phone_hangup"
        case .status: return "phone_status"
        }
    }
}

private enum CallAction {
    case call
    case hangup
    case status
}

private struct PhoneCallRequest: Encodable {
    let caller: String
    let to: String
    let missionBrief: String
    let context: String?
    let maxDurationSeconds: Int
}

private struct JarvisConfiguration {
    static var baseURLString: String {
        let value =
            ProcessInfo.processInfo.environment["JARVIS_BASE_URL"]
            ?? ProcessInfo.processInfo.environment["JARVIS_PHONE_BASE_URL"]
            ?? "http://127.0.0.1:3100"
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var baseURL: URL? {
        URL(string: baseURLString)
    }

    static var apiKey: String {
        let env = ProcessInfo.processInfo.environment["JARVIS_API_KEY"] ?? ""
        let stored = UserDefaults.standard.string(forKey: AppSettings.jarvisAPIKeyKey) ?? ""
        return env.isEmpty ? stored : env
    }

    static var operatorSecret: String {
        let env = ProcessInfo.processInfo.environment["OPERATOR_API_SECRET"] ?? ""
        let stored = UserDefaults.standard.string(forKey: AppSettings.jarvisOperatorSecretKey) ?? ""
        return env.isEmpty ? stored : env
    }
}

private struct JarvisClient {
    func postJSON<T: Encodable>(toolName: String, paths: [String], body: T) async throws -> JarvisHTTPResponse {
        let data = try JSONEncoder().encode(body)
        return try await send(method: "POST", toolName: toolName, paths: paths, body: data)
    }

    func postEmpty(toolName: String, paths: [String]) async throws -> JarvisHTTPResponse {
        try await send(method: "POST", toolName: toolName, paths: paths, body: nil)
    }

    func getJSON(toolName: String, paths: [String]) async throws -> JarvisHTTPResponse {
        try await send(method: "GET", toolName: toolName, paths: paths, body: nil)
    }

    private func send(method: String, toolName: String, paths: [String], body: Data?) async throws -> JarvisHTTPResponse {
        guard let baseURL = JarvisConfiguration.baseURL else {
            throw JarvisClientError.invalidURL(toolName: toolName)
        }

        var lastNetworkError: Bool = false
        for path in paths {
            guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
                throw JarvisClientError.invalidURL(toolName: toolName)
            }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let apiKey = JarvisConfiguration.apiKey
            if apiKey.isEmpty == false {
                request.setValue(apiKey, forHTTPHeaderField: "X-Jarvis-Key")
            }
            let operatorSecret = JarvisConfiguration.operatorSecret
            if operatorSecret.isEmpty == false {
                request.setValue(operatorSecret, forHTTPHeaderField: "x-operator-secret")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    continue
                }

                if http.statusCode == 404, path != paths.last {
                    continue
                }

                return JarvisHTTPResponse(statusCode: http.statusCode, data: data)
            } catch {
                lastNetworkError = true
            }
        }

        if lastNetworkError {
            throw JarvisClientError.unreachable(toolName: toolName)
        }
        throw JarvisClientError.unreachable(toolName: toolName)
    }
}

private struct JarvisHTTPResponse {
    let statusCode: Int
    let data: Data

    var bodyText: String {
        String(decoding: data, as: UTF8.self)
    }

    var bodyTextTruncated: String {
        OutputLimits.truncateShellStdout(bodyText)
    }
}

private enum JarvisClientError: Error {
    case unreachable(toolName: String)
    case invalidURL(toolName: String)
}

private extension JarvisClientError {
    var toolName: String {
        switch self {
        case .unreachable(let toolName), .invalidURL(let toolName):
            return toolName
        }
    }
}

private struct JarvisResponseEnvelope: Decodable {
    let fields: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        fields = (try? container.decode([String: JSONValue].self)) ?? [:]
    }

    init(data: Data) {
        fields = (try? JSONDecoder().decode(JarvisResponseEnvelope.self, from: data).fields) ?? [:]
    }

    func string(for keys: [String]) -> String? {
        for key in keys {
            if let value = fields[key]?.stringValue, value.isEmpty == false {
                return value
            }
            if let value = fields[key] {
                switch value {
                case .number(let number):
                    return PhoneTool.formatNumber(number)
                case .bool(let bool):
                    return bool ? "true" : "false"
                case .string(let string) where string.isEmpty == false:
                    return string
                default:
                    continue
                }
            }
        }
        return nil
    }

    func double(for keys: [String]) -> Double? {
        for key in keys {
            guard let value = fields[key] else { continue }
            switch value {
            case .number(let number):
                return number
            case .string(let string):
                if let parsed = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return parsed
                }
            default:
                continue
            }
        }
        return nil
    }
}
