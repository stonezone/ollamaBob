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

    // MARK: - v1.0.55: actionItemsStatus tri-state + recordingUrl

    func testMockActionItemsIncludeRecordingUrl() async throws {
        // v1.0.55 daemon-side change: GET /call/action-items/:id now
        // returns an optional `recordingUrl` field. Mock mirrors that
        // so DEBUG UI can exercise the Play button without spinning
        // up the real daemon.
        let mock = JarvisCallClientMock.shared
        mock.reset()
        let items = try await mock.actionItems(callID: JarvisCallClientMock.fixtureCallID)
        let unwrapped = try XCTUnwrap(items)
        XCTAssertNotNil(unwrapped.recordingUrl, "mock should populate recordingUrl for fixture call")
        XCTAssertTrue(unwrapped.recordingUrl?.hasPrefix("http://") ?? false)
    }

    func testMockActionItemsStatusIsReadyForFixtureCall() async throws {
        // v1.0.55: daemon emits actionItemsStatus on /call/status/:id;
        // mock returns `.ready` for any call it has a transcript for
        // so the LiveCallView's status-aware branching path can be
        // exercised end-to-end.
        let mock = JarvisCallClientMock.shared
        mock.reset()
        let status = try await mock.actionItemsStatus(callID: JarvisCallClientMock.fixtureCallID)
        XCTAssertEqual(status, .ready)
    }

    func testMockActionItemsStatusIsUnknownForUnseenCallID() async throws {
        // Negative case: the mock has no record of arbitrary callIDs,
        // so it falls back to `.unknown` (the conservative state that
        // tells the UI to use legacy fetch behavior). Distinguishes
        // "I don't know about this call" from "I know it has no items".
        let mock = JarvisCallClientMock.shared
        mock.reset()
        let status = try await mock.actionItemsStatus(callID: "nonexistent-call-id")
        XCTAssertEqual(status, .unknown)
    }

    func testJarvisActionItemsStatusRawValuesMatchDaemonContract() {
        // The daemon ships these exact strings in the
        // actionItemsStatus field. If either side renames a state,
        // this test catches it before the UI silently falls into
        // `.unknown` and degrades to legacy behavior.
        XCTAssertEqual(JarvisActionItemsStatus.pending.rawValue, "pending")
        XCTAssertEqual(JarvisActionItemsStatus.ready.rawValue, "ready")
        XCTAssertEqual(JarvisActionItemsStatus.skipped.rawValue, "skipped")
        XCTAssertEqual(JarvisActionItemsStatus.failed.rawValue, "failed")
    }
}
