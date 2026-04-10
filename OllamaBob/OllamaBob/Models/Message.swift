import Foundation

/// A chat message in the Ollama /api/chat wire format.
///
/// Note: `thinking` is **decoded** from Ollama responses (gemma4 emits a "thinking"
/// field alongside content) but is **never encoded** back. Echoing chain-of-thought
/// to the model on the next turn confuses tool-calling and bloats context, so we
/// drop it on the way out.
struct OllamaMessage: Sendable {
    let role: String
    var content: String
    var thinking: String?
    var toolCalls: [OllamaToolCall]?
    var toolName: String?  // used when role == "tool"

    init(
        role: String,
        content: String,
        thinking: String? = nil,
        toolCalls: [OllamaToolCall]? = nil,
        toolName: String? = nil
    ) {
        self.role = role
        self.content = content
        self.thinking = thinking
        self.toolCalls = toolCalls
        self.toolName = toolName
    }

    static func system(_ content: String) -> OllamaMessage {
        OllamaMessage(role: "system", content: content)
    }

    static func user(_ content: String) -> OllamaMessage {
        OllamaMessage(role: "user", content: content)
    }

    static func assistant(_ content: String, toolCalls: [OllamaToolCall]? = nil) -> OllamaMessage {
        OllamaMessage(role: "assistant", content: content, toolCalls: toolCalls)
    }

    static func toolResult(name: String, content: String) -> OllamaMessage {
        OllamaMessage(role: "tool", content: content, toolName: name)
    }
}

extension OllamaMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case role, content, thinking
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try c.decode(String.self, forKey: .role)
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
        self.toolCalls = try c.decodeIfPresent([OllamaToolCall].self, forKey: .toolCalls)
        self.toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        // thinking is intentionally omitted on encode — see type comment.
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(toolName, forKey: .toolName)
    }
}

/// The full request body sent to /api/chat
struct OllamaChatRequest: Codable, Sendable {
    let model: String
    let messages: [OllamaMessage]
    let tools: [OllamaToolDef]?
    let options: OllamaOptions?
    let stream: Bool
    /// Controls how long the model stays loaded after the response.
    /// `"0"` unloads immediately (used by the compactor so qwen3
    /// doesn't compete for VRAM with the primary model). Nil omits
    /// the field, keeping the Ollama default (typically 5 minutes).
    let keepAlive: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, options, stream
        case keepAlive = "keep_alive"
    }

    struct OllamaOptions: Codable, Sendable {
        let numCtx: Int?

        enum CodingKeys: String, CodingKey {
            case numCtx = "num_ctx"
        }
    }
}

/// The response from /api/chat
struct OllamaChatResponse: Codable, Sendable {
    let model: String
    let createdAt: String?
    let message: OllamaMessage
    let done: Bool
    let doneReason: String?

    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case message, done
        case doneReason = "done_reason"
    }
}
