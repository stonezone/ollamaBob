import XCTest
@testable import OllamaBob

final class JarvisCallMockTests: XCTestCase {

    // MARK: - Mock client fixture

    func testMockReturnsOneFixtureCall() async throws {
        let mock = JarvisCallClientMock.shared
        mock.reset()

        let calls = try await mock.listCalls()

        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.callID, JarvisCallClientMock.fixtureCallID)
        XCTAssertEqual(call.to, "Glennel")
        XCTAssertEqual(call.persona, "bob")
        XCTAssertEqual(call.status, "in_progress")
        XCTAssertGreaterThan(call.durationSeconds, 0)
    }

    func testMockTranscriptContainsCallerAndCallee() async throws {
        let mock = JarvisCallClientMock.shared
        mock.reset()

        let transcript = try await mock.transcript(callID: JarvisCallClientMock.fixtureCallID)

        XCTAssertEqual(transcript.callID, JarvisCallClientMock.fixtureCallID)
        XCTAssertFalse(transcript.lines.isEmpty, "Fixture transcript should have lines")
        let speakers = Set(transcript.lines.map(\.speaker))
        XCTAssertTrue(speakers.contains("caller"), "Expected a 'caller' line")
        XCTAssertTrue(speakers.contains("callee"), "Expected a 'callee' line")
    }

    func testMockInjectAppendsCallerLineAndAcknowledges() async throws {
        let mock = JarvisCallClientMock.shared
        mock.reset()

        let before = try await mock.transcript(callID: JarvisCallClientMock.fixtureCallID)
        let beforeCount = before.lines.count

        let result = try await mock.inject(callID: JarvisCallClientMock.fixtureCallID, text: "What time does it close?")

        XCTAssertTrue(result.acknowledged)
        XCTAssertEqual(result.callID, JarvisCallClientMock.fixtureCallID)

        let after = try await mock.transcript(callID: JarvisCallClientMock.fixtureCallID)
        XCTAssertEqual(after.lines.count, beforeCount + 1)

        let injectedLine = try XCTUnwrap(after.lines.last)
        XCTAssertEqual(injectedLine.speaker, "caller")
        XCTAssertEqual(injectedLine.text, "What time does it close?")
    }

    // HTTP route/auth coverage lives in PhoneSupervisionToolsTests.
}
