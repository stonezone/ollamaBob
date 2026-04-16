import Foundation

@MainActor
protocol ChatSessionAgentLooping: AnyObject {
    var toolActivity: [AgentLoop.ToolLogEntry] { get }
    func process(
        userMessage: String,
        history: [OllamaMessage],
        conversationId: String
    ) async throws -> [OllamaMessage]
}

protocol ChatSessionDatabaseManaging: AnyObject {
    func currentConversation() throws -> ConversationRecord?
    func loadMessages(conversationId: String) throws -> [ChatMessage]
    func createConversation(title: String) throws -> ConversationRecord
    func saveMessage(_ msg: ChatMessage, conversationId: String) throws
    func saveToolLog(
        conversationId: String,
        toolName: String,
        inputJson: String,
        outputText: String,
        approvalLevel: ApprovalLevel,
        approved: Bool,
        durationMs: Int
    ) throws
}

protocol ChatSessionToolOutputStoring: AnyObject {
    func clearConversation(_ conversationId: String) async
}

extension AgentLoop: ChatSessionAgentLooping {}
extension DatabaseManager: ChatSessionDatabaseManaging {}
extension ToolOutputStore: ChatSessionToolOutputStoring {}
