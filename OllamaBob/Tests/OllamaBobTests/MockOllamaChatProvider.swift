import Foundation
@testable import OllamaBob

/// Test-only `OllamaChatProviding` impl backed by a scripted response
/// list (v1.0.57). Each `chat(...)` call dequeues the next response;
/// running off the end is a fatal error so missing scripted responses
/// surface as test failures rather than silent hangs.
///
/// Why this exists: the four agent-loop guards (BatchContinuation,
/// BatchAudit, GenericContinuation, ShellRecovery) had no integration
/// coverage — they were verified at the static-helper level only,
/// with the wiring in `AgentLoop.process()` "tested" by code review.
/// Twice this session we shipped a guard whose helper unit-tests
/// passed but whose `process()` wiring was wrong; production fired
/// the bug before a test could. With this mock + the new protocol
/// seam we can drive `process()` end-to-end with synthetic response
/// streams and assert that each guard's nudge actually appears in
/// the message list at the right point.
///
/// Sendable is required for actor / `any OllamaChatProviding`. We
/// reach in with an `NSLock` — the surface is small (one queue, one
/// recorded-input list) and the alternative (an actor) would force
/// `await` at every `script(_:)` call which is awkward in tests.
final class MockOllamaChatProvider: OllamaChatProviding, @unchecked Sendable {
    /// Each `Response` represents one scripted reply to a single
    /// `chat(...)` call.
    struct Response: Sendable {
        var content: String = ""
        var thinking: String? = nil
        var toolCalls: [OllamaToolCall]? = nil
        var doneReason: String? = "stop"

        /// Convenience for the most common shape — plain assistant
        /// text response with no tool calls.
        static func text(_ s: String, thinking: String? = nil) -> Response {
            Response(content: s, thinking: thinking)
        }

        /// Convenience for a tool-calling response. Args go in as a
        /// dict; we map to JSONValue.object using the same encoding
        /// the real daemon would emit.
        static func toolCall(_ name: String, args: [String: String] = [:], thinking: String? = nil, content: String = "") -> Response {
            let jsonArgs: JSONValue = .object(args.mapValues { .string($0) })
            return Response(
                content: content,
                thinking: thinking,
                toolCalls: [
                    OllamaToolCall(
                        id: nil,
                        function: OllamaToolCall.FunctionCall(
                            index: 0,
                            name: name,
                            arguments: jsonArgs
                        )
                    )
                ]
            )
        }

        /// Convenience for the empty-content + zero-tool-calls
        /// response that triggers the loop's "no tool calls = final"
        /// branch with no surface text. Useful for testing the
        /// audit-guard's "fire on empty content" path.
        static let empty = Response()
    }

    /// Captured input from each `chat(...)` call. Tests assert on
    /// these to verify the loop sent the right messages (especially
    /// after a guard nudge fires).
    struct CapturedCall: Sendable {
        let model: String
        let messages: [OllamaMessage]
    }

    private let lock = NSLock()
    private var script: [Response] = []
    private(set) var calls: [CapturedCall] = []

    /// Append a response (or many) to the script. Each scripted
    /// entry will be returned by exactly one `chat(...)` call in
    /// FIFO order.
    func enqueue(_ responses: Response...) {
        lock.lock(); defer { lock.unlock() }
        script.append(contentsOf: responses)
    }

    /// Reset between test cases so a single mock instance can be
    /// reused without state leakage.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        script.removeAll()
        calls.removeAll()
    }

    /// Snapshot of all calls observed so far. Returns a copy under
    /// lock so test assertions can iterate without races.
    func capturedCalls() -> [CapturedCall] {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    /// Number of scripted responses still pending.
    var remainingScriptCount: Int {
        lock.lock(); defer { lock.unlock() }
        return script.count
    }

    func chat(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaToolDef]?,
        numCtx: Int,
        keepAlive: String?
    ) async throws -> OllamaChatResponse {
        lock.lock()
        guard !script.isEmpty else {
            lock.unlock()
            preconditionFailure("MockOllamaChatProvider: chat() called \(calls.count + 1) times but only \(calls.count) responses were scripted. Add another `enqueue(...)` to the test setup.")
        }
        let response = script.removeFirst()
        calls.append(CapturedCall(model: model, messages: messages))
        lock.unlock()

        return OllamaChatResponse(
            model: model,
            createdAt: nil,
            message: OllamaMessage(
                role: "assistant",
                content: response.content,
                thinking: response.thinking,
                toolCalls: response.toolCalls
            ),
            done: true,
            doneReason: response.doneReason
        )
    }
}
