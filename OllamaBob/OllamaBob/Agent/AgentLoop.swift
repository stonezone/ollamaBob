import Foundation

enum AgentLoopError: Error, LocalizedError {
    case maxIterationsReached(Int)
    case totalTimeoutReached(TimeInterval)
    case ollamaUnavailable(String)
    case uncensoredModelUnavailable(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .maxIterationsReached(let limit):
            return "Reached maximum tool call iterations (\(limit))"
        case .totalTimeoutReached(let seconds):
            return "Agent loop timed out after \(Int(seconds))s"
        case .ollamaUnavailable(let msg):
            return msg
        case .uncensoredModelUnavailable(let model):
            return "Uncensored mode is enabled for this conversation, but model '\(model)' is not installed. Run: ollama pull \(model)"
        case .cancelled:
            return "Cancelled by user."
        }
    }
}

/// Callback for approval requests. Returns true if approved.
typealias ApprovalHandler = @Sendable (String, String, ApprovalLevel) async -> Bool

/// Callback for model switch notifications.
typealias ModelSwitchHandler = @Sendable (String, String) async -> Void

/// Visual mood that drives which Bob portrait sprite the UI shows.
/// Set at meaningful state transitions inside the agent loop. Persists
/// until the next transition — view layer reads it and cross-fades.
enum BobMood: String {
    case idle, thinking, typing, happy, sheepish, confused
}

@MainActor
final class AgentLoop: ObservableObject {
    @Published var isProcessing = false
    @Published var currentModel: String = AppConfig.primaryModel
    @Published var toolActivity: [ToolLogEntry] = []
    /// Most recent model-switch event, if any. Cleared by the UI after display.
    @Published var modelSwitchNotice: ModelSwitchNotice?
    /// Drives the Bob portrait sprite. Updated at transitions in process().
    @Published var bobMood: BobMood = .idle
    /// Live wait state during a chat request (v1.0.52). UI surfaces
    /// this in the status strip below the avatar so the user can
    /// distinguish "Bob is genuinely thinking" from "Ollama dropped
    /// the connection and Bob is wedged" during the long blank window
    /// when no response bytes have arrived yet.
    @Published var waitState: WaitState = .idle

    /// Lifecycle of a single Ollama chat request from the user's POV.
    /// Computed from the OllamaHeartbeat sample plus elapsed time.
    enum WaitState: Equatable, Sendable {
        /// Not currently waiting on Ollama.
        case idle
        /// Recently fired the request; waiting for the first signal.
        /// Heartbeat may not have polled yet.
        case thinking(elapsedSec: Int)
        /// Heartbeat confirms the model is loaded and Ollama is busy.
        /// Includes elapsed seconds and the message count so the user
        /// understands "this is taking a while because the chat is huge".
        case processing(elapsedSec: Int, messageCount: Int)
        /// Model was loaded then unloaded mid-request — Ollama silently
        /// dropped us. The chat call is not going to complete; user
        /// should cancel.
        case modelDropped(elapsedSec: Int)
        /// Wall-clock cap (`AppConfig.ollamaSingleRequestWallClockCapSeconds`)
        /// reached — we're about to force-cancel.
        case exceededHardCap(elapsedSec: Int)

        /// Human-readable status line for the UI.
        var displayText: String {
            switch self {
            case .idle:
                return ""
            case .thinking(let s):
                return "thinking… (\(formatElapsed(s)))"
            case .processing(let s, let n):
                let context = n > 50 ? " — \(n) msgs is a lot of context" : ""
                return "Bob is processing… (\(formatElapsed(s)))\(context)"
            case .modelDropped(let s):
                return "Ollama dropped the connection at \(formatElapsed(s)) — hit ⌘. and retry"
            case .exceededHardCap(let s):
                return "exceeded \(formatElapsed(s)) — auto-cancelling"
            }
        }

        private func formatElapsed(_ s: Int) -> String {
            if s < 60 { return "\(s)s" }
            let m = s / 60
            let sec = s % 60
            return "\(m)m\(sec)s"
        }
    }

