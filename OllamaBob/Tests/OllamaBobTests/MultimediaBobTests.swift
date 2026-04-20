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

    func testPresentationServiceActivatesBrowserForURLs() throws {
        let workspace = FakeWorkspace()
        let activator = FakeBrowserActivator()
        let service = PresentationService(
            workspace: workspace,
            richHTMLState: RichHTMLState(),
            browserActivator: activator
        )
        let url = "https://en.wikipedia.org/wiki/MacOS_Sequoia"

        let result = try service.present(kind: .url, content: url)

        XCTAssertEqual(result, "Opened URL: \(url)")
        XCTAssertEqual(workspace.openedURLs, [URL(string: url)!])
        XCTAssertEqual(activator.activatedURLs, [URL(string: url)!])
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

    func testArtifactDetectorTurnsRemoteMarkdownImagesIntoBrowserArtifacts() {
        let text = "![diagram](https://example.com/assets/diagram.png)"

        let artifacts = ArtifactDetector.detect(in: text)

        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.kind, .url)
        XCTAssertEqual(artifacts.first?.content, "https://example.com/assets/diagram.png")
        XCTAssertEqual(artifacts.first?.systemImage, "photo")
    }

    func testArtifactDetectorTrimsTrailingClosingPunctuationFromBareURLs() {
        let text = #"Read this (https://example.com/docs?q=1)."#

        let artifacts = ArtifactDetector.detect(in: text)

        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.content, "https://example.com/docs?q=1")
    }

    func testOperatingRulesRequireRawMarkdownForMarkdownOnlyRequests() {
        let prompt = BobOperatingRules.systemPrompt

        XCTAssertTrue(prompt.contains("\"Markdown only\" means raw markdown only"))
        XCTAssertTrue(prompt.contains("If the user explicitly asked for a fenced code block, output only that fenced block."))
        XCTAssertTrue(prompt.contains("If the user asks for one sentence, answer with exactly one sentence."))
    }

    func testOperatingRulesRequireClickableLinksAndPlainFailureWording() {
        let prompt = BobOperatingRules.systemPrompt

        XCTAssertTrue(prompt.contains("include real clickable `<a href=\"...\">` links"))
        XCTAssertTrue(prompt.contains("If a tool returns an error, denial, or refusal"))
        XCTAssertTrue(prompt.contains("say what was refused and why in one short sentence"))
    }

    func testAgentLoopRedirectsOpenIntentAwayFromReadFile() {
        XCTAssertTrue(
            AgentLoop.shouldRedirectReadFileToPresent(
                userMessage: "Open /etc/passwd so I can read it.",
                path: "/etc/passwd"
            )
        )
    }

    func testAgentLoopAllowsReadFileForExplicitContentRequests() {
        XCTAssertFalse(
            AgentLoop.shouldRedirectReadFileToPresent(
                userMessage: "Read the contents of /etc/passwd and summarize it.",
                path: "/etc/passwd"
            )
        )
    }

    func testAgentLoopRedirectsSimpleAppleScriptOpenRequestsToShell() {
        XCTAssertTrue(
            AgentLoop.shouldRedirectAppleScriptOpenToShell(
                userMessage: "Open ~/Desktop/m3-test.png in Preview for me.",
                script: #"tell application "Finder" to open POSIX file "/Users/zack/Desktop/m3-test.png""#
            )
        )
    }

    func testAgentLoopRedirectsPreviewAppleScriptOpenRequestsToShell() {
        XCTAssertTrue(
            AgentLoop.shouldRedirectAppleScriptOpenToShell(
                userMessage: "Open ~/Desktop/m3-test.png in Preview for me.",
                script: #"tell application "Preview" to open POSIX file "/Users/zack/Desktop/m3-test.png""#
            )
        )
    }

    func testAgentLoopRedirectsPreviewAppleScriptFileChainOpenRequestsToShell() {
        XCTAssertTrue(
            AgentLoop.shouldRedirectAppleScriptOpenToShell(
                userMessage: "Open ~/Desktop/m3-test.png in Preview for me.",
                script: #"tell application "Preview" to open file "m3-test.png" of folder "Desktop" of container "Macintosh HD:Users:$(whoami)""#
            )
        )
    }

    func testNormalizedFinalAssistantContentSynthesizesExplicitMarkdownImageReply() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "Basically sir, here is the note you wanted.",
            for: "Don't open anything. Just write me a short Markdown note that embeds the image at /Users/zack/Desktop/m3-test.png using the ![alt](path) syntax. Markdown only, no tool calls.",
            turnHadToolFailure: false,
            lastFailedToolResult: nil,
            lastToolResult: nil
        )

        XCTAssertEqual(normalized, "![m3-test](/Users/zack/Desktop/m3-test.png)")
    }

    func testNormalizedFinalAssistantContentCollapsesOneSentenceRequests() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "Actually sir, dis is very simple matter, na? Basically sir, the zsh config file is usually located at ~/.zshrc sir. Anything else sir?",
            for: "In one sentence, where's the zsh config file on macOS?",
            turnHadToolFailure: false,
            lastFailedToolResult: nil,
            lastToolResult: nil
        )

        XCTAssertEqual(normalized, "Basically sir, the zsh config file is usually located at ~/.zshrc sir.")
    }

    func testNormalizedFinalAssistantContentKeepsOnlyFencedCodeBlock() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "Yes sir.\n```bash\ncat ~/.zshrc\n```\nAnything else sir?",
            for: "Show me in a fenced bash code block the command to cat my zshrc. No tool calls — just the code block.",
            turnHadToolFailure: false,
            lastFailedToolResult: nil,
            lastToolResult: nil
        )

        XCTAssertEqual(normalized, "```bash\ncat ~/.zshrc\n```")
    }

    func testNormalizedFinalAssistantContentOverridesCheeryFailureCopy() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "Oh dear, dis is most inconvenient sir.",
            for: "Open /etc/passwd so I can read it.",
            turnHadToolFailure: true,
            lastFailedToolResult: .failure(tool: "present", error: "path not allowed", durationMs: 0),
            lastToolResult: .failure(tool: "present", error: "path not allowed", durationMs: 0)
        )

        XCTAssertEqual(normalized, "I couldn't open /etc/passwd because that path is not allowed.")
    }

    func testNormalizedFinalAssistantContentPrefersFinalSuccessfulOpenAfterEarlierFailure() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "I couldn't complete that request: a “\"” can't go after this property.",
            for: "Open ~/Desktop/m3-test.png in Preview for me.",
            turnHadToolFailure: true,
            lastFailedToolResult: .failure(tool: "applescript", error: #"A “"” can't go after this property. (-2740)"#, durationMs: 0),
            lastToolResult: .success(tool: "shell", content: "(no output)", durationMs: 0)
        )

        XCTAssertEqual(normalized, "I opened ~/Desktop/m3-test.png in Preview.")
    }

    func testNormalizedFinalAssistantContentPrefersSuccessfulOpenOverVagueFiller() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "Oh dear, dis is most inconvenient sir.",
            for: "Open ~/Desktop/m3-test.png in Preview for me.",
            turnHadToolFailure: true,
            lastFailedToolResult: .failure(tool: "applescript", error: "Could not parse script.", durationMs: 0),
            lastToolResult: .success(tool: "shell", content: "(no output)", durationMs: 0)
        )

        XCTAssertEqual(normalized, "I opened ~/Desktop/m3-test.png in Preview.")
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

    func testPresentationServiceInjectsDocumentDefaultsForFragments() {
        let html = PresentationService.injectDocumentDefaults(into: "<p>Hello</p>", allowRemoteResources: false)

        XCTAssertTrue(html.contains("color-scheme"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("<body>"))
        XCTAssertTrue(html.contains("<p>Hello</p>"))
    }

    func testPresentationServiceSanitizerStripsEventHandlersAndJavascriptURLs() {
        let html = PresentationService.sanitizeHTML(
            #"<a href="javascript:alert('x')" onclick="steal()">Click</a><img src="https://example.com/a.png" onload="steal()">"#,
            allowRemoteResources: false
        )

        XCTAssertFalse(html.localizedCaseInsensitiveContains("javascript:"))
        XCTAssertFalse(html.localizedCaseInsensitiveContains("onclick"))
        XCTAssertFalse(html.localizedCaseInsensitiveContains("onload"))
        XCTAssertFalse(html.contains("example.com/a.png"))
    }

    func testExternalURLPresenterOpensAndActivatesBrowser() {
        let workspace = FakeWorkspace()
        let activator = FakeBrowserActivator()
        let url = URL(string: "https://example.com/docs")!

        let didOpen = ExternalURLPresenter.open(url, workspace: workspace, browserActivator: activator)

        XCTAssertTrue(didOpen)
        XCTAssertEqual(workspace.openedURLs, [url])
        XCTAssertEqual(activator.activatedURLs, [url])
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

private final class FakeBrowserActivator: BrowserActivating {
    var activatedURLs: [URL] = []

    func activateBrowser(for url: URL) {
        activatedURLs.append(url)
    }
}
