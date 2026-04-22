import XCTest
@testable import OllamaBob

@MainActor
final class ChatBubbleRenderingTests: XCTestCase {
    func testShouldShowAssistantBodySuppressesHTMLPayloadForPresentHTMLToolCall() {
        let call = makeToolCall(
            name: "present",
            arguments: [
                "kind": .string("html"),
                "content": .string("<!DOCTYPE html><html><body>Hello</body></html>")
            ]
        )

        XCTAssertFalse(
            ChatBubbleRendering.shouldShowAssistantBody(
                content: "<!DOCTYPE html><html><body>Hello</body></html>",
                toolCalls: [call]
            )
        )
    }

    func testShouldShowAssistantBodyKeepsHumanReadableMixedTurnText() {
        let call = makeToolCall(
            name: "present",
            arguments: [
                "kind": .string("url"),
                "content": .string("https://example.com")
            ]
        )

        XCTAssertTrue(
            ChatBubbleRendering.shouldShowAssistantBody(
                content: "Opening the page for you now.",
                toolCalls: [call]
            )
        )
    }

    func testToolCallSummaryIncludesPresentKindAndPreview() {
        let call = makeToolCall(
            name: "present",
            arguments: [
                "kind": .string("file"),
                "content": .string("/Users/zack/Desktop/m3-test.png")
            ]
        )

        XCTAssertEqual(
            ChatBubbleRendering.toolCallSummary(call),
            "file: /Users/zack/Desktop/m3-test.png"
        )
    }

    func testBlocksSplitMarkdownAndFencedCode() {
        let blocks = ChatBubbleRendering.blocks(
            for: """
            Here is **bold** text.

            ```bash
            cat ~/.zshrc
            ```
            """
        )

        XCTAssertEqual(blocks.count, 2)
        if case .markdown = blocks[0] {
        } else {
            XCTFail("Expected markdown block first")
        }

        if case .code(let language, let content) = blocks[1] {
            XCTAssertEqual(language, "bash")
            XCTAssertEqual(content, "cat ~/.zshrc")
        } else {
            XCTFail("Expected code block second")
        }
    }

