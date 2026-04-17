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

// MARK: - System Notice  (F4 compaction + F1 greeting)

/// Lightweight in-memory overlay item rendered inline in the transcript.
/// Never persisted to the database.
struct SystemNotice: Identifiable {
    let id = UUID()
    let text: String
    let at: Date
    var isGreeting: Bool = false
}

// MARK: - BobsDeskView

struct BobsDeskView: View {

    // MARK: Style Constants

    private static let phosphorGreen = Color(red: 0.22, green: 1.0, blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)

    /// Exposed for PersonaQuickSwapMenu so it can share the same green tint.
    static let phosphorGreenPublic = Color(red: 0.22, green: 1.0, blue: 0.08)

    // MARK: State

    @ObservedObject var agentLoop: AgentLoop
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var personaStore = PersonaStore.shared
    @StateObject private var session: ChatSessionController
    @State private var breathPhase     = false
    @State private var bubbleVisible   = false

    // F1 — greeting (display-only, not persisted)
    @State private var hasGreeted = false

    // F3 — memory count
    @State private var factCount = 0
    @State private var memoryRefreshTimer: Timer?

    // F4 — compaction notices (and greeting) rendered inline
    @State private var systemNotices: [SystemNotice] = []
    @State private var lastSeenToolActivityIndex = 0

    // F5 — keyboard focus
    @FocusState private var inputFocused: Bool

    // F6 — real-time tool feedback
    @State private var currentToolName: String? = nil

    // F8 — sound: true once the user has dispatched at least one message
    @State private var hasProcessed = false

    // F2 — celebration: per-turn tool count + start time. Set when isProcessing
    // flips true, compared when it flips false. Real tools only (not the
    // pseudo "compaction" and "prompt_compose" log entries).
    @State private var turnStartedAt: Date? = nil
    @State private var turnStartingToolCount: Int = 0

    // Bob-voice idle-return: last time the user sent something. If >5min,
    // the next send plays an "idle_return" clip.
    @State private var lastSendAt: Date? = nil

    // F12 — preferences window access
    @Environment(\.openWindow) private var openWindow

    init(agentLoop: AgentLoop) {
        self.agentLoop = agentLoop
        _session = StateObject(wrappedValue: ChatSessionController(agentLoop: agentLoop))
    }

    // MARK: Computed helpers

