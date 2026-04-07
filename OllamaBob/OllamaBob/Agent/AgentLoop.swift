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
    func process(userMessage: String, history: [OllamaMessage]) async throws -> [OllamaMessage] {
        isProcessing = true
        bobMood = .thinking
        defer { isProcessing = false }

        let loopStart = Date()
        var messages = history
        if messages.isEmpty || messages.first?.role != "system" {
            messages.insert(.system(BobPersonality.systemPrompt), at: 0)
        }
        messages.append(.user(userMessage))

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
                    tools: registry.toolDefs
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

            // Process each tool call
            for call in toolCalls {
                let result = await executeToolCall(call)
                messages.append(.toolResult(name: result.toolName, content: result.content))
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

        default:
            return .failure(tool: name, error: "Tool not implemented", durationMs: 0)
        }
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
        default:
            return "\(name): \(args)"
        }
    }
}
