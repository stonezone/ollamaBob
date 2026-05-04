import Foundation

// MARK: - JarvisCallClientHTTP
// Production HTTP client for Jarvis call supervision.

final class JarvisCallClientHTTP: JarvisCallClient, JarvisWebhookRegistrationClient {

    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = JarvisCallClientHTTP.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func listCalls() async throws -> [JarvisCallSummary] {
        let data = try await send(method: "GET", path: "/calls/active", body: nil)
        let response = try decode(ActiveCallsResponse.self, from: data)
        let now = Date()
        return (response.active + response.recent).map { $0.summary(now: now) }
    }

    func transcript(callID: String) async throws -> JarvisTranscript {
        let trimmed = callID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw JarvisCallClientError.other("Missing call_id.")
        }

        let data = try await send(method: "GET", path: "/call/status/\(Self.pathSegment(trimmed))", body: nil)
        let response = try decode(CallStatusResponse.self, from: data)
        let resolvedID = response.callSid ?? response.callID ?? trimmed
        let lines = (response.transcript ?? []).map { line in
            JarvisTranscript.Line(
                speaker: line.speaker,
                text: line.content,
                at: line.date
            )
        }
        return JarvisTranscript(callID: resolvedID, lines: lines)
    }

    func actionItems(callID: String) async throws -> JarvisCallActionItems? {
        let trimmed = callID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw JarvisCallClientError.other("Missing call_id.")
        }
        do {
            let data = try await send(method: "GET", path: "/call/action-items/\(Self.pathSegment(trimmed))", body: nil)
            let response = try decode(ActionItemsResponse.self, from: data)
            return JarvisCallActionItems(
                callID: response.callSid ?? trimmed,
                outcome: response.outcome,
                followUps: response.followUps,
                facts: response.facts,
                topics: response.topics,
                recordingUrl: response.recordingUrl
            )
        } catch JarvisCallClientError.other(let detail) where detail.contains("404") {
            // Daemon returns 404 while the call is still in flight or when
            // extraction was skipped — treat as "no action items yet" and
            // let the UI render an empty state instead of erroring.
            return nil
        }
    }

    func actionItemsStatus(callID: String) async throws -> JarvisActionItemsStatus {
        let trimmed = callID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw JarvisCallClientError.other("Missing call_id.")
        }
        let data = try await send(method: "GET", path: "/call/status/\(Self.pathSegment(trimmed))", body: nil)
        let response = try decode(CallStatusResponse.self, from: data)
        guard let raw = response.actionItemsStatus,
              let parsed = JarvisActionItemsStatus(rawValue: raw) else {
            return .unknown
        }
        return parsed
    }

    func inject(callID: String, text: String) async throws -> JarvisInjectResult {
        let trimmedID = callID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedID.isEmpty == false else {
            throw JarvisCallClientError.other("Missing call_id.")
        }
        guard trimmedText.isEmpty == false else {
            throw JarvisCallClientError.other("Missing text.")
        }

        let request = InjectRequest(text: trimmedText, role: "user")
        let body = try JSONEncoder().encode(request)
        let data = try await send(method: "POST", path: "/call/\(Self.pathSegment(trimmedID))/message", body: body)
        let response = try decode(InjectResponse.self, from: data)
        return JarvisInjectResult(
            callID: trimmedID,
            acknowledged: response.ok ?? response.acknowledged ?? false,
            detail: response.message ?? response.detail
        )
    }

    func registerWebhook(url: URL, events: [String]) async throws -> String {
        let trimmedEvents = events
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard trimmedEvents.isEmpty == false else {
            throw JarvisCallClientError.other("Missing webhook events.")
        }
        let request = RegisterWebhookRequest(url: url.absoluteString, events: trimmedEvents)
        let body = try JSONEncoder().encode(request)
        let data = try await send(method: "POST", path: "/call/webhooks/register", body: body)
        let response = try decode(RegisterWebhookResponse.self, from: data)
        guard let id = response.resolvedID?.trimmingCharacters(in: .whitespacesAndNewlines),
              id.isEmpty == false else {
            throw JarvisCallClientError.other("Jarvis webhook registration returned no subscriber id.")
        }
        return id
    }

    func unregisterWebhook(id: String) async throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw JarvisCallClientError.other("Missing webhook subscriber id.")
        }
        _ = try await send(method: "DELETE", path: "/call/webhooks/register/\(Self.pathSegment(trimmed))", body: nil)
    }

    func webhookSubscriberIDs() async throws -> Set<String> {
        let data = try await send(method: "GET", path: "/call/webhooks", body: nil)
        let response = try decode(WebhookSubscribersResponse.self, from: data)
        return response.resolvedIDs
    }

    private func send(method: String, path: String, body: Data?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw JarvisCallClientError.other("Invalid Jarvis URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let apiKey = Self.jarvisAPIKey
        if apiKey.isEmpty == false {
            request.setValue(apiKey, forHTTPHeaderField: "X-Jarvis-Key")
        }
        let operatorSecret = Self.operatorSecret
        if operatorSecret.isEmpty == false {
            request.setValue(operatorSecret, forHTTPHeaderField: "x-operator-secret")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JarvisCallClientError.other("Jarvis returned a non-HTTP response.")
            }

            switch http.statusCode {
            case 200...299:
                return data
            case 401:
                throw JarvisCallClientError.authFailure("Jarvis supervision auth failed (401).")
            default:
                let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = raw?.isEmpty == false ? ": \(String(raw!.prefix(300)))" : ""
                throw JarvisCallClientError.other("Jarvis supervision HTTP \(http.statusCode)\(suffix)")
            }
        } catch let error as JarvisCallClientError {
            throw error
        } catch {
            throw JarvisCallClientError.daemonUnreachable
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw JarvisCallClientError.other("Failed to decode Jarvis response: \(error.localizedDescription)")
        }
    }

    private static var baseURLString: String {
        let value =
            ProcessInfo.processInfo.environment["JARVIS_BASE_URL"]
            ?? ProcessInfo.processInfo.environment["JARVIS_PHONE_BASE_URL"]
            ?? AppConfig.jarvisBaseURL
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var defaultBaseURL: URL {
        if let configured = URL(string: baseURLString) {
            return configured
        }
        if let appDefault = URL(string: AppConfig.jarvisBaseURL) {
            return appDefault
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 3100
        return components.url ?? URL(fileURLWithPath: "/")
    }

    private static var jarvisAPIKey: String {
        if let keychain = KeychainService.current.read(.jarvisAPIKey), !keychain.isEmpty {
            return keychain
        }
        let env = ProcessInfo.processInfo.environment["JARVIS_API_KEY"] ?? ""
        if !env.isEmpty { return env }
        return UserDefaults.standard.string(forKey: AppSettings.jarvisAPIKeyKey) ?? ""
    }

    private static var operatorSecret: String {
        if let keychain = KeychainService.current.read(.jarvisOperatorSecret), !keychain.isEmpty {
            return keychain
        }
        let env = ProcessInfo.processInfo.environment["OPERATOR_API_SECRET"] ?? ""
        if !env.isEmpty { return env }
        return UserDefaults.standard.string(forKey: AppSettings.jarvisOperatorSecretKey) ?? ""
    }

    private static func pathSegment(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}

private struct ActiveCallsResponse: Decodable {
    let active: [CallSummaryDTO]
    let recent: [CallSummaryDTO]

    private enum CodingKeys: String, CodingKey {
        case active
        case recent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.active = try container.decodeIfPresent([CallSummaryDTO].self, forKey: .active) ?? []
        self.recent = try container.decodeIfPresent([CallSummaryDTO].self, forKey: .recent) ?? []
    }
}

private struct CallSummaryDTO: Decodable {
    let callSid: String?
    let callID: String?
    let callId: String?
    let to: String?
    let caller: String?
    let persona: String?
    let status: String?
    let startedAt: Double?
    let durationSeconds: Int?

    func summary(now: Date) -> JarvisCallSummary {
        let started = Self.date(fromMilliseconds: startedAt)
        let duration = durationSeconds ?? max(0, Int(now.timeIntervalSince(started)))
        return JarvisCallSummary(
            callID: callSid ?? callID ?? callId ?? "unknown",
            to: to ?? "unknown",
            persona: caller ?? persona ?? "unknown",
            status: status ?? "unknown",
            startedAt: started,
            durationSeconds: duration
        )
    }

    private static func date(fromMilliseconds value: Double?) -> Date {
        guard let value, value > 0 else { return Date() }
        return Date(timeIntervalSince1970: value / 1000.0)
    }
}

private struct CallStatusResponse: Decodable {
    let callSid: String?
    let callID: String?
    let transcript: [TranscriptLineDTO]?
    /// v1.0.55: tri-state extraction status.
    /// `pending` | `ready` | `skipped` | `failed` | nil (unknown / pre-2026-05-04).
    let actionItemsStatus: String?
}

private struct TranscriptLineDTO: Decodable {
    let role: String
    let content: String
    let timestamp: Double?

    var speaker: String {
        switch role {
        case "assistant": return "caller"
        case "user": return "callee"
        default: return role
        }
    }

    var date: Date {
        guard let timestamp, timestamp > 0 else { return Date() }
        return Date(timeIntervalSince1970: timestamp / 1000.0)
    }
}

private struct InjectRequest: Encodable {
    let text: String
    let role: String
}

private struct RegisterWebhookRequest: Encodable {
    let url: String
    let events: [String]
}

private struct RegisterWebhookResponse: Decodable {
    let id: String?
    let subscriberId: String?
    let subscriberID: String?
    let subscriptionId: String?
    let subscriptionID: String?

    var resolvedID: String? {
        id ?? subscriberId ?? subscriberID ?? subscriptionId ?? subscriptionID
    }
}

private struct WebhookSubscribersResponse: Decodable {
    let subscribers: [WebhookSubscriberDTO]
    let webhooks: [WebhookSubscriberDTO]

    private enum CodingKeys: String, CodingKey {
        case subscribers
        case webhooks
    }

    init(from decoder: Decoder) throws {
        if let array = try? [WebhookSubscriberDTO](from: decoder) {
            self.subscribers = array
            self.webhooks = []
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.subscribers = try container.decodeIfPresent([WebhookSubscriberDTO].self, forKey: .subscribers) ?? []
        self.webhooks = try container.decodeIfPresent([WebhookSubscriberDTO].self, forKey: .webhooks) ?? []
    }

    var resolvedIDs: Set<String> {
        Set((subscribers + webhooks).compactMap { $0.resolvedID })
    }
}

private struct WebhookSubscriberDTO: Decodable {
    let id: String?
    let subscriberId: String?
    let subscriberID: String?
    let subscriptionId: String?
    let subscriptionID: String?

    var resolvedID: String? {
        let value = id ?? subscriberId ?? subscriberID ?? subscriptionId ?? subscriptionID
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct InjectResponse: Decodable {
    let ok: Bool?
    let acknowledged: Bool?
    let message: String?
    let detail: String?
}

private struct ActionItemsResponse: Decodable {
    let callSid: String?
    let outcome: String
    let followUps: [String]
    let facts: [String]
    let topics: [String]
    /// v1.0.55: optional MP3 URL added daemon-side in commit 31d9be7.
    let recordingUrl: String?
}