    struct ModelSwitchNotice: Equatable, Identifiable {
        let id = UUID()
        let from: String
        let to: String
        let at: Date
    }

    struct LoopBudget: Equatable {
        let maxIterations: Int
        let timeoutSeconds: TimeInterval
    }

    struct BatchAudioAudit: Equatable {
        let requestedTracks: [String]
        let downloadedTracks: [String]
        let missingTracks: [String]
        let unmatchedDownloads: [String]
        let outputDirectory: String?
    }

    // Phase 2a: lifted from `private` to module-internal so the
    // AgentLoop+* coordinator extensions in sibling files
    // (AgentLoopOllamaPump, AgentLoopToolDispatch, ...) can read and
    // mutate the same in-flight state. The class is `final` and the
    // module is the trust boundary; nothing outside the module can
    // reach these names.
    let client: OllamaClient
    let registry: ToolRegistry
    var searchProvider: SearchProvider?
    var consecutiveFailures = 0
    /// Set for the duration of a single `process()` call. The ToolOutputStore
    /// and the `read_tool_output` meta-tool use this to scope spillout files
    /// per conversation.
    var currentConversationId: String?
    var currentUserMessage: String?
    var currentPhoneCallContext: String?
    var currentUncensoredMode = false

    var approvalHandler: ApprovalHandler?
    var modelSwitchHandler: ModelSwitchHandler?

    // MARK: - Cancellation
    //
    // Phase A (long-running shell): the user can stop a turn mid-flight from
    // the ⏹ button in DeskInputView, or per-tool from a glyph on the live
    // tool-call bubble in ChatBubble. Three pieces work together:
    //
    //   1. `cancelRequested` — a polled flag. The agent loop checks it
    //      after each Ollama response and after each tool call so cancel
    //      becomes effective at the next safe seam, even if the wrapping
    //      Task is not actually cancelled.
    //   2. `activeCancelHandles` — every in-flight tool that supports
    //      cancellation (currently only `shell`) registers a CancelHandle
    //      keyed by its ToolLogEntry id. `cancel()` walks the dictionary
    //      and fires SIGTERM→SIGKILL on each child process.
    //   3. `processingTask` — optional handle to the wrapping Task. If
    //      registered by the session controller, `cancel()` also calls
    //      `Task.cancel()` so an in-flight Ollama HTTP request that
    //      respects cooperative cancellation will tear down faster.
    //
    // Reset at the top of `process()` so a stale cancel from a prior turn
    // does not silently kill the next one.
    private(set) var cancelRequested = false
    var processingTask: Task<Void, Never>?
    private var activeCancelHandles: [UUID: ProcessRunner.CancelHandle] = [:]
    /// Long-lived heartbeat helper. One instance, reused across turns;
    /// it `start()`s when the chat request fires and `stop()`s when the
    /// response arrives or the request is cancelled. v1.0.52.
    /// `internal` because the chat-with-heartbeat extension lives in a
    /// sibling file and Swift's `private` is per-file.
    let heartbeat = OllamaHeartbeat()

    /// Cancel everything in flight: pending shell processes (SIGTERM→SIGKILL),
    /// the wrapping Task if registered, and the agent loop itself at the next
    /// iteration boundary. Idempotent; safe to call when nothing is running.
    func cancel() {
        cancelRequested = true
        let handles = Array(activeCancelHandles.values)
        activeCancelHandles.removeAll()
        for handle in handles {
            handle.cancel()
        }
        processingTask?.cancel()
    }

    /// Cancel a single in-flight tool (currently only `shell`) without
    /// aborting the whole turn. The loop continues with the cancelled
    /// tool's result fed back to the model so it can react.
    func cancelToolEntry(id: UUID) {
        guard let handle = activeCancelHandles.removeValue(forKey: id) else { return }
        handle.cancel()
    }

