import SwiftUI
import AppKit

// MARK: - Window Transparency

/// Strips all macOS chrome from the chat window: makes the NSWindow non-opaque,
/// hides the title bar visuals and traffic-light buttons, and lets the user
/// drag from any background area. Result is a chrome-free surface where only
/// the SwiftUI content (Bob's sprite + the rounded chat container) is visible.
/// Close via Cmd+W.
private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

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
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var session: ChatSessionController
    @State private var breathPhase     = false
    @State private var bubbleVisible   = false

    init(agentLoop: AgentLoop) {
        self.agentLoop = agentLoop
        _session = StateObject(wrappedValue: ChatSessionController(agentLoop: agentLoop))
    }

    // MARK: Computed helpers

    /// The most recent assistant message with non-empty content, for the speech bubble.
    private var latestAssistantLine: String? {
        session.messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })
            .map { $0.content }
    }

    /// True only when the very last visible message is an assistant text reply.
    private var shouldShowBubble: Bool {
        guard let last = session.messages.last(where: { $0.role != .system }) else { return false }
        return last.role == .assistant && !last.content.isEmpty
    }

    private var statusWord: String {
        agentLoop.isProcessing ? agentLoop.bobMood.rawValue : "idle"
    }

    // MARK: - Context Budget

    /// Rough token estimate for everything Bob currently carries: system prompt
    /// plus every persisted message. Ollama counts tokens, not characters; the
    /// common rule of thumb is ~4 chars per token for English which is close
    /// enough for a visual meter.
    private var contextTokensUsed: Int {
        let persona = PersonaStore.shared.activePersona
        var chars = PromptComposer.compose(persona: persona).count
        for msg in session.history where msg.role != "system" {
            chars += msg.content.count
            if let calls = msg.toolCalls {
                for call in calls {
                    chars += call.function.name.count
                    chars += String(describing: call.function.parsedArguments).count
                }
            }
        }
        return chars / 4
    }

    private var contextFraction: Double {
        min(1.0, Double(contextTokensUsed) / Double(settings.numCtx))
    }

    private var contextColor: Color {
        switch contextFraction {
        case ..<0.75: return Self.phosphorGreen
        case ..<0.90: return .yellow
        default:      return .red
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            if settings.showBob {
                portraitSection
                    .frame(height: 240)
                    .padding(.top, 8)
            }

            chatContainer
        }
        .frame(width: 520, height: 760)
        .background(WindowTransparencyConfigurator())
        .task { session.loadExistingConversationIfNeeded() }
        // Sync bubble visibility whenever messages change
        .onChange(of: session.messages.count) {
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

    // MARK: - Chat Container

    /// Rounded matte-dark panel holding status, transcript, divider and input.
    /// Bob's portrait lives outside this container (above it), so the area
    /// around Bob is fully transparent — the desktop shows through directly.
    private var chatContainer: some View {
        VStack(spacing: 0) {
            statusLine
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            transcriptSection
                .frame(maxHeight: .infinity)

            Divider()
                .background(Self.phosphorGreen.opacity(0.15))

            inputRow
                .frame(height: 48)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Self.bgBlack.opacity(settings.chatWindowOpacity))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
        )
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
                    .frame(maxHeight: 140)
            } else if let url = Bundle.module.url(forResource: imageName, withExtension: "png"),
                      let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
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

            ConversationManagerView(session: session)
                .foregroundColor(Self.phosphorGreen)
                .padding(.trailing, 10)

            // Context meter — shows how full the 8K window is.
            Text("ctx \(Int(contextFraction * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(contextColor)
                .padding(.trailing, 10)
        }
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
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
            .onChange(of: session.messages.count) {
                withAnimation {
                    proxy.scrollTo(session.messages.last?.id ?? "thinking", anchor: .bottom)
                }
            }
        }
        .padding(.horizontal, 12)
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
            .background(Self.bgPanel)
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Ask Bob…", text: $session.inputText)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .font(.system(size: 13))
                .onSubmit { session.sendCurrentInput(allowsLocalCommands: true) }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)

            Button(action: { session.sendCurrentInput(allowsLocalCommands: true) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(Self.phosphorGreen)
            }
            .buttonStyle(.plain)
            .disabled(session.inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

}
