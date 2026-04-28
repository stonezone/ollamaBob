import XCTest
@testable import OllamaBob

/// Tests for `DevModeStore`, `EnableDevModeTool`, `DisableDevModeTool`, and
/// the `ApprovalPolicy.check` dev-mode downgrade (Phase 6).
///
/// All tests reset `DevModeStore.shared.repoRoot = nil` in `tearDown` so
/// they cannot bleed state into one another.
@MainActor
final class DevModeStoreTests: XCTestCase {

    // MARK: - Test lifecycle

    override func setUp() async throws {
        try await super.setUp()
        DevModeStore.shared.repoRoot = nil
        DevModeStorage.shared.set(nil)
    }

    override func tearDown() async throws {
        DevModeStore.shared.repoRoot = nil
        DevModeStorage.shared.set(nil)
        try await super.tearDown()
    }

    // MARK: - Default state

    func testDefaultStateIsNil() {
        XCTAssertNil(DevModeStore.shared.repoRoot, "Dev mode should be off by default")
        XCTAssertNil(DevModeStorage.shared.get(), "DevModeStorage should be nil by default")
    }

    // MARK: - Setting repoRoot publishes change

    func testSettingRepoRootPublishesChange() async throws {
        var received: String? = "sentinel"
        let cancellable = DevModeStore.shared.$repoRoot.sink { received = $0 }
        defer { cancellable.cancel() }

        DevModeStore.shared.repoRoot = "/tmp/testrepo"
        // Give Combine a tick to deliver the value.
        try await Task.sleep(nanoseconds: 1_000_000)

        XCTAssertEqual(received, "/tmp/testrepo", "Published value should equal the set root")
    }

    // MARK: - DevModeStorage mirrors DevModeStore writes

    func testStorageMirrorsDevModeStoreWrite() {
        DevModeStore.shared.repoRoot = "/tmp/mirrortest"
        XCTAssertEqual(
            DevModeStorage.shared.get(), "/tmp/mirrortest",
            "DevModeStorage should mirror DevModeStore.repoRoot via didSet"
        )
    }

    func testStorageClearsMirror() {
        DevModeStore.shared.repoRoot = "/tmp/mirrortest"
        DevModeStore.shared.repoRoot = nil
        XCTAssertNil(DevModeStorage.shared.get(), "DevModeStorage should be nil after clearing repoRoot")
    }

    // MARK: - ApprovalPolicy: write_file under repoRoot returns .none

    func testApprovalPolicyDowngradesWriteFileUnderRepoRoot() {
        // Set up a real tmp directory as the repo root.
        let root = NSTemporaryDirectory().hasSuffix("/")
            ? String(NSTemporaryDirectory().dropLast())
            : NSTemporaryDirectory()
        let repoRoot = root + "/devmode-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: repoRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }

        DevModeStore.shared.repoRoot = repoRoot

        let targetPath = repoRoot + "/Sources/main.swift"
        let result = ApprovalPolicy.check(
            toolName: "write_file",
            arguments: ["path": targetPath, "content": "let x = 1"]
        )
        XCTAssertEqual(
            result, .none,
            "write_file inside dev-mode repo root should be .none, got \(result)"
        )
    }

    // MARK: - ApprovalPolicy: write_file OUTSIDE repoRoot stays .modal

    func testApprovalPolicyDoesNotDowngradeWriteFileOutsideRepoRoot() {
        let root = NSTemporaryDirectory().hasSuffix("/")
            ? String(NSTemporaryDirectory().dropLast())
            : NSTemporaryDirectory()
        let repoRoot = root + "/devmode-inside-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: repoRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }

        DevModeStore.shared.repoRoot = repoRoot

        // Target is OUTSIDE the repo root — at /tmp directly.
        let outsidePath = root + "/outside-devmode.swift"
        let result = ApprovalPolicy.check(
            toolName: "write_file",
            arguments: ["path": outsidePath, "content": "let y = 2"]
        )
        XCTAssertEqual(
            result, .modal,
            "write_file OUTSIDE dev-mode repo root must stay .modal, got \(result)"
        )
    }