    /// Session controller registers its wrapping Task here so `cancel()` can
    /// also call `Task.cancel()`. Optional — the polled `cancelRequested`
    /// flag is the primary mechanism.
    func registerProcessingTask(_ task: Task<Void, Never>?) {
        processingTask = task
    }

    /// Add an in-flight cancel handle to the registry. Caller is responsible
    /// for `deregister`ing on completion. Internal — used by tool dispatchers.
    func registerCancelHandle(_ handle: ProcessRunner.CancelHandle, entryId: UUID) {
        activeCancelHandles[entryId] = handle
    }

    /// Remove a cancel handle from the registry without firing it. Used when
    /// a tool completes normally.
    func deregisterCancelHandle(entryId: UUID) {
        activeCancelHandles.removeValue(forKey: entryId)
    }

    /// Live, observable record of a single tool invocation.
    ///
    /// Was a value type until Phase A (long-running shell). Now a reference
    /// type so streaming tools (`shell`) can append to `output` and toggle
    /// `isInFlight` while UI views observe the same entry. The class is
    /// pure in-memory UI state — never Codable, never persisted to SQLite,
    /// never re-encoded into Ollama messages — so the value→reference
    /// switch has no downstream cascade.
    ///
    /// `@MainActor` is explicit because nested types do not inherit the
    /// outer `AgentLoop` isolation. All mutation goes through `appendOutput`
    /// or `finalize`, which therefore must be called on the main actor.
    @MainActor
    final class ToolLogEntry: ObservableObject, Identifiable {
        nonisolated let id = UUID()
        let toolName: String
        let input: String
        let approval: ApprovalLevel
        let approved: Bool
        let timestamp: Date

        @Published var output: String
        @Published var durationMs: Int
        @Published var isInFlight: Bool
        @Published var success: Bool

        /// Cancel handle for in-flight tools that support cancellation
        /// (currently only `shell`). nil for atomic tools. Set by the
        /// dispatcher when the run starts; cleared on `finalize`.
        var cancelHandle: ProcessRunner.CancelHandle?

        /// Soft tail-cap on `output` to keep memory bounded under chatty
        /// long-runners (e.g. `brew upgrade` printing ~50 lines/sec). When
        /// the buffer would exceed this size, the oldest half is dropped
        /// and a `[output truncated to last X KB]` marker is prepended.
        private let outputTailCap: Int
        private var didTruncate = false

        init(
            toolName: String,
            input: String,
            output: String = "",
            approval: ApprovalLevel,
            approved: Bool,
            durationMs: Int = 0,
            isInFlight: Bool = false,
            success: Bool = true,
            timestamp: Date = Date(),
            cancelHandle: ProcessRunner.CancelHandle? = nil,
            outputTailCap: Int = 200_000
        ) {
            self.toolName = toolName
            self.input = input
            self.output = output
            self.approval = approval
            self.approved = approved
            self.durationMs = durationMs
            self.isInFlight = isInFlight
            self.success = success
            self.timestamp = timestamp
            self.cancelHandle = cancelHandle
            self.outputTailCap = outputTailCap
        }

        /// Append a streamed chunk to the live output, applying a tail cap
        /// so a long-running noisy command can't blow up memory.
        func appendOutput(_ chunk: String) {
            var next = output + chunk
            if next.count > outputTailCap {
                let keep = outputTailCap / 2
                let dropped = next.count - keep
                next = String(next.suffix(keep))
                if !didTruncate {
                    didTruncate = true
                    next = "[output truncated — dropped earliest \(dropped) chars]\n" + next
                } else {
                    next = "[output truncated — dropped earliest \(dropped) chars]\n" + next
                }
            }
            output = next
        }

        /// Mark the entry complete with its final output and duration. Also
        /// detaches any cancel handle so the per-tool ⏹ glyph can disable.
        func finalize(output finalOutput: String, durationMs ms: Int, success ok: Bool) {
            self.output = finalOutput
            self.durationMs = ms
            self.success = ok
            self.isInFlight = false
            self.cancelHandle = nil
        }
    }

