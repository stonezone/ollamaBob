import Foundation

// MARK: - AgentLoop / Meta Tools
//
// Phase 2a (peer-review plan, 2026-04-28): split out of
// AgentLoopToolDispatch.swift to keep each coordinator file under the
// 600 LOC ceiling.
//
// Scope of this file: the "tools that talk about tools" plus the
// large-output spillout helper.
//   - `tool_help` — catalog renderer.
//   - `remember`/`forget`/`list_facts` — sticky memory facts.
//   - `read_tool_output` + `spilloutIfNeeded` — large-output cache so
//     a 50KB shell dump doesn't poison the context window.
extension AgentLoop {

    func executeToolHelp(args: [String: Any]) -> ToolResult {
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

    func executeRemember(args: [String: Any]) -> ToolResult {
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

    func executeForget(args: [String: Any]) -> ToolResult {
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

    func executeListFacts(args: [String: Any]) -> ToolResult {
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

    func spilloutIfNeeded(_ result: ToolResult) async -> ToolResult {
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
    func executeReadToolOutput(args: [String: Any]) async -> ToolResult {
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
}
