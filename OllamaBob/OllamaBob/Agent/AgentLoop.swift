import Foundation

enum AgentLoopError: Error, LocalizedError {
    case maxIterationsReached(Int)
    case totalTimeoutReached(TimeInterval)
    case ollamaUnavailable(String)
    case uncensoredModelUnavailable(String)

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

    struct ToolLogEntry: Identifiable {
        let id = UUID()
        let toolName: String
        let input: String
        let output: String
        let approval: ApprovalLevel
        let approved: Bool
        let durationMs: Int
        let timestamp: Date
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
        defer {
            isProcessing = false
            currentConversationId = nil
            currentUserMessage = nil
            currentPhoneCallContext = nil
            currentUncensoredMode = false
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
        var batchContinuationNudges = 0
        var turnHadToolFailure = false
        var lastFailedToolResult: ToolResult?
        var lastToolResult: ToolResult?
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

        for _ in 0..<loopBudget.maxIterations {
            // Check total timeout
            if Date().timeIntervalSince(loopStart) > loopBudget.timeoutSeconds {
                bobMood = .confused
                throw AgentLoopError.totalTimeoutReached(loopBudget.timeoutSeconds)
            }

            // Send to Ollama
            let response: OllamaChatResponse
            do {
                response = try await client.chat(
                    model: effectiveModel,
                    messages: messages,
                    tools: effectiveTools,
                    numCtx: AppSettings.shared.numCtx
                )
            } catch {
                bobMood = .confused
                throw AgentLoopError.ollamaUnavailable(error.localizedDescription)
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
                    messages.append(.system(Self.batchAudioContinuationNudge(for: assistantMessage.content)))
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
                    messages.append(.system(Self.batchAudioAuditNudge(audit: batchAudit!)))
                    bobMood = .thinking
                    continue
                }
                if let batchAudit,
                   Self.shouldReplaceBatchAudioFinalContent(assistantMessage.content, audit: batchAudit) {
                    assistantMessage.content = Self.batchAudioFinalSummary(audit: batchAudit)
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
                let rawResult = await executeToolCall(call)
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
