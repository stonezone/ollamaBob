import Foundation
import AppKit
import Network

enum JarvisWebhookEventName: String, Equatable, Sendable {
    case callEnded = "call.ended"
    case actionItemsReady = "call.action-items.ready"
}

struct JarvisWebhookEvent: Equatable, Sendable {
    let name: JarvisWebhookEventName
    let callID: String
}

enum JarvisWebhookParseError: Error, Equatable {
    case incomplete
    case unsupportedRequest
    case missingContentLength
    case invalidContentLength
    case invalidBody
    case unsupportedEvent
    case missingCallID
}

enum JarvisWebhookHTTPParser {
    private static let endpointPath = "/jarvis-webhook"
    private static let maxBodyBytes = 64 * 1024

    static func parse(_ data: Data) throws -> JarvisWebhookEvent {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            throw JarvisWebhookParseError.incomplete
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw JarvisWebhookParseError.unsupportedRequest
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw JarvisWebhookParseError.unsupportedRequest
        }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2,
              requestParts[0] == "POST",
              requestParts[1] == endpointPath else {
            throw JarvisWebhookParseError.unsupportedRequest
        }

        let contentLength = try contentLength(from: lines.dropFirst())
        guard contentLength <= maxBodyBytes else {
            throw JarvisWebhookParseError.invalidContentLength
        }

        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else {
            throw JarvisWebhookParseError.incomplete
        }
        let body = data[bodyStart..<(bodyStart + contentLength)]
        return try decodeEvent(from: Data(body))
    }

    static func decodeEvent(from body: Data) throws -> JarvisWebhookEvent {
        guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw JarvisWebhookParseError.invalidBody
        }
        guard let rawEvent = root["event"] as? String,
              let name = JarvisWebhookEventName(rawValue: rawEvent) else {
            throw JarvisWebhookParseError.unsupportedEvent
        }
        guard let callID = callID(from: root) else {
            throw JarvisWebhookParseError.missingCallID
        }
        return JarvisWebhookEvent(name: name, callID: callID)
    }

    private static func contentLength<S: Sequence>(from lines: S) throws -> Int where S.Element == String {
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            guard parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                continue
            }
            let raw = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(raw), value >= 0 else {
                throw JarvisWebhookParseError.invalidContentLength
            }
            return value
        }
        throw JarvisWebhookParseError.missingContentLength
    }

    private static func callID(from root: [String: Any]) -> String? {
        if let direct = firstString(in: root, keys: ["callID", "callId", "callSid"]) {
            return direct
        }
        if let data = root["data"] as? [String: Any],
           let nested = firstString(in: data, keys: ["callID", "callId", "callSid"]) {
            return nested
        }
        if let payload = root["payload"] as? [String: Any],
           let nested = firstString(in: payload, keys: ["callID", "callId", "callSid"]) {
            return nested
        }
        return nil
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false { return trimmed }
            }
        }
        return nil
    }
}

enum JarvisWebhookNotifications {
    static let callIDKey = "callID"

    static func post(_ event: JarvisWebhookEvent, center: NotificationCenter = .default) {
        let name: Notification.Name
        switch event.name {
        case .callEnded:
            name = .jarvisCallEndedWebhook
        case .actionItemsReady:
            name = .jarvisActionItemsReadyWebhook
        }
        center.post(name: name, object: nil, userInfo: [callIDKey: event.callID])
    }
}

extension Notification.Name {
    static let jarvisCallEndedWebhook = Notification.Name("com.ollamabob.jarvis.webhook.callEnded")
    static let jarvisActionItemsReadyWebhook = Notification.Name("com.ollamabob.jarvis.webhook.actionItemsReady")
}

protocol JarvisWebhookRegistrationClient: Sendable {
    func registerWebhook(url: URL, events: [String]) async throws -> String
    func unregisterWebhook(id: String) async throws
    func webhookSubscriberIDs() async throws -> Set<String>
}

final class JarvisWebhookListener: @unchecked Sendable {
    static let defaultPort: UInt16 = 3101
    static let defaultEvents = [
        JarvisWebhookEventName.callEnded.rawValue,
        JarvisWebhookEventName.actionItemsReady.rawValue
    ]

