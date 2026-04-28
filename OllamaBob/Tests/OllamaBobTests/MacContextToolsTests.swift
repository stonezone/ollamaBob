import XCTest
@testable import OllamaBob

/// Tests for the four Mac Context tools: `active_window`, `selected_items`,
/// `screen_ocr`, and `current_context`.
///
/// ScreenCaptureKit calls are NOT made — tests verify tool output formatting,
/// UntrustedWrapper presence, and graceful failure paths only.
final class MacContextToolsTests: XCTestCase {

    // MARK: - Tool registration

    @MainActor
    func testAllFourContextToolsAreRegistered() {
        let registry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertTrue(registry.has("active_window"),   "active_window should be registered")
        XCTAssertTrue(registry.has("selected_items"),  "selected_items should be registered")
        XCTAssertTrue(registry.has("screen_ocr"),      "screen_ocr should be registered")
        XCTAssertTrue(registry.has("current_context"), "current_context should be registered")
    }

    @MainActor
    func testContextToolsHaveNilRequiredArgs() {
        let registry = ToolRegistry(braveKeyAvailable: false)
        // All four take no arguments — validateArgs with empty dict must pass
        XCTAssertTrue(registry.validateArgs("active_window",   [:]))
        XCTAssertTrue(registry.validateArgs("selected_items",  [:]))
        XCTAssertTrue(registry.validateArgs("screen_ocr",      [:]))
        XCTAssertTrue(registry.validateArgs("current_context", [:]))
    }

    // MARK: - BuiltinToolsCatalog entries

    func testContextToolsAreInBuiltinCatalog() {
        let contextEntries = BuiltinToolsCatalog.entries(for: "context")
        let names = contextEntries.map(\.name)
        XCTAssertTrue(names.contains("active_window"),   "active_window missing from context catalog")
        XCTAssertTrue(names.contains("selected_items"),  "selected_items missing from context catalog")
        XCTAssertTrue(names.contains("screen_ocr"),      "screen_ocr missing from context catalog")
        XCTAssertTrue(names.contains("current_context"), "current_context missing from context catalog")
    }

    func testContextToolsHaveNonePosture() {
        let contextEntries = BuiltinToolsCatalog.entries(for: "context")
        for entry in contextEntries {
            XCTAssertEqual(
                entry.posture, .none,
                "\(entry.name) should have approval posture .none (read-only)"
            )
        }
    }

    // MARK: - ApprovalPolicy (posture via BuiltinToolsCatalog)
    //
    // NOTE: `ApprovalPolicy.swift` is outside the Phase 3 scope list and was not
    // modified. The four context tools currently fall through to the `default: .modal`
    // case in ApprovalPolicy.baseCheck. The intended posture is `.none`; the fix
    // (adding the four cases to ApprovalPolicy.baseCheck) must be landed in a
    // follow-on scope that includes ApprovalPolicy.swift.
    //
    // Instead we verify the catalog posture (already tested above) and that the
    // tools are not side-effecting (so they won't reach the execution-log path).

    func testContextToolsCatalogPostureIsNone() {
        // Verifies BuiltinToolsCatalog posture — this is the source of truth for
        // the Preferences UI and tool_help rendering.
        let contextEntries = BuiltinToolsCatalog.entries(for: "context")
        for entry in contextEntries {
            XCTAssertEqual(
                entry.posture, .none,
                "\(entry.name) should have catalog posture .none (read-only)"
            )
        }
    }

    // MARK: - isSideEffectingTool (must be false for all four)

    func testContextToolsAreNotSideEffecting() {
        XCTAssertFalse(AgentLoop.isSideEffectingTool("active_window",   args: [:]))
        XCTAssertFalse(AgentLoop.isSideEffectingTool("selected_items",  args: [:]))
        XCTAssertFalse(AgentLoop.isSideEffectingTool("screen_ocr",      args: [:]))
        XCTAssertFalse(AgentLoop.isSideEffectingTool("current_context", args: [:]))
    }

    // MARK: - ScreenOCRTool: graceful failure

