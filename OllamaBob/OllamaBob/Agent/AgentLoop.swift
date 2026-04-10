import Foundation

enum AgentLoopError: Error, LocalizedError {
    case maxIterationsReached
    case totalTimeoutReached
    case ollamaUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .maxIterationsReached:
            return "Reached maximum tool call iterations (\(AppConfig.agentLoopMaxIterations))"
        case .totalTimeoutReached:
            return "Agent loop timed out after \(Int(AppConfig.agentLoopTimeoutSeconds))s"
        case .ollamaUnavailable(let msg):
            return msg
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

    private let client: OllamaClient
    private let registry: ToolRegistry
    private var searchProvider: SearchProvider?
    private var consecutiveFailures = 0
    /// Set for the duration of a single `process()` call. The ToolOutputStore
    /// and the `read_tool_output` meta-tool use this to scope spillout files
    /// per conversation.
    private var currentConversationId: String?

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
        conversationId: String
    ) async throws -> [OllamaMessage] {
        isProcessing = true
        bobMood = .thinking
        currentConversationId = conversationId
        defer {
            isProcessing = false
            currentConversationId = nil
        }

        let loopStart = Date()
        // Always re-prepend a FRESH system prompt. We strip any inherited
        // system messages from history so the persona/tool rules can never
        // be evicted by Ollama's context truncation as the conversation grows
        // — they are re-injected at position 0 on every single request.
        var messages = history.filter { $0.role != "system" }

        // Phase 5: compact if the conversation is approaching 75% of num_ctx.
        // Check BEFORE adding the new user message and system prompt so
        // the compactor sees the existing history as-is.
        let numCtx = AppSettings.shared.numCtx
        if ConversationCompactor.shouldCompact(messages: messages, numCtx: numCtx) {
            let before = ConversationCompactor.approxTokens(messages)
            messages = await ConversationCompactor.compact(messages: messages, client: client)
            let after = ConversationCompactor.approxTokens(messages)
            logCompaction(beforeTokens: before, afterTokens: after, numCtx: numCtx)
        }

        let composed = PromptComposer.composeWithBreakdown(persona: PersonaStore.shared.activePersona)
        messages.insert(.system(composed.prompt), at: 0)
        messages.append(.user(userMessage))
        logPromptBreakdown(composed.breakdown)

        for _ in 0..<AppConfig.agentLoopMaxIterations {
            // Check total timeout
            if Date().timeIntervalSince(loopStart) > AppConfig.agentLoopTimeoutSeconds {
                bobMood = .confused
                throw AgentLoopError.totalTimeoutReached
            }

            // Send to Ollama
            let response: OllamaChatResponse
            do {
                response = try await client.chat(
                    model: currentModel,
                    messages: messages,
                    tools: registry.toolDefs,
                    numCtx: AppSettings.shared.numCtx
                )
            } catch {
                bobMood = .confused
                throw AgentLoopError.ollamaUnavailable(error.localizedDescription)
            }

            let assistantMessage = response.message

            // No tool calls — final response
            guard let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty else {
                messages.append(assistantMessage)
                consecutiveFailures = 0
                bobMood = .happy
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
                let rawResult = await executeToolCall(call)
                let spilled = await spilloutIfNeeded(rawResult)
                let wrapped = UntrustedWrapper.wrap(spilled.content)
                messages.append(.toolResult(name: spilled.toolName, content: wrapped))
            }
        }

        bobMood = .confused
        throw AgentLoopError.maxIterationsReached
    }

    // MARK: - Tool Execution

    private func executeToolCall(_ call: OllamaToolCall) async -> ToolResult {
        let name = call.function.name
        let args = call.function.parsedArguments

        // Validate tool exists
        guard registry.has(name) else {
            logTool(name: name, input: "\(args)", output: "Unknown tool", approval: .forbidden, approved: false, durationMs: 0)
            consecutiveFailures += 1
            await checkFallback()
            bobMood = .confused
            return .failure(tool: name, error: "Unknown tool '\(name)'. Available tools: \(registry.toolNames.joined(separator: ", "))", durationMs: 0)
        }

        // Validate arguments
        guard registry.validateArgs(name, args) else {
            logTool(name: name, input: "\(args)", output: "Invalid arguments", approval: .forbidden, approved: false, durationMs: 0)
            consecutiveFailures += 1
            await checkFallback()
            bobMood = .confused
            return .failure(tool: name, error: "Invalid or missing arguments for '\(name)'", durationMs: 0)
        }

        // Check approval
        let approval = ApprovalPolicy.check(toolName: name, arguments: args)

        if approval == .forbidden {
            let result = ToolResult.forbidden(tool: name)
            logTool(name: name, input: "\(args)", output: result.content, approval: .forbidden, approved: false, durationMs: 0)
            bobMood = .sheepish
            return result
        }

        if approval == .modal {
            let commandDesc = describeToolCall(name: name, args: args)
            let approved = await requestApproval(command: commandDesc, toolName: name, level: approval)
            if !approved {
                let result = ToolResult.denied(tool: name, reason: "User denied this action.")
                logTool(name: name, input: "\(args)", output: result.content, approval: .modal, approved: false, durationMs: 0)
                bobMood = .sheepish
                return result
            }
        }

        // Execute
        consecutiveFailures = 0
        let result = await executeTool(name: name, args: args)
        logTool(name: name, input: "\(args)", output: result.content, approval: approval, approved: true, durationMs: result.durationMs)
        return result
    }

    private func executeTool(name: String, args: [String: Any]) async -> ToolResult {
        switch name {
        case "shell":
            let command = args["command"] as? String ?? ""
            return await ShellTool.execute(command: command)

        case "read_file":
            let path = args["path"] as? String ?? ""
            return await FileReadTool.execute(path: path)

        case "search_files":
            let pattern = args["pattern"] as? String ?? ""
            let path = args["path"] as? String
            return await FileSearchTool.execute(pattern: pattern, path: path)

        case "web_search":
            let query = args["query"] as? String ?? ""
            guard let provider = searchProvider else {
                return .failure(tool: "web_search", error: "Web search is not configured (no API key)", durationMs: 0)
            }
            return await WebSearchTool.execute(query: query, provider: provider)

        case "read_tool_output":
            return await executeReadToolOutput(args: args)

        case "tool_help":
            return executeToolHelp(args: args)

        case "remember":
            return executeRemember(args: args)

        case "forget":
            return executeForget(args: args)

        case "list_facts":
            return executeListFacts(args: args)

        default:
            return .failure(tool: name, error: "Tool not implemented", durationMs: 0)
        }
    }

    /// Meta-tool handler for `tool_help`. Zero-cost lookup from the in-memory
    /// ToolCatalog via ToolRuntime. `name` may be the literal "list" to get
    /// a categorized summary, or any live tool's name for full detail.
    private func executeToolHelp(args: [String: Any]) -> ToolResult {
        let start = Date()
        let raw = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            return .failure(
                tool: "tool_help",
                error: "Missing 'name' argument — pass 'list' or a tool name.",
                durationMs: Int(Date().timeIntervalSince(start) * 1000)
            )
        }
        let content: String
        if raw.lowercased() == "list" {
            content = ToolRuntime.shared.renderToolHelpList()
        } else {
            content = ToolRuntime.shared.renderToolHelp(name: raw)
        }
        return .success(
            tool: "tool_help",
            content: content,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    // MARK: - Facts (Phase 4 sticky memory)

    private func executeRemember(args: [String: Any]) -> ToolResult {
        let start = Date()
        let category = (args["category"] as? String ?? "other").trimmingCharacters(in: .whitespaces).lowercased()
        let content = (args["content"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else {
            return .failure(tool: "remember", error: "Content cannot be empty.", durationMs: 0)
        }
        let validCategories = ["identity", "preference", "project", "reference", "other"]
        let safeCategory = validCategories.contains(category) ? category : "other"
        do {
            let record = try DatabaseManager.shared.saveFact(category: safeCategory, content: content)
            return .success(
                tool: "remember",
                content: "Remembered (id=\(record.id), category=\(safeCategory)): \(String(content.prefix(80)))",
                durationMs: Int(Date().timeIntervalSince(start) * 1000)
            )
        } catch {
            return .failure(tool: "remember", error: error.localizedDescription, durationMs: 0)
        }
    }

    private func executeForget(args: [String: Any]) -> ToolResult {
        let start = Date()
        let id = (args["id"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else {
            return .failure(tool: "forget", error: "Missing 'id'. Call list_facts first to get fact ids.", durationMs: 0)
        }
        do {
            let deleted = try DatabaseManager.shared.deleteFact(id: id)
            let msg = deleted ? "Forgot fact id=\(id)." : "No fact found with id=\(id)."
            return .success(tool: "forget", content: msg, durationMs: Int(Date().timeIntervalSince(start) * 1000))
        } catch {
            return .failure(tool: "forget", error: error.localizedDescription, durationMs: 0)
        }
    }

    private func executeListFacts(args: [String: Any]) -> ToolResult {
        let start = Date()
        let category = args["category"] as? String
        do {
            let facts = try DatabaseManager.shared.fetchFacts(category: category)
            if facts.isEmpty {
                let scope = category.map { "in category '\($0)'" } ?? "in any category"
                return .success(
                    tool: "list_facts",
                    content: "No facts stored \(scope).",
                    durationMs: Int(Date().timeIntervalSince(start) * 1000)
                )
            }
            var lines: [String] = ["\(facts.count) fact(s):"]
            for f in facts {
                lines.append("[\(f.category)] id=\(f.id) — \(f.content)")
            }
            return .success(
                tool: "list_facts",
                content: lines.joined(separator: "\n"),
                durationMs: Int(Date().timeIntervalSince(start) * 1000)
            )
        } catch {
            return .failure(tool: "list_facts", error: error.localizedDescription, durationMs: 0)
        }
    }

    // MARK: - Tool Output Spillout

    /// If a tool result is larger than `AppConfig.toolInlineMax`, write it
    /// to disk via ToolOutputStore and return a new ToolResult whose content
    /// is a short pointer the model can resolve with `read_tool_output`.
    /// Leaves small results untouched. Failures fall through with the
    /// original result so a broken filesystem does not block the chat.
    private func spilloutIfNeeded(_ result: ToolResult) async -> ToolResult {
        guard result.content.count > AppConfig.toolInlineMax,
              let convoId = currentConversationId else {
            return result
        }
        do {
            let id = try await ToolOutputStore.shared.write(
                content: result.content,
                conversationId: convoId
            )
            let marker = """
                [output too large to inline — \(result.content.count) chars stored as id=\(id). \
                Call read_tool_output with id=\(id) to read the whole thing, or id=\(id) and range="0-2000" to read a slice.]
                """
            return ToolResult(
                toolName: result.toolName,
                content: marker,
                success: result.success,
                durationMs: result.durationMs
            )
        } catch {
            return result
        }
    }

    /// Meta-tool handler. Pulls a previously-stored tool output by its
    /// integer id and returns its contents (or a slice if `range` is set).
    private func executeReadToolOutput(args: [String: Any]) async -> ToolResult {
        let start = Date()
        guard let convoId = currentConversationId else {
            return .failure(
                tool: "read_tool_output",
                error: "No active conversation — nothing stored to read.",
                durationMs: 0
            )
        }
        guard let id = Self.parseInt(args["id"]) else {
            return .failure(
                tool: "read_tool_output",
                error: "Missing or invalid 'id' (must be an integer from a prior [output too large] pointer).",
                durationMs: 0
            )
        }
        let range = args["range"] as? String
        do {
            let content = try await ToolOutputStore.shared.read(
                id: id,
                conversationId: convoId,
                range: range
            )
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(tool: "read_tool_output", content: content, durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(
                tool: "read_tool_output",
                error: error.localizedDescription,
                durationMs: durationMs
            )
        }
    }

    /// Best-effort int coercion — Ollama may send the id as Int, Double,
    /// NSNumber, or a string-encoded integer depending on the model.
    private static func parseInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    // MARK: - Approval

    private func requestApproval(command: String, toolName: String, level: ApprovalLevel) async -> Bool {
        guard let handler = approvalHandler else { return false }
        return await handler(command, toolName, level)
    }

    // MARK: - Model Fallback

    private func checkFallback() async {
        if consecutiveFailures >= AppConfig.maxConsecutiveFailures && currentModel != AppConfig.fallbackModel {
            let oldModel = currentModel
            currentModel = AppConfig.fallbackModel
            consecutiveFailures = 0
            modelSwitchNotice = ModelSwitchNotice(from: oldModel, to: currentModel, at: Date())
            if let handler = modelSwitchHandler {
                await handler(oldModel, currentModel)
            }
        }
    }

    // MARK: - Logging

    private func logTool(name: String, input: String, output: String, approval: ApprovalLevel, approved: Bool, durationMs: Int) {
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
    private func logCompaction(beforeTokens: Int, afterTokens: Int, numCtx: Int) {
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
    private func logPromptBreakdown(_ b: PromptComposer.Breakdown) {
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

    private func describeToolCall(name: String, args: [String: Any]) -> String {
        switch name {
        case "shell":
            return args["command"] as? String ?? "shell command"
        case "read_file":
            return "Read file: \(args["path"] as? String ?? "unknown")"
        case "search_files":
            return "Search files: \(args["pattern"] as? String ?? "unknown")"
        case "web_search":
            return "Web search: \(args["query"] as? String ?? "unknown")"
        case "read_tool_output":
            let id = Self.parseInt(args["id"]).map(String.init) ?? "?"
            return "Read stored output: id=\(id)"
        case "tool_help":
            return "Tool help: \(args["name"] as? String ?? "?")"
        case "remember":
            return "Remember: \(String((args["content"] as? String ?? "").prefix(60)))"
        case "forget":
            return "Forget fact: \(args["id"] as? String ?? "?")"
        case "list_facts":
            return "List facts\(args["category"].map { " (\($0))" } ?? "")"
        default:
            return "\(name): \(args)"
        }
    }
}