    init(client: OllamaClient = OllamaClient(), braveKeyAvailable: Bool = !AppConfig.braveAPIKey.isEmpty) {
        self.client = client
        self.registry = ToolRegistry(braveKeyAvailable: braveKeyAvailable)
        self.currentModel = AppSettings.shared.effectiveStandardModelName
        if braveKeyAvailable {
            self.searchProvider = BraveSearchProvider(apiKey: AppConfig.braveAPIKey)
        }
    }

    /// Process a user message through the agent loop.
    /// Returns the full message history including tool calls and final response.
    /// `conversationId` scopes the tool output spillout store so `/clear` can
    /// wipe its files and `read_tool_output` ids don't collide across chats.
    func process(
        userMessage: String,
        history: [OllamaMessage],
        conversationId: String,
        uncensoredMode: Bool
    ) async throws -> [OllamaMessage] {
        isProcessing = true
        bobMood = .thinking
        consecutiveFailures = 0
        currentConversationId = conversationId
        currentUserMessage = userMessage
        currentUncensoredMode = uncensoredMode
        // Phase A: clear any stale cancel from a prior aborted turn so the
        // first iteration is not immediately treated as cancelled.
        cancelRequested = false
        activeCancelHandles.removeAll()
        defer {
            isProcessing = false
            currentConversationId = nil
            currentUserMessage = nil
            currentPhoneCallContext = nil
            currentUncensoredMode = false
            processingTask = nil
            activeCancelHandles.removeAll()
        }

        let effectiveModel = uncensoredMode
            ? AppSettings.shared.effectiveUncensoredModelName
            : AppSettings.shared.effectiveStandardModelName
        let effectiveTools: [OllamaToolDef] = uncensoredMode ? [] : registry.toolDefs

        if uncensoredMode {
            let installedModels = await client.installedModels()
            guard installedModels.contains(effectiveModel) else {
                bobMood = .confused
                throw AgentLoopError.uncensoredModelUnavailable(effectiveModel)
            }
        }

        await updateCurrentModelForTurn(effectiveModel, notify: currentModel != effectiveModel)

        let loopStart = Date()
        let loopBudget = Self.loopBudget(for: userMessage)
        DebugLog.log(.agent, "turn-start", [
            "model": effectiveModel,
            "userMsgLen": "\(userMessage.count)",
            "userMsgPreview": String(userMessage.prefix(200)),
            "loopBudgetSec": "\(Int(loopBudget.timeoutSeconds))",
            "maxIter": "\(loopBudget.maxIterations)",
            "uncensored": "\(uncensoredMode)"
        ])
        var batchContinuationNudges = 0
        var continuationNudges = 0
        var shellRecoveryNudges = 0
        var turnHadToolFailure = false
        var lastFailedToolResult: ToolResult?
        var lastToolResult: ToolResult?
        // Phase 4: tool wall-clock excluded from loop budget. The 120s budget
        // is for model + Swift overhead; long shells (`brew upgrade`, `npm
        // install`) get their own idle/hard-cap ceilings inside ProcessRunner
        // and a user-driven Cancel button (Phase C) as the hard fail-safe.
        var toolTimeAccumulated: TimeInterval = 0
        // Always re-prepend a FRESH system prompt. We strip any inherited
        // system messages from history so the persona/tool rules can never
        // be evicted by Ollama's context truncation as the conversation grows
        // — they are re-injected at position 0 on every single request.
        var messages = history.filter { $0.role != "system" }

        // Phase 5: compact if the conversation is approaching 75% of num_ctx.
        // Check BEFORE adding the new user message and system prompt so
        // the compactor sees the existing history as-is.
        let numCtx = AppSettings.shared.numCtx
        if uncensoredMode == false,
           ConversationCompactor.shouldCompact(messages: messages, numCtx: numCtx) {
            let before = ConversationCompactor.approxTokens(messages)
            messages = await ConversationCompactor.compact(messages: messages, client: client)
            let after = ConversationCompactor.approxTokens(messages)
            logCompaction(beforeTokens: before, afterTokens: after, numCtx: numCtx)
        }
        currentPhoneCallContext = Self.phoneCallContext(
            from: messages + [.user(userMessage)],
            conversationId: conversationId
        )

        let composed = PromptComposer.composeWithBreakdown(
            persona: PersonaStore.shared.activePersona,
            includeCheatSheet: uncensoredMode == false,
            uncensoredMode: uncensoredMode,
            availableToolNames: Set(registry.toolNames),
            taintActive: TaintPolicy.shared.tainted(forSession: conversationId)
        )
        messages.insert(.system(composed.prompt), at: 0)
        messages.append(.user(userMessage))
        logPromptBreakdown(composed.breakdown)

        // v1.0.52: pre-flight context-pressure check. When the
        // composed prompt + history would exceed
        // `chatContextPressureWarningFraction` of numCtx, log a
        // visible Tool Activity entry so the user can choose to
        // /clear and retry rather than wait through a sluggish turn.
        // gemma4:e4b in particular gets significantly slower past
        // ~60% utilization. Doesn't block — just informs.
        let estimatedTokens = ConversationCompactor.approxTokens(messages)
        let pressureFrac = Double(estimatedTokens) / Double(numCtx)
        if pressureFrac >= AppConfig.chatContextPressureWarningFraction {
            logContextPressureWarning(
                estimatedTokens: estimatedTokens,
                numCtx: numCtx,
                fraction: pressureFrac,
                messageCount: messages.count
            )
            DebugLog.log(.agent, "context-pressure-warning", [
                "tokens": "\(estimatedTokens)",
                "numCtx": "\(numCtx)",
                "fraction": String(format: "%.2f", pressureFrac),
                "msgCount": "\(messages.count)"
            ])
        }

        for _ in 0..<loopBudget.maxIterations {
            // Phase A: cooperative cancellation. The wrapping Task may also
            // be cancelled, but the polled flag guarantees a deterministic
            // exit point even if Task cancellation is suppressed somewhere.
            if cancelRequested || Task.isCancelled {
                bobMood = .idle
                throw AgentLoopError.cancelled
            }

            // Check total timeout. Tool wall-clock is excluded — see
            // `toolTimeAccumulated` above.
            if Date().timeIntervalSince(loopStart) - toolTimeAccumulated > loopBudget.timeoutSeconds {
                bobMood = .confused
                throw AgentLoopError.totalTimeoutReached(loopBudget.timeoutSeconds)
            }

            // Send to Ollama. v1.0.52: wrapped with heartbeat (publishes
            // `waitState` so the UI can show "Bob is processing… (45s)"
            // during the long blank window) and a wall-clock race that
            // force-cancels if the request exceeds the configured cap.
            // The cap exists because URLSession's idle-only timeout
            // never trips when Ollama keeps the TCP socket alive while
            // doing nothing — that's the wedge that ate 19 minutes.
            let response: OllamaChatResponse
            do {
                response = try await chatWithHeartbeat(
                    model: effectiveModel,
                    messages: messages,
                    tools: effectiveTools,
                    numCtx: AppSettings.shared.numCtx
                )
            } catch is CancellationError {
                bobMood = .idle
                throw AgentLoopError.cancelled
            } catch {
                if cancelRequested || Task.isCancelled {
                    bobMood = .idle
                    throw AgentLoopError.cancelled
                }
                bobMood = .confused
                throw AgentLoopError.ollamaUnavailable(error.localizedDescription)
            }

            if cancelRequested || Task.isCancelled {
                bobMood = .idle
                throw AgentLoopError.cancelled
            }

            var assistantMessage = response.message

            // No tool calls — final response
            guard let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty else {
                assistantMessage.content = Self.normalizedFinalAssistantContent(
                    assistantMessage.content,
                    for: userMessage,
                    turnHadToolFailure: turnHadToolFailure,
                    lastFailedToolResult: lastFailedToolResult,
                    lastToolResult: lastToolResult
                )
                if Self.shouldForceBatchAudioContinuation(
                    userMessage: userMessage,
                    assistantContent: assistantMessage.content,
                    lastToolResult: lastToolResult,
                    loopBudget: loopBudget,
                    nudgeCount: batchContinuationNudges
                ) {
                    batchContinuationNudges += 1
                    messages.append(.system(Self.batchAudioContinuationNudge(for: assistantMessage.content, lastToolResult: lastToolResult)))
                    bobMood = .thinking
                    continue
                }
                let batchAudit = Self.batchAudioAudit(userMessage: userMessage, messages: messages)
                if Self.shouldForceBatchAudioAuditContinuation(
                    audit: batchAudit,
                    assistantContent: assistantMessage.content,
                    lastToolResult: lastToolResult,
                    loopBudget: loopBudget,
                    nudgeCount: batchContinuationNudges
                ) {
                    batchContinuationNudges += 1
                    messages.append(.system(Self.batchAudioAuditNudge(audit: batchAudit!, lastToolResult: lastToolResult)))
                    bobMood = .thinking
                    continue
                }
                if let batchAudit,
                   Self.shouldReplaceBatchAudioFinalContent(assistantMessage.content, audit: batchAudit) {
                    assistantMessage.content = Self.batchAudioFinalSummary(audit: batchAudit)
                }
                // Generic announce-and-stop guard. Fires when the model
                // ended a non-tool-call turn with future-action language
                // ("Now running nmap", "Let me check", "I'll run X")
                // without actually emitting the tool call. Capped low
                // (AppConfig.continuationNudgeMax = 1) so a stuck model
                // surfaces to the user instead of spinning. Runs after
                // the batch-audio guards so it doesn't double-fire on
                // batch turns.
                // Shell-recovery guard. Fires when the previous shell
                // tool exited non-zero with a syntax/usage error AND
                // the model's reply gives up instead of diagnosing
                // and retrying. Fires BEFORE the generic continuation
                // guard because it's strictly more specific (shell-
                // failure-specific stderr classification + give-up
                // detection) and produces a more actionable nudge.
                // Cap=1 (AppConfig.shellRecoveryNudgeMax).
                if Self.shouldForceShellRecovery(
                    assistantContent: assistantMessage.content,
                    lastToolResult: lastToolResult,
                    nudgeCount: shellRecoveryNudges
                ) {
                    shellRecoveryNudges += 1
                    DebugLog.log(.guardx, "shell-recovery-guard fire", [
                        "attempt": "\(shellRecoveryNudges)/\(AppConfig.shellRecoveryNudgeMax)",
                        "lastToolStderr": String((lastToolResult?.content ?? "").prefix(300)),
                        "giveUpReply": String(assistantMessage.content.prefix(300))
                    ])
                    logShellRecoveryGuard(
                        lastToolResult: lastToolResult,
                        outcome: "nudged (attempt \(shellRecoveryNudges)/\(AppConfig.shellRecoveryNudgeMax)) — re-prompting model to diagnose stderr and retry"
                    )
                    if let last = lastToolResult {
                        messages.append(.system(Self.shellRecoveryNudge(for: last)))
                    }
                    bobMood = .thinking
                    continue
                }
                if Self.shouldForceContinuation(
                    assistantContent: assistantMessage.content,
                    lastToolResult: lastToolResult,
                    nudgeCount: continuationNudges
                ) {
                    continuationNudges += 1
                    DebugLog.log(.guardx, "continuation-guard fire", [
                        "attempt": "\(continuationNudges)/\(AppConfig.continuationNudgeMax)",
                        "brokenReply": String(assistantMessage.content.prefix(300))
                    ])
                    logContinuationGuard(
                        preview: assistantMessage.content,
                        outcome: "nudged (attempt \(continuationNudges)/\(AppConfig.continuationNudgeMax)) — re-prompting model to call the tool"
                    )
                    messages.append(.system(Self.continuationNudge(for: assistantMessage.content)))
                    bobMood = .thinking
                    continue
                }
                // Cap-reached visibility: if we already nudged and this
                // is the SECOND announce-and-stop in the same turn, the
                // user is about to see a broken reply. Surface that in
                // the Tool Activity panel so it's not silent. Detection
                // mirrors the guard's pattern matcher to stay accurate.
                if continuationNudges >= AppConfig.continuationNudgeMax,
                   Self.shouldForceContinuation(
                       assistantContent: assistantMessage.content,
                       lastToolResult: lastToolResult,
                       nudgeCount: 0  // bypass cap to test the pattern only
                   ) {
                    DebugLog.log(.guardx, "continuation-guard cap reached", [
                        "brokenReply": String(assistantMessage.content.prefix(300))
                    ])
                    logContinuationGuard(
                        preview: assistantMessage.content,
                        outcome: "nudge cap reached — surfacing broken reply to user"
                    )
                }
                messages.append(assistantMessage)
                if lastToolResult?.success != false {
                    consecutiveFailures = 0
                }
                bobMood = lastToolResult?.success == false ? .sheepish : .happy
                return messages
            }

            // Append the assistant message with tool calls
            messages.append(assistantMessage)
            bobMood = .typing

            // Process each tool call. Tool output takes this trip before
            // it lands in the message list:
            //   1. executeToolCall() — approval, path policy, dispatch
            //   2. spilloutIfNeeded() — if the raw content is > inlineMax,
            //      write it to disk and swap the inline content for a
            //      short pointer `[output too large — id=7]`.
            //   3. UntrustedWrapper.wrap() — wrap in <untrusted>…</untrusted>
            //      so a malicious file or web page cannot pretend to be an
            //      instruction from the user.
            // Both stages together keep the context small *and* the model
            // honest. See BobOperatingRules for the matching rules.
            for call in toolCalls {
                currentPhoneCallContext = Self.phoneCallContext(
                    from: messages,
                    conversationId: conversationId
                )
                let toolStart = Date()
                let rawResult = await executeToolCall(call)
                toolTimeAccumulated += Date().timeIntervalSince(toolStart)
                lastToolResult = rawResult
                if rawResult.success {
                    turnHadToolFailure = false
                    lastFailedToolResult = nil
                } else {
                    turnHadToolFailure = true
                    lastFailedToolResult = rawResult
                }
                let spilled = await spilloutIfNeeded(rawResult)
                let wrapped = UntrustedWrapper.wrap(spilled.content)
                messages.append(.toolResult(name: spilled.toolName, content: wrapped))
                currentPhoneCallContext = Self.phoneCallContext(
                    from: messages,
                    conversationId: conversationId
                )
                if cancelRequested || Task.isCancelled {
                    bobMood = .idle
                    throw AgentLoopError.cancelled
                }
            }
        }

        bobMood = .confused
        throw AgentLoopError.maxIterationsReached(loopBudget.maxIterations)
    }



