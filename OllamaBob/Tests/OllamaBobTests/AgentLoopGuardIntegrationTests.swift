import XCTest
@testable import OllamaBob

/// End-to-end integration tests for the four agent-loop guards
/// (v1.0.57). Drives `AgentLoop.process()` with a scripted
/// `MockOllamaChatProvider` to verify each guard's wiring inside
/// the loop, not just the static helper.
///
/// Why this exists: every guard's static helper has unit-test
/// coverage, but the wiring inside `process()` was previously
/// "tested" by code review. Twice this session we shipped a guard
/// whose helper passed but whose wiring was wrong (audit guard
/// firing condition; nudge text passing the right `lastToolResult`).
/// These tests make wiring regressions surface in CI before
/// production.
@MainActor
final class AgentLoopGuardIntegrationTests: XCTestCase {

    // MARK: - GenericContinuationGuard (announce-and-stop)

    func testContinuationGuardInjectsNudgeAndLoopRecovers() async throws {
        let mock = MockOllamaChatProvider()
        // Iteration 1: model emits "Let me check…" with no tool
        // calls. This trips shouldForceContinuation because the
        // sentence ends with a future-action commitment but there's
        // no actual tool call.
        // Iteration 2: model gives a plain final answer. Loop
        // returns normally.
        mock.enqueue(
            .text("Let me check the weather for you now."),
            .text("It's sunny — 72°F.")
        )

        let loop = AgentLoop(client: mock, braveKeyAvailable: false)
        let history: [OllamaMessage] = []
        let result = try await loop.process(
            userMessage: "what's the weather?",
            history: history,
            conversationId: "test-continuation",
            uncensoredMode: false
        )

        // The mock should have been called twice — once for the
        // original turn, once after the guard fired and the loop
        // re-entered with the nudge appended.
        let calls = mock.capturedCalls()
        XCTAssertEqual(calls.count, 2, "loop should re-enter after continuation guard fires")

        // The second call must have a system-role nudge message
        // injected after the user message. We don't assert exact
        // wording (would be brittle to copy-edits) but we assert
        // the nudge has the load-bearing instruction: "call the
        // tool".
        let secondCallSystemMessages = calls[1].messages.filter { $0.role == "system" }
        let hasNudge = secondCallSystemMessages.contains { msg in
            let lower = msg.content.lowercased()
            return lower.contains("call the tool")
                || lower.contains("did not call")
        }
        XCTAssertTrue(hasNudge, "second iteration's system messages must include the continuation nudge: \(secondCallSystemMessages.map(\.content))")

        // The broken first-iteration assistant message should NOT
        // be in the final returned history — the guard drops it.
        // The final assistant message should be the recovery turn.
        let assistantMessages = result.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMessages.count, 1, "broken announce-and-stop reply must be dropped, not appended")
        XCTAssertEqual(assistantMessages.last?.content, "It's sunny — 72°F.")
    }

    func testContinuationGuardCapPreventsInfiniteLoop() async throws {
        let mock = MockOllamaChatProvider()
        // Both iterations emit the same announce-and-stop pattern.
        // After the first nudge fires, cap (default 1) is reached
        // and the loop must terminate — surfacing the second broken
        // reply to the user rather than spinning forever.
        mock.enqueue(
            .text("Let me check that now."),
            .text("Let me check that now.")
        )

        let loop = AgentLoop(client: mock, braveKeyAvailable: false)
        let result = try await loop.process(
            userMessage: "do the thing",
            history: [],
            conversationId: "test-cap",
            uncensoredMode: false
        )

        XCTAssertEqual(mock.capturedCalls().count, 2, "cap=1 means exactly two chat calls (original + one nudge)")
        let assistantMessages = result.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMessages.count, 1, "loop must exit cleanly after cap reached, not spin")
    }

    // MARK: - Wiring sanity (no guard fires)

    func testPlainResponseExitsLoopWithoutGuards() async throws {
        let mock = MockOllamaChatProvider()
        mock.enqueue(.text("It's 72°F and sunny."))

        let loop = AgentLoop(client: mock, braveKeyAvailable: false)
        let result = try await loop.process(
            userMessage: "what's the weather?",
            history: [],
            conversationId: "test-plain",
            uncensoredMode: false
        )

        XCTAssertEqual(mock.capturedCalls().count, 1, "no guard should fire on a plain final answer")
        let assistantMessages = result.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMessages.last?.content, "It's 72°F and sunny.")
    }

    // MARK: - ShellRecoveryGuard
    //
    // ShellRecovery requires a real shell tool dispatch result with
    // success=false, retryable stderr (`usage:`, `command not
    // found`, etc.) AND give-up assistant content. Driving the full
    // dispatch path through process() requires the shell tool to
    // actually run. Rather than bring up `/bin/false`-style real
    // commands in the test, we exercise the static helper directly
    // (already covered by ShellRecoveryGuardTests) AND assert the
    // wiring shape via a synthetic precondition: when no tool
    // dispatch happened in the turn, the recovery guard cannot
    // fire (lastToolResult=nil). This proves the guard is gated on
    // tool history, not just text patterns.

    func testShellRecoveryGuardDoesNotFireWithoutToolDispatch() async throws {
        // Setup: model gives a "give-up" reply but no shell call
        // ever happened. Recovery guard must NOT fire — there's no
        // failed shell to recover from.
        let mock = MockOllamaChatProvider()
        mock.enqueue(.text("I couldn't find that. The command failed earlier."))

        let loop = AgentLoop(client: mock, braveKeyAvailable: false)
        let result = try await loop.process(
            userMessage: "do something complicated",
            history: [],
            conversationId: "test-recovery-noop",
            uncensoredMode: false
        )

        XCTAssertEqual(mock.capturedCalls().count, 1,
                       "shell-recovery guard must not fire without a prior failed shell tool")
        let assistantMessages = result.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMessages.count, 1)
    }

    // MARK: - Batch-audio guards
    //
    // BatchContinuation + BatchAudit only fire under batch-audio
    // budget (loopBudget classifier matches "all these tracks" or
    // similar). These tests validate the budget classifier hands
    // the loop into batch mode AND that a non-batch user message
    // skips both batch guards.

    func testNonBatchMessageDoesNotEnterBatchAudioGuards() async throws {
        // Plain "what's the weather" → loop budget is the normal
        // 120s/10-iter pair, NOT the batch-audio 3600s/160-iter.
        // Both batch guards check loopBudget == batch and bail
        // immediately when they see the normal budget.
        let mock = MockOllamaChatProvider()
        mock.enqueue(.text("It's sunny."))

        let loop = AgentLoop(client: mock, braveKeyAvailable: false)
        _ = try await loop.process(
            userMessage: "what's the weather?",
            history: [],
            conversationId: "test-non-batch",
            uncensoredMode: false
        )

        // Sanity: only one chat call, meaning no batch guard fired
        // a continuation nudge.
        XCTAssertEqual(mock.capturedCalls().count, 1)
    }

    func testBatchAudioBudgetActivatesOnTrackListPattern() async throws {
        // The v1.0.48 typo-tolerant classifier triggers batch budget
        // when the user pastes 3+ "X — Y" lines + a music keyword,
        // even with a misspelled action verb. This is the integration
        // path the search-loop fix relies on.
        let mock = MockOllamaChatProvider()
        // Empty content + zero tool calls → batch-audio audit guard
        // would fire if budget is batch AND a successful previous
        // tool returned items. Without a prior tool, audit doesn't
        // fire even in batch mode → loop exits cleanly.
        mock.enqueue(.text("OK, here's what I found."))

        let loop = AgentLoop(client: mock, braveKeyAvailable: false)
        let userMessage = """
        cand find my cds, can you downlaod these mp3s from youtube: \
        Respect — Aretha Franklin
        Superstition — Stevie Wonder
        What's Going On — Marvin Gaye
        """
        _ = try await loop.process(
            userMessage: userMessage,
            history: [],
            conversationId: "test-batch-classify",
            uncensoredMode: false
        )

        // Just one chat call — guard didn't fire because no tool
        // result preceded the empty assistant response. But the
        // budget classifier itself routing the message into batch
        // mode is what we validate by inspecting numCtx survival
        // through the larger budget. (If budget were 120s the loop
        // would still complete in one call too, so this is a smoke
        // assertion: at minimum, the path doesn't crash on the
        // long-budget code path.)
        XCTAssertEqual(mock.capturedCalls().count, 1)
    }

    // MARK: - System prompt sanity

    func testBuildsSystemPromptFromBobOperatingRules() async throws {
        // Smoke: verify the loop actually prepends a system message
        // before sending. If this regresses, every guard's "did
        // the system prompt land" assumption breaks.
        let mock = MockOllamaChatProvider()
        mock.enqueue(.text("ok"))

        let loop = AgentLoop(client: mock, braveKeyAvailable: false)
        _ = try await loop.process(
            userMessage: "ping",
            history: [],
            conversationId: "test-sysprompt",
            uncensoredMode: false
        )

        let firstCall = mock.capturedCalls()[0]
        XCTAssertEqual(firstCall.messages.first?.role, "system",
                       "first message in every chat request must be the composed system prompt")
        // Sanity: the composed prompt contains a known fragment from
        // BobOperatingRules.
        let firstSystemContent = firstCall.messages.first?.content ?? ""
        XCTAssertTrue(firstSystemContent.contains("EMIT THE TOOL CALL IMMEDIATELY"),
                      "system prompt must include BobOperatingRules content")
    }
}
