import XCTest
@testable import OllamaBob

final class ContextBudgetTests: XCTestCase {
    func testContextBudgetReportsZeroOnEmptyStack() {
        let snapshot = ContextBudget.snapshot(messages: [OllamaMessage](), numCtx: 100)

        XCTAssertEqual(snapshot.approxTokens, 0)
        XCTAssertEqual(snapshot.percent, 0)
        XCTAssertFalse(snapshot.shouldWarn)
    }

    func testContextBudgetCountsAllRoles() {
        let call = OllamaToolCall(
            id: "call-1",
            function: .init(
                index: 0,
                name: "read_file",
                arguments: .object(["path": .string("/tmp/a.txt")])
            )
        )
        let messages = [
            OllamaMessage.system(String(repeating: "s", count: 35)),
            OllamaMessage.user(String(repeating: "u", count: 35)),
            OllamaMessage.assistant(String(repeating: "a", count: 35), toolCalls: [call]),
            OllamaMessage.toolResult(name: "read_file", content: String(repeating: "t", count: 35))
        ]

        let snapshot = ContextBudget.snapshot(messages: messages, numCtx: 1_000)

        XCTAssertGreaterThanOrEqual(snapshot.approxTokens, 40)
    }

    func testContextBudgetPercentageCorrectAtKnownNumCtx() {
        let messages = [OllamaMessage.user(String(repeating: "a", count: 346))]
        let snapshot = ContextBudget.snapshot(messages: messages, numCtx: 100)

        XCTAssertEqual(snapshot.approxTokens, 100)
        XCTAssertEqual(snapshot.percent, 1.0)
        XCTAssertTrue(snapshot.shouldWarn)
    }

    func testContextBudgetUsesQwenAbliteratedDefaultNumCtx() {
        let snapshot = ContextBudget.snapshot(messages: [.user(String(repeating: "a", count: 350))])

        XCTAssertEqual(snapshot.numCtx, ContextBudget.qwenAbliteratedDefaultNumCtx)
        XCTAssertEqual(ContextBudget.qwenAbliteratedDefaultNumCtx, AppConfig.numCtx)
    }

    func testContextBudgetCountsVisibleChatMessages() {
        let messages = [
            ChatMessage(role: .user, content: String(repeating: "u", count: 100)),
            ChatMessage(role: .assistant, content: String(repeating: "a", count: 100))
        ]

        let snapshot = ContextBudget.snapshot(messages: messages, numCtx: 100)

        XCTAssertGreaterThan(snapshot.percent, 0.5)
        XCTAssertLessThan(snapshot.percent, 0.7)
        XCTAssertFalse(snapshot.shouldWarn)
    }

    func testContextBudgetWarningThresholdStartsAtEightyFivePercent() {
        let below = ContextBudget.snapshot(messages: [.user(String(repeating: "a", count: 290))], numCtx: 100)
        let atThreshold = ContextBudget.snapshot(messages: [.user(String(repeating: "a", count: 291))], numCtx: 100)

        XCTAssertEqual(below.approxTokens, 84)
        XCTAssertFalse(below.shouldWarn)
        XCTAssertEqual(atThreshold.approxTokens, 85)
        XCTAssertTrue(atThreshold.shouldWarn)
    }

    func testContextBudgetIgnoresDecodedThinking() {
        let plain = ContextBudget.snapshot(messages: [OllamaMessage.user("hello")], numCtx: 100)
        let withThinking = ContextBudget.snapshot(
            messages: [OllamaMessage(role: "user", content: "hello", thinking: String(repeating: "x", count: 1_000))],
            numCtx: 100
        )

        XCTAssertEqual(withThinking.approxTokens, plain.approxTokens)
    }
}
