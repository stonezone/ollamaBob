import Foundation
import XCTest
@testable import OllamaBob

final class JarvisPhoneV1Tests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        URLProtocol.unregisterClass(JarvisURLProtocol.self)
        JarvisURLProtocol.requestHandler = nil
        URLProtocol.registerClass(JarvisURLProtocol.self)
    }

    override func tearDownWithError() throws {
        JarvisURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(JarvisURLProtocol.self)
        try super.tearDownWithError()
    }

    func testJarvisPhonePreflightWarningIsNonFatal() async {
        let status = await Preflight.run(
            clientReachable: { true },
            installedModels: { [AppConfig.primaryModel] },
            braveKeyPresent: true,
            jarvisPhoneEnabled: true,
            jarvisAPIKeyPresent: false,
            jarvisOperatorSecretPresent: false,
            databaseWritable: { true },
            sandboxDisabled: { true }
        )

        XCTAssertTrue(status.canLaunch)
        XCTAssertTrue(status.jarvisPhoneEnabled)
        XCTAssertFalse(status.jarvisAPIKeyPresent)
        XCTAssertFalse(status.jarvisOperatorSecretPresent)
    }

    func testPhoneToolExecuteSendsAuthenticatedCallRequestAndSummarizesResponse() async {
        let override = JarvisDefaultsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = override }

        JarvisURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/call/initiate")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Jarvis-Key"), "unit-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-operator-secret"), "unit-test-operator")

            let body = try XCTUnwrap(Self.requestBodyData(from: request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body, options: []) as? [String: Any])
            XCTAssertEqual(object["caller"] as? String, "bob")
            XCTAssertEqual(object["to"] as? String, "Pickup Vendor")
            XCTAssertEqual(object["missionBrief"] as? String, "Ask about the pickup")
            XCTAssertEqual(object["maxDurationSeconds"] as? Int, 420)

            let responseJSON = Data(#"{"callSid":"call_123","status":"queued","message":"Queued"}"#.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseJSON)
        }
        defer { JarvisURLProtocol.requestHandler = nil }

        let result = await PhoneTool.execute(persona: "jarvis", to: "Pickup Vendor", purpose: "Ask about the pickup", maxMinutes: 7)

        XCTAssertTrue(result.success, result.content)
        XCTAssertEqual(result.toolName, "phone_call")
        XCTAssertTrue(result.content.contains("callSid=call_123"), result.content)
        XCTAssertTrue(result.content.contains("persona=bob"), result.content)
        XCTAssertTrue(result.content.contains("to=Pickup Vendor"), result.content)
        XCTAssertTrue(result.content.contains("status=queued"), result.content)
        XCTAssertTrue(result.content.contains("maxMinutes=7"), result.content)
        XCTAssertTrue(result.content.contains("Queued"), result.content)
    }

    func testPhoneToolDefaultsUnknownPersonaToBob() async {
        let override = JarvisDefaultsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = override }

        JarvisURLProtocol.requestHandler = { request in
            let body = try XCTUnwrap(Self.requestBodyData(from: request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body, options: []) as? [String: Any])
            XCTAssertEqual(object["caller"] as? String, "bob")
            XCTAssertEqual(object["to"] as? String, "+18082925669")
            XCTAssertEqual(object["missionBrief"] as? String, "Ask how the day is going")

            let responseJSON = Data(#"{"callSid":"call_456","status":"queued","message":"Queued"}"#.utf8)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseJSON)
        }
        defer { JarvisURLProtocol.requestHandler = nil }

        let result = await PhoneTool.execute(
            persona: "friend",
            to: "808-292-5669",
            purpose: "Ask how the day is going",
            maxMinutes: nil
        )

        XCTAssertTrue(result.success, result.content)
        XCTAssertTrue(result.content.contains("persona=bob"), result.content)
        XCTAssertTrue(result.content.contains("callSid=call_456"), result.content)
    }

    func testPhoneToolNormalizesNorthAmericanNumbersBeforeSending() {
        XCTAssertEqual(PhoneTool.resolvedDestinationLabel("8082925669"), "+18082925669")
        XCTAssertEqual(PhoneTool.resolvedDestinationLabel("1-808-292-5669"), "+18082925669")
        XCTAssertEqual(PhoneTool.resolvedDestinationLabel("(808) 292-5669"), "+18082925669")
    }

    func testPhoneToolExtractsEmbeddedPhoneNumbersBeforeFallingBackToContactLookup() {
        XCTAssertEqual(PhoneTool.resolvedDestinationLabel("me=zack=8082925669"), "+18082925669")
        XCTAssertEqual(
            PhoneTool.resolvedDestinationLabel("call me at 808-292-5669 please"),
            "+18082925669"
        )
    }

    func testPhoneToolResolvesLocalAliasesFromAddressBook() {
        let lookup: (String) -> String? = { alias in
            switch alias {
            case "me", "zack":
                return "+18082925669"
            case "glennel":
                return "+18082197398"
            default:
                return nil
            }
        }

        XCTAssertEqual(
            PhoneTool.resolvedDestinationLabel("me", addressBookLookup: lookup),
            "+18082925669"
        )
        XCTAssertEqual(
            PhoneTool.resolvedDestinationLabel("Glennel", addressBookLookup: lookup),
            "+18082197398"
        )
    }

    func testPhoneToolRejectsMissingInputsBeforeNetwork() async {
        let result = await PhoneTool.execute(persona: " ", to: "", purpose: "", maxMinutes: nil)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.toolName, "phone_call")
        XCTAssertTrue(result.content.contains("Missing destination or purpose."))
    }

    func testPhoneToolHangupAndStatusRequestsSummarizeJarvisResponses() async {
        let override = JarvisDefaultsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = override }

        JarvisURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                XCTFail("Missing request URL")
                throw URLError(.badURL)
            }

            switch url.path {
            case "/call/hangup/call_123":
                let responseJSON = Data(#"{"callSid":"call_123","status":"ended","detail":"Hung up"}"#.utf8)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, responseJSON)

            case "/call/status/call_123":
                let responseJSON = Data(#"{"callSid":"call_123","status":"active","durationSeconds":61.5,"costUsd":0.42,"message":"Still in progress"}"#.utf8)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, responseJSON)

            default:
                XCTFail("Unexpected path: \(url.path)")
                throw URLError(.badURL)
            }
        }
        defer { JarvisURLProtocol.requestHandler = nil }

        let hangup = await PhoneTool.hangup(callID: "call_123")
        XCTAssertTrue(hangup.success, hangup.content)
        XCTAssertEqual(hangup.toolName, "phone_hangup")
        XCTAssertTrue(hangup.content.contains("Hangup sent: callSid=call_123, status=ended"), hangup.content)
        XCTAssertTrue(hangup.content.contains("Hung up"), hangup.content)

        let status = await PhoneTool.status(callID: "call_123")
        XCTAssertTrue(status.success, status.content)
        XCTAssertEqual(status.toolName, "phone_status")
        XCTAssertTrue(status.content.contains("Call status: callSid=call_123, status=active"), status.content)
        XCTAssertTrue(status.content.contains("duration=61.50s"), status.content)
        XCTAssertTrue(status.content.contains("cost=$0.42"), status.content)
        XCTAssertTrue(status.content.contains("Still in progress"), status.content)
    }

    @MainActor
    func testJarvisPhoneRegistryAndApprovalContractsWhenToolEntriesExist() throws {
        let phoneToolNames = ["phone_call", "phone_hangup", "phone_status"]
        guard Self.phoneToolEntriesExist(named: phoneToolNames) else {
            throw XCTSkip("Jarvis phone tool entries are not present yet.")
        }

        let settings = AppSettings.shared
        let originalEnabled = settings.jarvisPhoneEnabled
        let originalKey = settings.jarvisAPIKey
        let originalOperatorSecret = settings.jarvisOperatorSecret
        defer {
            settings.jarvisPhoneEnabled = originalEnabled
            settings.jarvisAPIKey = originalKey
            settings.jarvisOperatorSecret = originalOperatorSecret
        }

        settings.jarvisPhoneEnabled = false
        settings.jarvisAPIKey = ""
        settings.jarvisOperatorSecret = ""

        let disabledRegistry = ToolRegistry(braveKeyAvailable: false)
        for name in phoneToolNames {
            XCTAssertFalse(disabledRegistry.has(name), "\(name) should stay out of the registry until Jarvis is enabled")
        }

        settings.jarvisPhoneEnabled = true
        settings.jarvisAPIKey = "local-test-key"
        settings.jarvisOperatorSecret = "local-operator-secret"

        let enabledRegistry = ToolRegistry(braveKeyAvailable: false)
        for name in phoneToolNames {
            XCTAssertTrue(enabledRegistry.has(name), "\(name) should become visible once Jarvis is enabled")
        }
        XCTAssertTrue(enabledRegistry.validateArgs("phone_call", ["to": "Glennel", "purpose": "Pickup"]))

        settings.jarvisOperatorSecret = ""
        let missingOperatorRegistry = ToolRegistry(braveKeyAvailable: false)
        for name in phoneToolNames {
            XCTAssertFalse(missingOperatorRegistry.has(name), "\(name) should stay hidden until the operator secret is configured")
        }

        settings.jarvisOperatorSecret = "local-operator-secret"

        XCTAssertEqual(
            ApprovalPolicy.check(
                toolName: "phone_call",
                arguments: [
                    "persona": "jarvis",
                    "to": "Glennel",
                    "purpose": "Ask about the pickup",
                    "max_minutes": 10
                ]
            ),
            .modal
        )
        XCTAssertEqual(
            ApprovalPolicy.check(toolName: "phone_hangup", arguments: ["call_id": "call_123"]),
            .none
        )
        XCTAssertEqual(
            ApprovalPolicy.check(toolName: "phone_status", arguments: ["call_id": "call_123"]),
            .none
        )
    }

    @MainActor
    func testPhoneRulesDefaultPersonaToBobInPromptAndCatalog() throws {
        let settings = AppSettings.shared
        let originalEnabled = settings.jarvisPhoneEnabled
        let originalKey = settings.jarvisAPIKey
        let originalOperatorSecret = settings.jarvisOperatorSecret
        defer {
            settings.jarvisPhoneEnabled = originalEnabled
            settings.jarvisAPIKey = originalKey
            settings.jarvisOperatorSecret = originalOperatorSecret
        }

        settings.jarvisPhoneEnabled = true
        settings.jarvisAPIKey = "local-test-key"
        settings.jarvisOperatorSecret = "local-operator-secret"

        let prompt = BobOperatingRules.systemPrompt
        XCTAssertTrue(prompt.contains("omit `persona` or set it to `bob`"), prompt)
        XCTAssertTrue(prompt.contains("Never invent unsupported caller labels"), prompt)
        XCTAssertTrue(prompt.contains("If the user says `call me`, pass `to` as `me`"), prompt)
        XCTAssertTrue(prompt.contains("If the user gives a plain local number like `8082925669`"), prompt)

        let catalog = try ToolCatalog.loadFromBundle()
        let phoneEntry = try XCTUnwrap(catalog.tools.first { $0.name == "phone_call" })
        XCTAssertTrue(phoneEntry.whenToUse.contains("`me`"))
    }

    func testPhoneToolDistinguishesOperatorAndCallAuthFailures() async {
        let override = JarvisDefaultsScope(apiKey: "unit-test-key", operatorSecret: "unit-test-operator")
        defer { _ = override }

        JarvisURLProtocol.requestHandler = { request in
            // jarvis-phone-service intentionally uses two different 401 bodies:
            // outer operator auth => "Unauthorized", inner call auth => "unauthorized".
            let operatorAuth = request.value(forHTTPHeaderField: "x-operator-secret")
            let responseBody: String
            if operatorAuth == "unit-test-operator" {
                responseBody = #"{"error":"unauthorized"}"#
            } else {
                responseBody = #"{"error":"Unauthorized"}"#
            }
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responseBody.utf8))
        }
        defer { JarvisURLProtocol.requestHandler = nil }

        let callAuthFailure = await PhoneTool.execute(
            persona: "bob",
            to: "8082925669",
            purpose: "Check in",
            maxMinutes: nil
        )
        XCTAssertFalse(callAuthFailure.success)
        XCTAssertTrue(callAuthFailure.content.contains("Jarvis call API key rejected"), callAuthFailure.content)
    }

    func testPhoneToolSurfacesOperatorAuthFailureWhenOuterSecretIsMissing() async {
        let override = JarvisDefaultsScope(apiKey: "unit-test-key", operatorSecret: nil)
        defer { _ = override }

        JarvisURLProtocol.requestHandler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "x-operator-secret"))
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"error":"Unauthorized"}"#.utf8))
        }
        defer { JarvisURLProtocol.requestHandler = nil }

        let result = await PhoneTool.execute(
            persona: "bob",
            to: "8082925669",
            purpose: "Check in and ask how your day is going",
            maxMinutes: nil
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("Jarvis operator secret rejected"), result.content)
    }

    private static func phoneToolEntriesExist(named names: [String]) -> Bool {
        let catalogNames = Set(BuiltinToolsCatalog.entries.map(\.name))
        return names.allSatisfy(catalogNames.contains)
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        let chunkSize = 1024
        var data = Data()
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

private final class JarvisDefaultsScope {
    private let originalAPIKey = UserDefaults.standard.string(forKey: AppSettings.jarvisAPIKeyKey)
    private let originalOperatorSecret = UserDefaults.standard.string(forKey: AppSettings.jarvisOperatorSecretKey)

    init(apiKey: String?, operatorSecret: String?) {
        apply(value: apiKey, forKey: AppSettings.jarvisAPIKeyKey)
        apply(value: operatorSecret, forKey: AppSettings.jarvisOperatorSecretKey)
    }

    deinit {
        apply(value: originalAPIKey, forKey: AppSettings.jarvisAPIKeyKey)
        apply(value: originalOperatorSecret, forKey: AppSettings.jarvisOperatorSecretKey)
    }

    private func apply(value: String?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

private final class JarvisURLProtocol: URLProtocol {
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