    // MARK: - ApprovalPolicy: shell NEVER changed by dev mode

    /// Dev mode must NOT downgrade shell commands. Shell retains its own policy
    /// regardless of whether dev mode is active.
    func testShellWritePatternRemainsModalInDevMode() {
        DevModeStore.shared.repoRoot = "/tmp/some-repo"

        let result = ApprovalPolicy.check(
            toolName: "shell",
            arguments: ["command": "rm /tmp/some-repo/junk.txt"]
        )
        XCTAssertEqual(result, .modal, "shell rm command must remain .modal in dev mode, got \(result)")
    }

    func testShellForbiddenPatternRemainsForbiddenInDevMode() {
        DevModeStore.shared.repoRoot = "/tmp/some-repo"

        let result = ApprovalPolicy.check(
            toolName: "shell",
            arguments: ["command": "sudo rm -rf /tmp/some-repo"]
        )
        XCTAssertEqual(result, .forbidden, "shell sudo must remain .forbidden in dev mode, got \(result)")
    }

    func testDevModeDoesNotAffectShellApprovalLevel() {
        // Verify dev mode has zero effect on shell by comparing with and without it.
        let command = "swift test"
        let withoutDevMode = ApprovalPolicy.check(toolName: "shell", arguments: ["command": command])
        DevModeStore.shared.repoRoot = "/tmp/some-repo"
        let withDevMode = ApprovalPolicy.check(toolName: "shell", arguments: ["command": command])
        XCTAssertEqual(
            withDevMode, withoutDevMode,
            "Dev mode must not change shell approval level (was \(withoutDevMode), got \(withDevMode))"
        )
    }

    // MARK: - Path-prefix attack: /tmp/foo must NOT match /tmp/foobar

    func testPathPrefixAttackRemainsModal() {
        let root = NSTemporaryDirectory().hasSuffix("/")
            ? String(NSTemporaryDirectory().dropLast())
            : NSTemporaryDirectory()
        let repoRoot = root + "/foo"
        try? FileManager.default.createDirectory(atPath: repoRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: repoRoot) }

        DevModeStore.shared.repoRoot = repoRoot