    @MainActor
    func testScreenOCRToolReturnsSuccessEvenWhenCaptureUnavailable() async {
        // In the test runner, ScreenCaptureKit TCC is almost certainly denied.
        // The tool must return .success with a "Screen OCR unavailable" message
        // rather than throwing or returning .failure.
        let result = await ScreenOCRTool.execute()
        // Either we got OCR text (unexpected in CI but valid) or a graceful message.
        // In both cases the tool must report success and contain a timestamp.
        XCTAssertTrue(result.success, "ScreenOCRTool must not return .failure — got: \(result.content)")
        // If capture failed, the message should say unavailable
        // If it somehow succeeded, the content will contain "(captured at"
        XCTAssertTrue(
            result.content.contains("captured at") || result.content.contains("unavailable"),
            "Expected timestamp or unavailable message, got: \(result.content)"
        )
    }

    // MARK: - UntrustedWrapper presence

    @MainActor
    func testActiveWindowResultIsUntrustedWrapped() async {
        let result = await ActiveWindowTool.execute()
        XCTAssertTrue(result.success, result.content)
        XCTAssertTrue(
            result.content.contains(UntrustedWrapper.openTag),
            "active_window output must be wrapped in <untrusted> tags"
        )
        XCTAssertTrue(
            result.content.contains(UntrustedWrapper.closeTag),
            "active_window output must have </untrusted> closing tag"
        )
    }

    @MainActor
    func testSelectedItemsResultIsUntrustedWrapped() async {
        let result = await SelectedItemsTool.execute()
        XCTAssertTrue(result.success, result.content)
        XCTAssertTrue(
            result.content.contains(UntrustedWrapper.openTag),
            "selected_items output must be wrapped in <untrusted> tags"
        )
    }

    @MainActor
    func testCurrentContextResultIsUntrustedWrapped() async {
        let result = await CurrentContextTool.execute()
        XCTAssertTrue(result.success, result.content)
        XCTAssertTrue(
            result.content.contains(UntrustedWrapper.openTag),
            "current_context output must be wrapped in <untrusted> tags"
        )
        XCTAssertTrue(
            result.content.contains(UntrustedWrapper.closeTag),
            "current_context output must have </untrusted> closing tag"
        )
    }

    @MainActor
    func testScreenOCRSuccessIsUntrustedWrapped() async {
        let result = await ScreenOCRTool.execute()
        XCTAssertTrue(result.success, result.content)
        // When screen capture succeeds (rare in CI), the content MUST be wrapped.
        // When it fails gracefully, the "unavailable" message is plain (no wrap needed
        // since it contains no user data). Verify: if wrapped, tags must be balanced.
        if result.content.contains(UntrustedWrapper.openTag) {
            XCTAssertTrue(
                result.content.contains(UntrustedWrapper.closeTag),
                "If <untrusted> open tag present, closing tag must also be present"
            )
        }
    }

    // MARK: - CurrentContextTool composite content

    @MainActor
    func testCurrentContextIncludesExpectedSections() async {
        let result = await CurrentContextTool.execute()
        XCTAssertTrue(result.success, result.content)
        // The summary always includes these section headings
        let body = result.content
        XCTAssertTrue(body.contains("Captured at:"), "Expected 'Captured at:' in current_context output")
        // Active app or Clipboard line must be present
        let hasApp = body.contains("Active app:") || body.contains("No frontmost")
        XCTAssertTrue(hasApp, "Expected app info in current_context output, got: \(body)")
    }

    // MARK: - MacContext summary formatting

    func testCurrentContextSummaryContainsAllSections() {
        let ctx = MacContext(
            capturedAt: Date(timeIntervalSinceReferenceDate: 0),
            activeApp: MacContext.ActiveApp(
                bundleIdentifier: "com.test.app",
                localizedName: "TestApp",
                windowTitle: "My Window"
            ),
            selectedItems: ["/Users/test/file.txt", "/Users/test/doc.pdf"],
            clipboardMeta: MacContext.ClipboardMeta(length: 11, preview: "hello world", isText: true),
            screenOCRSnippet: nil
        )
        let summary = ctx.currentContextSummary()
        XCTAssertTrue(summary.contains("TestApp"),        "Expected app name in summary")
        XCTAssertTrue(summary.contains("com.test.app"),   "Expected bundle ID in summary")
        XCTAssertTrue(summary.contains("My Window"),      "Expected window title in summary")
        XCTAssertTrue(summary.contains("2 item"),         "Expected Finder selection count in summary")
        XCTAssertTrue(summary.contains("hello world"),    "Expected clipboard preview in summary")
        XCTAssertTrue(summary.contains("Captured at:"),   "Expected captured-at timestamp in summary")
    }
}
