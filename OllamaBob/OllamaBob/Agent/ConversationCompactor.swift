import Foundation

/// Structural conversation compactor for Phase 5.
///
/// When the conversation approaches 75% of num_ctx, this compactor
/// mechanically reduces the message history without asking an LLM to
/// "summarize" (which leaks the active persona into the summary):
///
///   1. User turns     → kept verbatim
///   2. Tool calls     → compressed to one-line summaries
///   3. Tool results   → compressed to one-line summaries
///   4. Assistant turns → facts extracted by qwen3:14b, flattened
///
/// The compactor uses qwen3:14b (not the primary model) for step 4,
/// with `keep_alive: "0"` so it unloads immediately after and doesn't
/// compete for VRAM with the primary model.
///
/// Persona persistence: the system prompt is always stripped from the
/// input and re-prepended fresh by AgentLoop on the next turn, so the
/// compactor never touches it.
enum ConversationCompactor {

    /// Rough token estimate: ~4 chars per token. Same heuristic as
    /// PromptComposer — intentionally consistent across the codebase.
    static func approxTokens(_ messages: [OllamaMessage]) -> Int {
        messages.reduce(0) { sum, msg in
            sum + approxChars(for: msg) / 4
        }
    }

    private static func approxChars(for msg: OllamaMessage) -> Int {
        var chars = msg.content.count
        if let thinking = msg.thinking {
            chars += thinking.count
        }
        if let toolName = msg.toolName {
            chars += toolName.count
        }
        if let toolCalls = msg.toolCalls {
            chars += approxChars(for: toolCalls)
        }
        return chars
    }

    private static func approxChars(for toolCalls: [OllamaToolCall]) -> Int {
        var total = 0
        let encoder = JSONEncoder()
        for call in toolCalls {
            total += call.id?.count ?? 0
            total += call.function.name.count
            if let data = try? encoder.encode(call.function.arguments) {
                total += data.count
            } else {
                total += String(describing: call.function.parsedArguments).count
            }
        }
        return total
    }

    /// Returns true if the conversation should be compacted before the
    /// next turn. Threshold: 75% of the active num_ctx.
    static func shouldCompact(messages: [OllamaMessage], numCtx: Int) -> Bool {
        let tokens = approxTokens(messages)
        let threshold = Int(Double(numCtx) * 0.75)
        return tokens > threshold
    }

    /// Compact a conversation history. The system message (index 0) is
    /// passed through untouched — AgentLoop strips and re-adds it on
    /// every turn anyway, but we preserve it here so the returned array
    /// is structurally identical to the input.
    ///
    /// `client` is used for qwen3:14b extraction calls on assistant turns.
    /// If qwen3 is unreachable or returns no facts, the original assistant
    /// content is kept in a shortened form so the turn is never lost.
    static func compact(
        messages: [OllamaMessage],
        client: any OllamaChatProviding
    ) async -> [OllamaMessage] {
        var result: [OllamaMessage] = []

        for msg in messages {
            switch msg.role {
            case "system":
                // Pass through — AgentLoop will strip and re-add it.
                result.append(msg)

            case "user":
                // Kept verbatim per plan §5.2.
                result.append(msg)

            case "tool":
                // Compress tool results to one-liners.
                let name = msg.toolName ?? "unknown"
                let chars = msg.content.count
                let success = !msg.content.lowercased().contains("error")
                let summary = "[tool result: \(name), \(chars) chars, success=\(success)]"
                result.append(.toolResult(name: name, content: summary))

            case "assistant":
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    // Assistant turn that triggered tool calls — compress
                    // to one-liner per call.
                    var lines: [String] = []
                    for call in toolCalls {
                        let name = call.function.name
                        let args = call.function.parsedArguments
                        let argsStr = String(String(describing: args).prefix(120))
                        lines.append("[tool call: \(name), args: \(argsStr)]")
                    }
                    result.append(.assistant(lines.joined(separator: "\n")))
                } else if !msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Plain assistant text — extract facts via qwen3.
                    let extracted = await extractFacts(from: msg.content, client: client)
                    if let extracted, !extracted.isEmpty {
                        result.append(.assistant("[assistant: \(extracted)]"))
                    } else {
                        let trimmed = msg.content
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: " ")
                        let fallback = String(trimmed.prefix(240))
                        result.append(.assistant("[assistant: \(fallback)]"))
                    }
                }

            default:
                // Unknown role — keep it, don't silently drop data.
                result.append(msg)
            }
        }

        return result
    }

    // MARK: - Fact Extraction

    /// The deterministic extraction prompt from plan §5.2 step 3.
    private static let extractionSystemPrompt = """
        You are a fact extractor. Given an assistant message from a chat conversation, \
        extract any factual commitments, decisions, file paths, identifiers, or concrete \
        information as a bulleted list. One line per fact, prefixed with "- ". \
        Do NOT paraphrase the voice or add commentary. If there are no extractable facts, \
        respond with exactly "none".
        """

    /// Send a single assistant message to qwen3:14b for fact extraction.
    /// Returns the extracted bullet list (without the leading "- " markers),
    /// or nil if the call fails. Uses keep_alive=0 so qwen3 unloads
    /// immediately after.
    private static func extractFacts(from content: String, client: any OllamaChatProviding) async -> String? {
        let messages: [OllamaMessage] = [
            .system(extractionSystemPrompt),
            .user(content)
        ]
        do {
            let response = try await client.chat(
                model: AppConfig.compactionModel,
                messages: messages,
                tools: nil,
                numCtx: 4096,
                keepAlive: "0"
            )
            let text = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased() == "none" || text.isEmpty {
                return nil
            }
            // Flatten bullets to a semicolon-separated single line to
            // minimize token usage in the compacted history.
            let facts = text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
            return facts
        } catch {
            // Best-effort — if qwen3 is unavailable, the caller keeps a
            // shortened copy of the original assistant turn.
            print("[ConversationCompactor] qwen3 extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
}