    // MARK: - Logging

    /// Phase 2a: lifted from `private` so the AgentLoop+ToolDispatch
    /// extension in AgentLoopToolDispatch.swift can call into the same
    /// activity log without re-implementing it.
    func logTool(name: String, input: String, output: String, approval: ApprovalLevel, approved: Bool, durationMs: Int) {
        let entry = ToolLogEntry(
            toolName: name,
            input: input,
            output: output,
            approval: approval,
            approved: approved,
            durationMs: durationMs,
            timestamp: Date()
        )
        toolActivity.append(entry)
    }

    /// Record a compaction event in the activity log.
    func logCompaction(beforeTokens: Int, afterTokens: Int, numCtx: Int) {
        let ratio = afterTokens > 0 ? String(format: "%.1fx", Double(beforeTokens) / Double(afterTokens)) : "∞"
        let output = "compacted \(beforeTokens) → \(afterTokens) tok (\(ratio) reduction) at \(numCtx) ctx"
        let entry = ToolLogEntry(
            toolName: "compaction",
            input: "trigger: >\(Int(Double(numCtx) * 0.75)) tok",
            output: output,
            approval: .none,
            approved: true,
            durationMs: 0,
            timestamp: Date()
        )
        toolActivity.append(entry)
    }

    /// Record a shell-recovery-guard fire in the activity log.
    /// Symmetric to `logContinuationGuard`. Mirrors the same
    /// observability contract: silence when no-op, visible row when
    /// firing, distinct outcome strings for nudged vs cap-reached.
    func logShellRecoveryGuard(lastToolResult: ToolResult?, outcome: String) {
        let stderrSlice = lastToolResult.map { result -> String in
            let content = result.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(content.prefix(160))
        } ?? ""
        let entry = ToolLogEntry(
            toolName: "shell_recovery_guard",
            input: "shell exit !=0: \"\(stderrSlice)\"",
            output: outcome,
            approval: .none,
            approved: true,
            durationMs: 0,
            timestamp: Date()
        )
        toolActivity.append(entry)
    }

