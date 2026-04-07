import SwiftUI

// MARK: - Speech Bubble Shape

/// Rounded rectangle with a small downward-pointing triangular tail centered
/// at the bottom edge. Used to position the bubble above Bob's portrait with
/// the tail pointing at his head.
private struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat = 12
    var tailWidth: CGFloat = 16
    var tailHeight: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - tailHeight
        )

        var path = Path()
        path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // Tail: triangle below the center-bottom of the body
        let tailLeft = rect.midX - tailWidth / 2
        let tailRight = rect.midX + tailWidth / 2
        let tailTop = bodyRect.maxY
        let tailTip = rect.maxY

        path.move(to: CGPoint(x: tailLeft, y: tailTop))
        path.addLine(to: CGPoint(x: rect.midX, y: tailTip))
        path.addLine(to: CGPoint(x: tailRight, y: tailTop))
        path.closeSubpath()

        return path
    }
}

// MARK: - BobsDeskView

struct BobsDeskView: View {

    // MARK: Style Constants

    private static let phosphorGreen = Color(red: 0.22, green: 1.0, blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)

    // MARK: State

    @ObservedObject var agentLoop: AgentLoop
    @State private var inputText      = ""
    @State private var messages:       [ChatMessage]   = []
    @State private var ollamaHistory:  [OllamaMessage] = []
    @State private var errorMessage:   String?
    @State private var conversationId: String?
    @State private var breathPhase     = false
    @State private var bubbleVisible   = false

    // MARK: Computed helpers

    /// The most recent assistant message with non-empty content, for the speech bubble.
    private var latestAssistantLine: String? {
        messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })
            .map { $0.content }
    }

    /// True only when the very last visible message is an assistant text reply.
    private var shouldShowBubble: Bool {
        guard let last = messages.last(where: { $0.role != .system }) else { return false }
        return last.role == .assistant && !last.content.isEmpty
    }

    private var statusWord: String {
        agentLoop.isProcessing ? agentLoop.bobMood.rawValue : "idle"
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            portraitSection
                .frame(height: 304)   // ~40% of 760

            statusLine
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            Divider()
                .background(Self.phosphorGreen.opacity(0.3))

            transcriptSection
                .frame(maxHeight: .infinity)  // fills remaining ~50%

            inputRow
                .frame(height: 48)
        }
        .frame(width: 520, height: 760)
        .background(Self.bgBlack)
        .task { loadExistingConversation() }
        // Sync bubble visibility whenever messages change
        .onChange(of: messages.count) {
            withAnimation(.easeInOut(duration: 0.3)) {
                bubbleVisible = shouldShowBubble
            }
        }
        // Also react when a message's content changes (tool result fills in)
        .onReceive(agentLoop.$isProcessing) { processing in
            if processing {
                withAnimation(.easeInOut(duration: 0.3)) {
                    bubbleVisible = false
                }
            }
        }
    }

    // MARK: - Portrait Section

    private var portraitSection: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Speech bubble sits above the portrait, centered
                speechBubbleView
                    .padding(.bottom, 6)
                    .opacity(bubbleVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: bubbleVisible)

                bobPortrait
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Kick off breathing idle animation
            withAnimation(
                .easeInOut(duration: 3.5).repeatForever(autoreverses: true)
            ) {
                breathPhase = true
            }
        }
    }

    private var bobPortrait: some View {
        let mood = agentLoop.bobMood
        let imageName = "bob_\(mood.rawValue)"

        // The ZStack + .id causes SwiftUI to create a new view (cross-fade) on mood change
        return ZStack {
            if let nsImage = NSImage(named: imageName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
            } else if let url = Bundle.module.url(forResource: imageName, withExtension: "png"),
                      let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
            } else {
                // Fallback placeholder when sprite not found
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgPanel)
                    .frame(width: 140, height: 200)
                    .overlay(
                        Text(imageName)
                            .font(.caption2)
                            .foregroundColor(Self.phosphorGreen.opacity(0.6))
                    )
            }
        }
        .id(mood)                                                   // triggers cross-fade on mood change
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: mood)
        .scaleEffect(idleBreathScale(mood: mood))
        .animation(
            mood == .idle
                ? .easeInOut(duration: 3.5).repeatForever(autoreverses: true)
                : .easeInOut(duration: 0.25),
            value: breathPhase
        )
    }

    /// Returns 1.015 when breathing out, 1.0 when breathing in — only active in idle.
    private func idleBreathScale(mood: BobMood) -> CGFloat {
        guard mood == .idle else { return 1.0 }
        return breathPhase ? 1.015 : 1.0
    }

    // MARK: - Speech Bubble

    private var speechBubbleView: some View {
        let rawText = latestAssistantLine ?? ""
        let display = rawText.count > 140
            ? String(rawText.prefix(140)) + "…"
            : rawText

        return ZStack {
            SpeechBubbleShape()
                .fill(Color.white)
            SpeechBubbleShape()
                .stroke(Color.black, lineWidth: 1.5)
            // Text sits inside the body (above the tail)
            Text(display)
                .font(.system(size: 11))
                .foregroundColor(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 18)   // leave room for the tail
        }
        .frame(maxWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Status Line

    private var statusLine: some View {
        HStack(spacing: 0) {
            Text(">_ ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen)
            Text(agentLoop.currentModel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen)
            Text("  •  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen)
            Text(statusWord)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen)
            Spacer()
        }
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
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
                                .tint(Self.phosphorGreen)
                            Text("Bob is thinking...")
                                .font(.caption)
                                .foregroundColor(Self.phosphorGreen.opacity(0.8))
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
        .background(Self.bgPanel)
        .cornerRadius(8)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // Model switch notice
        .safeAreaInset(edge: .top, spacing: 0) {
            modelSwitchBanner
        }
        // Error notice
        .safeAreaInset(edge: .bottom, spacing: 0) {
            errorBanner
        }
    }

    @ViewBuilder
    private var modelSwitchBanner: some View {
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
            .background(Self.bgPanel)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
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
            .background(Self.bgPanel)
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Ask Bob…", text: $inputText)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .onSubmit { sendMessage() }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Self.bgPanel)
                .cornerRadius(8)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(Self.phosphorGreen)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Conversation Persistence (verbatim from ChatPanel)

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

        do {
            try DatabaseManager.shared.saveMessage(userMsg, conversationId: convoId)
        } catch {
            errorMessage = "Failed to save message: \(error.localizedDescription)"
        }

        let previousHistoryCount      = ollamaHistory.count
        let previousToolActivityCount = agentLoop.toolActivity.count

        Task {
            do {
                let updatedHistory = try await agentLoop.process(userMessage: text, history: ollamaHistory)

                let startIndex = previousHistoryCount + 1  // +1 for the user message we just added
                if startIndex < updatedHistory.count {
                    for i in startIndex..<updatedHistory.count {
                        let ollamaMsg = updatedHistory[i]
                        if ollamaMsg.role == "assistant" {
                            if let toolCalls = ollamaMsg.toolCalls, !toolCalls.isEmpty {
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
