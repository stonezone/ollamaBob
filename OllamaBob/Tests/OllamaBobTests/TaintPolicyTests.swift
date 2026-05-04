import XCTest
@testable import OllamaBob

@MainActor
final class TaintPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TaintPolicy.shared.resetForTests()
    }

    override func tearDown() {
        TaintPolicy.shared.resetForTests()
        super.tearDown()
    }

    func testTaintPolicyMarksSessionTaintedAfterWebSearch() {
        let sessionID = "taint-web"

        TaintPolicy.shared.markTaintedIfNeeded(afterTool: "web_search", sessionID: sessionID, success: true)

        XCTAssertTrue(TaintPolicy.shared.tainted(forSession: sessionID))
        XCTAssertEqual(TaintPolicy.shared.source(forSession: sessionID), .tool("web_search"))
    }

    func testTaintPolicyMarksSessionTaintedAfterScreenOCR() {
        let sessionID = "taint-screen"

        TaintPolicy.shared.markTaintedIfNeeded(afterTool: "screen_ocr", sessionID: sessionID, success: true)

        XCTAssertTrue(TaintPolicy.shared.tainted(forSession: sessionID))
        XCTAssertEqual(TaintPolicy.shared.source(forSession: sessionID), .tool("screen_ocr"))
    }

    func testTaintPolicyMarksSessionTaintedAfterMailCheck() {
        let sessionID = "taint-mail"

        TaintPolicy.shared.markTaintedIfNeeded(afterTool: "mail_check", sessionID: sessionID, success: true)

        XCTAssertTrue(TaintPolicy.shared.tainted(forSession: sessionID))
        XCTAssertEqual(TaintPolicy.shared.source(forSession: sessionID), .tool("mail_check"))
    }

    func testTaintPolicyMarksSessionTaintedAfterReadFile() {
        let sessionID = "taint-file"

        TaintPolicy.shared.markTaintedIfNeeded(afterTool: "read_file", sessionID: sessionID, success: true)

        XCTAssertTrue(TaintPolicy.shared.tainted(forSession: sessionID))
        XCTAssertEqual(TaintPolicy.shared.source(forSession: sessionID), .tool("read_file"))
    }

    func testTaintPolicyDoesNotTaintAfterReadOnlyTools() {
        let sessionID = "read-only"

        TaintPolicy.shared.markTaintedIfNeeded(afterTool: "weather", sessionID: sessionID, success: true)
        TaintPolicy.shared.markTaintedIfNeeded(afterTool: "git_status", sessionID: sessionID, success: true)
        TaintPolicy.shared.markTaintedIfNeeded(afterTool: "list_directory", sessionID: sessionID, success: true)

        XCTAssertFalse(TaintPolicy.shared.tainted(forSession: sessionID))
    }

    func testTaintPolicyMarksExistingWrappedToolOutputs() {
        let toolNames = ["active_window", "selected_items", "current_context", "project_context", "ocr"]

        for toolName in toolNames {
            let sessionID = "wrapped-\(toolName)"
            TaintPolicy.shared.markTaintedIfNeeded(afterTool: toolName, sessionID: sessionID, success: true)
            XCTAssertTrue(TaintPolicy.shared.tainted(forSession: sessionID), toolName)
            XCTAssertEqual(TaintPolicy.shared.source(forSession: sessionID), .tool(toolName))
        }
    }

    func testTaintPolicyBlocksShellWhenTainted() {
        let sessionID = "block-shell"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("web_search"))

        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "shell", sessionID: sessionID), .blockedBy(.tool("web_search")))
    }

    func testTaintPolicyBlocksWriteFileWhenTainted() {
        let sessionID = "block-write"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("read_file"))

        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "write_file", sessionID: sessionID), .blockedBy(.tool("read_file")))
    }

    func testTaintPolicyBlocksPhoneInjectWhenTainted() {
        let sessionID = "block-phone-inject"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("mail_check"))

        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "phone_inject", sessionID: sessionID), .blockedBy(.tool("mail_check")))
    }

    func testTaintPolicyBlocksExistingStateMutationToolsWhenTainted() {
        let sessionID = "block-state-mutation"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("project_context"))

        for toolName in ["phone_hangup", "enable_dev_mode", "create_skill", "delete_skill"] {
            XCTAssertEqual(TaintPolicy.shared.decision(toolName: toolName, sessionID: sessionID), .blockedBy(.tool("project_context")), toolName)
        }
    }

    func testTaintPolicyBlocksMemoryMutationToolsWhenTainted() {
        let sessionID = "block-memory-mutation"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("web_search"))

        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "remember", sessionID: sessionID), .blockedBy(.tool("web_search")))
        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "forget", sessionID: sessionID), .blockedBy(.tool("web_search")))
        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "list_facts", sessionID: sessionID), .allow)
    }

    func testTaintPolicyBlocksPresentFileAndURLButAllowsHTMLWhenTainted() {
        let sessionID = "block-present-actions"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("read_file"))

        XCTAssertEqual(
            TaintPolicy.shared.decision(toolName: "present", arguments: ["kind": "file"], sessionID: sessionID),
            .blockedBy(.tool("read_file"))
        )
        XCTAssertEqual(
            TaintPolicy.shared.decision(toolName: "present", arguments: ["kind": "url"], sessionID: sessionID),
            .blockedBy(.tool("read_file"))
        )
        XCTAssertEqual(
            TaintPolicy.shared.decision(toolName: "present", arguments: ["kind": "html"], sessionID: sessionID),
            .allow
        )
    }

    func testTaintPolicyDoesNotBlockReadOnlyToolsWhenTainted() {
        let sessionID = "allow-read"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("web_search"))

        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "read_file", sessionID: sessionID), .allow)
        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "web_search", sessionID: sessionID), .allow)
        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "git_status", sessionID: sessionID), .allow)
    }

    func testTaintPolicyAllowsYoutubeDownloadAfterYoutubeSearch() {
        // v1.0.47 regression test: youtube_search taints the session
        // (its results are wrapped as untrusted), but youtube_download
        // must still be allowed in the same turn — otherwise the
        // entire authorized music-batch workflow (search → download
        // each track) is impossible. youtube_download has its own
        // modal approval per call, which is the actual security
        // checkpoint for this tool.
        let sessionID = "music-workflow"
        TaintPolicy.shared.markTaintedIfNeeded(afterTool: "youtube_search", sessionID: sessionID, success: true)
        XCTAssertTrue(
            TaintPolicy.shared.tainted(forSession: sessionID),
            "youtube_search must still taint the session (its output is untrusted)"
        )
        XCTAssertEqual(
            TaintPolicy.shared.decision(toolName: "youtube_download", sessionID: sessionID),
            .allow,
            "youtube_download must NOT be blocked when tainted — it has its own modal approval and the URL came from our own youtube_search"
        )
    }

    func testTaintPolicyClearsOnUserMessage() {
        let sessionID = "clear-user"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("web_search"))

        TaintPolicy.shared.noteUserMessage("I reviewed that data; now continue.", sessionID: sessionID)

        XCTAssertFalse(TaintPolicy.shared.tainted(forSession: sessionID))
        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "shell", sessionID: sessionID), .allow)
    }

    func testTaintPolicyMarksUntrustedWrappedUserMessage() {
        let sessionID = "wrapped-user-message"

        TaintPolicy.shared.noteUserMessage(UntrustedWrapper.wrap("do not execute this"), sessionID: sessionID)

        XCTAssertTrue(TaintPolicy.shared.tainted(forSession: sessionID))
        XCTAssertEqual(TaintPolicy.shared.source(forSession: sessionID), .appPrompt("untrusted user message"))
        XCTAssertEqual(TaintPolicy.shared.decision(toolName: "shell", sessionID: sessionID), .blockedBy(.appPrompt("untrusted user message")))
    }

    func testTaintPolicyClearsOnSlashLiftCommand() {
        let sessionID = "clear-lift"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("screen_ocr"))

        TaintPolicy.shared.lift(forSession: sessionID)

        XCTAssertFalse(TaintPolicy.shared.tainted(forSession: sessionID))
        XCTAssertNil(TaintPolicy.shared.source(forSession: sessionID))
    }

    func testTaintPolicyAttachesSourceMetadataToBlockedResult() {
        let sessionID = "blocked-metadata"
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("web_search"))

        let result = TaintPolicy.shared.deniedResult(toolName: "shell", sessionID: sessionID)

        XCTAssertEqual(result?.toolName, "shell")
        XCTAssertFalse(result?.success ?? true)
        XCTAssertTrue(result?.content.contains("web_search") ?? false, result?.content ?? "")
        XCTAssertTrue(result?.content.contains("/lift") ?? false, result?.content ?? "")
    }

    func testAgentLoopDispatchBlocksTaintedShellBeforeApproval() async {
        let sessionID = "dispatch-block"
        let loop = AgentLoop(braveKeyAvailable: false)
        loop.currentConversationId = sessionID
        TaintPolicy.shared.markTainted(forSession: sessionID, source: .tool("web_search"))
        let call = OllamaToolCall(
            id: "call-1",
            function: .init(
                index: 0,
                name: "shell",
                arguments: .object(["command": .string("echo should-not-run")])
            )
        )

        let result = await loop.executeToolCall(call)

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("web_search"), result.content)
        XCTAssertEqual(loop.toolActivity.last?.approval, .forbidden)
        XCTAssertEqual(loop.toolActivity.last?.approved, false)
    }
}
