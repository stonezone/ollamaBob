import XCTest
@testable import OllamaBob

final class ExecutionLogTests: XCTestCase {

    // MARK: - Helpers

    private func withTemporaryDatabase(_ body: (DatabaseManager) throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbURL = tempDir.appendingPathComponent("exec_log_test.sqlite", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try DatabaseManager.shared.setup(at: dbURL)
        try body(DatabaseManager.shared)
        DatabaseManager.shared.resetForTesting()
    }

    override func tearDown() {
        DatabaseManager.shared.resetForTesting()
        super.tearDown()
    }

    // MARK: - Test 1: Append → fetch round-trip

    func testAppendAndFetchRoundTrip() throws {
        try withTemporaryDatabase { manager in
            try manager.appendExecutionLog(
                toolName: "write_file",
                approvalLevel: .modal,
                summary: "Wrote 42 bytes to ~/test.txt",
                success: true,
                durationMs: 150
            )

            let rows = try manager.fetchExecutionLog(since: nil, until: nil, limit: 100)
            XCTAssertEqual(rows.count, 1)
            let entry = rows[0]
            XCTAssertEqual(entry.toolName, "write_file")
            XCTAssertEqual(entry.approvalLevel, .modal)
            XCTAssertEqual(entry.summary, "Wrote 42 bytes to ~/test.txt")
            XCTAssertTrue(entry.success)
            XCTAssertEqual(entry.durationMs, 150)
        }
    }

    // MARK: - Test 2: Date-range filter returns only matching rows

    func testDateRangeFilterReturnsMatchingRowsOnly() throws {
        try withTemporaryDatabase { manager in
            // Insert an "old" row with a timestamp 2 hours ago
            let twoHoursAgo = Date().addingTimeInterval(-7_200)
            let oneHourAgo  = Date().addingTimeInterval(-3_600)

            // We can't set the timestamp directly through the public API, so
            // we insert a row now and then insert another after a tiny sleep,
            // then use `since` to filter. Instead, let's exercise the since/until
            // parameters by doing two appends, one before and one after a cutoff.

            try manager.appendExecutionLog(
                toolName: "move_file",
                approvalLevel: .modal,
                summary: "Moved file A",
                success: true,
                durationMs: 10
            )

            // Use `since` set to 1 second from now — the already-inserted row
            // should be excluded.
            let futureCutoff = Date().addingTimeInterval(1)
            let rowsBefore = try manager.fetchExecutionLog(since: futureCutoff, until: nil, limit: 100)
            XCTAssertEqual(rowsBefore.count, 0, "Rows before the since cutoff should be excluded")

            // Use `since` set to 5 seconds ago — the row should be included.
            let pastCutoff = Date().addingTimeInterval(-5)
            let rowsAfter = try manager.fetchExecutionLog(since: pastCutoff, until: nil, limit: 100)
            XCTAssertEqual(rowsAfter.count, 1, "Rows after the since cutoff should be included")

            // Verify until also works: until = 5 seconds ago excludes the row.
            let rowsUntil = try manager.fetchExecutionLog(since: nil, until: twoHoursAgo, limit: 100)
            XCTAssertEqual(rowsUntil.count, 0, "until cutoff before the row timestamp should exclude it")

            // until = now should include it.
            let rowsUntilNow = try manager.fetchExecutionLog(since: nil, until: Date().addingTimeInterval(1), limit: 100)
            XCTAssertEqual(rowsUntilNow.count, 1)

            _ = twoHoursAgo // suppress unused-variable warning
            _ = oneHourAgo
        }
    }

    // MARK: - Test 3: Limit parameter caps result count

    func testLimitCapsResultCount() throws {
        try withTemporaryDatabase { manager in
            for i in 0..<10 {
                try manager.appendExecutionLog(
                    toolName: "applescript",
                    approvalLevel: .modal,
                    summary: "Run script #\(i)",
                    success: true,
                    durationMs: i * 10
                )
            }

            let capped = try manager.fetchExecutionLog(since: nil, until: nil, limit: 3)
            XCTAssertEqual(capped.count, 3, "Limit should cap the result to 3 rows")

            let all = try manager.fetchExecutionLog(since: nil, until: nil, limit: 100)
            XCTAssertEqual(all.count, 10)
        }
    }

    // MARK: - Test 4: isSideEffectingTool returns true for side-effecting tools

    func testIsSideEffectingToolReturnsTrueForMutatingTools() {
        let sideEffectingTools = [
            "write_file", "move_file", "clipboard_write",
            "applescript", "youtube_download", "phone_call",
            "create_directory", "image_convert", "phone_hangup"
        ]
        let dummyArgs: [String: Any] = [:]
        for tool in sideEffectingTools {
            XCTAssertTrue(
                AgentLoop.isSideEffectingTool(tool, args: dummyArgs),
                "Expected \(tool) to be side-effecting"
            )
        }
    }

    // MARK: - Test 5: isSideEffectingTool returns false for read-only tools

    func testIsSideEffectingToolReturnsFalseForReadOnlyTools() {
        let readOnlyTools = [
            "read_file", "list_directory", "git_status",
            "web_search", "mail_check", "weather",
            "ocr", "speak", "clipboard_read",
            "git_diff", "search_files", "unit_convert",
            "phone_status", "youtube_search", "mail_triage",
            "remember", "forget", "list_facts"
        ]
        let dummyArgs: [String: Any] = [:]
        for tool in readOnlyTools {
            XCTAssertFalse(
                AgentLoop.isSideEffectingTool(tool, args: dummyArgs),
                "Expected \(tool) to NOT be side-effecting"
            )
        }
    }

    // MARK: - Test 6: isSideEffectingTool for "present" discriminates by kind

    func testIsSideEffectingToolPresentKindFileIsLogged() {
        XCTAssertTrue(
            AgentLoop.isSideEffectingTool("present", args: ["kind": "file"]),
            "present kind=file should be side-effecting"
        )
    }

    func testIsSideEffectingToolPresentKindHtmlIsNotLogged() {
        XCTAssertFalse(
            AgentLoop.isSideEffectingTool("present", args: ["kind": "html"]),
            "present kind=html should NOT be side-effecting"
        )
    }

    func testIsSideEffectingToolPresentKindUrlIsNotLogged() {
        XCTAssertFalse(
            AgentLoop.isSideEffectingTool("present", args: ["kind": "url"]),
            "present kind=url should NOT be side-effecting"
        )
    }

    func testIsSideEffectingToolPresentMissingKindIsNotLogged() {
        XCTAssertFalse(
            AgentLoop.isSideEffectingTool("present", args: [:]),
            "present with no kind should NOT be side-effecting"
        )
    }
}
