import XCTest
import WebKit
@testable import OllamaBob

@MainActor
final class MultimediaBobTests: XCTestCase {
    func testApprovalPolicyClassifiesPresentAsAutomatic() {
        XCTAssertEqual(
            ApprovalPolicy.check(
                toolName: "present",
                arguments: ["kind": "url", "content": "https://example.com"]
            ),
            .none
        )
    }

    func testToolRegistryHidesPresentWhenRichPresentationDisabled() {
        let original = AppSettings.shared.richPresentationEnabled
        defer { AppSettings.shared.richPresentationEnabled = original }

        AppSettings.shared.richPresentationEnabled = false
        let disabledRegistry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertFalse(disabledRegistry.has("present"))
        XCTAssertFalse(disabledRegistry.toolNames.contains("present"))

        AppSettings.shared.richPresentationEnabled = true
        let enabledRegistry = ToolRegistry(braveKeyAvailable: false)
        XCTAssertTrue(enabledRegistry.has("present"))
        XCTAssertTrue(enabledRegistry.toolNames.contains("present"))
    }

    func testPresentationServicePresentsHTMLAndStripsScripts() throws {
        let workspace = FakeWorkspace()
        let state = RichHTMLState()
        let service = PresentationService(workspace: workspace, richHTMLState: state)
        var didOpenWindow = false
        service.registerOpenRichHTMLWindow { didOpenWindow = true }

        let original = AppSettings.shared.richPresentationRemoteResourcesEnabled
        defer { AppSettings.shared.richPresentationRemoteResourcesEnabled = original }
        AppSettings.shared.richPresentationRemoteResourcesEnabled = false

        let message = try service.present(
            kind: .html,
            content: "<script>alert('x')</script><img src=\"https://example.com/a.png\"><p>Hello</p>",
            title: "News"
        )

        XCTAssertEqual(message, "Opened rich view: News")
        XCTAssertTrue(didOpenWindow)
        XCTAssertEqual(state.title, "News")
        XCTAssertTrue(state.html.contains("<p>Hello</p>"))
        XCTAssertFalse(state.html.contains("<script"))
        XCTAssertFalse(state.html.contains("example.com/a.png"))
    }

    func testPresentationServiceRejectsWhenRichPresentationDisabled() {
        let service = PresentationService(workspace: FakeWorkspace(), richHTMLState: RichHTMLState())
        let original = AppSettings.shared.richPresentationEnabled
        defer { AppSettings.shared.richPresentationEnabled = original }

        AppSettings.shared.richPresentationEnabled = false

        XCTAssertThrowsError(try service.present(kind: .html, content: "<p>Hello</p>")) { error in
            XCTAssertEqual(error as? PresentationError, .richPresentationDisabled)
        }
    }

    func testPresentationServiceStripsRefreshAndRemoteEmbedsWhenRemoteResourcesDisabled() throws {
        let service = PresentationService(workspace: FakeWorkspace(), richHTMLState: RichHTMLState())
        let original = AppSettings.shared.richPresentationRemoteResourcesEnabled
        defer { AppSettings.shared.richPresentationRemoteResourcesEnabled = original }
        AppSettings.shared.richPresentationRemoteResourcesEnabled = false
        service.registerOpenRichHTMLWindow { }

        _ = try service.present(
            kind: .html,
            content: """
            <meta http-equiv="refresh" content="0;url=https://example.com">
            <iframe src="https://example.com/embed"></iframe>
            <video src="https://example.com/video.mp4"></video>
            <p>Hello</p>
            """
        )

        let html = service.richHTMLState.html
        XCTAssertFalse(html.localizedCaseInsensitiveContains("http-equiv=\"refresh\""))
        XCTAssertFalse(html.contains("example.com/embed"))
        XCTAssertFalse(html.contains("example.com/video.mp4"))
        XCTAssertTrue(html.contains("<p>Hello</p>"))
    }

    func testPresentationServiceRejectsUnsupportedURLSchemes() {
        let service = PresentationService(workspace: FakeWorkspace(), richHTMLState: RichHTMLState())

        XCTAssertThrowsError(try service.present(kind: .url, content: "file:///tmp/secret.txt")) { error in
            XCTAssertEqual(error as? PresentationError, .urlSchemeNotAllowed)
        }
    }

    func testPresentationServiceOpensAllowedFiles() throws {
        let workspace = FakeWorkspace()
        let service = PresentationService(workspace: workspace, richHTMLState: RichHTMLState())
        let fileURL = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try service.present(kind: .file, content: fileURL.path)

        XCTAssertEqual(result, "Opened file: \(fileURL.path)")
        XCTAssertEqual(workspace.openedURLs, [fileURL])
    }

    func testPresentationServiceRejectsSensitiveFiles() {
        let service = PresentationService(workspace: FakeWorkspace(), richHTMLState: RichHTMLState())

        XCTAssertThrowsError(try service.present(kind: .file, content: "/etc/passwd")) { error in
            XCTAssertEqual(error as? PresentationError, .pathNotAllowed("/etc/passwd"))
        }
    }

    func testArtifactDetectorFindsMarkdownArtifactsAndBareURLs() {
        let text = """
        Here's [release notes](https://developer.apple.com/release-notes/).
        ![shot](/Users/zack/Desktop/screenshot.png)
        Also check https://example.com/plain for more.
        """

        let artifacts = ArtifactDetector.detect(in: text)

        XCTAssertEqual(artifacts.count, 3)
        XCTAssertTrue(artifacts.contains { $0.kind == .url && $0.content == "https://developer.apple.com/release-notes/" })
        XCTAssertTrue(artifacts.contains { $0.kind == .file && $0.content == "/Users/zack/Desktop/screenshot.png" })
        XCTAssertTrue(artifacts.contains { $0.kind == .url && $0.content == "https://example.com/plain" })
    }

    func testArtifactDetectorSkipsCodeAndBareLocalPaths() {
        let text = """
        Use `/Users/zack/Desktop/private.txt` later.
        ```
        https://inside-fence.example
        ![skip](/Users/zack/Desktop/skip.png)
        ```
        Inline `https://inline.example` also should not show.
        """

        let artifacts = ArtifactDetector.detect(in: text)

        XCTAssertTrue(artifacts.isEmpty)
    }

    func testRichHTMLNavigationDecisionOpensClickedHTTPLinksExternally() {
        let decision = RichHTMLView.navigationDecision(
            url: URL(string: "https://example.com/docs"),
            navigationType: .linkActivated,
            isMainFrame: true
        )

        XCTAssertEqual(decision, .openExternal)
    }

    func testRichHTMLNavigationDecisionCancelsAutomaticTopLevelNavigation() {
        let decision = RichHTMLView.navigationDecision(
            url: URL(string: "https://example.com/redirect"),
            navigationType: .other,
            isMainFrame: true
        )

        XCTAssertEqual(decision, .cancel)
    }

    func testRichHTMLNavigationDecisionAllowsInitialDocumentLoad() {
        let decision = RichHTMLView.navigationDecision(
            url: URL(string: "about:blank"),
            navigationType: .other,
            isMainFrame: true
        )

        XCTAssertEqual(decision, .allow)
    }
}

private final class FakeWorkspace: WorkspaceOpening {
    var openedURLs: [URL] = []

    @discardableResult
    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}
