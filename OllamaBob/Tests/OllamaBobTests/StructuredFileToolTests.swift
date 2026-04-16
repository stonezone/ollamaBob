import XCTest
@testable import OllamaBob

final class StructuredFileToolTests: XCTestCase {
    func testApprovalPolicyClassifiesStructuredFileTools() {
        XCTAssertEqual(ApprovalPolicy.check(toolName: "list_directory", arguments: ["path": "/tmp"]), .none)
        XCTAssertEqual(ApprovalPolicy.check(toolName: "create_directory", arguments: ["path": "/tmp/example"]), .modal)
        XCTAssertEqual(
            ApprovalPolicy.check(toolName: "write_file", arguments: ["path": "/tmp/example.txt", "content": "hello"]),
            .modal
        )
        XCTAssertEqual(
            ApprovalPolicy.check(
                toolName: "move_file",
                arguments: ["source": "/tmp/source.txt", "destination": "/dev/dest.txt"]
            ),
            .forbidden
        )
    }

    func testCreateWriteMoveAndListDirectory() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let nestedURL = baseURL.appendingPathComponent("nested", isDirectory: true)
        let fileURL = baseURL.appendingPathComponent("notes.txt")
        let movedURL = nestedURL.appendingPathComponent("notes-renamed.txt")

        let createResult = await DirectoryCreateTool.execute(path: nestedURL.path)
        XCTAssertTrue(createResult.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedURL.path))

        let writeResult = await FileWriteTool.execute(path: fileURL.path, content: "hello")
        XCTAssertTrue(writeResult.success)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "hello")

        let listDepth1 = await DirectoryListTool.execute(path: baseURL.path, depth: 1)
        XCTAssertTrue(listDepth1.content.contains("[DIR] \(nestedURL.path)"))
        XCTAssertTrue(listDepth1.content.contains("[FILE] \(fileURL.path)"))
        XCTAssertFalse(listDepth1.content.contains(movedURL.path))

        let moveResult = await FileMoveTool.execute(source: fileURL.path, destination: movedURL.path)
        XCTAssertTrue(moveResult.success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path))

        let listDepth2 = await DirectoryListTool.execute(path: baseURL.path, depth: 2)
        XCTAssertTrue(listDepth2.content.contains("[FILE] \(movedURL.path)"))
    }
}
