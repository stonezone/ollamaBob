import GRDB
import XCTest
@testable import OllamaBob

final class ActivityEventDatabaseTests: XCTestCase {
    override func tearDown() {
        DatabaseManager.shared.resetForTesting()
        super.tearDown()
    }

    func testActivityEventRoundtrip() throws {
        try withDB { db, _ in
            let at = Date(timeIntervalSince1970: 1_776_000_000)
            let inserted = ActivityEvent(id: nil, timestamp: at, source: "tool", kind: "tool_call", detail: "read", conversationID: "c1", metadataJSON: #"{"tool":"read_file"}"#)
            let id = try db.appendActivityEvent(inserted)
            let fetched = try db.fetchActivityEvents(since: at.addingTimeInterval(-1), until: at.addingTimeInterval(1))
            XCTAssertGreaterThan(id, 0)
            XCTAssertEqual(fetched, [ActivityEvent(id: id, timestamp: at, source: "tool", kind: "tool_call", detail: "read", conversationID: "c1", metadataJSON: #"{"tool":"read_file"}"#)])
        }
    }

    func testActivityEventTimestampIndexUsedByRangeQuery() throws {
        try withDB { db, url in
            let at = Date(timeIntervalSince1970: 1_776_000_000)
            for offset in [-60.0, 0, 60.0] {
                _ = try db.appendActivityEvent(event(at.addingTimeInterval(offset), detail: offset == 0 ? "inside" : "outside"))
            }
            let fetched = try db.fetchActivityEvents(since: at.addingTimeInterval(-1), until: at.addingTimeInterval(1))
            XCTAssertEqual(fetched.map(\.detail), ["inside"])
            assertPlan(url, """
                EXPLAIN QUERY PLAN SELECT * FROM activity_event
                WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp DESC LIMIT ?
                """, [at.addingTimeInterval(-1).timeIntervalSince1970, at.addingTimeInterval(1).timeIntervalSince1970, 100], "idx_activity_event_timestamp")
        }
    }

    func testActivityEventSourceKindIndexUsedByFilterQuery() throws {
        try withDB { db, url in
            let at = Date(timeIntervalSince1970: 1_776_000_000)
            _ = try db.appendActivityEvent(event(at, source: "tool", kind: "tool_call", detail: "call"))
            _ = try db.appendActivityEvent(event(at, source: "tool", kind: "tool_result", detail: "result"))
            _ = try db.appendActivityEvent(event(at, source: "chat", kind: "user_message", detail: "message"))
            let fetched = try db.fetchActivityEvents(since: at.addingTimeInterval(-1), until: at.addingTimeInterval(1), source: "tool", kind: "tool_call")
            XCTAssertEqual(fetched.map(\.detail), ["call"])
            assertPlan(url, "EXPLAIN QUERY PLAN SELECT * FROM activity_event WHERE source = ? AND kind = ? LIMIT ?", ["tool", "tool_call", 100], "idx_activity_event_source_kind")
        }
    }

    func testActivityEventDetailTruncatedAt500Chars() throws {
        try withDB { db, _ in
            let at = Date(timeIntervalSince1970: 1_776_000_000)
            let detail = String(repeating: "a", count: 600)
            _ = try db.appendActivityEvent(event(at, detail: detail))
            let fetched = try db.fetchActivityEvents(since: at.addingTimeInterval(-1), until: at.addingTimeInterval(1))
            XCTAssertEqual(fetched.first?.detail, String(detail.prefix(500)))
        }
    }

    func testActivityEventMetadataJSONCappedAt1KB() throws {
        try withDB { db, _ in
            let at = Date(timeIntervalSince1970: 1_776_000_000)
            _ = try db.appendActivityEvent(event(at, detail: "accepted", metadataJSON: String(repeating: "a", count: 1_024)))
            XCTAssertThrowsError(try db.appendActivityEvent(event(at, detail: "rejected", metadataJSON: String(repeating: "b", count: 1_025))))
            let fetched = try db.fetchActivityEvents(since: at.addingTimeInterval(-1), until: at.addingTimeInterval(1))
            XCTAssertEqual(fetched.map(\.detail), ["accepted"])
        }
    }

    func testActivityEventConcurrentAppendIsThreadSafe() throws {
        try withDB { db, _ in
            let group = DispatchGroup()
            let lock = NSLock()
            var ids: [Int64] = []
            var errors: [Error] = []
            for index in 0..<10 {
                group.enter()
                DispatchQueue.global().async {
                    defer { group.leave() }
                    do {
                        let id = try db.appendActivityEvent(self.event(Date(timeIntervalSince1970: 1_776_000_000 + Double(index)), detail: "event-\(index)"))
                        lock.withLock { ids.append(id) }
                    } catch {
                        lock.withLock { errors.append(error) }
                    }
                }
            }
            XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
            XCTAssertTrue(errors.isEmpty, "Unexpected append errors: \(errors)")
            XCTAssertEqual(Set(ids).count, 10)
            let fetched = try db.fetchActivityEvents(since: Date(timeIntervalSince1970: 1_775_999_999), until: Date(timeIntervalSince1970: 1_776_000_100), limit: 20)
            XCTAssertEqual(fetched.count, 10)
        }
    }

    private func withDB(_ body: (DatabaseManager, URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("ollamabob.sqlite")
        defer { DatabaseManager.shared.resetForTesting(); try? FileManager.default.removeItem(at: dir) }
        try DatabaseManager.shared.setup(at: url)
        try body(DatabaseManager.shared, url)
    }

    private func event(_ at: Date, source: String = "tool", kind: String = "tool_call", detail: String, metadataJSON: String? = nil) -> ActivityEvent {
        ActivityEvent(id: nil, timestamp: at, source: source, kind: kind, detail: detail, conversationID: nil, metadataJSON: metadataJSON)
    }

    private func assertPlan(_ url: URL, _ sql: String, _ args: StatementArguments, _ index: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let queue = try DatabaseQueue(path: url.path)
            let details = try queue.read { db in try Row.fetchAll(db, sql: sql, arguments: args).compactMap { $0["detail"] as String? } }
            XCTAssertTrue(details.contains { $0.contains(index) }, "Expected \(index), got: \(details)", file: file, line: line)
        } catch {
            XCTFail("Failed to inspect query plan: \(error)", file: file, line: line)
        }
    }
}
