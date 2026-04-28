import XCTest
@testable import OllamaBob

/// Tests for the `project_context` tool (Phase 6 — Code Companion Mode).
///
/// All tests use temporary directories on disk — no network calls, no real
/// git operations that would hit remote, and no fixtures outside /tmp.
final class ProjectContextToolTests: XCTestCase {

    // MARK: - Test lifecycle

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProjectContextToolTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Create a minimal fake .git directory so `findGitRoot` treats `dir` as a repo root.
    private func makeFakeGitRepo(at dir: URL) throws {
        let gitDir = dir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
    }

    // MARK: - findGitRoot: no .git ancestor

    func testReturnsFailureWhenNoGitAncestor() async {
        // tmpDir has no .git in any ancestor under /tmp for our UUID subdir.
        // Use a deep subdirectory to stay away from any accidental .git.
        let deepDir = tmpDir
            .appendingPathComponent("a")
            .appendingPathComponent("b")
            .appendingPathComponent("c")
        try? FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)

        let result = await ProjectContextTool.execute(path: deepDir.path)

        XCTAssertFalse(result.success, "Expected failure when no .git ancestor")
        XCTAssertTrue(
            result.content.lowercased().contains("no .git"),
            "Error message should mention .git, got: \(result.content)"
        )
    }

    // MARK: - findGitRoot helper directly

    func testFindGitRootReturnsFolderContainingDotGit() throws {
        try makeFakeGitRepo(at: tmpDir)
        let subDir = tmpDir.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let found = ProjectContextTool.findGitRoot(from: subDir)
        XCTAssertNotNil(found, "findGitRoot should find the .git directory")
        XCTAssertEqual(
            found?.standardizedFileURL.path,
            tmpDir.standardizedFileURL.path,
            "findGitRoot should return the directory containing .git"
        )
    }

    func testFindGitRootReturnsNilWhenNoDotGit() {
        // Pure temp directory tree with no .git anywhere above.
        let isolated = tmpDir.appendingPathComponent("isolated/deep/path")
        try? FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
        let found = ProjectContextTool.findGitRoot(from: isolated)
        XCTAssertNil(found, "findGitRoot should return nil when no .git ancestor exists")
    }

    // MARK: - Language detection: Swift project

    func testDetectsSwiftProjectFromPackageSwift() async throws {
        try makeFakeGitRepo(at: tmpDir)
        // Write a minimal Package.swift
        let packageSwift = """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "TestPkg")
        """
        try packageSwift.write(
            to: tmpDir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = await ProjectContextTool.execute(path: tmpDir.path)

        // The tool runs git log/diff which will fail (no real git repo), but
        // it should still succeed and report Swift as the language.
        XCTAssertTrue(result.success, "project_context should succeed even if git fails, got: \(result.content)")
        XCTAssertTrue(
            result.content.contains("Swift"),
            "Should detect Swift language from Package.swift, got: \(result.content)"
        )
        XCTAssertTrue(
            result.content.contains("Package.swift"),
            "Should mention Package.swift as manifest, got: \(result.content)"
        )
    }

    // MARK: - Language detection: multiple manifests joined

    func testDetectsMultipleManifestsJoined() async throws {
        try makeFakeGitRepo(at: tmpDir)
        // Write Package.swift + package.json (polyglot project)
        try "// swift-tools-version: 5.9\nimport PackageDescription".write(
            to: tmpDir.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )
        try "{\"name\": \"frontend\", \"version\": \"1.0.0\"}".write(
            to: tmpDir.appendingPathComponent("package.json"),
            atomically: true, encoding: .utf8
        )

        let result = await ProjectContextTool.execute(path: tmpDir.path)

        XCTAssertTrue(result.success, "project_context should succeed, got: \(result.content)")
        // Both languages should appear in the output
        let content = result.content
        XCTAssertTrue(
            content.contains("Swift") && content.contains("JavaScript"),
            "Should list both Swift and JavaScript for polyglot project, got: \(content)"
        )
        XCTAssertTrue(
            content.contains("+"),
            "Multiple languages should be joined with '+', got: \(content)"
        )
    }

    // MARK: - Output is <untrusted> wrapped

    func testOutputIsUntrustedWrapped() async throws {
        try makeFakeGitRepo(at: tmpDir)
        try "// swift-tools-version: 5.9".write(
            to: tmpDir.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )

        let result = await ProjectContextTool.execute(path: tmpDir.path)

        XCTAssertTrue(result.success, "project_context must succeed, got: \(result.content)")
        XCTAssertTrue(
            result.content.contains(UntrustedWrapper.openTag),
            "Output must start with <untrusted> tag, got: \(result.content)"
        )
        XCTAssertTrue(
            result.content.contains(UntrustedWrapper.closeTag),
            "Output must have </untrusted> closing tag, got: \(result.content)"
        )
    }

    // MARK: - Output is bounded

    func testOutputIsBoundedAt8KB() async throws {
        try makeFakeGitRepo(at: tmpDir)
        // Write a very large Package.swift to trigger the 8KB bound
        let bigContent = String(repeating: "// line\n", count: 2000)
        try bigContent.write(
            to: tmpDir.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )

        let result = await ProjectContextTool.execute(path: tmpDir.path)
        XCTAssertTrue(result.success)
        // Raw content (inside untrusted tags) should not exceed 8KB + small wrapper overhead
        XCTAssertLessThanOrEqual(
            result.content.utf8.count,
            9 * 1024,
            "Output should be bounded near 8KB"
        )
    }

    // MARK: - Rust project

    func testDetectsRustProjectFromCargoToml() async throws {
        try makeFakeGitRepo(at: tmpDir)
        try "[package]\nname = \"myapp\"\nversion = \"0.1.0\"".write(
            to: tmpDir.appendingPathComponent("Cargo.toml"),
            atomically: true, encoding: .utf8
        )

        let result = await ProjectContextTool.execute(path: tmpDir.path)
        XCTAssertTrue(result.success, "project_context should succeed, got: \(result.content)")
        XCTAssertTrue(
            result.content.contains("Rust"),
            "Should detect Rust from Cargo.toml, got: \(result.content)"
        )
    }

    // MARK: - Invalid path

    func testReturnsFailureForInvalidPath() async {
        let result = await ProjectContextTool.execute(path: "")
        XCTAssertFalse(result.success, "Empty path should produce failure")
    }
}