    func testBlockEntriesUseStableIDsAcrossCalls() {
        let content = """
        Here is **bold** text.

        ```bash
        cat ~/.zshrc
        ```
        """

        let first = ChatBubbleRendering.blockEntries(for: content, cacheIdentity: "message-123")
        let second = ChatBubbleRendering.blockEntries(for: content, cacheIdentity: "message-123")

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.count, 2)
    }

    func testBlocksPreserveMarkdownAroundImageSyntax() {
        let blocks = ChatBubbleRendering.blocks(
            for: """
            Here is a chart: ![chart](https://example.com/chart.png)

            **Summary:** Sales up 12%.
            """
        )

        XCTAssertEqual(blocks.count, 1)
        if case .markdown(let attributed) = blocks[0] {
            let rendered = String(attributed.characters)
            XCTAssertTrue(rendered.contains("Here is a chart"))
            XCTAssertTrue(rendered.contains("Summary"))
        } else {
            XCTFail("Expected markdown block")
        }
    }

    func testAvatarBubblePreviewSummarizesPureCodeAsSpeech() {
        let preview = ChatBubbleRendering.avatarBubblePreview(
            for: """
            ```bash
            cat ~/.zshrc
            ```
            """
        )

        XCTAssertEqual(preview.blocks.count, 1)
        if case .markdown(let attributed) = preview.blocks[0] {
            XCTAssertEqual(
                String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines),
                "I have a shell snippet ready."
            )
        } else {
            XCTFail("Expected markdown speech summary")
        }
    }

    func testAvatarBubblePreviewReplacesMarkdownImageSyntaxWithPlaceholder() {
        let preview = ChatBubbleRendering.avatarBubblePreview(
            for: "![alt](/Users/zack/Desktop/m3-test.png)"
        )

        XCTAssertEqual(preview.blocks.count, 1)
        if case .markdown(let attributed) = preview.blocks[0] {
            XCTAssertEqual(
                String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines),
                "Image attached below."
            )
        } else {
            XCTFail("Expected markdown placeholder block")
        }
    }

    func testAvatarBubblePreviewReplacesHTMLPayloadWithPlaceholder() {
        let preview = ChatBubbleRendering.avatarBubblePreview(
            for: "<!DOCTYPE html><html><body><h1>Hello</h1></body></html>"
        )

        XCTAssertEqual(preview.blocks.count, 1)
        if case .markdown(let attributed) = preview.blocks[0] {
            XCTAssertEqual(
                String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines),
                "Opened rich view."
            )
        } else {
            XCTFail("Expected markdown placeholder block")
        }
    }

    func testAvatarBubblePreviewCondensesLongProseIntoThreeSpeechLines() {
        let preview = ChatBubbleRendering.avatarBubblePreview(
            for: """
            I reviewed the reply. I pulled the main point forward. I cut the extra implementation detail. The full explanation is still there.
            """
        )

        XCTAssertEqual(
            avatarPreviewLines(preview),
            [
                "I reviewed the reply.",
                "I pulled the main point forward.",
                "I cut the extra implementation detail."
            ]
        )
    }

    func testAvatarBubblePreviewCollapsesProseAndListIntoSpeechLikeSummary() {
        let preview = ChatBubbleRendering.avatarBubblePreview(
            for: """
            Here's the plan:

            - Tighten the avatar preview.
            - Keep Full mode unchanged.
            - Leave the geometry work for later.
            """
        )

        XCTAssertEqual(
            avatarPreviewLines(preview),
            ["Key points: Tighten the avatar preview; Keep Full mode unchanged; Leave the geometry work for later."]
        )
    }

    func testAvatarBubblePreviewKeepsSpeechButDropsRawCodeTranscript() {
        let content = """
        I tightened the preview for avatar mode.

        ```swift
        print("hello")
        ```
        """

        let preview = ChatBubbleRendering.avatarBubblePreview(for: content)

        XCTAssertEqual(
            avatarPreviewLines(preview),
            [
                "I tightened the preview for avatar mode.",
                "I also included a Swift snippet."
            ]
        )
        XCTAssertFalse(preview.blocks.contains(where: { block in
            if case .code = block {
                return true
            }
            return false
        }))
    }

    func testAvatarBubblePreviewDropsToolNoiseButKeepsHumanSummary() {
        let preview = ChatBubbleRendering.avatarBubblePreview(
            for: """
            I checked the repo and found local changes.
            stdout:
             M OllamaBob/OllamaBob/Views/ChatBubble.swift
             M OllamaBob/Tests/OllamaBobTests/ChatBubbleRenderingTests.swift
            exit code: 0
            """
        )

        XCTAssertEqual(
            avatarPreviewLines(preview),
            ["I checked the repo and found local changes."]
        )
    }

    func testFullModeBlocksRemainDetailedWhileAvatarPreviewTightens() {
        let content = """
        Here is the change.

        ```bash
        cat ~/.zshrc
        ```
        """

        let blocks = ChatBubbleRendering.blocks(for: content)
        let preview = ChatBubbleRendering.avatarBubblePreview(for: content)

        XCTAssertEqual(blocks.count, 2)
        if case .markdown(let attributed) = blocks[0] {
            XCTAssertEqual(
                String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines),
                "Here is the change."
            )
        } else {
            XCTFail("Expected markdown block first")
        }

        if case .code(let language, let code) = blocks[1] {
            XCTAssertEqual(language, "bash")
            XCTAssertEqual(code, "cat ~/.zshrc")
        } else {
            XCTFail("Expected code block second")
        }

        XCTAssertEqual(
            avatarPreviewLines(preview),
            [
                "Here is the change.",
                "I also included a shell snippet."
            ]
        )
    }

    func testTranscriptPreviewTruncatesLongContentWhenCollapsed() {
        let longText = Array(repeating: "line", count: 30).joined(separator: "\n")

        let preview = ChatBubbleRendering.transcriptPreview(for: longText, expanded: false, maxLines: 5, maxCharacters: 1000)
        let expanded = ChatBubbleRendering.transcriptPreview(for: longText, expanded: true, maxLines: 5, maxCharacters: 1000)

        XCTAssertTrue(preview.isTruncated)
        XCTAssertTrue(preview.text.hasSuffix("…"))
        XCTAssertFalse(expanded.isTruncated)
        XCTAssertEqual(expanded.text, longText)
    }

    private func makeToolCall(name: String, arguments: [String: JSONValue]) -> OllamaToolCall {
        OllamaToolCall(
            id: nil,
            function: OllamaToolCall.FunctionCall(
                index: nil,
                name: name,
                arguments: .object(arguments)
            )
        )
    }

    private func avatarPreviewLines(_ preview: ChatBubbleRendering.AvatarPreview) -> [String] {
        preview.blocks.compactMap { block in
            guard case .markdown(let attributed) = block else { return nil }
            let text = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}
