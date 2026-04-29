import XCTest
@testable import OllamaBob

final class DeskPromptActionsTests: XCTestCase {
    func testWalkieTalkiePromptExtractsTrimmedTranscript() {
        let notification = Notification(
            name: .bobWalkieTalkieTranscript,
            object: nil,
            userInfo: ["transcript": "  remind me to test the build  "]
        )

        XCTAssertEqual(
            DeskPromptActions.walkieTalkiePrompt(from: notification),
            "remind me to test the build"
        )
    }

    func testWalkieTalkiePromptRejectsEmptyTranscript() {
        let notification = Notification(
            name: .bobWalkieTalkieTranscript,
            object: nil,
            userInfo: ["transcript": " \n\t "]
        )

        XCTAssertNil(DeskPromptActions.walkieTalkiePrompt(from: notification))
    }

    func testStackTracePromptUsesFullContentAndWrapsAsUntrustedData() {
        let notification = Notification(
            name: .clipboardCortexSummarizeStackTrace,
            object: nil,
            userInfo: [
                "preview": "short preview",
                "content": "Fatal error\n    at realFrame(app.js:42:5)"
            ]
        )

        let prompt = DeskPromptActions.stackTracePrompt(from: notification)

        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt?.contains("Summarize this stack trace") == true)
        XCTAssertTrue(prompt?.contains(UntrustedWrapper.openTag) == true)
        XCTAssertTrue(prompt?.contains("realFrame(app.js:42:5)") == true)
        XCTAssertFalse(prompt?.contains("short preview") == true)
        XCTAssertTrue(prompt?.contains(UntrustedWrapper.closeTag) == true)
    }

    func testStackTracePromptFallsBackToPreview() {
        let notification = Notification(
            name: .clipboardCortexSummarizeStackTrace,
            object: nil,
            userInfo: ["preview": "Traceback fallback"]
        )

        XCTAssertTrue(
            DeskPromptActions.stackTracePrompt(from: notification)?
                .contains("Traceback fallback") == true
        )
    }

    @MainActor
    func testDeskPromptInboxDrainsQueuedPromptsOnce() {
        DeskPromptInbox.shared.resetForTesting()
        DeskPromptInbox.shared.enqueue("  summarize this later  ")

        XCTAssertEqual(DeskPromptInbox.shared.drain(), ["summarize this later"])
        XCTAssertEqual(DeskPromptInbox.shared.drain(), [])
    }
}