    /// The most recent assistant message with non-empty content, for the speech bubble.
    private var latestAssistantLine: String? {
        // Check system notices (greeting) first if no real messages
        let realLine = session.messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })
            .map { $0.content }
        if let line = realLine { return line }
        // Fallback: show greeting in bubble too
        return systemNotices.first(where: { $0.isGreeting })?.text
    }

    /// True only when the very last visible message is an assistant text reply.
    private var shouldShowBubble: Bool {
        if let last = session.messages.last(where: { $0.role != .system }) {
            return last.role == .assistant && !last.content.isEmpty
        }
        // Show bubble for greeting even when chat is otherwise empty
        return systemNotices.contains(where: { $0.isGreeting })
    }

    private var statusWord: String {
        agentLoop.isProcessing ? agentLoop.bobMood.rawValue : "idle"
    }

    // F7 — persona sprite tint
    private var spriteAccent: Color {
        let rgb = GreetingLines.accentColor(for: personaStore.activePersonaID)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // MARK: - Context Budget

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
                // F2 — start-of-turn bookkeeping
                turnStartedAt = Date()
                turnStartingToolCount = agentLoop.toolActivity.filter {
                    $0.toolName != "compaction" && $0.toolName != "prompt_compose"
                }.count
            } else {
                // F6 — clear tool chip when processing finishes
                currentToolName = nil
                // F8 — play receive sound only after a user-initiated round-trip
                if hasProcessed {
                    BobSounds.playReceive()
                }
                // F2 — celebrate only when the turn did real work. A plain chat
                // reply on a local model can easily hit 10s, so time alone isn't
                // enough — we require at least one tool call plus either a
                // meaningful duration or multiple tools.
                if let start = turnStartedAt {
                    let elapsed = Date().timeIntervalSince(start)
                    let endCount = agentLoop.toolActivity.filter {
                        $0.toolName != "compaction" && $0.toolName != "prompt_compose"
                    }.count
                    let delta = endCount - turnStartingToolCount
                    let didRealWork = (delta >= 2) || (delta >= 1 && elapsed >= 15)
                    if didRealWork {
                        let text = GreetingLines.celebrationForPersona(personaStore.activePersonaID)
                        if !text.isEmpty {
                            systemNotices.append(SystemNotice(text: text, at: Date()))
                        }
                        // 60% boast / 40% celebration mix so Bob sounds less repetitive.
                        BobSayings.play(Double.random(in: 0...1) < 0.6 ? .boast : .celebration)
                    }
                }
                turnStartedAt = nil
            }
        }
        // F4 — watch toolActivity for compaction events
        .onReceive(agentLoop.$toolActivity) { activity in
            checkForCompaction(in: activity)
        }
        // F6 — watch toolActivity for in-progress tool names
        .onChange(of: agentLoop.toolActivity.count) {
            if agentLoop.isProcessing, let last = agentLoop.toolActivity.last {
                currentToolName = last.toolName
            }
        }
        // F5 — new chat notification
        .onReceive(NotificationCenter.default.publisher(for: .bobNewChat)) { _ in
            session.startFreshConversation()
            systemNotices.removeAll(where: { $0.isGreeting })
            hasGreeted = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                maybeGreet()
            }
        }
        .onAppear {
            refreshFactCount()
            startMemoryRefreshTimer()
            // Delay greeting slightly so loadExistingConversationIfNeeded() can run first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                maybeGreet()
                updateBubbleForGreeting()
            }
        }
        .onDisappear {
            memoryRefreshTimer?.invalidate()
            memoryRefreshTimer = nil
        }
    }

    // MARK: - Chat Container

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

        return ZStack {
            if let nsImage = NSImage(named: imageName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .colorMultiply(spriteAccent)     // F7 — persona tint
            } else if let url = Bundle.module.url(forResource: imageName, withExtension: "png"),
                      let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .colorMultiply(spriteAccent)     // F7 — persona tint
            } else {
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
        .id(mood)
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

    private func idleBreathScale(mood: BobMood) -> CGFloat {
        guard mood == .idle else { return 1.0 }
        return breathPhase ? 1.015 : 1.0
    }

    // MARK: - Speech Bubble

    private var speechBubbleView: some View {
        let rawText = latestAssistantLine ?? ""
        let display = rawText.count > 140
            ? String(rawText.prefix(140)) + "\u{2026}"
            : rawText

        return ZStack {
            SpeechBubbleShape()
                .fill(Color.white)
            SpeechBubbleShape()
                .stroke(Color.black, lineWidth: 1.5)
            Text(display)
                .font(.system(size: 11))
                .foregroundColor(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 18)
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
            Text("  \u{2022}  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen)
            Text(statusWord)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen)

            // F3 — memory count badge (clickable, opens preferences)
            Text("  \u{2022}  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen)
            Button {
                openWindow(id: "preferences")
            } label: {
                Text("\u{1F9E0} \(factCount) facts")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Self.phosphorGreen)
            }
            .buttonStyle(.plain)

            Spacer()

            // F12 — persona quick-swap badge
            PersonaQuickSwapMenu()
                .padding(.trailing, 6)

            ConversationManagerView(session: session)
                .foregroundColor(Self.phosphorGreen)
                .padding(.trailing, 10)

            // Context meter
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
                    ForEach(interleavedItems) { item in
                        switch item.content {
                        case .message(let msg):
                            if msg.role != .system {
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }
                        case .notice(let notice):
                            systemNoticeRow(notice)
                                .id(notice.id.uuidString)
                        }
                    }

                    // F6 — real-time tool feedback chip
                    if agentLoop.isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(Self.phosphorGreen)
                            if let toolName = currentToolName, !toolName.isEmpty {
                                Text("\u{2699} \(toolName)\u{2026}")
                                    .font(.caption)
                                    .foregroundColor(Self.phosphorGreen.opacity(0.8))
                            } else {
                                Text("Bob is thinking...")
                                    .font(.caption)
                                    .foregroundColor(Self.phosphorGreen.opacity(0.8))
                            }
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
            .onChange(of: systemNotices.count) {
                withAnimation {
                    if let last = systemNotices.last {
                        proxy.scrollTo(last.id.uuidString, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .safeAreaInset(edge: .top, spacing: 0) {
            modelSwitchBanner
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            errorBanner
        }
    }

    // MARK: - Interleaving helpers (F1 + F4)

    private enum ItemContent {
        case message(ChatMessage)
        case notice(SystemNotice)
    }

    private struct InterleavedItem: Identifiable {
        let id: String
        let timestamp: Date
        let content: ItemContent
    }

    private var interleavedItems: [InterleavedItem] {
        var items: [InterleavedItem] = []
        for msg in session.messages {
            items.append(InterleavedItem(id: msg.id, timestamp: msg.timestamp, content: .message(msg)))
        }
        for notice in systemNotices {
            items.append(InterleavedItem(id: notice.id.uuidString, timestamp: notice.at, content: .notice(notice)))
        }
        return items.sorted { $0.timestamp < $1.timestamp }
    }

    @ViewBuilder
    private func systemNoticeRow(_ notice: SystemNotice) -> some View {
        if notice.isGreeting {
            // Greeting renders as a speech-bubble-style assistant message row
            HStack {
                Spacer()
                Text(notice.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Self.bgPanel)
                    )
                    .padding(.trailing, 8)
            }
        } else {
            // Compaction notice: centered dim italic line
            HStack {
                Spacer()
                Text(notice.text)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(Color.white.opacity(0.30))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var modelSwitchBanner: some View {
        if let notice = agentLoop.modelSwitchNotice {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                Text("Switched model: \(notice.from) \u{2192} \(notice.to)")
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
            TextField("Ask Bob\u{2026}", text: $session.inputText)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .font(.system(size: 13))
                .onSubmit { sendWithSound() }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .focused($inputFocused)                              // F5 — focus binding

            Button(action: { sendWithSound() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(Self.phosphorGreen)
            }
            .buttonStyle(.plain)
            .disabled(session.inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // F5 — Cmd+K focuses the input field
        .background(
            Button("") { inputFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        )
    }

    // F8 — play send sound then dispatch; set hasProcessed so receive sound is enabled
    private func sendWithSound() {
        let text = session.inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // /clear and /new don't involve the agent loop, skip sounds for them
        let isLocalCommand = text == "/clear" || text == "/new"
        if !isLocalCommand {
            BobSounds.playSend()
            hasProcessed = true
            if let last = lastSendAt, Date().timeIntervalSince(last) > 300 {
                BobSayings.play(.idleReturn)
            }
            lastSendAt = Date()
        }
        session.sendCurrentInput(allowsLocalCommands: true)
    }

    // MARK: - F1 Greeting

    private func maybeGreet() {
        guard !hasGreeted else { return }
        let hasRealMessages = !session.messages.filter({ $0.role != .system }).isEmpty
        guard !hasRealMessages else {
            hasGreeted = true
            return
        }
        let text = GreetingLines.forPersona(personaStore.activePersonaID)
        guard !text.isEmpty else {
            hasGreeted = true
            return
        }
        let notice = SystemNotice(text: text, at: Date(), isGreeting: true)
        systemNotices.append(notice)
        hasGreeted = true
        BobSayings.play(.greeting)
        withAnimation(.easeInOut(duration: 0.3)) {
            bubbleVisible = true
        }
    }

    private func updateBubbleForGreeting() {
        withAnimation(.easeInOut(duration: 0.3)) {
            bubbleVisible = shouldShowBubble
        }
    }

    // MARK: - F3 Memory count helpers

    private func refreshFactCount() {
        factCount = (try? DatabaseManager.shared.fetchFacts().count) ?? 0
    }

    private func startMemoryRefreshTimer() {
        memoryRefreshTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                self.refreshFactCount()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        memoryRefreshTimer = t
    }

    // MARK: - F4 Compaction detection

    private func checkForCompaction(in activity: [AgentLoop.ToolLogEntry]) {
        guard activity.count > lastSeenToolActivityIndex else { return }
        let newEntries = activity[lastSeenToolActivityIndex...]
        lastSeenToolActivityIndex = activity.count
        for entry in newEntries where entry.toolName == "compaction" {
            let notice = SystemNotice(
                text: "\u{2014} compacted older turns to free up context \u{2014}",
                at: entry.timestamp,
                isGreeting: false
            )
            systemNotices.append(notice)
        }
    }
}

// MARK: - Notification name (F5)

extension Notification.Name {
    static let bobNewChat = Notification.Name("com.ollamabob.newChat")
}
