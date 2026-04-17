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
            // Keep the macOS-drawn shadow — it's the only visual cue for
            // the resize edges now that we've removed every other chrome.
            window.hasShadow = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // Resizable mask must be present for edge-drag resizing to work.
            window.styleMask.insert(.resizable)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 420, height: 520)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Drag Handle

/// Transparent strip at the top of the chat window. Mouse-down initiates
/// `window.performDrag(with:)` so the user can move the chromeless window
/// by grabbing this area — without it, SwiftUI content covers every pixel
/// and `isMovableByWindowBackground` has no empty region to activate on.
private struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
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
    @ObservedObject private var avatarStore = AvatarStore.shared
    @StateObject private var session: ChatSessionController
    @State private var breathPhase     = false
    @State private var bubbleVisible   = false

    // F1 — greeting (display-only, not persisted)
    @State private var hasGreeted = false

    // F3 — memory count
    @State private var factCount = 0
    @State private var memoryRefreshTimer: Timer?
    @State private var totalMemoryLabel = "--"
    @State private var processMemoryTimer: Timer?

    // F4 — compaction notices (and greeting) rendered inline
    @State private var systemNotices: [SystemNotice] = []
    @State private var lastSeenToolActivityIndex = 0

    // F5 — keyboard focus
    @FocusState private var inputFocused: Bool

    // F6 — real-time tool feedback
    @State private var currentToolName: String? = nil
    @State private var autoScrollEnabled = true

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

    private var surfaceOpacity: Double {
        settings.chatWindowOpacity
    }

    private var textOpacity: Double {
        min(1.0, settings.chatWindowOpacity + 0.1)
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
            // Invisible top strip — grab anywhere up here to drag the window.
            // Needed because the chromeless NSWindow has no titlebar handle
            // and every other row is interactive SwiftUI that swallows clicks.
            WindowDragHandle()
                .frame(height: 18)

            if settings.showBob {
                portraitSection
                    .frame(height: 240)
                    .padding(.top, 4)
            }

            chatContainer
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 520, idealHeight: 760)
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
            refreshProcessMemory()
            startProcessMemoryTimer()
            // Delay greeting slightly so loadExistingConversationIfNeeded() can run first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                maybeGreet()
                updateBubbleForGreeting()
            }
            // Heartbeat: ticks every minute, fires at most once per 10–20 min
            // when Bob is idle and the app is frontmost.
            Heartbeat.shared.start(agentIsProcessing: { [agentLoop] in
                agentLoop.isProcessing
            })
            // First-launch onboarding — opens once, then never again
            // unless the user picks "Welcome / Tour…" from the menu bar.
            if !UserDefaults.standard.bool(forKey: OnboardingView.completionKey) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    openWindow(id: "onboarding")
                }
            }
        }
        .onDisappear {
            memoryRefreshTimer?.invalidate()
            memoryRefreshTimer = nil
            processMemoryTimer?.invalidate()
            processMemoryTimer = nil
            Heartbeat.shared.stop()
        }
        // Heartbeat: append inline notice whenever the controller publishes a new one.
        .onReceive(Heartbeat.shared.$lastNoticeAt) { at in
            guard let at, let text = Heartbeat.shared.lastNoticeText else { return }
            systemNotices.append(SystemNotice(text: text, at: at))
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
                .background(Self.phosphorGreen.opacity(0.15 * surfaceOpacity))

            inputRow
                .frame(height: 48)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Self.bgBlack.opacity(surfaceOpacity))
                .shadow(color: .black.opacity(0.4 * surfaceOpacity), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Portrait Section

    private var portraitSection: some View {
        VStack(spacing: 0) {
            // Above-Bob slot: speech bubble when idle (final answer),
            // transparent "invisible thoughts" while he's working. They
            // share this real estate so the UI never feels cluttered —
            // only the one that's relevant right now is visible.
            ZStack(alignment: .bottom) {
                thoughtsOverlay
                    .allowsHitTesting(false)

                speechBubbleView
                    .opacity(bubbleVisible && !agentLoop.isProcessing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: bubbleVisible)
                    .animation(.easeInOut(duration: 0.2), value: agentLoop.isProcessing)
            }
            .frame(maxWidth: 360, minHeight: 56)
            .padding(.bottom, 6)

            bobPortrait
                .padding(.bottom, 8)
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
        let pack = avatarStore.effectivePack(activePersonaID: personaStore.activePersonaID)
        // Only the classic robot pack is a monochrome phosphor sprite where
        // the persona tint reads as "different character." Cartoon packs are
        // full-color and need the identity color (.white) so colorMultiply is
        // a no-op — tinting them turns the shirt into sludge.
        let tint = pack.id == AvatarPacks.classicRobot.id ? spriteAccent : Color.white

        return ZStack {
            if let nsImage = pack.image(for: mood) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .colorMultiply(tint)
                    .opacity(surfaceOpacity)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgPanel.opacity(surfaceOpacity))
                    .frame(width: 140, height: 200)
                    .overlay(
                        Text("\(pack.filePrefix)\(mood.rawValue)")
                            .font(.caption2)
                            .foregroundColor(Self.phosphorGreen.opacity(0.6 * textOpacity))
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

    // MARK: - Thoughts Overlay

    /// Up to three of the most recent tool activity lines rendered as
    /// transparent floating text. No background, no border — just the words.
    /// Oldest fades to near-zero, newest is brightest. Empty while idle.
    private var thoughtsOverlay: some View {
        let lines = currentThoughtLines
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                // Newest line = index (count-1); oldest = 0. Fade older lines.
                let ageRatio = Double(idx) / Double(max(lines.count - 1, 1))
                let opacity = 0.25 + 0.55 * ageRatio
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Self.phosphorGreen.opacity(opacity * textOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(agentLoop.isProcessing ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: agentLoop.isProcessing)
        .animation(.easeInOut(duration: 0.25), value: lines)
    }

    /// Flatten recent tool activity into display-ready one-liners. Skips
    /// synthetic entries (compaction, prompt_compose) so the user only sees
    /// real reasoning/tool traffic. If a tool is currently running (set from
    /// `onChange(toolActivity.count)`), prepend an in-progress marker so the
    /// overlay has something to show even before the first entry settles.
    private var currentThoughtLines: [String] {
        let recent = agentLoop.toolActivity
            .filter { $0.toolName != "compaction" && $0.toolName != "prompt_compose" }
            .suffix(3)
        var lines = recent.map { entry in
            let input = entry.input.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = input.isEmpty ? "" : " \(input)"
            let line = "⚡ \(entry.toolName)\(summary)"
            return line.count > 80 ? String(line.prefix(80)) + "…" : line
        }
        // While Bob is processing but hasn't logged activity yet, show that
        // he's working so the overlay isn't blank for the opening beat.
        if agentLoop.isProcessing && lines.isEmpty {
            lines = ["⚡ thinking…"]
        }
        return lines
    }

    // MARK: - Speech Bubble

    private var speechBubbleView: some View {
        let rawText = latestAssistantLine ?? ""
        let display = rawText.count > 140
            ? String(rawText.prefix(140)) + "\u{2026}"
            : rawText

        return ZStack {
            SpeechBubbleShape()
                .fill(Color.white.opacity(surfaceOpacity))
            SpeechBubbleShape()
                .stroke(Color.black.opacity(surfaceOpacity), lineWidth: 1.5)
            Text(display)
                .font(.system(size: 11))
                .foregroundColor(.black.opacity(textOpacity))
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
                .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
            Text(agentLoop.currentModel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
            Text("  \u{2022}  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
            Text("ram \(totalMemoryLabel)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
                .help("Combined resident memory of the Bob app and the Ollama server")
            Text("  \u{2022}  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
            Text(statusWord)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen.opacity(textOpacity))

            // F3 — memory count badge (clickable, opens preferences)
            Text("  \u{2022}  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
            Button {
                openWindow(id: "preferences")
            } label: {
                Text("\u{1F9E0} \(factCount) facts")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
            }
            .buttonStyle(.plain)

            Spacer()

            // F12 — persona quick-swap badge
            PersonaQuickSwapMenu()
                .opacity(textOpacity)
                .padding(.trailing, 6)

            ConversationManagerView(session: session)
                .foregroundColor(Self.phosphorGreen)
                .opacity(textOpacity)
                .padding(.trailing, 10)

            // Context meter
            Text("ctx \(Int(contextFraction * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(contextColor.opacity(textOpacity))
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
                            if Self.shouldShowInTranscript(msg) {
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }
                        case .notice(let notice):
                            systemNoticeRow(notice)
                                .id(notice.id.uuidString)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { _ in autoScrollEnabled = false }
            )
            .onChange(of: session.messages.count) {
                guard autoScrollEnabled else { return }
                withAnimation {
                    proxy.scrollTo(session.messages.last?.id ?? "thinking", anchor: .bottom)
                }
            }
            .onChange(of: systemNotices.count) {
                guard autoScrollEnabled else { return }
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

    // MARK: - Transcript Filter

    /// Pure tool-invocation wrappers (assistant turn with only tool_calls, no
    /// visible body) live in the thoughts overlay. Everything else — user
    /// messages, tool output blocks like `df -h` results, and Bob's final
    /// replies — stays in the transcript so the chat reads like a terminal.
    private static func shouldShowInTranscript(_ msg: ChatMessage) -> Bool {
        switch msg.role {
        case .system: return false
        case .tool:   return true
        case .user:   return true
        case .assistant:
            let body = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty, let calls = msg.toolCalls, !calls.isEmpty {
                return false
            }
            return true
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
                    .foregroundColor(.white.opacity(0.85 * textOpacity))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Self.bgPanel.opacity(surfaceOpacity))
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
                    .foregroundColor(Color.white.opacity(0.30 * textOpacity))
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
                    .foregroundColor(.blue.opacity(textOpacity))
                Text("Switched model: \(notice.from) \u{2192} \(notice.to)")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(textOpacity))
                Spacer()
                Button("Dismiss") { agentLoop.modelSwitchNotice = nil }
                    .font(.caption)
            }
            .padding(8)
            .background(Self.bgPanel.opacity(surfaceOpacity))
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = session.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange.opacity(textOpacity))
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(textOpacity))
                Spacer()
                Button("Dismiss") { session.dismissError() }
                    .font(.caption)
            }
            .padding(8)
            .background(Self.bgPanel.opacity(surfaceOpacity))
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Ask Bob\u{2026}", text: $session.inputText)
                .textFieldStyle(.plain)
                .foregroundColor(.white.opacity(textOpacity))
                .font(.system(size: 13))
                .onSubmit { sendWithSound() }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .focused($inputFocused)                              // F5 — focus binding

            Button(action: { sendWithSound() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
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
        autoScrollEnabled = true
        // /clear and /new don't involve the agent loop, skip sounds for them
        let isLocalCommand = text == "/clear" || text == "/new"
        if !isLocalCommand {
            BobSounds.playSend()
            hasProcessed = true
            if let last = lastSendAt, Date().timeIntervalSince(last) > 300 {
                BobSayings.play(.idleReturn)
            }
            lastSendAt = Date()
            Heartbeat.shared.registerActivity()
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

    private func refreshProcessMemory() {
        Task {
            let snapshot = await ProcessMemorySampler.sample()
            await MainActor.run {
                let total: Int64? = {
                    switch (snapshot.bobBytes, snapshot.ollamaBytes) {
                    case let (b?, o?): return b + o
                    case let (b?, nil): return b
                    case let (nil, o?): return o
                    case (nil, nil):   return nil
                    }
                }()
                totalMemoryLabel = ProcessMemorySampler.format(total)
            }
        }
    }

    private func startProcessMemoryTimer() {
        processMemoryTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.refreshProcessMemory()
        }
        RunLoop.main.add(timer, forMode: .common)
        processMemoryTimer = timer
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
