import XCTest
@testable import OllamaBob

final class ConversationCompactorTests: XCTestCase {
    func testApproxTokensAndShouldCompactUseSeventyFivePercentThreshold() {
        let underThreshold = [OllamaMessage.user(String(repeating: "a", count: 300))]
        let overThreshold = [OllamaMessage.user(String(repeating: "a", count: 304))]

        XCTAssertEqual(ConversationCompactor.approxTokens(underThreshold), 75)
        XCTAssertFalse(ConversationCompactor.shouldCompact(messages: underThreshold, numCtx: 100))
        XCTAssertTrue(ConversationCompactor.shouldCompact(messages: overThreshold, numCtx: 100))
    }

    func testCompactPreservesStructureAndSummarizesToolActivity() async {
        let firstCall = OllamaToolCall(
            id: "call-1",
            function: .init(
                index: 0,
                name: "read_file",
                arguments: .object(["path": .string("/tmp/file.txt")])
            )
        )
        let secondCall = OllamaToolCall(
            id: "call-2",
            function: .init(
                index: 1,
                name: "search_files",
                arguments: .object(["query": .string("report")])
            )
        )

        let input: [OllamaMessage] = [
            .system("system prompt"),
            .user("hello"),
            .toolResult(name: "shell", content: "fatal error: not found"),
            .assistant("tool invocation", toolCalls: [firstCall, secondCall]),
            OllamaMessage(role: "critic", content: "keep me")
        ]

        let client = OllamaClient(baseURL: "http://127.0.0.1:1")
        let output = await ConversationCompactor.compact(messages: input, client: client)

        XCTAssertEqual(output.count, 5)
        XCTAssertEqual(output[0].role, "system")
        XCTAssertEqual(output[0].content, "system prompt")
        XCTAssertEqual(output[1].role, "user")
        XCTAssertEqual(output[1].content, "hello")
        XCTAssertEqual(output[2].role, "tool")
        XCTAssertEqual(output[2].toolName, "shell")
        XCTAssertTrue(output[2].content.contains("tool result: shell"))
        XCTAssertTrue(output[2].content.contains("success=false"))
        XCTAssertEqual(output[3].role, "assistant")
        XCTAssertEqual(output[3].content.split(separator: "\n").count, 2)
        XCTAssertTrue(output[3].content.contains("tool call: read_file"))
        XCTAssertTrue(output[3].content.contains("tool call: search_files"))
        XCTAssertEqual(output[4].role, "critic")
        XCTAssertEqual(output[4].content, "keep me")
    }
}
