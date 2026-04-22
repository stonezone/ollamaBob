import Foundation

@MainActor
final class ChatSessionController: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var transcriptRevision = 0
    @Published private(set) var terminalTurnRevision = 0
    @Published private(set) var lastTerminalTurnToken = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var conversationId: String?
    @Published private(set) var conversationTitle = "New Chat"
    @Published private(set) var conversationUncensoredMode = false
    @Published private(set) var conversations: [ConversationSummary] = []

    private let agentLoop: ChatSessionAgentLooping
    private let database: ChatSessionDatabaseManaging
    private let toolOutputStore: ChatSessionToolOutputStoring
    private let conversationStore: ConversationStoring?
    private var nextTurnToken = 0
    private var activeTurn: InFlightTurn?
    private var ollamaHistory: [OllamaMessage] = []

    private struct InFlightTurn: Equatable {
        let conversationId: String
        let token: Int
    }

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
        renameSelectedConversation(to: conversationTitle)
    }

    func renameSelectedConversation(to title: String) {
        guard let conversationId else { return }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
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
        markTranscriptChanged()
        inputText = ""
        errorMessage = nil

        do {
            try database.saveMessage(userMsg, conversationId: convoId)
        } catch {
            errorMessage = "Failed to save message: \(error.localizedDescription)"
        }

        let requestHistory = ollamaHistory
        let requestUncensoredMode = conversationUncensoredMode
        let turn = beginTurn(conversationId: convoId)
        let previousHistoryCount = requestHistory.count
        let previousToolActivityCount = agentLoop.toolActivity.count

        Task {
            defer { finishTurn(turn) }

            do {
                let updatedHistory = try await agentLoop.process(
                    userMessage: text,
                    history: requestHistory,
                    conversationId: convoId,
                    uncensoredMode: requestUncensoredMode
                )

                let shouldApplyLiveUpdate = shouldApplyLiveUpdate(for: turn)
                appendNewMessages(
                    from: updatedHistory,
                    startingAt: previousHistoryCount + 1,
                    conversationId: convoId,
                    applyToLiveSession: shouldApplyLiveUpdate
                )
                if shouldApplyLiveUpdate {
                    ollamaHistory = updatedHistory
                }
                persistToolActivity(
                    from: previousToolActivityCount,
                    conversationId: convoId,
                    reportErrorsToLiveSession: shouldApplyLiveUpdate
                )
            } catch {
                if shouldApplyLiveUpdate(for: turn) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func appendNewMessages(
        from updatedHistory: [OllamaMessage],
        startingAt startIndex: Int,
        conversationId: String,
        applyToLiveSession: Bool
    ) {
        guard startIndex < updatedHistory.count else { return }

        var appendedMessages = false
        for i in startIndex..<updatedHistory.count {
            let ollamaMsg = updatedHistory[i]
            if ollamaMsg.role == "assistant" {
                let chatMsg = ChatMessage(
                    role: .assistant,
                    content: ollamaMsg.content,
                    thinking: ollamaMsg.thinking,
                    toolCalls: ollamaMsg.toolCalls
                )
                if !chatMsg.content.isEmpty || (chatMsg.toolCalls?.isEmpty == false) {
                    if applyToLiveSession {
                        messages.append(chatMsg)
                        appendedMessages = true
                    }
                    persist(chatMsg, in: conversationId, reportErrorsToLiveSession: applyToLiveSession)
                }
            } else if ollamaMsg.role == "tool" {
                let chatMsg = ChatMessage(
                    role: .tool,
                    content: ollamaMsg.content,
                    toolName: ollamaMsg.toolName
                )
                if applyToLiveSession {
                    messages.append(chatMsg)
                    appendedMessages = true
                }
                persist(chatMsg, in: conversationId, reportErrorsToLiveSession: applyToLiveSession)
            }
        }

        if applyToLiveSession && appendedMessages {
            markTranscriptChanged()
        }
    }

    private func persistToolActivity(
        from previousCount: Int,
        conversationId: String,
        reportErrorsToLiveSession: Bool
    ) {
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
                if reportErrorsToLiveSession {
                    errorMessage = "Failed to log tool: \(error.localizedDescription)"
                }
            }
        }
    }

    private func persist(_ msg: ChatMessage, in conversationId: String, reportErrorsToLiveSession: Bool) {
        do {
            try database.saveMessage(msg, conversationId: conversationId)
        } catch {
            if reportErrorsToLiveSession {
                errorMessage = "Failed to save message: \(error.localizedDescription)"
            }
        }
    }

    private func clearCurrentConversationState() {
        conversationId = nil
        conversationTitle = "New Chat"
        conversationUncensoredMode = false
        messages = []
        ollamaHistory = []
        markTranscriptChanged()
    }

    private func applyConversation(id: String, title: String, uncensoredMode: Bool, messages: [ChatMessage]) {
        conversationId = id
        conversationTitle = title
        conversationUncensoredMode = uncensoredMode
        self.messages = messages
        ollamaHistory = messages.compactMap(Self.toOllamaMessage(_:))
        markTranscriptChanged()
    }

    private func markTranscriptChanged() {
        transcriptRevision += 1
    }

    private func beginTurn(conversationId: String) -> InFlightTurn {
        nextTurnToken += 1
        let turn = InFlightTurn(conversationId: conversationId, token: nextTurnToken)
        activeTurn = turn
        return turn
    }

    private func shouldApplyLiveUpdate(for turn: InFlightTurn) -> Bool {
        activeTurn == turn && conversationId == turn.conversationId
    }

    private func finishTurn(_ turn: InFlightTurn) {
        if activeTurn == turn {
            activeTurn = nil
        }
        lastTerminalTurnToken = turn.token
        terminalTurnRevision += 1
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
}
