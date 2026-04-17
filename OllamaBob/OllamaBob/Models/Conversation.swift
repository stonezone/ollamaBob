import Foundation

struct Conversation: Identifiable, Sendable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, title: String = "New Chat") {
        self.id = id
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// UI-facing message (distinct from OllamaMessage wire format)
struct ChatMessage: Identifiable, Sendable {
    let id: String
    let role: MessageRole
    let content: String
    let thinking: String?
    let toolCalls: [OllamaToolCall]?
    let toolName: String?
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        thinking: String? = nil,
        toolCalls: [OllamaToolCall]? = nil,
        toolName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
        self.toolCalls = toolCalls
        self.toolName = toolName
        self.timestamp = timestamp
    }
}

enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}
