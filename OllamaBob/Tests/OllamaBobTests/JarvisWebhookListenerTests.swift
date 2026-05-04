import Foundation
import XCTest
@testable import OllamaBob

final class JarvisWebhookListenerTests: XCTestCase {
    func testParserAcceptsReadyEventWithNestedCallSid() throws {
        let body = #"{"event":"call.action-items.ready","data":{"callSid":"call_123"}}"#
        let request = """
        POST /jarvis-webhook HTTP/1.1\r
        Host: 127.0.0.1:3101\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        let event = try JarvisWebhookHTTPParser.parse(Data(request.utf8))

        XCTAssertEqual(event.name, .actionItemsReady)
        XCTAssertEqual(event.callID, "call_123")
    }

    func testParserAcceptsCallEndedEventWithTopLevelCallID() throws {
        let body = #"{"event":"call.ended","callID":"call_ended"}"#
        let request = """
        POST /jarvis-webhook HTTP/1.1\r
        Host: 127.0.0.1:3101\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        let event = try JarvisWebhookHTTPParser.parse(Data(request.utf8))

        XCTAssertEqual(event.name, .callEnded)
        XCTAssertEqual(event.callID, "call_ended")
    }

    func testParserRejectsUnsupportedPath() {
        let body = #"{"event":"call.ended","callID":"call_ended"}"#
        let request = """
        POST /wrong HTTP/1.1\r
        Host: 127.0.0.1:3101\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        XCTAssertThrowsError(try JarvisWebhookHTTPParser.parse(Data(request.utf8))) { error in
            XCTAssertEqual(error as? JarvisWebhookParseError, .unsupportedRequest)
        }
    }

    func testNotificationPostingIncludesCallID() {
        let center = NotificationCenter()
        let expectation = expectation(description: "webhook notification")
        var observedCallID: String?

        let observer = center.addObserver(
            forName: .jarvisActionItemsReadyWebhook,
            object: nil,
            queue: nil
        ) { note in
            observedCallID = note.userInfo?[JarvisWebhookNotifications.callIDKey] as? String
            expectation.fulfill()
        }
        defer { center.removeObserver(observer) }

        JarvisWebhookNotifications.post(
            JarvisWebhookEvent(name: .actionItemsReady, callID: "call_123"),
            center: center
        )

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(observedCallID, "call_123")
    }
}
