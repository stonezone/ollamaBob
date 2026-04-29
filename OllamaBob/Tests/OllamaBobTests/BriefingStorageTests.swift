import XCTest
@testable import OllamaBob

/// Tests for BriefingStorage CRUD via DatabaseManager.
final class BriefingStorageTests: XCTestCase {

    override func tearDown() {
        DatabaseManager.shared.resetForTesting()
        super.tearDown()
    }

    // MARK: - Helper

    private func withTemporaryDatabase(_ body: (DatabaseManager) throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbURL = tempDir.appendingPathComponent("briefing_storage_test.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try DatabaseManager.shared.setup(at: dbURL)
        try body(DatabaseManager.shared)
        DatabaseManager.shared.resetForTesting()
    }

    private func makeResult(
        summary: String = "Test summary",
        toolResults: [String] = ["[mail_check]\n<untrusted>ok</untrusted>"],
        success: Bool = true,
        runAt: Date = Date()
    ) -> BriefingResult {
        BriefingResult(
            id: 0,
            runAt: runAt,
            summary: summary,
            toolResults: toolResults,
            success: success
        )
    }

    // MARK: - Test 1: Append + fetch round-trip

    func testAppendAndFetchRoundTrip() throws {
        try withTemporaryDatabase { db in
            let result = makeResult(summary: "Morning briefing summary")
            let persisted = try db.appendBriefing(result)

            // Row id must be positive.
            XCTAssertGreaterThan(persisted.id, 0, "id should be assigned by the database")
            XCTAssertEqual(persisted.summary, "Morning briefing summary")
            XCTAssertTrue(persisted.success)

            // Fetch back.
            let all = try db.fetchRecentBriefings(limit: 10)
            XCTAssertEqual(all.count, 1)
            XCTAssertEqual(all[0].summary, "Morning briefing summary")
            XCTAssertEqual(all[0].toolResults, result.toolResults)
            XCTAssertTrue(all[0].success)
        }
    }

    // MARK: - Test 2: Limit cap

    func testLimitCapReturnsMostRecent() throws {
        try withTemporaryDatabase { db in
            // Insert 5 briefings with distinct summaries.
            var insertedRunAts: [Date] = []
            for i in 1...5 {
                let runAt = Date(timeIntervalSince1970: Double(i) * 1000)
                insertedRunAts.append(runAt)
                try db.appendBriefing(makeResult(summary: "Briefing \(i)", runAt: runAt))
            }

            // Ask for at most 3 — should get the 3 most recent.
            let results = try db.fetchRecentBriefings(limit: 3)
            XCTAssertEqual(results.count, 3, "Should return exactly the requested limit")

            // Results are newest-first.
            XCTAssertEqual(results[0].summary, "Briefing 5")
            XCTAssertEqual(results[1].summary, "Briefing 4")
            XCTAssertEqual(results[2].summary, "Briefing 3")
        }
    }

    // MARK: - Test 3: Date-range filter

    func testDateRangeFilterIncludesOnlyMatchingRows() throws {
        try withTemporaryDatabase { db in
            let base = Date(timeIntervalSince1970: 1_000_000)
            let early  = base
            let middle = Date(timeIntervalSince1970: base.timeIntervalSince1970 + 3600)   // +1h
            let late   = Date(timeIntervalSince1970: base.timeIntervalSince1970 + 7200)   // +2h

            try db.appendBriefing(makeResult(summary: "Early",  runAt: early))
            try db.appendBriefing(makeResult(summary: "Middle", runAt: middle))
            try db.appendBriefing(makeResult(summary: "Late",   runAt: late))

            // Ask for everything between early and middle (inclusive).
            let filtered = try db.fetchBriefings(since: early, until: middle, limit: 10)
            XCTAssertEqual(filtered.count, 2)
            let summaries = filtered.map(\.summary).sorted()
            XCTAssertTrue(summaries.contains("Early"))
            XCTAssertTrue(summaries.contains("Middle"))
            XCTAssertFalse(summaries.contains("Late"))
        }
    }

    // MARK: - Test 4: Success flag round-trip

    func testSuccessFalseRoundTrip() throws {
        try withTemporaryDatabase { db in
            let failedResult = makeResult(summary: "Failed run", success: false)
            let stored = try db.appendBriefing(failedResult)
            XCTAssertFalse(stored.success)

            let fetched = try db.fetchRecentBriefings(limit: 1)
            XCTAssertFalse(fetched[0].success)
        }
    }

    // MARK: - Test 5: Multiple tool results preserved

    func testMultipleToolResultsRoundTrip() throws {
        try withTemporaryDatabase { db in
            let tools = [
                "[mail_check]\n<untrusted>2 emails</untrusted>",
                "[weather]\n<untrusted>Sunny 72°F</untrusted>",
                "[list_facts]\n<untrusted>3 facts</untrusted>"
            ]
            let result = makeResult(summary: "Full briefing", toolResults: tools)
            try db.appendBriefing(result)

            let fetched = try db.fetchRecentBriefings(limit: 1)
            XCTAssertEqual(fetched[0].toolResults.count, 3)
            XCTAssertEqual(fetched[0].toolResults[0], tools[0])
            XCTAssertEqual(fetched[0].toolResults[1], tools[1])
            XCTAssertEqual(fetched[0].toolResults[2], tools[2])
        }
    }

    // MARK: - Test 6: Date range with no lower bound

    func testDateRangeOpenLowerBound() throws {
        try withTemporaryDatabase { db in
            let base = Date(timeIntervalSince1970: 2_000_000)
            let t1 = base
            let t2 = Date(timeIntervalSince1970: base.timeIntervalSince1970 + 1000)
            let t3 = Date(timeIntervalSince1970: base.timeIntervalSince1970 + 2000)

            try db.appendBriefing(makeResult(summary: "A", runAt: t1))
            try db.appendBriefing(makeResult(summary: "B", runAt: t2))
            try db.appendBriefing(makeResult(summary: "C", runAt: t3))

            // No lower bound — just until=t2.
            let results = try db.fetchBriefings(since: nil, until: t2, limit: 10)
            XCTAssertEqual(results.count, 2)
            let summaries = results.map(\.summary).sorted()
            XCTAssertEqual(summaries, ["A", "B"])
        }
    }
}
