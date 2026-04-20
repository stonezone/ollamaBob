import SwiftUI

struct ChatPanel: View {
    @ObservedObject var agentLoop: AgentLoop
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var session: ChatSessionController

    init(agentLoop: AgentLoop) {
        self.agentLoop = agentLoop
        _session = StateObject(wrappedValue: ChatSessionController(agentLoop: agentLoop))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ConversationManagerView(session: session)
                if uncensoredModeEnabled {
                    uncensoredConversationBadge
                }
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
                                ChatBubble(
                                    message: msg,
                                    chatWindowOpacity: settings.chatWindowOpacity,
                                    richPresentationEnabled: settings.richPresentationEnabled,
                                    richPresentationArtifactChipsEnabled: settings.richPresentationArtifactChipsEnabled
                                )
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

                uncensoredTogglePill

                Button(action: { session.sendCurrentInput(allowsLocalCommands: false) }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(session.inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing)
            }
            .padding(12)
        }
        .frame(minWidth: 400, minHeight: 500)
        .task {
            session.loadExistingConversationIfNeeded()
            enforceMasterUncensoredSetting()
        }
        .onChange(of: session.conversationId) {
            enforceMasterUncensoredSetting()
        }
        .onChange(of: settings.uncensoredModeAvailable) {
            enforceMasterUncensoredSetting()
        }
    }

    private var uncensoredModeEnabled: Bool {
        settings.uncensoredModeAvailable && session.conversationUncensoredMode
    }

    private var uncensoredToggleDisabled: Bool {
        agentLoop.isProcessing
    }

    private func enforceMasterUncensoredSetting() {
        guard settings.uncensoredModeAvailable == false, session.conversationUncensoredMode else { return }
        session.setConversationUncensoredMode(false)
    }

    private var uncensoredConversationBadge: some View {
        Text("UNCENSORED")
            .font(.system(size: 9, design: .monospaced).weight(.bold))
            .foregroundColor(.black.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 1.0, green: 0.60, blue: 0.22))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.15), lineWidth: 0.6)
            )
            .fixedSize()
            .help("This conversation is marked uncensored. Configured tag: \(settings.effectiveUncensoredModelName)")
    }

    @ViewBuilder
    private var uncensoredTogglePill: some View {
        if settings.uncensoredModeAvailable {
            Button {
                session.toggleConversationUncensoredMode()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: uncensoredModeEnabled ? "flame.fill" : "flame")
                    Text("UNCENSORED")
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(
                    uncensoredModeEnabled
                        ? Color.black.opacity(0.82)
                        : Color.primary.opacity(0.75)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            uncensoredModeEnabled
                                ? Color(red: 1.0, green: 0.60, blue: 0.22)
                                : Color(.controlBackgroundColor)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            uncensoredModeEnabled
                                ? Color.black.opacity(0.15)
                                : Color.primary.opacity(0.18),
                            lineWidth: 0.8
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(uncensoredToggleDisabled)
            .opacity(uncensoredToggleDisabled ? 0.5 : 1.0)
            .help(
                session.conversationId == nil
                    ? "Toggle uncensored mode for the next conversation. Configured tag: \(settings.effectiveUncensoredModelName)"
                    : "Toggle uncensored mode for this conversation. Configured tag: \(settings.effectiveUncensoredModelName)"
            )
        }
    }
}
