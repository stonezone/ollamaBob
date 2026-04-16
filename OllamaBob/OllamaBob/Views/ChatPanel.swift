import SwiftUI

struct ChatPanel: View {
    @ObservedObject var agentLoop: AgentLoop
    @StateObject private var session: ChatSessionController

    init(agentLoop: AgentLoop) {
        self.agentLoop = agentLoop
        _session = StateObject(wrappedValue: ChatSessionController(agentLoop: agentLoop))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ConversationManagerView(session: session)
                Spacer()
                Button("New Chat") {
                    session.startFreshConversation()
                }
                .disabled(agentLoop.isProcessing)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(session.messages) { msg in
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
                .onChange(of: session.messages.count) {
                    withAnimation {
                        proxy.scrollTo(session.messages.last?.id ?? "thinking", anchor: .bottom)
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

            if let error = session.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") { session.dismissError() }
                        .font(.caption)
                }
                .padding(8)
                .background(Color(.controlBackgroundColor))
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask Bob...", text: $session.inputText)
                    .textFieldStyle(.plain)
                    .onSubmit { session.sendCurrentInput(allowsLocalCommands: false) }

                Button(action: { session.sendCurrentInput(allowsLocalCommands: false) }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(session.inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing)
            }
            .padding(12)
        }
        .frame(minWidth: 400, minHeight: 500)
        .task { session.loadExistingConversationIfNeeded() }
    }
}
