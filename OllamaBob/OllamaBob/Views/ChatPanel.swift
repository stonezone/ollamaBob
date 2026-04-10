import SwiftUI

struct ChatPanel: View {
    @ObservedObject var agentLoop: AgentLoop
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var ollamaHistory: [OllamaMessage] = []
    @State private var errorMessage: String?
    @State private var conversationId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(messages) { msg in
                            if msg.role != .system {
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }
                        }

                        if agentLoop.isProcessing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Bob is thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .id("thinking")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo(messages.last?.id ?? "thinking", anchor: .bottom)
                    }
                }
            }

            if let notice = agentLoop.modelSwitchNotice {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue)
                    Text("Switched model: \(notice.from) → \(notice.to)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") { agentLoop.modelSwitchNotice = nil }
                        .font(.caption)
                }
                .padding(8)
                .background(Color(.controlBackgroundColor))
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }
                        .font(.caption)
                }
                .padding(8)
                .background(Color(.controlBackgroundColor))
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask Bob...", text: $inputText)
                    .textFieldStyle(.plain)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing)
            }
            .padding(12)
        }
        .frame(minWidth: 400, minHeight: 500)
        .task { loadExistingConversation() }
    }

    /// On first appear, restore the most recent conversation (if any) so the chat
    /// survives panel close/reopen and full app relaunch.
    private func loadExistingConversation() {
        guard conversationId == nil else { return }
        do {
            guard let convo = try DatabaseManager.shared.currentConversation() else { return }
            let stored = try DatabaseManager.shared.loadMessages(conversationId: convo.id)
            conversationId = convo.id
            messages = stored
            ollamaHistory = stored.compactMap(Self.toOllamaMessage(_:))
        } catch {
            errorMessage = "Failed to load history: \(error.localizedDescription)"
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        // Lazily create the conversation row on the first user message so we don't
        // litter the DB with empty conversations on every app launch.
        let convoId: String
        do {
            if let existing = conversationId {
                convoId = existing
            } else {
                let new = try DatabaseManager.shared.createConversation()
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

        // Persist the user message immediately so it survives a crash mid-loop.
        do {
            try DatabaseManager.shared.saveMessage(userMsg, conversationId: convoId)
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
                    conversationId: convoId
                )

                // Extract new messages from the updated history
                // Skip the system message and messages we already had, plus the user message we just added
                let startIndex = previousHistoryCount + 1  // +1 for the user message
                if startIndex < updatedHistory.count {
                    for i in startIndex..<updatedHistory.count {
                        let ollamaMsg = updatedHistory[i]
                        if ollamaMsg.role == "assistant" {
                            if let toolCalls = ollamaMsg.toolCalls, !toolCalls.isEmpty {
                                // Content is intentionally empty — ChatBubble
                                // renders a distinct tool-call row based on the
                                // toolCalls array itself. Using a literal string
                                // like "Using shell…" collides with model output.
                                for call in toolCalls {
                                    let chatMsg = ChatMessage(
                                        role: .assistant,
                                        content: "",
                                        toolCalls: [call]
                                    )
                                    messages.append(chatMsg)
                                    persist(chatMsg, in: convoId)
                                }
                            } else if !ollamaMsg.content.isEmpty {
                                let chatMsg = ChatMessage(role: .assistant, content: ollamaMsg.content)
                                messages.append(chatMsg)
                                persist(chatMsg, in: convoId)
                            }
                        } else if ollamaMsg.role == "tool" {
                            let chatMsg = ChatMessage(
                                role: .tool,
                                content: ollamaMsg.content,
                                toolName: ollamaMsg.toolName
                            )
                            messages.append(chatMsg)
                            persist(chatMsg, in: convoId)
                        }
                    }
                }

                ollamaHistory = updatedHistory

                // Persist any new tool log entries that the agent loop produced.
                let newActivity = agentLoop.toolActivity.dropFirst(previousToolActivityCount)
                for entry in newActivity {
                    do {
                        try DatabaseManager.shared.saveToolLog(
                            conversationId: convoId,
                            toolName: entry.toolName,
                            inputJson: entry.input,
                            outputText: entry.output,
                            approvalLevel: entry.approval,
                            approved: entry.approved,
                            durationMs: entry.durationMs
                        )
                    } catch {
                        // Tool log persistence is best-effort — surface but don't abort.
                        errorMessage = "Failed to log tool: \(error.localizedDescription)"
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func persist(_ msg: ChatMessage, in convoId: String) {
        do {
            try DatabaseManager.shared.saveMessage(msg, conversationId: convoId)
        } catch {
            errorMessage = "Failed to save message: \(error.localizedDescription)"
        }
    }

    /// Convert a stored ChatMessage back into the Ollama wire-format so that
    /// the agent loop can resume an existing conversation. The system prompt is
    /// re-added by AgentLoop.process if missing, so we never store/replay it.
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