    /// Record a context-pressure warning in the activity log.
    /// v1.0.52. Surfaces "your chat history is filling up the model's
    /// context window" before the user pays for a slow turn. The
    /// warning is informational, not blocking — Bob still tries to
    /// respond. The user can choose to /clear after seeing this.
    func logContextPressureWarning(
        estimatedTokens: Int,
        numCtx: Int,
        fraction: Double,
        messageCount: Int
    ) {
        let pct = Int(fraction * 100)
        let entry = ToolLogEntry(
            toolName: "context_pressure",
            input: "msgs=\(messageCount), tokens≈\(estimatedTokens), numCtx=\(numCtx)",
            output: "Chat is using \(pct)% of context window. Bob may be slow on this turn — consider /clear or a fresh chat if responses lag.",
            approval: .none,
            approved: true,
            durationMs: 0,
            timestamp: Date()
        )
        toolActivity.append(entry)
    }

    /// Record a continuation-guard fire in the activity log. Surfaces
    /// the silent "we caught Bob announcing without acting and nudged
    /// him" event so the user (and operator-debugging) can tell when
    /// the guard saved the turn vs. when it was a no-op. Distinct
    /// `outcome` strings mean the activity row makes the eventual fate
    /// of the nudge legible without opening source.
    func logContinuationGuard(preview: String, outcome: String) {
        let trimmed = preview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let inputPreview = String(trimmed.prefix(120))
        let entry = ToolLogEntry(
            toolName: "continuation_guard",
            input: "broken reply: \"\(inputPreview)\"",
            output: outcome,
            approval: .none,
            approved: true,
            durationMs: 0,
            timestamp: Date()
        )
        toolActivity.append(entry)
    }

    /// Record the per-turn system prompt composition breakdown in the
    /// activity log. Surfaces prompt drift (persona growing huge, cheat
    /// sheet blowing past budget) without needing a separate debug view.
    /// Logged as a pseudo-tool entry so it shows up in the same list as
    /// real tool calls.
    func logPromptBreakdown(_ b: PromptComposer.Breakdown) {
        let input = "numCtx=\(AppSettings.shared.numCtx)"
        let warn = b.overBudget ? " [OVER BUDGET]" : ""
        let output = """
            rules=\(b.operatingRulesChars)ch  persona=\(b.personaChars)ch  cheatsheet=\(b.cheatSheetChars)ch
            total=\(b.totalChars)ch  ≈\(b.approxTokens) tok  budget=\(b.budgetTokens) tok\(warn)
            """
        let entry = ToolLogEntry(
            toolName: "prompt_compose",
            input: input,
            output: output,
            approval: .none,
            approved: true,
            durationMs: 0,
            timestamp: Date()
        )
        toolActivity.append(entry)
    }

}
