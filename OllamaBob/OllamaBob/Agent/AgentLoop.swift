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

    private let client: OllamaClient
    private let registry: ToolRegistry
    private var searchProvider: SearchProvider?
    private var consecutiveFailures = 0
    /// Set for the duration of a single `process()` call. The ToolOutputStore
    /// and the `read_tool_output` meta-tool use this to scope spillout files
    /// per conversation.
    private var currentConversationId: String?
    private var currentUserMessage: String?
    private var currentUncensoredMode = false

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

        let composed = PromptComposer.composeWithBreakdown(
            persona: PersonaStore.shared.activePersona,
            includeCheatSheet: uncensoredMode == false,
            uncensoredMode: uncensoredMode
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
            }
        }

        bobMood = .confused
        throw AgentLoopError.maxIterationsReached(loopBudget.maxIterations)
    }

    static func loopBudget(for userMessage: String) -> LoopBudget {
        let normalized = userMessage
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let actionTerms = [
            "download", "get", "save", "rip", "convert", "transcode",
            "grab", "fetch", "pull", "collect"
        ]
        let audioTerms = [
            "album", "albums", "playlist", "song", "songs", "track", "tracks",
            "mp3", "m4a", "flac", "audio", "music"
        ]
        let isAudioBatch = actionTerms.contains { normalized.contains($0) }
            && audioTerms.contains { normalized.contains($0) }
        let isListedTrackBatch = normalized.contains("all these")
            && (normalized.contains("track") || normalized.contains("song"))

        if isAudioBatch || isListedTrackBatch {
            return LoopBudget(
                maxIterations: AppConfig.batchAudioAgentLoopMaxIterations,
                timeoutSeconds: AppConfig.batchAudioAgentLoopTimeoutSeconds
            )
        }

        return LoopBudget(
            maxIterations: AppConfig.agentLoopMaxIterations,
            timeoutSeconds: AppConfig.agentLoopTimeoutSeconds
        )
    }

    static func shouldForceBatchAudioContinuation(
        userMessage: String,
        assistantContent: String,
        lastToolResult: ToolResult?,
        loopBudget: LoopBudget,
        nudgeCount: Int
    ) -> Bool {
        guard loopBudget == LoopBudget(
            maxIterations: AppConfig.batchAudioAgentLoopMaxIterations,
            timeoutSeconds: AppConfig.batchAudioAgentLoopTimeoutSeconds
        ) else {
            return false
        }
        guard nudgeCount < AppConfig.batchAudioContinuationNudgeMax else {
            return false
        }
        guard lastToolResult?.success == true else {
            return false
        }

        let normalizedUser = userMessage
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let normalizedContent = assistantContent
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let batchMarkers = [
            "all these", "remaining", "next up", "track list",
            "songs", "tracks", "album", "playlist"
        ]
        guard batchMarkers.contains(where: { normalizedUser.contains($0) }) else {
            return false
        }

        let statusOnlyContinuationMarkers = [
            "next up", "next track", "is the track", "<channel|>"
        ]
        return statusOnlyContinuationMarkers.contains { normalizedContent.contains($0) }
    }

    static func batchAudioAudit(userMessage: String, messages: [OllamaMessage]) -> BatchAudioAudit? {
        let requested = requestedBatchAudioTracks(userMessage: userMessage, messages: messages)
        guard requested.count >= 2 else { return nil }

        let downloadedPaths = messages
            .filter { $0.role == "tool" && $0.toolName == "youtube_download" }
            .compactMap { downloadedPath(from: $0.content) }

        let downloadedTracks = downloadedPaths.map { trackTitle(fromDownloadedPath: $0) }
        let downloadedKeys = Set(downloadedTracks.map(normalizedTrackKey))
        let missing = requested.filter { downloadedKeys.contains(normalizedTrackKey($0)) == false }
        let requestedKeys = Set(requested.map(normalizedTrackKey))
        let unmatched = downloadedTracks.filter { requestedKeys.contains(normalizedTrackKey($0)) == false }
        let outputDirectory = mostRecentCommonDirectory(from: downloadedPaths)

        return BatchAudioAudit(
            requestedTracks: requested,
            downloadedTracks: downloadedTracks,
            missingTracks: missing,
            unmatchedDownloads: unmatched,
            outputDirectory: outputDirectory
        )
    }

    static func requestedBatchAudioTracks(userMessage: String, messages: [OllamaMessage]) -> [String] {
        var candidates = [userMessage]
        candidates.append(contentsOf: messages
            .filter { $0.role == "user" }
            .map(\.content)
            .reversed())

        var seenMessages = Set<String>()
        for candidate in candidates {
            let key = candidate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            guard key.isEmpty == false, seenMessages.insert(key).inserted else { continue }
            let tracks = requestedBatchAudioTracks(from: candidate)
            if tracks.count >= 2 {
                return tracks
            }
        }
        return []
    }

    static func requestedBatchAudioTracks(from userMessage: String) -> [String] {
        let rawLines = userMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var candidates: [String] = []
        for (index, rawLine) in rawLines.enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if index == 0, let colon = line.lastIndex(of: ":") {
                line = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            line = line.replacingOccurrences(
                of: #"^\s*(?:[-*•]\s+|\d{1,3}[\.)-]\s*)"#,
                with: "",
                options: .regularExpression
            )
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLikelyTrackLine(line) else { continue }
            candidates.append(line)
        }

        var seen = Set<String>()
        return candidates.filter { track in
            let key = normalizedTrackKey(track)
            guard !key.isEmpty, seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    static func shouldForceBatchAudioAuditContinuation(
        audit: BatchAudioAudit?,
        assistantContent: String,
        lastToolResult: ToolResult?,
        loopBudget: LoopBudget,
        nudgeCount: Int
    ) -> Bool {
        guard let audit, audit.missingTracks.isEmpty == false else { return false }
        guard loopBudget == LoopBudget(
            maxIterations: AppConfig.batchAudioAgentLoopMaxIterations,
            timeoutSeconds: AppConfig.batchAudioAgentLoopTimeoutSeconds
        ) else {
            return false
        }
        guard nudgeCount < AppConfig.batchAudioContinuationNudgeMax else { return false }
        guard lastToolResult?.success == true else { return false }

        let normalizedContent = assistantContent
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        if normalizedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let completionClaims = [
            "complete", "completed", "done", "finished", "all tools finished",
            "successful", "successfully", "got them", "downloaded them"
        ]
        return completionClaims.contains { normalizedContent.contains($0) }
    }

    static func shouldReplaceBatchAudioFinalContent(_ content: String, audit: BatchAudioAudit) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let normalizedContent = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let hasCount = normalizedContent.contains("\(audit.downloadedTracks.count)")
            && normalizedContent.contains("\(audit.requestedTracks.count)")
        if audit.missingTracks.isEmpty {
            return hasCount == false
        }
        let mentionsMissing = normalizedContent.contains("missing")
            || normalizedContent.contains("skipped")
            || normalizedContent.contains("failed")
        return mentionsMissing == false
    }

    static func batchAudioAuditNudge(audit: BatchAudioAudit) -> String {
        let missingPreview = audit.missingTracks.prefix(12).joined(separator: ", ")
        let more = audit.missingTracks.count > 12 ? ", ..." : ""
        return """
        Batch audio audit: only \(audit.downloadedTracks.count) of \(audit.requestedTracks.count) requested tracks have a matching downloaded MP3. Missing: \(missingPreview)\(more).
        Do not claim completion. Immediately continue the batch by calling `youtube_search` for the first missing track: \(audit.missingTracks.first ?? "unknown"). Continue through the remaining missing tracks unless a track is truly ambiguous, denied, or fails.
        """
    }

    static func batchAudioFinalSummary(audit: BatchAudioAudit) -> String {
        var lines: [String] = []
        let location = audit.outputDirectory.map { " in \($0)" } ?? ""
        lines.append("Downloaded \(audit.downloadedTracks.count) of \(audit.requestedTracks.count) requested tracks\(location).")
        if audit.missingTracks.isEmpty {
            lines.append("No requested tracks are missing.")
        } else {
            lines.append("Missing: \(audit.missingTracks.joined(separator: ", ")).")
        }
        if audit.unmatchedDownloads.isEmpty == false {
            lines.append("Extra/unmatched downloads: \(audit.unmatchedDownloads.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    static func batchAudioContinuationNudge(for assistantContent: String) -> String {
        let preview = assistantContent
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(300)
        return """
        Batch audio task is still in progress. Your last reply was status-only: "\(preview)".
        Do not answer with text only. If requested tracks remain, immediately call `youtube_search` for the next named track, or `youtube_download` if you already have a confirmed URL. Continue the batch until all listed tracks are complete, a track is truly ambiguous, a download is denied, or a tool fails.
        """
    }

    private static func isLikelyTrackLine(_ line: String) -> Bool {
        guard line.count >= 2, line.count <= 120 else { return false }
        let lowered = line.lowercased()
        let instructionPrefixes = [
            "search ", "download ", "grab ", "get ", "save ", "convert ",
            "please ", "bob ", "continue ", "skip ", "only "
        ]
        if instructionPrefixes.contains(where: { lowered.hasPrefix($0) }) {
            return false
        }
        let sentenceMarkers = [":", "http://", "https://"]
        if sentenceMarkers.contains(where: { lowered.contains($0) }) {
            return false
        }
        return true
    }

    private static func downloadedPath(from content: String) -> String? {
        guard let range = content.range(of: "Downloaded to ") else { return nil }
        let tail = content[range.upperBound...]
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tail.isEmpty ? nil : tail
    }

    private static func trackTitle(fromDownloadedPath path: String) -> String {
        URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(
                of: #"^\s*\d{1,3}\s*[-_.]\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTrackKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func mostRecentCommonDirectory(from paths: [String]) -> String? {
        paths.last.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
    }

    // MARK: - Tool Execution

    private func executeToolCall(_ call: OllamaToolCall) async -> ToolResult {
        let name = call.function.name
        let args = call.function.parsedArguments

        // Validate tool exists
        guard registry.has(name) else {
            if let result = redirectedDisabledPresentToolIfNeeded(name: name, args: args) {
                logTool(name: name, input: "\(args)", output: result.content, approval: .none, approved: false, durationMs: 0)
                bobMood = .sheepish
                return result
            }
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

        if let result = redirectedReadFileOpenIntentIfNeeded(name: name, args: args) {
            logTool(name: name, input: "\(args)", output: result.content, approval: .none, approved: false, durationMs: 0)
            bobMood = .sheepish
            return result
        }

        if let result = redirectedAppleScriptOpenIntentIfNeeded(name: name, args: args) {
            logTool(name: name, input: "\(args)", output: result.content, approval: .none, approved: false, durationMs: 0)
            bobMood = .sheepish
            return result
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
        let result = await executeTool(name: name, args: args)
        logTool(name: name, input: "\(args)", output: result.content, approval: approval, approved: true, durationMs: result.durationMs)
        if result.success {
            consecutiveFailures = 0
            bobMood = .typing
        } else {
            bobMood = .sheepish
        }
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

        case "create_directory":
            let path = args["path"] as? String ?? ""
            return await DirectoryCreateTool.execute(path: path)

        case "list_directory":
            let path = args["path"] as? String ?? ""
            let depth = Self.parseInt(args["depth"]) ?? 1
            return await DirectoryListTool.execute(path: path, depth: depth)

        case "write_file":
            let path = args["path"] as? String ?? ""
            let content = args["content"] as? String ?? ""
            return await FileWriteTool.execute(path: path, content: content)

        case "move_file":
            let source = args["source"] as? String ?? ""
            let destination = args["destination"] as? String ?? ""
            return await FileMoveTool.execute(source: source, destination: destination)

        case "git_status":
            let repoPath = args["repo_path"] as? String ?? ""
            return await GitStatusTool.execute(repoPath: repoPath)

        case "git_diff":
            let repoPath = args["repo_path"] as? String ?? ""
            let relativePath = args["relative_path"] as? String
            let staged = args["staged"] as? Bool ?? false
            return await GitDiffTool.execute(repoPath: repoPath, relativePath: relativePath, staged: staged)

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

        case "mail_check":
            let query = args["query"] as? String
            let unreadOnly = Self.parseBool(args["unread_only"])
            let limit = Self.parseInt(args["limit"])
            return await MailTool.checkInbox(query: query, unreadOnly: unreadOnly, limit: limit)

        case "mail_triage":
            let query = args["query"] as? String
            let unreadOnly = Self.parseBool(args["unread_only"])
            let limit = Self.parseInt(args["limit"])
            let previewChars = Self.parseInt(args["preview_chars"])
            return await MailTool.triageInbox(query: query, unreadOnly: unreadOnly, limit: limit, previewChars: previewChars)

        case "phone_call":
            let persona = args["persona"] as? String ?? ""
            let to = args["to"] as? String ?? ""
            let purpose = args["purpose"] as? String ?? ""
            let maxMinutes = Self.parseInt(args["max_minutes"])
            return await PhoneTool.execute(persona: persona, to: to, purpose: purpose, maxMinutes: maxMinutes)

        case "phone_hangup":
            let callID = args["call_id"] as? String ?? ""
            return await PhoneTool.hangup(callID: callID)

        case "phone_status":
            let callID = args["call_id"] as? String ?? ""
            return await PhoneTool.status(callID: callID)

        case "present":
            let kind = args["kind"] as? String ?? ""
            let content = args["content"] as? String ?? ""
            let title = args["title"] as? String
            return await PresentTool.execute(kind: kind, content: content, title: title)

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

        case "clipboard_read":
            return await ClipboardTool.read()

        case "clipboard_write":
            let content = args["content"] as? String ?? ""
            return await ClipboardTool.write(content: content)

        case "applescript":
            let script = args["script"] as? String ?? ""
            return await AppleScriptTool.execute(script: script)

        case "ocr":
            let path = args["path"] as? String
            return await OCRTool.execute(path: path)

        case "speak":
            let text = args["text"] as? String ?? ""
            let voice = args["voice"] as? String
            return await SayTool.execute(text: text, voice: voice)

        case "weather":
            let location = args["location"] as? String ?? ""
            return await WeatherTool.execute(location: location)

        case "unit_convert":
            let from = args["from"] as? String ?? ""
            let to = args["to"] as? String ?? ""
            return await UnitsTool.execute(from: from, to: to)

        case "image_convert":
            let inputPath = args["input_path"] as? String ?? ""
            let outputPath = args["output_path"] as? String ?? ""
            let format = args["format"] as? String ?? ""
            let maxDimension = Self.parseInt(args["max_dimension"])
            return await SipsTool.execute(
                inputPath: inputPath,
                outputPath: outputPath,
                format: format,
                maxDimension: maxDimension
            )

        case "youtube_search":
            let query = args["query"] as? String ?? ""
            let limit = Self.parseInt(args["limit"])
            return await YouTubeTool.search(query: query, limit: limit)

        case "youtube_download":
            let url = args["url"] as? String ?? ""
            let format = args["format"] as? String ?? ""
            let outputDir = args["output_dir"] as? String
            let filename = args["filename"] as? String
            return await YouTubeTool.download(url: url, format: format, outputDir: outputDir, filename: filename)

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
        if result.toolName == "tool_help", result.content.count <= 12_000 {
            return result
        }
        if result.toolName == "mail_triage", result.content.count <= 6_000 {
            // The point of mail_triage is for the local model to rank short
            // previews. Keep bounded approved previews inline; very large
            // triage outputs still spill to the output store.
            return result
        }
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

    private static func parseBool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        guard let s = value as? String else { return nil }
        switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "y", "1": return true
        case "false", "no", "n", "0": return false
        default: return nil
        }
    }

    private func redirectedReadFileOpenIntentIfNeeded(name: String, args: [String: Any]) -> ToolResult? {
        guard name == "read_file",
              let path = args["path"] as? String,
              let currentUserMessage,
              Self.shouldRedirectReadFileToPresent(userMessage: currentUserMessage, path: path) else {
            return nil
        }

        let guidance: String
        if AppSettings.shared.richPresentationEnabled {
            guidance = "User asked to open a local file in its default app, not to read its contents into chat. Use present with kind='file' and content='\(path)' instead of read_file. If present returns 'path not allowed', relay that refusal to the user."
        } else {
            guidance = "User asked to open a local file in its default app, not to read its contents into chat. Rich presentation is disabled, so do not use read_file here. Use shell with macOS open if appropriate, or explain that you cannot open it."
        }

        return .failure(tool: "read_file", error: guidance, durationMs: 0)
    }

    private func redirectedDisabledPresentToolIfNeeded(name: String, args: [String: Any]) -> ToolResult? {
        guard name == "present",
              AppSettings.shared.richPresentationEnabled == false,
              let currentUserMessage else {
            return nil
        }

        let lower = currentUserMessage.lowercased()
        let openIntent = ["open ", "launch ", "show ", "in preview", "in browser", "default app", "proper window"]
            .contains { lower.contains($0) }
        guard openIntent else { return nil }

        let content = (args["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind = (args["kind"] as? String)?.lowercased() ?? ""

        let guidance: String
        if kind == "file" || content.hasPrefix("/") || content.hasPrefix("~") {
            guidance = "Rich presentation is disabled, so the present tool is unavailable. Use shell with macOS open for the file instead, or explain that you cannot open it."
        } else if kind == "url" || content.lowercased().hasPrefix("http://") || content.lowercased().hasPrefix("https://") {
            guidance = "Rich presentation is disabled, so the present tool is unavailable. Use shell with macOS open for the URL instead, or explain that you cannot open it."
        } else {
            guidance = "Rich presentation is disabled, so the present tool is unavailable. Use shell with macOS open for simple open/show requests, or explain that you cannot open it."
        }

        return .failure(tool: "present", error: guidance, durationMs: 0)
    }

    private func redirectedAppleScriptOpenIntentIfNeeded(name: String, args: [String: Any]) -> ToolResult? {
        guard name == "applescript",
              let script = args["script"] as? String,
              let currentUserMessage,
              Self.shouldRedirectAppleScriptOpenToShell(userMessage: currentUserMessage, script: script) else {
            return nil
        }

        return .failure(
            tool: "applescript",
            error: "User asked to open a file or URL in its default app. Do not use applescript for that. Use shell with macOS open instead, or explain that you cannot open it.",
            durationMs: 0
        )
    }

    static func shouldRedirectReadFileToPresent(userMessage: String, path: String) -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.hasPrefix("/") || trimmedPath.hasPrefix("~") else {
            return false
        }

        let lower = userMessage.lowercased()
        let openPhrases = [
            "open ",
            "launch ",
            "in preview",
            "preview ",
            "in browser",
            "in my browser",
            "default app"
        ]
        guard openPhrases.contains(where: { lower.contains($0) }) else {
            return false
        }

        let contentReadPhrases = [
            "contents of",
            "content of",
            "show me the contents",
            "paste the contents",
            "quote the contents",
            "summarize the file",
            "cat ",
            "head ",
            "tail ",
            "grep "
        ]
        return contentReadPhrases.contains(where: { lower.contains($0) }) == false
    }

    static func shouldRedirectAppleScriptOpenToShell(userMessage: String, script: String) -> Bool {
        let lowerMessage = userMessage.lowercased()
        let lowerScript = script.lowercased()
        let openIntent = ["open ", "launch ", "show ", "preview ", "in preview", "in browser", "default app"]
            .contains { lowerMessage.contains($0) }
        guard openIntent else { return false }

        let isSimpleOpenScript =
            lowerScript.contains(" to open file ") ||
            lowerScript.contains(" to open posix file") ||
            lowerScript.contains(" to open alias ") ||
            lowerScript.contains(" to open location ") ||
            lowerScript.contains("tell application \"finder\" to open ") ||
            lowerScript.contains("open location ")

        let automationIntent = ["finder automation", "system events", "click", "select", "reveal in finder"]
            .contains { lowerMessage.contains($0) }

        return isSimpleOpenScript && automationIntent == false
    }

    static func normalizedFinalAssistantContent(
        _ content: String,
        for userMessage: String,
        turnHadToolFailure: Bool,
        lastFailedToolResult: ToolResult?,
        lastToolResult: ToolResult?
    ) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerUser = userMessage.lowercased()

        if let markdownImage = explicitMarkdownImageResponse(for: userMessage) {
            return markdownImage
        }

        if requestsOnlyFencedCodeBlock(lowerUser),
           let fencedBlock = firstFencedCodeBlock(in: trimmed) {
            return fencedBlock
        }

        if let lastToolResult,
           lastToolResult.success,
           finalSuccessfulOpenShouldOverride(content: trimmed, userMessage: userMessage, result: lastToolResult) {
            return conciseSuccessReply(for: userMessage, from: lastToolResult)
        }

        if trimmed.isEmpty,
           let lastToolResult,
           lastToolResult.success,
           let mailReply = fallbackMailReply(from: lastToolResult) {
            return mailReply
        }

        if turnHadToolFailure,
           let lastFailedToolResult,
           (contentAcknowledgesFailure(trimmed) == false || finalFailureReplyShouldOverride(content: trimmed, userMessage: userMessage, result: lastFailedToolResult)) {
            return conciseFailureReply(for: userMessage, from: lastFailedToolResult)
        }

        if requestsSingleLine(lowerUser) {
            return firstNonEmptyLine(in: trimmed)
        }

        if requestsSingleSentence(lowerUser) {
            return bestSentence(in: trimmed, userMessage: userMessage)
        }

        return trimmed
    }

    private static func fallbackMailReply(from result: ToolResult) -> String? {
        let detail = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard detail.isEmpty == false else { return nil }

        switch result.toolName {
        case "mail_check":
            return "I found these Mail messages:\n\(detail)"
        case "mail_triage":
            return "I pulled these Mail previews for triage, but I could not finish the ranking in this turn. Here are the previews I found:\n\(detail)"
        default:
            return nil
        }
    }

    private static func explicitMarkdownImageResponse(for userMessage: String) -> String? {
        let lowerUser = userMessage.lowercased()
        guard lowerUser.contains("markdown only"),
              lowerUser.contains("![alt](path)") else {
            return nil
        }

        guard let path = extractAbsoluteOrTildePath(from: userMessage) else {
            return nil
        }

        let fileName = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).deletingPathExtension().lastPathComponent
        let alt = fileName.isEmpty ? "image" : fileName
        return "![\(alt)](\(path))"
    }

    private static func requestsOnlyFencedCodeBlock(_ lowerUser: String) -> Bool {
        lowerUser.contains("fenced code block") ||
        lowerUser.contains("only that fenced block") ||
        lowerUser.contains("just the code block")
    }

    private static func requestsSingleSentence(_ lowerUser: String) -> Bool {
        lowerUser.contains("one sentence")
    }

    private static func requestsSingleLine(_ lowerUser: String) -> Bool {
        lowerUser.contains("one line")
    }

    private static func firstFencedCodeBlock(in content: String) -> String? {
        guard let openRange = content.range(of: "```") else { return nil }
        guard let closeRange = content.range(of: "```", range: openRange.upperBound..<content.endIndex) else { return nil }
        return String(content[openRange.lowerBound..<closeRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contentAcknowledgesFailure(_ content: String) -> Bool {
        let lower = content.lowercased()
        let markers = ["couldn't", "could not", "failed", "error", "not allowed", "denied", "refused", "did not succeed", "can't", "cannot"]
        return markers.contains { lower.contains($0) }
    }

    private static func finalSuccessfulOpenShouldOverride(content: String, userMessage: String, result: ToolResult) -> Bool {
        guard result.toolName == "shell" || result.toolName == "present" else { return false }
        guard isOpenIntent(userMessage) else { return false }
        if contentAcknowledgesFailure(content) { return true }
        return contentAcknowledgesOpenSuccess(content) == false
    }

    private static func finalFailureReplyShouldOverride(content: String, userMessage: String, result: ToolResult) -> Bool {
        guard isOpenIntent(userMessage) else { return false }
        let lowerDetail = result.content.lowercased()
        let lowerContent = content.lowercased()

        if lowerDetail.contains("command timed out after"),
           lowerContent.contains("command timed out after") {
            return true
        }

        return false
    }

    private static func isOpenIntent(_ userMessage: String) -> Bool {
        let lower = userMessage.lowercased()
        return ["open ", "launch ", "show ", "in preview", "in browser", "in my browser", "default app", "proper window"]
            .contains { lower.contains($0) }
    }

    private static func contentAcknowledgesOpenSuccess(_ content: String) -> Bool {
        let lower = content.lowercased()
        let markers = [
            "opened",
            "open in preview",
            "in preview",
            "in your browser",
            "in my browser",
            "rich view",
            "shown",
            "showing"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func conciseFailureReply(for userMessage: String, from result: ToolResult) -> String {
        let detail = result.content
            .replacingOccurrences(of: "Error: ", with: "")
            .replacingOccurrences(of: "Denied: ", with: "")
            .replacingOccurrences(of: "Forbidden: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if detail.localizedCaseInsensitiveContains("path not allowed"),
           let path = extractAbsoluteOrTildePath(from: userMessage) {
            return "I couldn't open \(path) because that path is not allowed."
        }

        // `open ~/Desktop/...` and similar shell fallbacks can block on a macOS
        // TCC prompt instead of returning promptly. When that happens we want a
        // retry/approval explanation, not a misleading generic shell failure.
        if detail.localizedCaseInsensitiveContains("command timed out after"),
           isOpenIntent(userMessage) {
            if let path = extractAbsoluteOrTildePath(from: userMessage),
               likelyTriggersMacOSFilePrompt(path: path) {
                return "I hit a macOS file-access prompt while opening \(path). Approve it and retry."
            }
            return "I hit a macOS prompt while opening that. Approve it and retry."
        }

        if detail.isEmpty {
            return "I couldn't complete that request."
        }

        let sentence = firstSentence(in: detail)
        return sentence.hasPrefix("I ") ? sentence : "I couldn't complete that request: \(sentence.prefix(1).lowercased())\(sentence.dropFirst())"
    }

    private static func conciseSuccessReply(for userMessage: String, from result: ToolResult) -> String {
        let detail = result.content
            .replacingOccurrences(of: "Opened file: ", with: "")
            .replacingOccurrences(of: "Opened URL: ", with: "")
            .replacingOccurrences(of: "Opened rich view: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lowerUser = userMessage.lowercased()
        if lowerUser.contains("in preview"),
           let path = extractAbsoluteOrTildePath(from: userMessage) {
            return "I opened \(path) in Preview."
        }

        if lowerUser.contains("in browser") || lowerUser.contains("in my browser") {
            return "I opened it in your browser."
        }

        if detail.isEmpty == false, detail != "(no output)" {
            return result.content
        }

        if let path = extractAbsoluteOrTildePath(from: userMessage) {
            return "I opened \(path)."
        }

        return "I completed that request."
    }

    private static func extractAbsoluteOrTildePath(from text: String) -> String? {
        let patterns = [#"(~\/[^\s`]+)"#, #"((?:\/[^\s`]+)+)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let capture = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[capture]).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:)]}\"'"))
        }
        return nil
    }

    private static func likelyTriggersMacOSFilePrompt(path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        let protectedRoots = [
            "\(NSHomeDirectory())/Desktop",
            "\(NSHomeDirectory())/Documents",
            "\(NSHomeDirectory())/Downloads"
        ]
        return protectedRoots.contains { expanded == $0 || expanded.hasPrefix($0 + "/") }
    }

    private static func firstNonEmptyLine(in content: String) -> String {
        content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? content
    }

    private static func firstSentence(in content: String) -> String {
        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"(?i)\b(anything else sir\??|bob is done sir[^\.\!\?]*[\.\!\?]?|most welcome sir[^\.\!\?]*[\.\!\?]?)"#,
                                  with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return content.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let regex = try? NSRegularExpression(pattern: #"[.!?](?=\s|$)"#) {
            let nsRange = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, range: nsRange),
               let range = Range(match.range, in: cleaned) {
                return String(cleaned[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return cleaned
    }

    private static func bestSentence(in content: String, userMessage: String) -> String {
        let sentences = splitSentences(in: content)
        guard sentences.isEmpty == false else {
            return firstSentence(in: content)
        }

        let keywords = significantKeywords(from: userMessage)
        return sentences.max { scoreSentence($0, keywords: keywords) < scoreSentence($1, keywords: keywords) } ?? firstSentence(in: content)
    }

    private static func splitSentences(in content: String) -> [String] {
        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"(?i)\b(anything else sir\??|bob is done sir[^\.\!\?]*[\.\!\?]?|most welcome sir[^\.\!\?]*[\.\!\?]?)"#,
                                  with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return [] }

        guard let regex = try? NSRegularExpression(pattern: #"[.!?](?=\s|$)"#) else {
            return [cleaned]
        }

        let range = NSRange(cleaned.startIndex..., in: cleaned)
        let matches = regex.matches(in: cleaned, range: range)
        guard matches.isEmpty == false else { return [cleaned] }

        var sentences: [String] = []
        var sentenceStart = cleaned.startIndex

        for match in matches {
            guard let punctuationRange = Range(match.range, in: cleaned) else { continue }
            let sentence = String(cleaned[sentenceStart..<punctuationRange.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.isEmpty == false {
                sentences.append(sentence)
            }

            sentenceStart = punctuationRange.upperBound
            while sentenceStart < cleaned.endIndex, cleaned[sentenceStart].isWhitespace {
                sentenceStart = cleaned.index(after: sentenceStart)
            }
        }

        if sentenceStart < cleaned.endIndex {
            let tail = String(cleaned[sentenceStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty == false {
                sentences.append(tail)
            }
        }

        return sentences.isEmpty ? [cleaned] : sentences
    }

    private static func scoreSentence(_ sentence: String, keywords: [String]) -> Int {
        let lower = sentence.lowercased()
        var score = 0

        if lower.contains("~/") || lower.contains("/") { score += 12 }
        if lower.range(of: #"(~\/|\/[A-Za-z0-9._-]+)"#, options: .regularExpression) != nil { score += 6 }
        if lower.contains("located") || lower.contains("called") || lower.contains("use ") { score += 3 }
        if lower.contains(" is ") || lower.hasPrefix("is ") || lower.contains(" are ") { score += 1 }

        for keyword in keywords where lower.contains(keyword) {
            score += 3
        }

        let fillerPatterns = [
            "actually sir",
            "yes sir",
            "very simple matter",
            "simple matter",
            "one moment",
            "bob will",
            "no tension",
            "most welcome"
        ]
        if fillerPatterns.contains(where: { lower.contains($0) }) { score -= 8 }
        if lower.contains("anything else") { score -= 10 }

        score -= max(0, sentence.count - 120) / 12
        return score
    }

    private static func significantKeywords(from userMessage: String) -> [String] {
        let lower = userMessage.lowercased()
        let stopWords: Set<String> = [
            "the", "a", "an", "in", "on", "at", "for", "to", "my", "me", "is", "where", "what",
            "show", "give", "just", "only", "one", "sentence", "line", "code", "block", "no", "tool", "tools"
        ]

        return lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && stopWords.contains($0) == false }
    }

    // MARK: - Approval

    private func requestApproval(command: String, toolName: String, level: ApprovalLevel) async -> Bool {
        guard let handler = approvalHandler else { return false }
        return await handler(command, toolName, level)
    }

    // MARK: - Model Fallback

    private func checkFallback() async {
        guard currentUncensoredMode == false else { return }
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

    private func updateCurrentModelForTurn(_ model: String, notify: Bool) async {
        guard currentModel != model else { return }
        let oldModel = currentModel
        currentModel = model
        guard notify else { return }
        modelSwitchNotice = ModelSwitchNotice(from: oldModel, to: model, at: Date())
        if let handler = modelSwitchHandler {
            await handler(oldModel, model)
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
        case "create_directory":
            return "Create directory: \(args["path"] as? String ?? "unknown")"
        case "list_directory":
            return "List directory: \(args["path"] as? String ?? "unknown")"
        case "write_file":
            let path = args["path"] as? String ?? "unknown"
            let content = args["content"] as? String ?? ""
            return "Write file: \(path) (\(content.count) chars)"
        case "move_file":
            let source = args["source"] as? String ?? "unknown"
            let destination = args["destination"] as? String ?? "unknown"
            return "Move file: \(source) -> \(destination)"
        case "git_status":
            return "Git status: \(args["repo_path"] as? String ?? "unknown")"
        case "git_diff":
            let repoPath = args["repo_path"] as? String ?? "unknown"
            let relativePath = args["relative_path"] as? String
            let staged = args["staged"] as? Bool ?? false
            let scope = relativePath.map { " (\($0))" } ?? ""
            return "Git diff: \(repoPath)\(scope)\(staged ? " [staged]" : "")"
        case "search_files":
            return "Search files: \(args["pattern"] as? String ?? "unknown")"
        case "web_search":
            return "Web search: \(args["query"] as? String ?? "unknown")"
        case "phone_call":
            let rawPersona = args["persona"] as? String ?? ""
            let persona = PhoneTool.resolvedCallerLabel(rawPersona)
            let to = args["to"] as? String ?? "unknown"
            let purpose = (args["purpose"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let shortPurpose = String(purpose.prefix(200))
            let ellipsis = purpose.count > 200 ? "…" : ""
            return "Bob wants to place a phone call to \(to) as \(persona).\nPurpose: \(shortPurpose)\(ellipsis)"
        case "phone_hangup":
            return "Hang up call: \(args["call_id"] as? String ?? "unknown")"
        case "phone_status":
            return "Check call status: \(args["call_id"] as? String ?? "unknown")"
        case "present":
            let kind = args["kind"] as? String ?? "?"
            let title = (args["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let label = title.map { " [\($0)]" } ?? ""
            return "Present \(kind)\(label)"
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
        case "clipboard_read":
            return "Read clipboard"
        case "clipboard_write":
            let content = args["content"] as? String ?? ""
            let preview = content.prefix(60)
            return "Copy to clipboard (\(content.count) chars): \(preview)\(content.count > 60 ? "…" : "")"
        case "applescript":
            let script = (args["script"] as? String ?? "").replacingOccurrences(of: "\n", with: " ")
            let preview = script.prefix(120)
            return "Run AppleScript: \(preview)\(script.count > 120 ? "…" : "")"
        case "ocr":
            return args["path"].map { "OCR file: \($0)" } ?? "OCR clipboard image"
        case "speak":
            return "Speak: \(String((args["text"] as? String ?? "").prefix(60)))"
        case "weather":
            return "Weather: \(args["location"] as? String ?? "?")"
        case "unit_convert":
            return "Convert \(args["from"] as? String ?? "?") → \(args["to"] as? String ?? "?")"
        case "image_convert":
            return "Convert image: \(args["input_path"] as? String ?? "?") → \(args["output_path"] as? String ?? "?")"
        case "youtube_search":
            return "YouTube search: \(args["query"] as? String ?? "?")"
        case "youtube_download":
            return "YouTube download: \(args["url"] as? String ?? "?")"
        default:
            return "\(name): \(args)"
        }
    }
}
