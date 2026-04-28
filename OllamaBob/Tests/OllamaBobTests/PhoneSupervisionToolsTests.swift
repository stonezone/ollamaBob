import XCTest
@testable import OllamaBob

@MainActor
final class PhoneSupervisionToolsTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Reset the mock to a known fixture state before each test
        JarvisCallClientMock.shared.reset()
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

    // MARK: - phone_inject on HTTP stub (notImplemented path)

    func testPhoneInjectOnHTTPStubReturnsNotImplementedError() async {
        // Directly exercise the HTTP stub path (production default)
        let stub = JarvisCallClientHTTP()
        do {
            _ = try await stub.inject(callID: "any_id", text: "test injection")
            XCTFail("Expected notImplemented")
        } catch let error as JarvisCallClientError {
            XCTAssertEqual(error, .notImplemented)
            // Verify the localizedDescription surfaces correctly
            XCTAssertTrue(error.localizedDescription.contains("Phase 4b"), error.localizedDescription)
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

    func testNewPhoneToolsAreRegisteredInRegistry() {
        let registry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertTrue(registry.has("phone_list_calls"), "phone_list_calls should be registered")
        XCTAssertTrue(registry.has("phone_get_transcript"), "phone_get_transcript should be registered")
        XCTAssertTrue(registry.has("phone_inject"), "phone_inject should be registered")
    }
}
