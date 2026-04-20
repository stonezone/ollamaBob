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

    func testAvatarBubblePreviewStripsFenceMarkersButKeepsCode() {
        let preview = ChatBubbleRendering.avatarBubblePreview(
            for: """
            ```bash
            cat ~/.zshrc
            ```
            """
        )

        XCTAssertEqual(preview.blocks.count, 1)
        if case .code(let language, let content) = preview.blocks[0] {
            XCTAssertEqual(language, "bash")
            XCTAssertEqual(content, "cat ~/.zshrc")
        } else {
            XCTFail("Expected code preview block")
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
}
