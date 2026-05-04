import Darwin
import XCTest
@testable import OllamaBob

@MainActor
final class PhoneSupervisionToolsTests: XCTestCase {
    private var originalMockedClient = false
    private var originalPhoneEnabled = false
    private var originalAPIKey = ""
    private var originalOperatorSecret = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        URLProtocol.unregisterClass(PhoneSupervisionURLProtocol.self)
        PhoneSupervisionURLProtocol.requestHandler = nil
        URLProtocol.registerClass(PhoneSupervisionURLProtocol.self)
    }

    override func tearDownWithError() throws {
        PhoneSupervisionURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(PhoneSupervisionURLProtocol.self)
        try super.tearDownWithError()
    }

    override func setUp() async throws {
        try await super.setUp()
        let settings = AppSettings.shared
        originalMockedClient = settings.useMockedJarvisClient
        originalPhoneEnabled = settings.jarvisPhoneEnabled
        originalAPIKey = settings.jarvisAPIKey
        originalOperatorSecret = settings.jarvisOperatorSecret
        settings.useMockedJarvisClient = true
        // Reset the mock to a known fixture state before each test
        JarvisCallClientMock.shared.reset()
    }

    override func tearDown() async throws {
        let settings = AppSettings.shared
        settings.useMockedJarvisClient = originalMockedClient
        settings.jarvisPhoneEnabled = originalPhoneEnabled
        settings.jarvisAPIKey = originalAPIKey
        settings.jarvisOperatorSecret = originalOperatorSecret
        try await super.tearDown()
    }

    // MARK: - phone_list_calls

    func testPhoneListCallsFormatsFixtureCorrectly() async {
        let result = await PhoneListCallsTool.execute()

        XCTAssertTrue(result.success, result.content)
        XCTAssertEqual(result.toolName, "phone_list_calls")
        XCTAssertTrue(result.content.contains("mock_call_001"), result.content)
        XCTAssertTrue(result.content.contains("Glennel"), result.content)
        XCTAssertTrue(result.content.contains("in_progress"), result.content)
    }

    // MARK: - phone_get_transcript

    func testPhoneTranscriptFormatsLinesWithSpeakerPrefixes() async {
        let result = await PhoneTranscriptTool.execute(callID: JarvisCallClientMock.fixtureCallID)

        XCTAssertTrue(result.success, result.content)
        XCTAssertEqual(result.toolName, "phone_get_transcript")
        XCTAssertTrue(result.content.contains("[caller]"), result.content)
        XCTAssertTrue(result.content.contains("[callee]"), result.content)
        XCTAssertTrue(result.content.contains("mock_call_001"), result.content)
    }

    // MARK: - phone_inject success path

    func testPhoneInjectSuccessOnMock() async {
        let result = await PhoneInjectTool.execute(
            callID: JarvisCallClientMock.fixtureCallID,
            text: "I'll circle back on that."
        )

        XCTAssertTrue(result.success, result.content)
        XCTAssertEqual(result.toolName, "phone_inject")
        XCTAssertTrue(result.content.contains("acknowledged=true"), result.content)
        XCTAssertTrue(result.content.contains("mock_call_001"), result.content)
    }

    // MARK: - HTTP client contract

    func testHTTPListCallsUsesJarvisSupervisionEndpointAndHeaders() async throws {
        let secrets = PhoneSupervisionSecretsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = secrets }

        PhoneSupervisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/calls/active")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Jarvis-Key"), "unit-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-operator-secret"), "unit-test-operator")

            let body = Data(#"{"active":[{"callSid":"call_123","caller":"bob","to":"+18082925669","status":"in-progress","startedAt":1700000000000}],"recent":[]}"#.utf8)
            return Self.response(request: request, statusCode: 200, body: body)
        }
        defer { PhoneSupervisionURLProtocol.requestHandler = nil }

        let calls = try await JarvisCallClientHTTP().listCalls()

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].callID, "call_123")
        XCTAssertEqual(calls[0].persona, "bob")
        XCTAssertEqual(calls[0].to, "+18082925669")
        XCTAssertEqual(calls[0].status, "in-progress")
    }

    func testHTTPListCallsIncludesRecentEndedCalls() async throws {
        let secrets = PhoneSupervisionSecretsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = secrets }

        PhoneSupervisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/calls/active")

            let body = Data(#"{"active":[{"callSid":"call_active","caller":"bob","to":"+18085550100","status":"in_progress","startedAt":1700000000000}],"recent":[{"callSid":"call_ended","caller":"bob","to":"+18085550101","status":"ended","startedAt":1700000100000,"durationSeconds":97}]}"#.utf8)
            return Self.response(request: request, statusCode: 200, body: body)
        }
        defer { PhoneSupervisionURLProtocol.requestHandler = nil }

        let calls = try await JarvisCallClientHTTP().listCalls()

        XCTAssertEqual(calls.map(\.callID), ["call_active", "call_ended"])
        XCTAssertEqual(calls[1].status, "ended")
        XCTAssertEqual(calls[1].durationSeconds, 97)
    }

    func testHTTPTranscriptMapsStatusTranscriptLines() async throws {
        let secrets = PhoneSupervisionSecretsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = secrets }

        PhoneSupervisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/call/status/call_123")

            let body = Data(#"{"callSid":"call_123","transcript":[{"role":"assistant","content":"Hi, this is Bob.","timestamp":1700000000000},{"role":"user","content":"Hello Bob.","timestamp":1700000001000}]}"#.utf8)
            return Self.response(request: request, statusCode: 200, body: body)
        }
        defer { PhoneSupervisionURLProtocol.requestHandler = nil }

        let transcript = try await JarvisCallClientHTTP().transcript(callID: "call_123")

        XCTAssertEqual(transcript.callID, "call_123")
        XCTAssertEqual(transcript.lines.count, 2)
        XCTAssertEqual(transcript.lines[0].speaker, "caller")
        XCTAssertEqual(transcript.lines[0].text, "Hi, this is Bob.")
        XCTAssertEqual(transcript.lines[1].speaker, "callee")
        XCTAssertEqual(transcript.lines[1].text, "Hello Bob.")
    }

    func testHTTPInjectPostsMessageAndAcknowledgesOk() async throws {
        let secrets = PhoneSupervisionSecretsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = secrets }

        PhoneSupervisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/call/call_123/message")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(Self.requestBodyData(from: request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["text"] as? String, "Please clarify the appointment time.")
            XCTAssertEqual(object["role"] as? String, "user")

            return Self.response(request: request, statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
        }
        defer { PhoneSupervisionURLProtocol.requestHandler = nil }

        let result = try await JarvisCallClientHTTP().inject(
            callID: "call_123",
            text: "Please clarify the appointment time."
        )

        XCTAssertEqual(result.callID, "call_123")
        XCTAssertTrue(result.acknowledged)
    }

    func testHTTPRegisterWebhookPostsURLAndEvents() async throws {
        let secrets = PhoneSupervisionSecretsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = secrets }

        PhoneSupervisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/call/webhooks/register")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Jarvis-Key"), "unit-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-operator-secret"), "unit-test-operator")

            let body = try XCTUnwrap(Self.requestBodyData(from: request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(object["url"] as? String, "http://127.0.0.1:3101/jarvis-webhook")
            XCTAssertEqual(object["events"] as? [String], ["call.ended", "call.action-items.ready"])

            return Self.response(request: request, statusCode: 200, body: Data(#"{"subscriberId":"sub_123"}"#.utf8))
        }
        defer { PhoneSupervisionURLProtocol.requestHandler = nil }

        let id = try await JarvisCallClientHTTP().registerWebhook(
            url: URL(string: "http://127.0.0.1:3101/jarvis-webhook")!,
            events: ["call.ended", "call.action-items.ready"]
        )

        XCTAssertEqual(id, "sub_123")
    }

    func testHTTPUnregisterWebhookDeletesSubscriber() async throws {
        let secrets = PhoneSupervisionSecretsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = secrets }

        PhoneSupervisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/call/webhooks/register/sub_123")
            return Self.response(request: request, statusCode: 204, body: Data())
        }
        defer { PhoneSupervisionURLProtocol.requestHandler = nil }

        try await JarvisCallClientHTTP().unregisterWebhook(id: "sub_123")
    }

    func testHTTPListWebhookSubscriberIDsUsesAdminEndpoint() async throws {
        let secrets = PhoneSupervisionSecretsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = secrets }

        PhoneSupervisionURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/call/webhooks")
            return Self.response(
                request: request,
                statusCode: 200,
                body: Data(#"{"subscribers":[{"id":"sub_123"},{"subscriberId":"sub_456"}]}"#.utf8)
            )
        }
        defer { PhoneSupervisionURLProtocol.requestHandler = nil }

        let ids = try await JarvisCallClientHTTP().webhookSubscriberIDs()

        XCTAssertEqual(ids, Set(["sub_123", "sub_456"]))
    }

    func testHTTPClientMapsUnauthorizedToAuthFailure() async {
        let secrets = PhoneSupervisionSecretsScope(apiKey: "bad-key", operatorSecret: "bad-operator")
        defer { _ = secrets }

        PhoneSupervisionURLProtocol.requestHandler = { request in
            Self.response(request: request, statusCode: 401, body: Data(#"{"error":"unauthorized"}"#.utf8))
        }
        defer { PhoneSupervisionURLProtocol.requestHandler = nil }

        do {
            _ = try await JarvisCallClientHTTP().listCalls()
            XCTFail("Expected authFailure")
        } catch let error as JarvisCallClientError {
            guard case .authFailure(let detail) = error else {
                return XCTFail("Expected authFailure, got \(error)")
            }
            XCTAssertTrue(detail.contains("401"), detail)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Approval policy contracts

    func testPhoneListCallsHasNoneApproval() {
        let level = ApprovalPolicy.check(toolName: "phone_list_calls", arguments: [:])
        XCTAssertEqual(level, .none)
    }

    func testPhoneTranscriptHasNoneApproval() {
        let level = ApprovalPolicy.check(toolName: "phone_get_transcript", arguments: ["call_id": "x"])
        XCTAssertEqual(level, .none)
    }

    func testPhoneInjectHasModalApproval() {
        let level = ApprovalPolicy.check(
            toolName: "phone_inject",
            arguments: ["call_id": "mock_call_001", "text": "hello"]
        )
        XCTAssertEqual(level, .modal)
    }

    // MARK: - ToolRegistry registration

    func testNewPhoneToolsAreHiddenUntilJarvisIsConfigured() {
        let settings = AppSettings.shared
        settings.jarvisPhoneEnabled = false
        settings.jarvisAPIKey = ""
        settings.jarvisOperatorSecret = ""

        let registry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertFalse(registry.has("phone_list_calls"), "phone_list_calls should stay hidden until Jarvis is configured")
        XCTAssertFalse(registry.has("phone_get_transcript"), "phone_get_transcript should stay hidden until Jarvis is configured")
        XCTAssertFalse(registry.has("phone_inject"), "phone_inject should stay hidden until Jarvis is configured")
    }

    func testNewPhoneToolsAreRegisteredWhenJarvisIsConfigured() {
        let settings = AppSettings.shared
        settings.jarvisPhoneEnabled = true
        settings.jarvisAPIKey = "local-test-key"
        settings.jarvisOperatorSecret = "local-operator-secret"

        let registry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertTrue(registry.has("phone_list_calls"), "phone_list_calls should be registered")
        XCTAssertTrue(registry.has("phone_get_transcript"), "phone_get_transcript should be registered")
        XCTAssertTrue(registry.has("phone_inject"), "phone_inject should be registered")
    }

    #if DEBUG
    func testJarvisCallClientFactoryUsesHTTPWhenMockToggleIsOff() {
        AppSettings.shared.useMockedJarvisClient = false
        XCTAssertTrue(JarvisCallClientFactory.current() is JarvisCallClientHTTP)
    }
    #endif

    func testOperatingRulesOnlyAdvertiseAvailablePhoneAndWebTools() {
        let minimalPrompt = BobOperatingRules.prompt(availableToolNames: ["shell"])
        XCTAssertFalse(minimalPrompt.contains("- web_search:"), minimalPrompt)
        XCTAssertFalse(minimalPrompt.contains("- phone_list_calls:"), minimalPrompt)
        XCTAssertFalse(minimalPrompt.contains("Call supervision:"), minimalPrompt)

        let availablePrompt = BobOperatingRules.prompt(availableToolNames: [
            "shell",
            "web_search",
            "phone_list_calls",
            "phone_get_transcript",
            "phone_inject"
        ])
        XCTAssertTrue(availablePrompt.contains("- web_search:"), availablePrompt)
        XCTAssertTrue(availablePrompt.contains("- phone_list_calls:"), availablePrompt)
        XCTAssertTrue(availablePrompt.contains("Call supervision:"), availablePrompt)
    }

    private static func response(
        request: URLRequest,
        statusCode: Int,
        body: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body)
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let chunkSize = 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: chunkSize)
            if read < 0 { return nil }
            if read == 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

private final class PhoneSupervisionSecretsScope {
    private static let jarvisAPIKeyEnvironmentName = "JARVIS_API_KEY"
    private static let operatorSecretEnvironmentName = "OPERATOR_API_SECRET"

    private let originalAPIKey = UserDefaults.standard.string(forKey: AppSettings.jarvisAPIKeyKey)
    private let originalOperatorSecret = UserDefaults.standard.string(forKey: AppSettings.jarvisOperatorSecretKey)
    private let originalAPIKeyEnvironment = ProcessInfo.processInfo.environment[jarvisAPIKeyEnvironmentName]
    private let originalOperatorSecretEnvironment = ProcessInfo.processInfo.environment[operatorSecretEnvironmentName]
    private let previousSecretOverride: SecretStoring?
    private let store = InMemorySecretStore()

    init(apiKey: String?, operatorSecret: String?) {
        previousSecretOverride = KeychainService.testOverride
        KeychainService.testOverride = store
        unsetenv(Self.jarvisAPIKeyEnvironmentName)
        unsetenv(Self.operatorSecretEnvironmentName)
        if let apiKey, !apiKey.isEmpty {
            try? store.write(apiKey, for: .jarvisAPIKey)
        }
        if let operatorSecret, !operatorSecret.isEmpty {
            try? store.write(operatorSecret, for: .jarvisOperatorSecret)
        }
        apply(value: apiKey, forKey: AppSettings.jarvisAPIKeyKey)
        apply(value: operatorSecret, forKey: AppSettings.jarvisOperatorSecretKey)
    }

    deinit {
        apply(value: originalAPIKey, forKey: AppSettings.jarvisAPIKeyKey)
        apply(value: originalOperatorSecret, forKey: AppSettings.jarvisOperatorSecretKey)
        restoreEnvironment(value: originalAPIKeyEnvironment, name: Self.jarvisAPIKeyEnvironmentName)
        restoreEnvironment(value: originalOperatorSecretEnvironment, name: Self.operatorSecretEnvironmentName)
        KeychainService.testOverride = previousSecretOverride
    }

    private func apply(value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func restoreEnvironment(value: String?, name: String) {
        if let value {
            setenv(name, value, 1)
        } else {
            unsetenv(name)
        }
    }
}

private final class PhoneSupervisionURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return url.scheme == "http"
            && url.host == "127.0.0.1"
            && url.port == 3100
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