    private let client: JarvisWebhookRegistrationClient
    private let notificationCenter: NotificationCenter
    private let portRange: ClosedRange<UInt16>
    private let queue = DispatchQueue(label: "com.ollamabob.jarvis.webhook")
    private var listener: NWListener?
    private var subscriberID: String?
    private var registrationURL: URL?
    private var registrationTask: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?
    private let lock = NSLock()

    init(
        client: JarvisWebhookRegistrationClient = JarvisCallClientHTTP(),
        notificationCenter: NotificationCenter = .default,
        portRange: ClosedRange<UInt16> = defaultPort...(defaultPort + 9)
    ) {
        self.client = client
        self.notificationCenter = notificationCenter
        self.portRange = portRange
    }

    func startIfConfigured() {
        guard PhoneTool.isConfigured else { return }
        start()
    }

    func start() {
        lock.lock()
        let alreadyStarted = listener != nil || registrationTask != nil
        lock.unlock()
        guard alreadyStarted == false else { return }

        registrationTask = Task { [weak self] in
            await self?.bindAndRegister()
        }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.stop() }
        }
    }

    func stop() async {
        registrationTask?.cancel()
        registrationTask = nil
        listener?.cancel()
        listener = nil
        if let observer = terminateObserver {
            NotificationCenter.default.removeObserver(observer)
            terminateObserver = nil
        }
        if let subscriberID {
            try? await client.unregisterWebhook(id: subscriberID)
            self.subscriberID = nil
        }
    }

    private func bindAndRegister() async {
        do {
            let bound = try await bindFirstAvailablePort()
            listener = bound.listener
            registrationURL = bound.url

            await ensureRegistered()
            await monitorRegistration()
        } catch {
            listener?.cancel()
            listener = nil
        }
    }

    private func bindFirstAvailablePort() async throws -> (listener: NWListener, url: URL) {
        var lastError: Error?
        for port in portRange {
            do {
                let listener = try makeListener(port: port)
                let ready = try await waitForReady(listener)
                let resolvedPort = ready.port?.rawValue ?? port
                let url = URL(string: "http://127.0.0.1:\(resolvedPort)/jarvis-webhook")!
                return (ready, url)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? JarvisCallClientError.daemonUnreachable
    }

    private func makeListener(port: UInt16) throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return listener
    }

    private func waitForReady(_ listener: NWListener) async throws -> NWListener {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWListener, Error>) in
            let readyBox = ListenerReadyContinuation(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    readyBox.resume(returning: listener)
                case .failed(let error):
                    readyBox.resume(throwing: error)
                case .cancelled:
                    readyBox.resume(throwing: JarvisCallClientError.daemonUnreachable)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                self.send(status: 400, on: connection)
                return
            }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }
            do {
                let event = try JarvisWebhookHTTPParser.parse(nextBuffer)
                JarvisWebhookNotifications.post(event, center: self.notificationCenter)
                self.send(status: 204, on: connection)
            } catch JarvisWebhookParseError.incomplete where nextBuffer.count < (64 * 1024) {
                self.receive(on: connection, buffer: nextBuffer)
            } catch {
                self.send(status: 400, on: connection)
            }
        }
    }

    private func send(status: Int, on connection: NWConnection) {
        let reason = status == 204 ? "No Content" : "Bad Request"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func monitorRegistration() async {
        while Task.isCancelled == false {
            do {
                try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            } catch {
                return
            }
            await ensureRegistered()
        }
    }

    private func ensureRegistered() async {
        guard let registrationURL else { return }
        if let subscriberID {
            do {
                let ids = try await client.webhookSubscriberIDs()
                if ids.contains(subscriberID) { return }
            } catch {
                // Daemon may be down during restart; fall through and try a
                // fresh registration below. If that fails too, next interval
                // retries without taking down the listener.
            }
        }

        do {
            subscriberID = try await client.registerWebhook(
                url: registrationURL,
                events: Self.defaultEvents
            )
        } catch {
            // Keep the localhost listener alive; daemon startup/restart races
            // are recovered by the next monitor tick.
        }
    }
}

private final class ListenerReadyContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NWListener, Error>?

    init(_ continuation: CheckedContinuation<NWListener, Error>) {
        self.continuation = continuation
    }

    func resume(returning listener: NWListener) {
        let continuation = take()
        continuation?.resume(returning: listener)
    }

    func resume(throwing error: Error) {
        let continuation = take()
        continuation?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<NWListener, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let current = continuation
        continuation = nil
        return current
    }
}
