import XCTest
@testable import OllamaBob

final class WriteDiffTests: XCTestCase {

    // MARK: - Helpers

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func tmpFile(name: String, content: String) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Test 1: New file (target does not exist) → nil

    func testNewFileReturnsNil() {
        let url = tmpDir.appendingPathComponent("nonexistent.txt")
        XCTAssertNil(
            WriteDiff.computeForWriteFile(at: url, proposedContent: "hello"),
            "Expected nil for a file that does not exist"
        )
    }

    // MARK: - Test 2: Identical content → nil

    func testIdenticalContentReturnsNil() throws {
        let content = "line one\nline two\nline three\n"
        let url = try tmpFile(name: "same.txt", content: content)
        XCTAssertNil(
            WriteDiff.computeForWriteFile(at: url, proposedContent: content),
            "Expected nil when proposed content equals existing content"
        )
    }

    // MARK: - Test 3: Single-line change → correct diff structure

    func testSingleLineChange() throws {
        let before = "alpha\nbeta\ngamma\n"
        let after  = "alpha\nBETA\ngamma\n"
        let url = try tmpFile(name: "single.txt", content: before)

        let diff = WriteDiff.computeForWriteFile(at: url, proposedContent: after)
        XCTAssertNotNil(diff, "Expected a diff for a single-line change")

        guard let diff else { return }

        // Must have standard header lines
        XCTAssertTrue(diff.contains("--- "), "Missing '--- ' header")
        XCTAssertTrue(diff.contains("+++ "), "Missing '+++ ' header")

        // Must have at least one hunk header
        XCTAssertTrue(diff.contains("@@"), "Missing hunk header '@@'")

        // Must have a removed line and an added line
        let lines = diff.components(separatedBy: "\n")
        let removedLines = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }
        let addedLines   = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }
        XCTAssertFalse(removedLines.isEmpty, "Expected at least one '-' line in diff")
        XCTAssertFalse(addedLines.isEmpty,   "Expected at least one '+' line in diff")
        XCTAssertTrue(removedLines.contains("-beta"),  "Expected '-beta' in diff, got: \(removedLines)")
        XCTAssertTrue(addedLines.contains("+BETA"),    "Expected '+BETA' in diff, got: \(addedLines)")
    }

    // MARK: - Test 4: Multi-hunk change → two @@ sections

    func testMultiHunkChange() throws {
        // Two change regions separated by many equal lines
        let beforeLines = (0..<30).map { "line \($0)" }
        var afterLines  = beforeLines

        // Change line 0 and line 29 — separated by 28 equal lines, well beyond 2*3=6 context
        afterLines[0]  = "CHANGED_FIRST"
        afterLines[29] = "CHANGED_LAST"

        let before = beforeLines.joined(separator: "\n") + "\n"
        let after  = afterLines.joined(separator: "\n") + "\n"

        let diff = WriteDiff.unified(
            beforeContent: before,
            afterContent: after,
            beforePath: "before.txt",
            afterPath: "after.txt"
        )
        XCTAssertNotNil(diff, "Expected a diff for a two-region change")

        guard let diff else { return }

        // Count @@ occurrences — must be >= 2
        let hunkCount = diff.components(separatedBy: "@@").count - 1
        XCTAssertGreaterThanOrEqual(hunkCount, 2, "Expected at least 2 hunk headers for separate change regions, got \(hunkCount)")
    }

    // MARK: - Test 5: Cap enforced — over 200 KB combined → nil

    func testOverCapReturnsNil() {
        // 201 KB of 'x' characters — exceeds 200 KB combined cap on its own
        let bigContent = String(repeating: "x", count: 201 * 1024)
        let result = WriteDiff.unified(
            beforeContent: bigContent,
            afterContent: bigContent + "y",
            beforePath: "a.txt",
            afterPath: "a.txt"
        )
        XCTAssertNil(result, "Expected nil when combined input exceeds 200 KB cap")
    }

    // MARK: - Test 6: Binary / unreadable file → nil without throwing

    func testBinaryFileReturnsNil() throws {
        // Write arbitrary non-UTF-8 bytes
        let binaryBytes: [UInt8] = [0xFF, 0xFE, 0x00, 0x01, 0xD8, 0x00]
        let url = tmpDir.appendingPathComponent("binary.bin")
        let data = Data(binaryBytes)
        try data.write(to: url)

        // Must not throw and must return nil (not readable as UTF-8)
        let result = WriteDiff.computeForWriteFile(at: url, proposedContent: "hello")
        XCTAssertNil(result, "Expected nil for a binary (non-UTF-8) file")
    }

    // MARK: - Test 7 (bonus): unified returns nil for identical content directly

    func testUnifiedNilForIdentical() {
        let content = "foo\nbar\nbaz\n"
        let result = WriteDiff.unified(
            beforeContent: content,
            afterContent: content,
            beforePath: "f.txt",
            afterPath: "f.txt"
        )
        XCTAssertNil(result, "Expected nil when before == after via unified()")
    }

    // MARK: - Test 8 (bonus): diffSeparator round-trip

    func testDiffSeparatorConstant() {
        // The sentinel must be stable so the split in ApprovalAlert.show works correctly.
        XCTAssertEqual(
            ApprovalAlert.diffSeparator,
            "\n\n--- WRITE_FILE DIFF ---\n",
            "diffSeparator constant value changed — update ApprovalAlert.show split logic too"
        )
    }
}
