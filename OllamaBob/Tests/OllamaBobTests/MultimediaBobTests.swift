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

    func testPresentationServiceReopensStoredRichHTMLSnapshots() throws {
        let state = RichHTMLState()
        let service = PresentationService(workspace: FakeWorkspace(), richHTMLState: state)
        var openCount = 0
        service.registerOpenRichHTMLWindow { openCount += 1 }

        let original = AppSettings.shared.richPresentationEnabled
        defer { AppSettings.shared.richPresentationEnabled = original }
        AppSettings.shared.richPresentationEnabled = true

        let document = PresentationService.injectDocumentDefaults(into: "<p>Saved</p>", allowRemoteResources: false)
        let presentationID = state.storePresentation(title: "Saved View", html: document)

        let result = try service.reopenHTML(id: presentationID)

        XCTAssertEqual(result, "Reopened rich view: Saved View")
        XCTAssertEqual(state.title, "Saved View")
        XCTAssertEqual(state.html, document)
        XCTAssertEqual(openCount, 1)
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

    func testPresentationServiceOpensFileURLInputs() throws {
        let workspace = FakeWorkspace()
        let service = PresentationService(workspace: workspace, richHTMLState: RichHTMLState())
        let fileURL = URL(fileURLWithPath: "/tmp").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try service.present(kind: .file, content: fileURL.absoluteString)

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
        XCTAssertTrue(prompt.contains("prefer `present` with `kind=\"html\"` instead of writing a temporary file first"))
        XCTAssertTrue(prompt.contains("If a tool returns an error, denial, or refusal"))
        XCTAssertTrue(prompt.contains("say what was refused and why in one short sentence"))
    }

    func testOperatingRulesDescribeAuthorizedMusicAlbumWorkflow() {
        let prompt = BobOperatingRules.systemPrompt

        XCTAssertTrue(prompt.contains("Authorized music collection workflow"), prompt)
        XCTAssertTrue(prompt.contains("~/Music/Bob/<Artist>_<Album>"), prompt)
        XCTAssertTrue(prompt.contains("Do not ask the user to provide a YouTube URL for an album request"), prompt)
        XCTAssertTrue(prompt.contains("An album request is not a request for one \"full album\" YouTube link"), prompt)
        XCTAssertTrue(prompt.contains("Auto-select the best candidate when it has a near-exact artist and track-title match"), prompt)
        XCTAssertTrue(prompt.contains("Do not make the user choose between routine candidates"), prompt)
        XCTAssertTrue(prompt.contains("Do not stop after one successful track"), prompt)
        XCTAssertTrue(prompt.contains("If the user asks for a number of songs by an artist"), prompt)
        XCTAssertTrue(prompt.contains("If the user pastes a track list"), prompt)
        XCTAssertTrue(prompt.contains("a message like \"Next up is...\" is not enough"), prompt)
        XCTAssertTrue(prompt.contains("If the user explicitly asks for the album as one file"), prompt)
        XCTAssertTrue(prompt.contains("Do not split that file"), prompt)
        XCTAssertTrue(prompt.contains("full-album split workflow"), prompt)
        XCTAssertTrue(prompt.contains("Local audio conversion workflow"), prompt)
        XCTAssertTrue(prompt.contains("folder of `.flac` files"), prompt)
        XCTAssertTrue(prompt.contains("Do not ask after each file whether to continue"), prompt)
        XCTAssertTrue(prompt.contains("use `list_directory` with the exact folder path"), prompt)
        XCTAssertTrue(prompt.contains("quote paths that contain spaces"), prompt)
        XCTAssertTrue(prompt.contains("downloaded, missing, and any extra/unmatched files"), prompt)
        XCTAssertTrue(prompt.contains("Use silence detection only as a secondary QA/fallback"), prompt)
        XCTAssertTrue(prompt.contains("Only call `youtube_download` for URLs the user authorized you to save"), prompt)
        XCTAssertTrue(prompt.contains("pass `filename` like `01_Track_Title`"), prompt)
        XCTAssertTrue(prompt.contains("Existing folders may still have spaces"), prompt)
    }

    func testOperatingRulesPreferMailCheckForMailQuestions() {
        let prompt = BobOperatingRules.systemPrompt

        XCTAssertTrue(prompt.contains("- mail_check: Check Apple Mail inbox summaries"), prompt)
        XCTAssertTrue(prompt.contains("- mail_triage: Read short Apple Mail previews"), prompt)
        XCTAssertTrue(prompt.contains("Mail workflow"), prompt)
        XCTAssertTrue(prompt.contains("use `mail_check` before generic `applescript`"), prompt)
        XCTAssertTrue(prompt.contains("use `mail_triage`, not `mail_check`"), prompt)
        XCTAssertTrue(prompt.contains("does not read message bodies"), prompt)
        XCTAssertTrue(prompt.contains("needs attention, what is important, or what needs a reply"), prompt)
        XCTAssertTrue(prompt.contains("no first-class mail write tool yet"), prompt)
    }

    func testEmptyFinalMailCheckReplyFallsBackToVisibleToolResult() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "",
            for: "check my unread mail",
            turnHadToolFailure: false,
            lastFailedToolResult: nil,
            lastToolResult: .success(
                tool: "mail_check",
                content: "Showing 1 Mail message(s).\nMonday | unread | OpenAI <noreply@example.com> | Account notice",
                durationMs: 12
            )
        )

        XCTAssertTrue(normalized.contains("I found these Mail messages:"), normalized)
        XCTAssertTrue(normalized.contains("OpenAI <noreply@example.com>"), normalized)
    }

    func testEmptyFinalMailTriageReplyFallsBackToVisiblePreviewResult() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "   \n",
            for: "read my unread mail and tell me what needs attention",
            turnHadToolFailure: false,
            lastFailedToolResult: nil,
            lastToolResult: .success(
                tool: "mail_triage",
                content: "Showing 1 Mail triage preview(s).\nDate: Monday\nStatus: unread\nSender: Boss\nSubject: Need approval\nPreview: Please approve this today.",
                durationMs: 12
            )
        )

        XCTAssertTrue(normalized.contains("I pulled these Mail previews for triage"), normalized)
        XCTAssertTrue(normalized.contains("Need approval"), normalized)
    }

    func testBatchAudioRequestsUseExpandedAgentLoopBudget() {
        let popularSongsBudget = AgentLoop.loopBudget(for: "Get me 15 different Ben Bohmer songs as mp3s")
        XCTAssertEqual(popularSongsBudget.maxIterations, AppConfig.batchAudioAgentLoopMaxIterations)
        XCTAssertEqual(popularSongsBudget.timeoutSeconds, AppConfig.batchAudioAgentLoopTimeoutSeconds)

        let pastedListBudget = AgentLoop.loopBudget(for: "search and grab all these tracks from ben bohmer that i used to have before i lost my cds")
        XCTAssertEqual(pastedListBudget.maxIterations, AppConfig.batchAudioAgentLoopMaxIterations)
        XCTAssertEqual(pastedListBudget.timeoutSeconds, AppConfig.batchAudioAgentLoopTimeoutSeconds)

        let flacBudget = AgentLoop.loopBudget(for: "Convert the FLAC folder to MP3")
        XCTAssertEqual(flacBudget.maxIterations, AppConfig.batchAudioAgentLoopMaxIterations)
        XCTAssertEqual(flacBudget.timeoutSeconds, AppConfig.batchAudioAgentLoopTimeoutSeconds)

        let normalBudget = AgentLoop.loopBudget(for: "What is on my calendar today?")
        XCTAssertEqual(normalBudget.maxIterations, AppConfig.agentLoopMaxIterations)
        XCTAssertEqual(normalBudget.timeoutSeconds, AppConfig.agentLoopTimeoutSeconds)
    }

    func testBatchAudioContinuationGuardRejectsStatusOnlyNextUpReply() {
        let userMessage = "search and grab all these tracks from ben bohmer that i used to have before i lost my cds"
        let budget = AgentLoop.loopBudget(for: userMessage)
        let lastDownload = ToolResult.success(
            tool: "youtube_download",
            content: "Downloaded to /Users/zack/Music/Bob/Ben Bohmer/Hiding.mp3",
            durationMs: 10
        )

        XCTAssertTrue(
            AgentLoop.shouldForceBatchAudioContinuation(
                userMessage: userMessage,
                assistantContent: "Bob has downloaded Hiding for you. Next up, sir, is the track Cappadocia!<channel|>",
                lastToolResult: lastDownload,
                loopBudget: budget,
                nudgeCount: 0
            )
        )

        XCTAssertFalse(
            AgentLoop.shouldForceBatchAudioContinuation(
                userMessage: userMessage,
                assistantContent: "Downloaded 28 tracks to /Users/zack/Music/Bob/Ben Bohmer.",
                lastToolResult: lastDownload,
                loopBudget: budget,
                nudgeCount: 0
            )
        )
        XCTAssertFalse(
            AgentLoop.shouldForceBatchAudioContinuation(
                userMessage: "what is the weather?",
                assistantContent: "Next up is tomorrow.",
                lastToolResult: lastDownload,
                loopBudget: AgentLoop.loopBudget(for: "what is the weather?"),
                nudgeCount: 0
            )
        )
        XCTAssertFalse(
            AgentLoop.shouldForceBatchAudioContinuation(
                userMessage: userMessage,
                assistantContent: "Next up, sir, is Cappadocia.",
                lastToolResult: lastDownload,
                loopBudget: budget,
                nudgeCount: AppConfig.batchAudioContinuationNudgeMax
            )
        )
    }

    func testBatchAudioAuditParsesRequestedTracksAndDownloadedFiles() {
        let userMessage = """
        search and grab all these tracks from ben bohmer that i used to have before i lost my cds: Breathing
        Weightless (jamesjamesjames Remix)
        Beyond Beliefs
        Begin Again
        Erase
        Rust
        Hiding
        Cappadocia
        Voodoo
        Run Away
        """
        let messages: [OllamaMessage] = [
            .toolResult(name: "youtube_download", content: "<untrusted>\nDownloaded to /Users/zack/Music/Bob/Ben Bohmer - Missing CDs/01 - Breathing.mp3\n</untrusted>"),
            .toolResult(name: "youtube_download", content: "<untrusted>\nDownloaded to /Users/zack/Music/Bob/Ben Bohmer - Missing CDs/03 - Beyond Beliefs.mp3\n</untrusted>"),
            .toolResult(name: "youtube_download", content: "<untrusted>\nDownloaded to /Users/zack/Music/Bob/Ben Bohmer - Missing CDs/06 - Best of Ben Böhmer (Mix).mp3\n</untrusted>"),
            .toolResult(name: "youtube_download", content: "<untrusted>\nDownloaded to /Users/zack/Music/Bob/Ben Bohmer - Missing CDs/08 - Hiding.mp3\n</untrusted>")
        ]

        let requested = AgentLoop.requestedBatchAudioTracks(from: userMessage)
        XCTAssertEqual(requested.first, "Breathing")
        XCTAssertEqual(requested.count, 10)

        let audit = AgentLoop.batchAudioAudit(userMessage: userMessage, messages: messages)
        XCTAssertEqual(audit?.requestedTracks.count, 10)
        XCTAssertEqual(audit?.downloadedTracks.count, 4)
        XCTAssertEqual(audit?.outputDirectory, "/Users/zack/Music/Bob/Ben Bohmer - Missing CDs")
        XCTAssertEqual(
            audit?.missingTracks,
            [
                "Weightless (jamesjamesjames Remix)",
                "Begin Again",
                "Erase",
                "Rust",
                "Cappadocia",
                "Voodoo",
                "Run Away"
            ]
        )
        XCTAssertEqual(audit?.unmatchedDownloads, ["Best of Ben Böhmer (Mix)"])
    }

    func testBatchAudioAuditFindsPriorPastedListForFollowUpFolderQuestion() {
        let originalRequest = """
        search and grab all these tracks from ben bohmer:
        Breathing
        Beyond Beliefs
        Cappadocia
        """
        let messages: [OllamaMessage] = [
            .user(originalRequest),
            .toolResult(name: "youtube_download", content: "Downloaded to /Users/zack/Music/Bob/Ben_Bohmer_Missing_CDs/01_Breathing.mp3"),
            .user("i dont see all the songs in the local folder")
        ]

        let audit = AgentLoop.batchAudioAudit(
            userMessage: "i dont see all the songs in the local folder",
            messages: messages
        )

        XCTAssertEqual(audit?.requestedTracks, ["Breathing", "Beyond Beliefs", "Cappadocia"])
        XCTAssertEqual(audit?.downloadedTracks, ["Breathing"])
        XCTAssertEqual(audit?.missingTracks, ["Beyond Beliefs", "Cappadocia"])
        XCTAssertEqual(audit?.outputDirectory, "/Users/zack/Music/Bob/Ben_Bohmer_Missing_CDs")
    }

    func testBatchAudioAuditRejectsFalseCompletionAndProducesVisibleSummary() {
        let userMessage = """
        search and grab all these tracks from ben bohmer:
        Breathing
        Beyond Beliefs
        Cappadocia
        """
        let messages: [OllamaMessage] = [
            .toolResult(name: "youtube_download", content: "Downloaded to /Users/zack/Music/Bob/Ben Bohmer - Missing CDs/01 - Breathing.mp3")
        ]
        let audit = AgentLoop.batchAudioAudit(userMessage: userMessage, messages: messages)
        let lastDownload = ToolResult.success(
            tool: "youtube_download",
            content: "Downloaded to /Users/zack/Music/Bob/Ben Bohmer - Missing CDs/01 - Breathing.mp3",
            durationMs: 10
        )

        XCTAssertTrue(
            AgentLoop.shouldForceBatchAudioAuditContinuation(
                audit: audit,
                assistantContent: "All tools finished sir, most wery successful.",
                lastToolResult: lastDownload,
                loopBudget: AgentLoop.loopBudget(for: userMessage),
                nudgeCount: 0
            )
        )
        XCTAssertTrue(
            AgentLoop.shouldReplaceBatchAudioFinalContent("", audit: audit!)
        )

        let summary = AgentLoop.batchAudioFinalSummary(audit: audit!)
        XCTAssertTrue(summary.contains("Downloaded 1 of 3 requested tracks"), summary)
        XCTAssertTrue(summary.contains("Missing: Beyond Beliefs, Cappadocia."), summary)
    }

    func testToolHelpListIncludesBuiltInInventory() {
        let help = ToolRuntime.shared.renderToolHelpList()

        XCTAssertTrue(help.contains("Built-in tools:"))
        XCTAssertTrue(help.contains("read_file — Read a file's contents into chat by absolute path"))
    }

    func testToolHelpReturnsBuiltInToolDetails() {
        let help = ToolRuntime.shared.renderToolHelp(name: "read_file")

        XCTAssertTrue(help.contains("read_file — Read a file's contents into chat by absolute path"))
        XCTAssertTrue(help.contains("category: files"))
        XCTAssertTrue(help.contains("approval: auto"))
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

    func testNormalizedFinalAssistantContentExplainsMacOSFilePromptTimeoutForDesktopOpen() {
        let normalized = AgentLoop.normalizedFinalAssistantContent(
            "I couldn't complete that request: command timed out after 30s",
            for: "Open ~/Desktop/m3-test.png in Preview for me.",
            turnHadToolFailure: true,
            lastFailedToolResult: .failure(tool: "shell", error: "Command timed out after 30s", durationMs: 0),
            lastToolResult: .failure(tool: "shell", error: "Command timed out after 30s", durationMs: 0)
        )

        XCTAssertEqual(normalized, "I hit a macOS file-access prompt while opening ~/Desktop/m3-test.png. Approve it and retry.")
    }

    func testRichHTMLNavigationDecisionOpensClickedHTTPLinksExternally() {
        let decision = RichHTMLView.navigationDecision(
            url: URL(string: "https://example.com/docs"),
            navigationType: .linkActivated,
            isMainFrame: true
        )

        XCTAssertEqual(decision, .openExternal)
    }

    func testRichHTMLNavigationDecisionOpensClickedMailtoLinksExternally() {
        let decision = RichHTMLView.navigationDecision(
            url: URL(string: "mailto:bob@example.com"),
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
