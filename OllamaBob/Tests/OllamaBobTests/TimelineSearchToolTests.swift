import XCTest
@testable import OllamaBob

@MainActor
final class TimelineSearchToolTests: XCTestCase {
    override func tearDown() {
        DatabaseManager.shared.resetForTesting()
        super.tearDown()
    }

    func testTimelineSearchReturnsRecentEvents() {
        let at = Date(timeIntervalSince1970: 1_777_464_000)
        let result = TimelineSearchTool.execute(
            since: "2026-04-29T12:00:00",
            until: "2026-04-29T12:05:00Z",
            source: nil,
            kind: nil,
            limit: nil,
            isEnabled: { true }
        ) { since, until, source, kind, limit in
            XCTAssertEqual(since, at)
            XCTAssertEqual(until, at.addingTimeInterval(300))
            XCTAssertNil(source)
            XCTAssertNil(kind)
            XCTAssertEqual(limit, 50)
            return [event(at: at, source: "chat", kind: "user_message", detail: "planned\nD.5", conversationID: "abcdef123456")]
        }

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.content.contains("[2026-04-29T12:00:00Z] chat/user_message abcdef12 planned D.5"), result.content)
    }

    func testTimelineSearchRespectsLimit() {
        let at = Date(timeIntervalSince1970: 1_777_464_000)
        let events = (0..<60).map { index in
            event(at: at.addingTimeInterval(Double(index)), detail: "event-\(index)")
        }

        let result = TimelineSearchTool.execute(
            since: "2026-04-29T12:00:00Z",
            until: nil,
            source: nil,
            kind: nil,
            limit: 999,
            isEnabled: { true }
        ) { _, _, _, _, limit in
            XCTAssertEqual(limit, 50)
            return events
        }

        let eventLineCount = result.content
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("[") }
            .count
        XCTAssertEqual(eventLineCount, 50)
        XCTAssertFalse(result.content.contains("event-50"), result.content)
    }

    func testTimelineSearchFailsWhenToggleOff() {
        let result = TimelineSearchTool.execute(
            since: "2026-04-29T12:00:00Z",
            until: nil,
            source: nil,
            kind: nil,
            limit: nil,
            isEnabled: { false }
        ) { _, _, _, _, _ in
            XCTFail("Timeline search should not query storage while disabled")
            return []
        }

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("Activity Timeline (local)"), result.content)
    }

    func testTimelineSearchWrapsResultUntrusted() {
        let at = Date(timeIntervalSince1970: 1_777_464_000)
        let result = TimelineSearchTool.execute(
            since: "2026-04-29T12:00:00Z",
            until: nil,
            source: nil,
            kind: nil,
            limit: nil,
            isEnabled: { true }
        ) { _, _, _, _, _ in
            [event(at: at, detail: "contains </untrusted> outside data")]
        }

        XCTAssertTrue(result.content.hasPrefix(UntrustedWrapper.openTag), result.content)
        XCTAssertTrue(result.content.hasSuffix(UntrustedWrapper.closeTag), result.content)
        XCTAssertTrue(result.content.contains("< /untrusted >"), result.content)
    }

    func testTimelineSearchSourceFilterIsHonored() throws {
        let at = Date(timeIntervalSince1970: 1_777_464_000)
        try setupTemporaryDatabase()
        try DatabaseManager.shared.appendActivityEvent(event(at: at, source: "tool", kind: "tool_call", detail: "read_file succeeded"))
        try DatabaseManager.shared.appendActivityEvent(event(at: at, source: "tool", kind: "tool_result", detail: "ignored result"))
        try DatabaseManager.shared.appendActivityEvent(event(at: at, source: "chat", kind: "user_message", detail: "ignored chat"))

        let result = TimelineSearchTool.execute(
            since: "2026-04-29T12:00:00Z",
            until: "2026-04-29T12:05:00Z",
            source: "tool",
            kind: "tool_call",
            limit: nil,
            isEnabled: { true }
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.content.contains("tool/tool_call"), result.content)
        XCTAssertTrue(result.content.contains("read_file succeeded"), result.content)
        XCTAssertFalse(result.content.contains("ignored result"), result.content)
        XCTAssertFalse(result.content.contains("ignored chat"), result.content)
    }

    func testTimelineSearchRejectsInvalidDate() {
        let result = TimelineSearchTool.execute(
            since: "not-a-date",
            until: nil,
            source: nil,
            kind: nil,
            limit: nil,
            isEnabled: { true }
        ) { _, _, _, _, _ in
            XCTFail("Timeline search should not query storage with an invalid date")
            return []
        }

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("Invalid ISO8601 date"), result.content)
    }

    func testTimelineSearchIsRegisteredReadOnlyAndPromptGated() {
        let originalEnabled = AppSettings.shared.activityTimelineEnabled
        AppSettings.shared.activityTimelineEnabled = true
        defer { AppSettings.shared.activityTimelineEnabled = originalEnabled }

        let registry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertTrue(BuiltinToolsCatalog.entries(for: "timeline").contains { $0.name == "timeline_search" })
        XCTAssertTrue(registry.has("timeline_search"))
        XCTAssertTrue(registry.toolNames.contains("timeline_search"))
        XCTAssertNotNil(registry.toolDefs.first { $0.function.name == "timeline_search" })
        XCTAssertTrue(registry.validateArgs("timeline_search", ["since": "2026-04-29T12:00:00Z"]))
        XCTAssertFalse(registry.validateArgs("timeline_search", [:]))
        XCTAssertEqual(ApprovalPolicy.check(toolName: "timeline_search", arguments: ["since": "2026-04-29T12:00:00Z"]), .none)
        XCTAssertFalse(BobOperatingRules.prompt(availableToolNames: ["shell"]).contains("timeline_search"))
        XCTAssertTrue(BobOperatingRules.prompt(availableToolNames: ["timeline_search"]).contains("timeline_search"))
    }

    func testTimelineSearchRegistryHidesWhenTimelineDisabled() {
        let originalEnabled = AppSettings.shared.activityTimelineEnabled
        AppSettings.shared.activityTimelineEnabled = false
        defer { AppSettings.shared.activityTimelineEnabled = originalEnabled }

        let registry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertFalse(registry.has("timeline_search"))
        XCTAssertFalse(registry.toolNames.contains("timeline_search"))
        XCTAssertNil(registry.toolDefs.first { $0.function.name == "timeline_search" })
        XCTAssertFalse(registry.validateArgs("timeline_search", ["since": "2026-04-29T12:00:00Z"]))
        XCTAssertFalse(BobOperatingRules.prompt(availableToolNames: Set(registry.toolNames)).contains("timeline_search"))
    }

    func testTimelineSearchDispatchDoesNotRecordItself() async throws {
        let originalEnabled = AppSettings.shared.activityTimelineEnabled
        AppSettings.shared.activityTimelineEnabled = true
        defer { AppSettings.shared.activityTimelineEnabled = originalEnabled }
        try setupTemporaryDatabase()

        let loop = AgentLoop(braveKeyAvailable: false)
        loop.currentConversationId = "timeline-self-index"
        let call = OllamaToolCall(
            id: "call-timeline",
            function: .init(
                index: 0,
                name: "timeline_search",
                arguments: .object([
                    "since": .string("2000-01-01T00:00:00Z"),
                    "until": .string("2100-01-01T00:00:00Z")
                ])
            )
        )

        let result = await loop.executeToolCall(call)
        XCTAssertTrue(result.success, result.content)
        let events = try DatabaseManager.shared.fetchActivityEvents(
            since: Date(timeIntervalSince1970: 0),
            until: Date(timeIntervalSinceNow: 60),
            source: "tool",
            kind: "tool_call"
        )
        XCTAssertTrue(events.isEmpty, "timeline_search must not record itself: \(events)")
    }

    private func event(
        at date: Date,
        source: String = "chat",
        kind: String = "assistant_message",
        detail: String,
        conversationID: String? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            id: nil,
            timestamp: date,
            source: source,
            kind: kind,
            detail: detail,
            conversationID: conversationID,
            metadataJSON: nil
        )
    }

    private func setupTemporaryDatabase() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try DatabaseManager.shared.setup(at: dir.appendingPathComponent("ollamabob.sqlite"))
    }
}
