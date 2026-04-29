import Foundation

// MARK: - AgentLoop / Tool Dispatch
//
// Phase 2a (peer-review plan, 2026-04-28): extracted from AgentLoop.swift.
// Owns the model-tool-call → registry-validate → approval-gate →
// runtime-execute → result pipeline. All entry points stay on
// `AgentLoop` so callers (incl. tests) keep using
// `AgentLoop.shouldRedirectReadFileToPresent(...)` etc. unchanged.
//
// Scope of this file:
//   - `executeToolCall(_:)` — main dispatch entry called from `process()`
//   - `executeTool(name:args:)` — switch over the catalog
//   - intent-redirect helpers (read_file → present, applescript → shell)
//   - meta-tool handlers (tool_help, remember/forget/list_facts,
//     read_tool_output)
//   - tool-output spillout
//   - `describeToolCall` — operator-facing approval-modal description
//   - `parseInt` / `parseBool` — flexible coercion for Ollama-emitted
//     tool args (Int, Double, NSNumber, or string)
extension AgentLoop {

    // MARK: - Tool Execution

    func executeToolCall(_ call: OllamaToolCall) async -> ToolResult {
        let name = call.function.name
        var args = call.function.parsedArguments
        args = phoneCallArgumentsWithContextIfNeeded(name: name, args: args)

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

        // Capture resolved paths at approval time for fail-closed execution.
        let approvedPaths = ApprovalPolicy.resolvedPaths(toolName: name, arguments: args)

        // Execute
        let result = await executeTool(name: name, args: args, approvedPaths: approvedPaths)
        logTool(name: name, input: "\(args)", output: result.content, approval: approval, approved: true, durationMs: result.durationMs)

        // Privacy Ledger: append a row for approved side-effecting executions.
        // Logging failure must never block the tool result — wrapped in try?.
        if Self.isSideEffectingTool(name, args: args) {
            let summary = String(result.content.prefix(500))
            try? DatabaseManager.shared.appendExecutionLog(
                toolName: name,
                approvalLevel: approval,
                summary: summary,
                success: result.success,
                durationMs: result.durationMs
            )
        }

        if result.success {
            consecutiveFailures = 0
            bobMood = .typing
        } else {
            bobMood = .sheepish
        }
        return result
    }

    func executeTool(name: String, args: [String: Any], approvedPaths: [String: String] = [:]) async -> ToolResult {
        switch name {
        case "shell":
            let command = args["command"] as? String ?? ""
            return await ShellTool.execute(command: command)

        case "read_file":
            let path = args["path"] as? String ?? ""
            return await FileReadTool.execute(path: path)

        case "create_directory":
            let path = args["path"] as? String ?? ""
            return await DirectoryCreateTool.execute(
                path: path,
                approvedResolvedPath: approvedPaths["path"]
            )

        case "list_directory":
            let path = args["path"] as? String ?? ""
            let depth = Self.parseInt(args["depth"]) ?? 1
            return await DirectoryListTool.execute(path: path, depth: depth)

        case "write_file":
            let path = args["path"] as? String ?? ""
            let content = args["content"] as? String ?? ""
            return await FileWriteTool.execute(
                path: path,
                content: content,
                approvedResolvedPath: approvedPaths["path"]
            )

        case "move_file":
            let source = args["source"] as? String ?? ""
            let destination = args["destination"] as? String ?? ""
            return await FileMoveTool.execute(
                source: source,
                destination: destination,
                approvedSourcePath: approvedPaths["source"],
                approvedDestinationPath: approvedPaths["destination"]
            )

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
            let context = args["context"] as? String
            return await PhoneTool.execute(
                persona: persona,
                to: to,
                purpose: purpose,
                maxMinutes: maxMinutes,
                context: context
            )

        case "phone_hangup":
            let callID = args["call_id"] as? String ?? ""
            return await PhoneTool.hangup(callID: callID)

        case "phone_status":
            let callID = args["call_id"] as? String ?? ""
            return await PhoneTool.status(callID: callID)

        // MARK: Phase 4a — Call Supervision
        case "phone_list_calls":
            return await PhoneListCallsTool.execute()

        case "phone_get_transcript":
            let callID = args["call_id"] as? String ?? ""
            return await PhoneTranscriptTool.execute(callID: callID)

        case "phone_inject":
            let callID = args["call_id"] as? String ?? ""
            let text = args["text"] as? String ?? ""
            return await PhoneInjectTool.execute(callID: callID, text: text)

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

        // MARK: Code Companion (Phase 6)
        case "project_context":
            let path = args["path"] as? String ?? ""
            return await ProjectContextTool.execute(path: path)

        case "enable_dev_mode":
            let path = args["path"] as? String ?? ""
            return EnableDevModeTool.execute(path: path)

        case "disable_dev_mode":
            return DisableDevModeTool.execute()

        // MARK: Mac Context (Phase 3)
        // All four are read-only — NOT in isSideEffectingTool, NOT logged.
        case "active_window":
            return await ActiveWindowTool.execute()

        case "selected_items":
            return await SelectedItemsTool.execute()

        case "screen_ocr":
            return await ScreenOCRTool.execute()

        case "current_context":
            return await CurrentContextTool.execute()

        // MARK: Skill Capsules (Phase 7a)
        case "create_skill":
            let skillName = args["name"] as? String ?? ""
            let skillDesc = args["description"] as? String ?? ""
            let stepsJson = args["steps_json"] as? String ?? ""
            let knownNames = Set(registry.toolNames)
            return CreateSkillTool.execute(
                name: skillName,
                description: skillDesc,
                stepsJson: stepsJson,
                knownToolNames: knownNames
            )

        case "list_skills":
            return ListSkillsTool.execute()

        case "inspect_skill":
            let skillName = args["name"] as? String ?? ""
            return InspectSkillTool.execute(name: skillName)

        case "run_skill":
            let skillName = args["name"] as? String ?? ""
            let parametersJson = args["parameters_json"] as? String
            return await RunSkillTool.execute(
                name: skillName,
                parametersJson: parametersJson,
                agentLoop: self
            )

        case "delete_skill":
            let skillName = args["name"] as? String ?? ""
            return DeleteSkillTool.execute(name: skillName)

        default:
            return .failure(tool: name, error: "Tool not implemented", durationMs: 0)
        }
    }

