import XCTest
@testable import OllamaBob

/// Coverage for the generic "announce-and-stop" continuation guard.
///
/// Failure mode the guard prevents: the model emits a future-action sentence
/// as the FINAL assistant text without actually calling the tool, then ends
/// the turn. Real example from production: user asked "use nmap to discover
/// what os is running on my router"; Bob said "Now, running nmap against
/// 192.168.1.1 to discover the operating system." and stopped without
/// calling the shell tool. See plan: announce-and-stop fix v1.0.45.
@MainActor
final class ContinuationGuardTests: XCTestCase {

    // MARK: - Positive: announce-and-stop should fire

    func testFiresOnNowRunningPattern() {
        let lastTool = ToolResult.success(tool: "shell", content: "default 192.168.1.1 ...", durationMs: 10)
        XCTAssertTrue(
            AgentLoop.shouldForceContinuation(
                assistantContent: "The default gateway appears to be 192.168.1.1. Now, running nmap against 192.168.1.1 to discover the operating system.",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
    }

    func testFiresOnLetMeRunPattern() {
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertTrue(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Got it. Let me run the conversion for you now.",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
    }

    func testFiresOnIllRunPattern() {
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertTrue(
            AgentLoop.shouldForceContinuation(
                assistantContent: "OK, I'll run the install now.",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
    }

    func testFiresOnRunningXNowPattern() {
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertTrue(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Running brew upgrade now.",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
    }

    func testFiresWhenNoPriorToolResultButAnnouncementPresent() {
        // Even with no prior tool, an announce-and-stop in the FIRST turn is
        // still a failure — the model said it would do something but didn't.
        XCTAssertTrue(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Let me check that for you now.",
                lastToolResult: nil,
                nudgeCount: 0
            )
        )
    }

    // MARK: - Negative: must NOT fire (false-positive guards)

    func testDoesNotFireOnPlainFinalAnswer() {
        let lastTool = ToolResult.success(tool: "shell", content: "192.168.1.1", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Your default gateway is 192.168.1.1.",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
    }

    func testDoesNotFireOnLegitimateQuestion() {
        // "Now I need to ask" / "Let me know" are legitimate user-facing
        // questions, not announce-and-stop. The guard must distinguish
        // "I'll do X" (action commitment) from "let me know what you want"
        // (turning the floor over to the user).
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Now I need to ask: which IP should I scan?",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Let me know which folder you want.",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
    }

    func testDoesNotFireOnEmptyContent() {
        // Empty content is a different failure mode; batch-audio guard
        // handles it for batch turns. Generic guard should only target
        // explicit announce-and-stop.
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
    }

    func testDoesNotFireWhenLastToolFailed() {
        // If the previous tool errored, pushing the model harder won't help;
        // it needs to recover or surface the error, not blindly retry.
        let failed = ToolResult.failure(tool: "shell", error: "exit 127", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Let me try that again now.",
                lastToolResult: failed,
                nudgeCount: 0
            )
        )
    }

    func testDoesNotFireAfterCapReached() {
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Now running nmap.",
                lastToolResult: lastTool,
                nudgeCount: AppConfig.continuationNudgeMax
            )
        )
    }

    func testDoesNotFireOnPastTenseRunning() {
        // "Just ran X" / "I ran X" describe completed work, not unkept
        // promises. Must not be confused with "running X now".
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "I ran the upgrade. Everything is up to date.",
                lastToolResult: lastTool,
                nudgeCount: 0
            )
        )
    }

    // MARK: - False-positive guards (regression cases caught in vibe-check)

    func testDoesNotFireOnRunningEveryNowAndThen() {
        // Real false positive caught during self-review: the regex
        // `\brunning\b(?:\s+\S+){1,5}\s+now\b` would match "running every
        // now and then" because `\bnow\b` is just a word boundary.
        // Tighten the regex to anchor `now` to a sentence-end (period,
        // exclamation, ellipsis, or end of string) so a mid-sentence
        // "now" doesn't trip it.
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "I have been running every now and then for the past hour.",
                lastToolResult: lastTool,
                nudgeCount: 0
            ),
            "must not fire on idiomatic 'every now and then'"
        )
    }

    func testDoesNotFireOnLetMeCheckAsThinkingLeadIn() {
        // Knowledge questions where "let me check" is just a thinking
        // lead-in for the model's own answer (no tool needed).
        // Without the trailing "now" / "for you" / similar action
        // marker, "let me check" should not be treated as an unkept
        // promise.
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "Let me check what I know about that. The answer is 42.",
                lastToolResult: lastTool,
                nudgeCount: 0
            ),
            "must not fire when 'let me check' is followed by a substantive answer"
        )
    }

    func testDoesNotFireOnRunningMentionedMidParagraph() {
        // "Running X now" must be at the END of the message, not
        // buried mid-paragraph followed by an actual answer.
        let lastTool = ToolResult.success(tool: "shell", content: "x", durationMs: 10)
        XCTAssertFalse(
            AgentLoop.shouldForceContinuation(
                assistantContent: "I tried running the command now and got the result. The output was 42.",
                lastToolResult: lastTool,
                nudgeCount: 0
            ),
            "must not fire when 'running X now' is mid-paragraph and a final answer follows"
        )
    }

    // MARK: - Nudge text

    func testNudgeTextEchoesAssistantPreview() {
        let preview = "Now, running nmap against 192.168.1.1 to discover the operating system."
        let nudge = AgentLoop.continuationNudge(for: preview)
        XCTAssertTrue(nudge.contains("nmap"), "nudge should echo a slice of what Bob said: \(nudge)")
        XCTAssertTrue(
            nudge.lowercased().contains("call the tool") || nudge.lowercased().contains("tool call"),
            "nudge should explicitly direct Bob to call the tool: \(nudge)"
        )
    }
}
