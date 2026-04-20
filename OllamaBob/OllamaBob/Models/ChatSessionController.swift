import Foundation

@MainActor
final class ChatSessionController: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var conversationId: String?
    @Published private(set) var conversationTitle = "New Chat"
    @Published private(set) var conversationUncensoredMode = false
    @Published private(set) var conversations: [ConversationSummary] = []

    private let agentLoop: ChatSessionAgentLooping
    private let database: ChatSessionDatabaseManaging
    private let toolOutputStore: ChatSessionToolOutputStoring
    private let conversationStore: ConversationStoring?
    private var ollamaHistory: [OllamaMessage] = []

    init(
        agentLoop: ChatSessionAgentLooping,
        database: ChatSessionDatabaseManaging = DatabaseManager.shared,
        toolOutputStore: ChatSessionToolOutputStoring = ToolOutputStore.shared,
        conversationStore: ConversationStoring? = nil
    ) {
        self.agentLoop = agentLoop
        self.database = database
        self.toolOutputStore = toolOutputStore
        self.conversationStore = conversationStore ?? (database as? ConversationStoring)
    }

    var history: [OllamaMessage] {
        ollamaHistory
    }

    func dismissError() {
        errorMessage = nil
    }

    func refreshConversations() {
        guard let conversationStore else { return }

        do {
            conversations = try conversationStore.listConversations()
            if let conversationId,
               conversations.contains(where: { $0.id == conversationId }) == false {
                clearCurrentConversationState()
            }
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    func loadExistingConversationIfNeeded() {
        guard conversationId == nil else { return }
        do {
            if conversationStore != nil {
                refreshConversations()
                guard let first = conversations.first else { return }
                loadConversation(id: first.id)
                return
            }

            guard let convo = try database.currentConversation() else { return }
            let stored = try database.loadMessages(conversationId: convo.id)
            applyConversation(
                id: convo.id,
                title: convo.title,
                uncensoredMode: convo.uncensoredMode,
                messages: stored
            )
        } catch {
            errorMessage = "Failed to load history: \(error.localizedDescription)"
        }
    }

    func loadConversation(_ snapshot: ConversationSnapshot) {
        applyConversation(
            id: snapshot.id,
            title: snapshot.title,
            uncensoredMode: snapshot.uncensoredMode,
            messages: snapshot.messages
        )
        inputText = ""
        errorMessage = nil
    }

    func loadConversation(id: String) {
        guard let conversationStore else {
            errorMessage = "Conversation management unavailable."
            return
        }

        do {
            guard let snapshot = try conversationStore.loadConversation(id: id) else {
                errorMessage = "Conversation not found."
                return
            }
            loadConversation(snapshot)
            refreshConversations()
        } catch {
            errorMessage = "Failed to load conversation: \(error.localizedDescription)"
        }
    }

    func updateConversationTitle(_ title: String) {
        conversationTitle = title
    }

    func setConversationUncensoredMode(_ isEnabled: Bool) {
        conversationUncensoredMode = isEnabled

        guard let conversationId else { return }
        do {
            guard let updated = try database.setConversationUncensoredMode(id: conversationId, isEnabled: isEnabled) else {
                errorMessage = "Conversation not found."
                return
            }
            conversations = conversations.map { $0.id == updated.id ? updated : $0 }
        } catch {
            errorMessage = "Failed to update conversation mode: \(error.localizedDescription)"
        }
    }

    func toggleConversationUncensoredMode() {
        setConversationUncensoredMode(!conversationUncensoredMode)
    }

    func renameSelectedConversation() {
        guard let conversationId else { return }

        let trimmed = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Conversation title cannot be empty."
            return
        }

        guard let conversationStore else {
            errorMessage = "Conversation management unavailable."
            return
        }

        do {
            guard let updated = try conversationStore.renameConversation(id: conversationId, title: trimmed) else {
                errorMessage = "Conversation not found."
                return
            }
            conversations = conversations.map { $0.id == updated.id ? updated : $0 }
            conversationTitle = updated.title
        } catch {
            errorMessage = "Failed to rename conversation: \(error.localizedDescription)"
        }
    }

    func deleteSelectedConversation() {
        guard let deletedId = conversationId else { return }

        guard let conversationStore else {
            errorMessage = "Conversation management unavailable."
            return
        }

        do {
            guard try conversationStore.deleteConversation(id: deletedId) else {
                errorMessage = "Conversation not found."
                return
            }

            Task { await toolOutputStore.clearConversation(deletedId) }
            refreshConversations()

            if let nextConversation = conversations.first {
                loadConversation(id: nextConversation.id)
            } else {
                startFreshConversation()
            }
        } catch {
            errorMessage = "Failed to delete conversation: \(error.localizedDescription)"
        }
    }

    func startFreshConversation() {
        if let oldId = conversationId {
            Task { await toolOutputStore.clearConversation(oldId) }
        }

        do {
            let new = try database.createConversation(title: "New Chat", uncensoredMode: false)
            applyConversation(id: new.id, title: new.title, uncensoredMode: new.uncensoredMode, messages: [])
            inputText = ""
            errorMessage = nil
            refreshConversations()
        } catch {
            errorMessage = "Failed to start new chat: \(error.localizedDescription)"
        }
    }

    func sendCurrentInput(allowsLocalCommands: Bool) {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        if allowsLocalCommands && (text == "/clear" || text == "/new") {
            startFreshConversation()
            return
        }

        let convoId: String
        do {
            if let existing = conversationId {
                convoId = existing
            } else {
                let new = try database.createConversation(title: "New Chat", uncensoredMode: conversationUncensoredMode)
                conversationId = new.id
                convoId = new.id
            }
        } catch {
            errorMessage = "Failed to start conversation: \(error.localizedDescription)"
            return
        }

        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        inputText = ""
        errorMessage = nil

        do {
            try database.saveMessage(userMsg, conversationId: convoId)
        } catch {
            errorMessage = "Failed to save message: \(error.localizedDescription)"
        }

        let previousHistoryCount = ollamaHistory.count
        let previousToolActivityCount = agentLoop.toolActivity.count

        Task {
            do {
                let updatedHistory = try await agentLoop.process(
                    userMessage: text,
                    history: ollamaHistory,
                    conversationId: convoId,
                    uncensoredMode: conversationUncensoredMode
                )

                appendNewMessages(from: updatedHistory, startingAt: previousHistoryCount + 1, conversationId: convoId)
                ollamaHistory = updatedHistory
                persistToolActivity(from: previousToolActivityCount, conversationId: convoId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func appendNewMessages(from updatedHistory: [OllamaMessage], startingAt startIndex: Int, conversationId: String) {
        guard startIndex < updatedHistory.count else { return }

        var sawToolResultInBatch = false
        for i in startIndex..<updatedHistory.count {
            let ollamaMsg = updatedHistory[i]
            if ollamaMsg.role == "assistant" {
                let content = sawToolResultInBatch
                    ? Self.conciseToolAnswer(from: ollamaMsg.content)
                    : ollamaMsg.content
                let chatMsg = ChatMessage(
                    role: .assistant,
                    content: content,
                    thinking: ollamaMsg.thinking,
                    toolCalls: ollamaMsg.toolCalls
                )
                if !chatMsg.content.isEmpty || (chatMsg.toolCalls?.isEmpty == false) {
                    messages.append(chatMsg)
                    persist(chatMsg, in: conversationId)
                }
            } else if ollamaMsg.role == "tool" {
                let chatMsg = ChatMessage(
                    role: .tool,
                    content: ollamaMsg.content,
                    toolName: ollamaMsg.toolName
                )
                sawToolResultInBatch = true
                messages.append(chatMsg)
                persist(chatMsg, in: conversationId)
            }
        }
    }

    private func persistToolActivity(from previousCount: Int, conversationId: String) {
        let newActivity = agentLoop.toolActivity.dropFirst(previousCount)
        for entry in newActivity {
            do {
                try database.saveToolLog(
                    conversationId: conversationId,
                    toolName: entry.toolName,
                    inputJson: entry.input,
                    outputText: entry.output,
                    approvalLevel: entry.approval,
                    approved: entry.approved,
                    durationMs: entry.durationMs
                )
            } catch {
                errorMessage = "Failed to log tool: \(error.localizedDescription)"
            }
        }
    }

    private func persist(_ msg: ChatMessage, in conversationId: String) {
        do {
            try database.saveMessage(msg, conversationId: conversationId)
        } catch {
            errorMessage = "Failed to save message: \(error.localizedDescription)"
        }
    }

    private func clearCurrentConversationState() {
        conversationId = nil
        conversationTitle = "New Chat"
        conversationUncensoredMode = false
        messages = []
        ollamaHistory = []
    }

    private func applyConversation(id: String, title: String, uncensoredMode: Bool, messages: [ChatMessage]) {
        conversationId = id
        conversationTitle = title
        conversationUncensoredMode = uncensoredMode
        self.messages = messages
        ollamaHistory = messages.compactMap(Self.toOllamaMessage(_:))
    }

    private static func toOllamaMessage(_ msg: ChatMessage) -> OllamaMessage? {
        switch msg.role {
        case .system:
            return nil
        case .user:
            return .user(msg.content)
        case .assistant:
            return .assistant(msg.content, toolCalls: msg.toolCalls)
        case .tool:
            return .toolResult(name: msg.toolName ?? "unknown", content: msg.content)
        }
    }

    private static func conciseToolAnswer(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return content }

        let newlineCount = trimmed.filter { $0 == "\n" }.count
        if trimmed.count <= 120 && newlineCount <= 1 {
            return trimmed
        }

        let unified = trimmed.replacingOccurrences(of: "\n", with: " ")
        let candidates = unified
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard let best = candidates.max(by: { score($0) < score($1) }) else {
            return trimmed
        }

        let focused = focusAnswerPhrase(in: best)
        let normalized = focused.hasSuffix(".") ? focused : focused + "."
        if normalized.range(of: "\\bsir\\b", options: [.regularExpression, .caseInsensitive]) == nil,
           trimmed.localizedCaseInsensitiveContains("sir") {
            return "Sir, \(normalized.prefix(1).lowercased())\(normalized.dropFirst())"
        }
        return normalized
    }

    private static func score(_ candidate: String) -> Int {
        let lowercased = candidate.lowercased()
        var score = 0

        if lowercased.rangeOfCharacter(from: .decimalDigits) != nil { score += 5 }
        if lowercased.contains("free") || lowercased.contains("available") { score += 6 }
        if lowercased.contains("%") || lowercased.contains("used") { score += 1 }
        if lowercased.contains("sir") { score += 1 }
        if lowercased.contains("gi") || lowercased.contains("gb") || lowercased.contains("mi") || lowercased.contains("mb") || lowercased.contains("tb") {
            score += 3
        }
        if lowercased.contains("basically") || lowercased.contains("usually") || lowercased.contains("situation") || lowercased.contains("looking at") {
            score -= 3
        }

        return score - max(0, candidate.count - 90) / 10
    }

    private static func focusAnswerPhrase(in candidate: String) -> String {
        let lowercased = candidate.lowercased()
        for marker in ["you have", "you've got", "there are", "there is", "it is"] {
            if let range = lowercased.range(of: marker) {
                return String(candidate[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return candidate
    }
}