    func phoneCallArgumentsWithContextIfNeeded(name: String, args: [String: Any]) -> [String: Any] {
        guard name == "phone_call" else { return args }
        let purpose = args["purpose"] as? String ?? ""
        let shouldAttachAutomaticContext = Self.shouldAttachAutomaticPhoneContext(
            purpose: purpose,
            userMessage: currentUserMessage ?? ""
        )
        let merged = Self.mergedPhoneCallContext(
            explicit: args["context"] as? String,
            automatic: shouldAttachAutomaticContext ? currentPhoneCallContext : nil
        )
        guard let merged, merged.isEmpty == false else { return args }

        var updated = args
        updated["context"] = merged
        return updated
    }

    /// Meta-tool handler for `tool_help`. Zero-cost lookup from the in-memory
    /// ToolCatalog via ToolRuntime. `name` may be the literal "list" to get
    /// a categorized summary, or any live tool's name for full detail.
    /// Returns true for tools that mutate state (filesystem, clipboard, phone,
    /// downloads, or local-file presentations). Read-only tools always return false.
    /// For "present", only the `kind == "file"` variant counts as a side effect
    /// (it opens/stages a local file); html and url are read-only renders.
    nonisolated static func isSideEffectingTool(_ name: String, args: [String: Any]) -> Bool {
        switch name {
        case "write_file", "move_file", "create_directory",
             "clipboard_write", "applescript",
             "youtube_download", "image_convert",
             "phone_call", "phone_hangup",
             "phone_inject",
             "enable_dev_mode",   // Phase 6: changes session approval policy
             "create_skill",      // Phase 7a: saves a new skill recipe
             "delete_skill":      // Phase 7a: deletes a saved skill recipe
            return true
        case "present":
            return (args["kind"] as? String) == "file"
        default:
            return false
        }
    }

    static func parseInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func parseBool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        guard let s = value as? String else { return nil }
        switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "y", "1": return true
        case "false", "no", "n", "0": return false
        default: return nil
        }
    }

    func describeToolCall(name: String, args: [String: Any]) -> String {
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
            let baseDesc = "Write file: \(path) (\(content.count) chars)"
            // Attempt to compute a diff against the existing file.
            // If anything goes wrong the diff is omitted and we fall back
            // to the plain description (fail-closed per approval policy).
            if path != "unknown" {
                let url = URL(fileURLWithPath: path)
                if let diff = WriteDiff.computeForWriteFile(at: url, proposedContent: content) {
                    return "\(baseDesc)\(ApprovalAlert.diffSeparator)\(diff)"
                }
            }
            return baseDesc
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
            return Self.phoneCallApprovalDescription(args: args)
        case "phone_hangup":
            return "Hang up call: \(args["call_id"] as? String ?? "unknown")"
        case "phone_status":
            return "Check call status: \(args["call_id"] as? String ?? "unknown")"
        case "phone_list_calls":
            return "List active Jarvis calls"
        case "phone_get_transcript":
            return "Fetch transcript for call: \(args["call_id"] as? String ?? "unknown")"
        case "phone_inject":
            let callID = args["call_id"] as? String ?? "unknown"
            let text = args["text"] as? String ?? ""
            return "Inject into call \(callID): \"\(text.prefix(80))\(text.count > 80 ? "…" : "")\""
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
        // MARK: Code Companion (Phase 6)
        case "project_context":
            return "Project context: \(args["path"] as? String ?? "?")"
        case "enable_dev_mode":
            return "Enable dev mode for repo containing: \(args["path"] as? String ?? "?")"
        case "disable_dev_mode":
            return "Disable dev mode (restore modal write_file approval)"
        // MARK: Skill Capsules (Phase 7a)
        case "create_skill":
            let skillName = args["name"] as? String ?? "?"
            let stepsJson = args["steps_json"] as? String ?? ""
            return "Save skill '\(skillName)' with steps: \(String(stepsJson.prefix(120)))"
        case "list_skills":
            return "List all saved skills"
        case "inspect_skill":
            return "Inspect skill '\(args["name"] as? String ?? "?")'"
        case "run_skill":
            return "Run skill '\(args["name"] as? String ?? "?")'"
        case "delete_skill":
            return "Delete skill '\(args["name"] as? String ?? "?")'"
        default:
            return "\(name): \(args)"
        }
    }
}