        // Path is /tmp/foobar/x.txt — shares a prefix with /tmp/foo but is NOT under it.
        let attackPath = root + "/foobar/x.txt"
        let result = ApprovalPolicy.check(
            toolName: "write_file",
            arguments: ["path": attackPath, "content": "attack"]
        )
        XCTAssertEqual(
            result, .modal,
            "Path /tmp/foobar/x.txt must NOT be treated as under /tmp/foo, got \(result)"
        )
    }

    // MARK: - EnableDevModeTool

    func testEnableDevModeToolSetsRepoRootWhenGitExists() throws {
        let repoDir = NSTemporaryDirectory() + "enable-devmode-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: repoDir + "/.git", withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: repoDir) }

        let result = EnableDevModeTool.execute(path: repoDir)

        XCTAssertTrue(result.success, "enable_dev_mode should succeed, got: \(result.content)")
        XCTAssertNotNil(DevModeStore.shared.repoRoot, "repoRoot should be set after enable_dev_mode")
        XCTAssertTrue(
            result.content.contains("Dev mode enabled"),
            "Success message should confirm activation, got: \(result.content)"
        )
        XCTAssertTrue(
            result.content.contains("shell remains gated"),
            "Message must clarify shell stays gated, got: \(result.content)"
        )
    }

    func testEnableDevModeToolFailsWhenNoGitRoot() {
        let isolated = NSTemporaryDirectory() + "no-git-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: isolated, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: isolated) }

        let result = EnableDevModeTool.execute(path: isolated)

        XCTAssertFalse(result.success, "enable_dev_mode should fail when no .git found")
        XCTAssertNil(DevModeStore.shared.repoRoot, "repoRoot must not be set on failure")
        XCTAssertTrue(
            result.content.lowercased().contains("no .git"),
            "Error should mention .git, got: \(result.content)"
        )
    }

    // MARK: - DisableDevModeTool

    func testDisableDevModeClearsRepoRoot() {
        DevModeStore.shared.repoRoot = "/tmp/active-repo"

        let result = DisableDevModeTool.execute()

        XCTAssertTrue(result.success, "disable_dev_mode should succeed, got: \(result.content)")
        XCTAssertNil(DevModeStore.shared.repoRoot, "repoRoot must be nil after disable_dev_mode")
        XCTAssertTrue(
            result.content.contains("Dev mode disabled"),
            "Message should confirm deactivation, got: \(result.content)"
        )
    }

    func testDisableDevModeSucceedsWhenAlreadyInactive() {
        // repoRoot is nil — disable_dev_mode should still succeed gracefully.
        let result = DisableDevModeTool.execute()
        XCTAssertTrue(result.success)
        XCTAssertNil(DevModeStore.shared.repoRoot)
    }

    // MARK: - ApprovalPolicy: no dev mode active → unchanged behavior

    func testNoDevModeActiveWriteFileRemainsModal() {
        // repoRoot is nil — write_file must remain .modal as before.
        let result = ApprovalPolicy.check(
            toolName: "write_file",
            arguments: ["path": "/tmp/nodev.swift", "content": "let z = 3"]
        )
        XCTAssertEqual(result, .modal, "write_file without dev mode must stay .modal")
    }

    // MARK: - ToolRegistry registration

    func testCodeCompanionToolsAreRegistered() {
        let registry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertTrue(registry.has("project_context"),  "project_context must be registered")
        XCTAssertTrue(registry.has("enable_dev_mode"),  "enable_dev_mode must be registered")
        XCTAssertTrue(registry.has("disable_dev_mode"), "disable_dev_mode must be registered")
    }

    func testCodeCompanionApprovalPolicies() {
        XCTAssertEqual(
            ApprovalPolicy.check(toolName: "project_context",  arguments: ["path": "/tmp"]),
            .none,  "project_context should be .none (read-only)"
        )
        XCTAssertEqual(
            ApprovalPolicy.check(toolName: "enable_dev_mode",  arguments: ["path": "/tmp"]),
            .modal, "enable_dev_mode should be .modal (changes policy)"
        )
        XCTAssertEqual(
            ApprovalPolicy.check(toolName: "disable_dev_mode", arguments: [:]),
            .none,  "disable_dev_mode should be .none (safe direction)"
        )
    }

    // MARK: - BuiltinToolsCatalog entries

    func testCodeCompanionToolsAreInCatalog() {
        let codeEntries = BuiltinToolsCatalog.entries(for: "code")
        let names = codeEntries.map(\.name)
        XCTAssertTrue(names.contains("project_context"),  "project_context missing from code catalog")
        XCTAssertTrue(names.contains("enable_dev_mode"),  "enable_dev_mode missing from code catalog")
        XCTAssertTrue(names.contains("disable_dev_mode"), "disable_dev_mode missing from code catalog")
    }

    func testEnableDevModeIsNotSideEffectingInDefaultMode() {
        // enable_dev_mode IS side-effecting (changes policy). Verify.
        XCTAssertTrue(
            AgentLoop.isSideEffectingTool("enable_dev_mode", args: [:]),
            "enable_dev_mode must be side-effecting (changes session approval policy)"
        )
    }

    func testProjectContextAndDisableAreNotSideEffecting() {
        XCTAssertFalse(
            AgentLoop.isSideEffectingTool("project_context",  args: [:]),
            "project_context is read-only and must not be side-effecting"
        )
        XCTAssertFalse(
            AgentLoop.isSideEffectingTool("disable_dev_mode", args: [:]),
            "disable_dev_mode only relaxes policy in safe direction"
        )
    }
}
