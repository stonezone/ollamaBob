import Foundation

// MARK: - AgentLoop / Chat-with-heartbeat wrapper
//
// v1.0.52. Wraps `client.chat()` with two coordinated mechanisms the
// raw URLSession path can't provide:
//
//   1. Heartbeat polling of `/api/ps` every ~5s while the request is
//      in flight, so the UI can show "Bob is processing… (45s)"
//      instead of a blank avatar. With `stream: false` no bytes
//      arrive until generation completes; the heartbeat is the only
//      way to tell "Ollama is genuinely busy" from "Ollama silently
//      dropped us and we'll wait forever". Updates `waitState` on
//      AgentLoop, which is `@Published` and surfaces in the UI.
//
//   2. Wall-clock cap. URLSession's `timeoutIntervalForRequest` is
//      an idle (between-byte) timeout — useless when the server
//      keeps the TCP socket open while doing nothing. We race
//      `client.chat()` against a `Task.sleep` of
//      `AppConfig.ollamaSingleRequestWallClockCapSeconds`; whichever
//      finishes first wins, the other is cancelled. Hitting the
//      cap throws `CancellationError` (translated by the caller
//      into `AgentLoopError.cancelled`) and surfaces a chat-level
//      explanation so the user knows what happened.
//
// The heartbeat itself is also cancelled on Task cancellation, so
// the user's ⌘. Cancel button cleanly tears down both the chat
// request and the heartbeat.
extension AgentLoop {

    /// Drop-in replacement for `client.chat(...)` that adds the
    /// heartbeat + wall-clock cap. Same return type and exceptions
    /// (plus `CancellationError` for the wall-clock case, which the
    /// caller catches alongside its existing cancel handling).
    func chatWithHeartbeat(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaToolDef]?,
        numCtx: Int
    ) async throws -> OllamaChatResponse {
        let startedAt = Date()
        let messageCount = messages.count

        // Initial state. Heartbeat will overwrite once it polls.
        waitState = .thinking(elapsedSec: 0)

        heartbeat.start(
            requestedModel: model,
            startedAt: startedAt
        ) { [weak self] (sample: OllamaHeartbeat.HeartbeatSample) in
            guard let self else { return }
            // Don't overwrite a higher-severity state once it's set.
            // (Hard cap is set by the racing task, model-dropped is
            // sticky once detected.)
            if case .exceededHardCap = self.waitState { return }
            if case .modelDropped = self.waitState { return }

            let elapsedSec = Int(sample.elapsedSeconds)
            if sample.requestedModelDroppedMidRequest {
                self.waitState = .modelDropped(elapsedSec: elapsedSec)
                DebugLog.log(.timeout, "ollama-model-dropped-mid-request", [
                    "model": model,
                    "elapsedSec": "\(elapsedSec)"
                ])
                return
            }
            if sample.requestedModelLoaded {
                self.waitState = .processing(elapsedSec: elapsedSec, messageCount: messageCount)
            } else {
                // Model not loaded yet — could be cold-loading. Stay
                // in "thinking" until we either see it loaded (→
                // processing) or it never appears (→ stays thinking,
                // wall-clock cap will eventually fire).
                self.waitState = .thinking(elapsedSec: elapsedSec)
            }
        }

        defer {
            heartbeat.stop()
            waitState = .idle
        }

        // Race: chat() vs wall-clock sleep. First to finish wins.
        let cap = AppConfig.ollamaSingleRequestWallClockCapSeconds
        return try await withThrowingTaskGroup(of: OllamaChatResponse?.self) { group in
            // The real chat call.
            group.addTask { [client] in
                try await client.chat(
                    model: model,
                    messages: messages,
                    tools: tools,
                    numCtx: numCtx
                )
            }
            // The wall-clock cap. Returns nil to signal "the cap won".
            group.addTask { [weak self] in
                try await Task.sleep(nanoseconds: UInt64(cap * 1_000_000_000))
                if let self {
                    await MainActor.run {
                        self.waitState = .exceededHardCap(elapsedSec: Int(cap))
                    }
                }
                DebugLog.log(.timeout, "ollama-wall-clock-cap-fired", [
                    "model": model,
                    "capSec": "\(Int(cap))"
                ])
                return nil
            }

            // First completion wins.
            for try await result in group {
                group.cancelAll()
                if let response = result {
                    return response
                }
                // nil means the wall-clock task won; surface as cancel.
                throw CancellationError()
            }
            // Group finished without producing a value (shouldn't reach).
            throw CancellationError()
        }
    }
}
