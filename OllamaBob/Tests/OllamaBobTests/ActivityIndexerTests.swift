import XCTest
@testable import OllamaBob

@MainActor
final class ActivityIndexerTests: XCTestCase {
    func testActivityIndexerNoOpWhenToggleOff() {
        ActivityIndexer.recordedEventsForTesting = []
        let indexer = ActivityIndexer(isEnabled: { false }) { _ in
            XCTFail("Appender should not run when timeline is disabled")
            return 0
        }

        indexer.recordToolCall(name: "read_file", success: true, conversationID: "c1")

        XCTAssertTrue(indexer.recordedEvents.isEmpty)
    }

    func testActivityIndexerRecordsToolCallWhenOn() {
        let indexer = ActivityIndexer.testRecordingIndexer()

        indexer.recordToolCall(name: "read_file", success: true, conversationID: "c1")

        XCTAssertEqual(indexer.recordedEvents.count, 1)
        XCTAssertEqual(indexer.recordedEvents.first?.source, "tool")
        XCTAssertEqual(indexer.recordedEvents.first?.kind, "tool_call")
        XCTAssertEqual(indexer.recordedEvents.first?.detail, "read_file succeeded")
        XCTAssertEqual(indexer.recordedEvents.first?.conversationID, "c1")
    }

    func testActivityIndexerRecordsUserMessage() {
        let indexer = ActivityIndexer.testRecordingIndexer()

        indexer.recordChatMessage(role: "user", conversationID: "c1", summary: "hello")

        XCTAssertEqual(indexer.recordedEvents.first?.source, "chat")
        XCTAssertEqual(indexer.recordedEvents.first?.kind, "user_message")
        XCTAssertEqual(indexer.recordedEvents.first?.detail, "hello")
    }

    func testActivityIndexerRecordsAssistantMessage() {
        let indexer = ActivityIndexer.testRecordingIndexer()

        indexer.recordChatMessage(role: "assistant", conversationID: "c1", summary: "done")

        XCTAssertEqual(indexer.recordedEvents.first?.source, "chat")
        XCTAssertEqual(indexer.recordedEvents.first?.kind, "assistant_message")
        XCTAssertEqual(indexer.recordedEvents.first?.detail, "done")
    }

    func testActivityIndexerCapsDetailLength() {
        let indexer = ActivityIndexer.testRecordingIndexer()
        let long = String(repeating: "x", count: 600)

        indexer.recordChatMessage(role: "assistant", conversationID: nil, summary: long)

        XCTAssertEqual(indexer.recordedEvents.first?.detail.count, 500)
    }

    func testActivityTimelineTogglePersists() {
        let settings = AppSettings.shared
        let original = settings.activityTimelineEnabled
        defer { settings.activityTimelineEnabled = original }

        settings.activityTimelineEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettings.activityTimelineEnabledKey))

        settings.activityTimelineEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettings.activityTimelineEnabledKey))
    }
}

@MainActor
private extension ActivityIndexer {
    var recordedEvents: [ActivityEvent] {
        Self.recordedEventsForTesting
    }

    static var recordedEventsForTesting: [ActivityEvent] {
        get { ActivityIndexerTestStore.events }
        set { ActivityIndexerTestStore.events = newValue }
    }

    static func testRecordingIndexer() -> ActivityIndexer {
        recordedEventsForTesting = []
        return ActivityIndexer(isEnabled: { true }) { event in
            recordedEventsForTesting.append(event)
            return Int64(recordedEventsForTesting.count)
        }
    }
}

@MainActor
private enum ActivityIndexerTestStore {
    static var events: [ActivityEvent] = []
}
