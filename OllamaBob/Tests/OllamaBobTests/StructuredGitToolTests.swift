import XCTest
@testable import OllamaBob

final class StructuredGitToolTests: XCTestCase {
    func testApprovalPolicyClassifiesStructuredGitTools() {
        XCTAssertEqual(ApprovalPolicy.check(toolName: "git_status", arguments: ["repo_path": "/tmp/repo"]), .none)
        XCTAssertEqual(ApprovalPolicy.check(toolName: "git_diff", arguments: ["repo_path": "/tmp/repo"]), .none)
        XCTAssertEqual(ApprovalPolicy.check(toolName: "git_status", arguments: ["repo_path": "/dev/repo"]), .forbidden)
    }

    func testGitStatusAndDiffReadRepositoryState() async throws {
        let repoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(arguments: ["init"], in: repoURL)

        let fileURL = repoURL.appendingPathComponent("notes.txt")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let status = await GitStatusTool.execute(repoPath: repoURL.path)
        XCTAssertTrue(status.success)
        XCTAssertTrue(status.content.contains("?? notes.txt"))

        try runGit(arguments: ["add", "notes.txt"], in: repoURL)
        try "hello\nworld\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let stagedDiff = await GitDiffTool.execute(repoPath: repoURL.path, relativePath: "notes.txt", staged: true)
        XCTAssertTrue(stagedDiff.success)
        XCTAssertTrue(stagedDiff.content.contains("+hello"))

        let workingTreeDiff = await GitDiffTool.execute(repoPath: repoURL.path, relativePath: "notes.txt", staged: false)
        XCTAssertTrue(workingTreeDiff.success)
        XCTAssertTrue(workingTreeDiff.content.contains("+world"))
    }

    private func runGit(arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(errorOutput)")
        }
    }
}
