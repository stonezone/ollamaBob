import Foundation
import XCTest
@testable import OllamaBob

@MainActor
final class JarvisPhoneV1Tests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(JarvisURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(JarvisURLProtocol.self)
        super.tearDown()
    }

    func testJarvisPhonePreflightWarningIsNonFatal() async {
        let status = await Preflight.run(
            clientReachable: { true },
            installedModels: { [AppConfig.primaryModel] },
            braveKeyPresent: true,
            jarvisPhoneEnabled: true,
            jarvisAPIKeyPresent: false,
            databaseWritable: { true },
            sandboxDisabled: { true }
        )

        XCTAssertTrue(status.canLaunch)
        XCTAssertTrue(status.jarvisPhoneEnabled)
        XCTAssertFalse(status.jarvisAPIKeyPresent)
    }

    func testPhoneToolExecuteSendsAuthenticatedCallRequestAndSummarizesResponse() async {
        let originalKey = UserDefaults.standard.string(forKey: AppSettings.jarvisAPIKeyKey)
        defer {
            if let originalKey {
                UserDefaults.standard.set(originalKey, forKey: AppSettings.jarvisAPIKeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppSettings.jarvisAPIKeyKey)
            }
        }

        UserDefaults.standard.set("unit-test-key", forKey: AppSettings.jarvisAPIKeyKey)

        JarvisURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "\(AppConfig.jarvisBaseURL)/call/initiate")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Jarvis-Key"), "unit-test-key")

            let body = try XCTUnwrap(Self.requestBodyData(from: request))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body, options: []) as? [String: Any])
            XCTAssertEqual(object["caller"] as? String, "bob")
            XCTAssertEqual(object["to"] as? String, "Glennel")
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

        let result = await PhoneTool.execute(persona: "jarvis", to: "Glennel", purpose: "Ask about the pickup", maxMinutes: 7)

        XCTAssertTrue(result.success, result.content)
        XCTAssertEqual(result.toolName, "phone_call")
        XCTAssertTrue(result.content.contains("callSid=call_123"), result.content)
        XCTAssertTrue(result.content.contains("persona=bob"), result.content)
        XCTAssertTrue(result.content.contains("to=Glennel"), result.content)
        XCTAssertTrue(result.content.contains("status=queued"), result.content)
        XCTAssertTrue(result.content.contains("maxMinutes=7"), result.content)
        XCTAssertTrue(result.content.contains("Queued"), result.content)
    }

    func testPhoneToolRejectsMissingInputsBeforeNetwork() async {
        let result = await PhoneTool.execute(persona: " ", to: "", purpose: "", maxMinutes: nil)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.toolName, "phone_call")
        XCTAssertTrue(result.content.contains("Missing persona, to, or purpose."))
    }

    func testPhoneToolHangupAndStatusRequestsSummarizeJarvisResponses() async {
        let originalKey = UserDefaults.standard.string(forKey: AppSettings.jarvisAPIKeyKey)
        defer {
            if let originalKey {
                UserDefaults.standard.set(originalKey, forKey: AppSettings.jarvisAPIKeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppSettings.jarvisAPIKeyKey)
            }
        }

        UserDefaults.standard.set("unit-test-key", forKey: AppSettings.jarvisAPIKeyKey)

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

    func testJarvisPhoneRegistryAndApprovalContractsWhenToolEntriesExist() throws {
        let phoneToolNames = ["phone_call", "phone_hangup", "phone_status"]
        guard Self.phoneToolEntriesExist(named: phoneToolNames) else {
            throw XCTSkip("Jarvis phone tool entries are not present yet.")
        }

        let settings = AppSettings.shared
        let originalEnabled = settings.jarvisPhoneEnabled
        let originalKey = settings.jarvisAPIKey
        defer {
            settings.jarvisPhoneEnabled = originalEnabled
            settings.jarvisAPIKey = originalKey
        }

        settings.jarvisPhoneEnabled = false
        settings.jarvisAPIKey = ""

        let disabledRegistry = ToolRegistry(braveKeyAvailable: false)
        for name in phoneToolNames {
            XCTAssertFalse(disabledRegistry.has(name), "\(name) should stay out of the registry until Jarvis is enabled")
        }

        settings.jarvisPhoneEnabled = true
        settings.jarvisAPIKey = "local-test-key"

        let enabledRegistry = ToolRegistry(braveKeyAvailable: false)
        for name in phoneToolNames {
            XCTAssertTrue(enabledRegistry.has(name), "\(name) should become visible once Jarvis is enabled")
        }

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
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: chunkSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
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
