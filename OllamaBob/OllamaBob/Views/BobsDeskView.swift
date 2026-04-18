import SwiftUI
import AppKit

// MARK: - Window Transparency

/// Strips all macOS chrome from the chat window: makes the NSWindow non-opaque,
/// hides the title bar visuals and traffic-light buttons, and lets the user
/// drag from any background area. Also walks the titlebar container tree and
/// hides every NSVisualEffectView — macOS's hidden-titlebar style still
/// renders a frosted-glass strip behind the content, and there's no public
/// API to disable it. Tracks window frames per-mode so the user can park
/// full mode and avatar-only mode in separate spots on the screen.
/// Close via Cmd+W.
private struct WindowTransparencyConfigurator: NSViewRepresentable {
    let avatarOnly: Bool

    private static let fullMinSize   = NSSize(width: 420, height: 520)
    private static let avatarMinSize = NSSize(width: 280, height: 320)

    func makeCoordinator() -> Coordinator {
        Coordinator(avatarOnly: avatarOnly)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let mode = avatarOnly
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
            window.minSize = mode ? Self.avatarMinSize : Self.fullMinSize
            // SwiftUI's content view can paint its own layer background on
            // top of an otherwise-transparent NSWindow. Force it clear so
            // avatar-only mode shows only Bob + bubbles over the desktop.
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = .clear
            }
            context.coordinator.attachIfNeeded(window: window)
            Self.hideChromeEffectViews(under: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if context.coordinator.avatarOnly != avatarOnly {
            let previousMode = context.coordinator.avatarOnly
            context.coordinator.avatarOnly = avatarOnly
            window.minSize = avatarOnly ? Self.avatarMinSize : Self.fullMinSize
            context.coordinator.handleModeSwitch(window: window, from: previousMode)
        }
        // The frosted titlebar view can be re-added by AppKit on window
        // state changes (resize, screen move). Re-hide on every update.
        Self.hideChromeEffectViews(under: window)
        // SwiftUI re-paints the contentView background on state changes —
        // clear it again so the desktop shows through.
        window.contentView?.layer?.backgroundColor = .clear
    }

    /// Walk every subview of the window's root content container and
    /// neutralise anything that paints a window-wide backdrop:
    /// - hide `NSVisualEffectView` (the frosted "liquid glass" strip the
    ///   hidden-titlebar style leaves behind)
    /// - clear the CALayer background on every view in the hierarchy.
    ///   NSThemeFrame, NSHostingView, and private SwiftUI backing views
    ///   all paint their own layer fill on macOS 14 even when the NSWindow
    ///   itself is set to `isOpaque = false` / `backgroundColor = .clear`.
    ///   SwiftUI draws its content via CoreGraphics into the layer's
    ///   drawing context, not via `layer.backgroundColor`, so stripping
    ///   every backdrop tint is safe for rendered content.
    private static func hideChromeEffectViews(under window: NSWindow) {
        guard let rootView = window.contentView?.superview ?? window.contentView else { return }
        var queue: [NSView] = [rootView]
        while let current = queue.popLast() {
            if current is NSVisualEffectView {
                current.isHidden = true
            }
            if let layer = current.layer, layer.backgroundColor != nil {
                layer.backgroundColor = .clear
            }
            queue.append(contentsOf: current.subviews)
        }
    }

    /// Holds the NSWindow reference and per-mode frame observers. Writes
    /// window-move/resize events back to `AppSettings` under the matching
    /// mode's key, and restores the saved frame on mode switches.
    @MainActor
    final class Coordinator {
        var avatarOnly: Bool
        private weak var window: NSWindow?
        private var moveObs: NSObjectProtocol?
        private var resizeObs: NSObjectProtocol?

        init(avatarOnly: Bool) { self.avatarOnly = avatarOnly }

        func attachIfNeeded(window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            applySavedFrame(window: window)
            startObserving(window: window)
        }

        func handleModeSwitch(window: NSWindow, from previous: Bool) {
            // Save the current frame under the mode we're leaving, then
            // restore whatever was saved for the mode we're entering.
            saveFrame(mode: previous, frame: window.frame)
            applySavedFrame(window: window)
        }

        private func applySavedFrame(window: NSWindow) {
            let raw = avatarOnly
                ? AppSettings.shared.avatarModeWindowFrame
                : AppSettings.shared.fullModeWindowFrame
            guard !raw.isEmpty else { return }
            let rect = NSRectFromString(raw)
            guard rect.width >= 200, rect.height >= 200 else { return }
            // Don't restore onto a screen the user no longer has plugged in.
            let visibleOnAnyScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
            guard visibleOnAnyScreen else { return }
            window.setFrame(rect, display: true, animate: false)
        }

        private func startObserving(window: NSWindow) {
            let center = NotificationCenter.default
            moveObs.map { center.removeObserver($0) }
            resizeObs.map { center.removeObserver($0) }
            moveObs = center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.saveFrame(mode: self.avatarOnly, frame: window.frame)
                }
            }
            resizeObs = center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.saveFrame(mode: self.avatarOnly, frame: window.frame)
                }
            }
        }

        private func saveFrame(mode: Bool, frame: NSRect) {
            let str = NSStringFromRect(frame)
            if mode {
                AppSettings.shared.avatarModeWindowFrame = str
            } else {
                AppSettings.shared.fullModeWindowFrame = str
            }
        }

        deinit {
            if let o = moveObs { NotificationCenter.default.removeObserver(o) }
            if let o = resizeObs { NotificationCenter.default.removeObserver(o) }
        }
    }
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

// MARK: - Comic Bubble Shape

/// Unified comic-book-style speech bubble: rounded square body with a
/// tapered triangular tail at the bottom. `tailDX` shifts the tail tip
/// horizontally (defaults to 0 = straight down). Used for Bob's response
/// bubble, the thinking-dots bubble, and the avatar-only input bubble.
///
/// Geometry constants aim for a thick-stroked, rounded-square silhouette
/// that reads as a comic panel rather than a system speech balloon:
/// generous corner radius, slim pointed tail, no fine detail.
private struct ComicBubbleShape: Shape {
    var tailDX: CGFloat = 0
    var cornerRadius: CGFloat = 18
    var tailWidth: CGFloat = 10
    var tailHeight: CGFloat = 14

    var animatableData: CGFloat {
        get { tailDX }
        set { tailDX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - tailHeight
        )

        var path = Path()
        path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        let tailLeft  = rect.midX - tailWidth / 2
        let tailRight = rect.midX + tailWidth / 2
        let tailTop   = bodyRect.maxY
        let tipX      = rect.midX + tailDX
        let tipY      = rect.maxY

        path.move(to: CGPoint(x: tailLeft, y: tailTop))
        path.addLine(to: CGPoint(x: tipX, y: tipY))
        path.addLine(to: CGPoint(x: tailRight, y: tailTop))
        path.closeSubpath()

        return path
    }
}

// MARK: - Thinking Dots

/// Three black "3D bubble" circles that scale and fade in sequence. Used
/// inside the avatar-only thinking bubble while Bob is processing, in place
/// of the normal response text.
private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                dot(phase: t * 1.6)
                dot(phase: t * 1.6 + 0.25)
                dot(phase: t * 1.6 + 0.5)
            }
        }
    }

    private func dot(phase: Double) -> some View {
        let cycle = phase.truncatingRemainder(dividingBy: 1.0)
        let wave  = 0.5 + 0.5 * sin(cycle * 2 * .pi)
        let scale = 0.65 + 0.35 * wave
        let opacity = 0.35 + 0.65 * wave
        return Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.35),
                        Color.black
                    ]),
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 1,
                    endRadius: 8
                )
            )
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 3, height: 3)
                    .offset(x: -1.5, y: -1.5)
            )
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

// MARK: - Input Bubble Tail Tracker

/// Observes window move/resize/screen notifications, computes the horizontal
/// delta between the tracked view's on-screen centre and the primary
/// monitor's bottom-centre (where a keyboard would be), and writes that
/// delta into `tailDX` so `OrientedSpeechBubbleShape` can lean its tail
/// toward the user's likely "mouth".
private struct InputBubbleTailTracker: NSViewRepresentable {
    @Binding var tailDX: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = TrackerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onPositionChange = { screenCenter in
            // Primary monitor (the one with the menu bar / Dock in the
            // default setup) is NSScreen.screens.first on macOS.
            let primary = NSScreen.screens.first ?? NSScreen.main
            let targetX = primary?.frame.midX ?? screenCenter.x
            let dx = targetX - screenCenter.x
            // Clamp so the tail doesn't leave the bubble body when Bob
            // is parked at a screen edge.
            let clamped = max(-60, min(60, dx))
            DispatchQueue.main.async {
                if abs(tailDX - clamped) > 0.5 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        tailDX = clamped
                    }
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackerView: NSView {
        var onPositionChange: ((CGPoint) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window = window else { return }
            let center = NotificationCenter.default
            for name in [
                NSWindow.didMoveNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didChangeScreenNotification
            ] {
                let obs = center.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in self?.report() }
                observers.append(obs)
            }
            // Report once after layout settles so the initial tail reflects
            // where the window actually opened.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        private func report() {
            guard let window = window else { return }
            let rectInWindow = convert(bounds, to: nil)
            let rectOnScreen = window.convertToScreen(rectInWindow)
            onPositionChange?(CGPoint(x: rectOnScreen.midX, y: rectOnScreen.midY))
        }

        private func removeObservers() {
            for obs in observers { NotificationCenter.default.removeObserver(obs) }
            observers.removeAll()
        }

        deinit { removeObservers() }
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

    // Avatar-only mode: horizontal offset of the input bubble's tail tip,
    // computed from the window's on-screen position vs. the primary
    // monitor's bottom-centre. Driven by InputBubbleTailTracker.
    @State private var inputTailDX: CGFloat = 0

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
        Group {
            if settings.avatarOnlyMode {
                avatarOnlyLayout
                    .frame(minWidth: 300, idealWidth: 360, minHeight: 340, idealHeight: 420)
            } else {
                fullLayout
                    .frame(minWidth: 420, idealWidth: 520, minHeight: 520, idealHeight: 760)
            }
        }
        .background(Color.clear)
        .background(WindowTransparencyConfigurator(avatarOnly: settings.avatarOnlyMode))
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
                // Re-sync the bubble a beat after processing ends. The
                // session controller appends the turn's messages AFTER
                // the agent loop returns, so at this instant the bubble
                // might still be stale; a short delay lets messages
                // settle, then shouldShowBubble reflects the final answer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        bubbleVisible = shouldShowBubble
                    }
                }
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

    // MARK: - Layouts

    /// The full terminal-style layout: drag strip → Bob (optional) → transcript
    /// + input row. This is the classic Bob's Desk surface.
    private var fullLayout: some View {
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
    }

    /// The stripped-back avatar-only layout: just Bob with a bubble above him
    /// (response or animated thinking dots) and a compact input bubble below.
    /// No transcript, no tool trace, no status line. Drag the window by
    /// clicking on Bob himself.
    private var avatarOnlyLayout: some View {
        VStack(spacing: 4) {
            // Top spacer nudges Bob down from the window's edge so the bubble
            // has room to breathe.
            Spacer(minLength: 8)

            // Bob's response/thinking area — speech bubble when idle, dots
            // when processing.
            ZStack(alignment: .bottom) {
                speechBubbleView
                    .opacity(bubbleVisible && !agentLoop.isProcessing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: bubbleVisible)
                    .animation(.easeInOut(duration: 0.2), value: agentLoop.isProcessing)

                thinkingDotsBubble
                    .opacity(agentLoop.isProcessing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: agentLoop.isProcessing)
            }
            .frame(maxWidth: 300, minHeight: 52)

            draggablePortrait

            compactInputBubble
                .opacity(agentLoop.isProcessing ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: agentLoop.isProcessing)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }

    /// Bob's portrait overlaid with a transparent drag handle. Mouse-down on
    /// Bob himself initiates window drag, so there's no separate drag strip
    /// in avatar-only mode.
    private var draggablePortrait: some View {
        ZStack {
            bobPortrait
            WindowDragHandle()
        }
        .frame(height: 160)
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

    // MARK: - Thinking Dots Bubble  (avatar-only mode)

    /// Bob's speech bubble with animated dots in place of text, shown in
    /// avatar-only mode while he's processing. Mirrors `speechBubbleView`'s
    /// white-with-black-stroke styling so the shape reads as "Bob thinking".
    private var thinkingDotsBubble: some View {
        ZStack {
            ComicBubbleShape()
                .fill(Color.white.opacity(surfaceOpacity))
            ComicBubbleShape()
                .stroke(Color.black.opacity(surfaceOpacity), lineWidth: 3)
            ThinkingDots()
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 22)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.25 * surfaceOpacity), radius: 0, x: 2, y: 2)
        .frame(width: 82, height: 48)
    }

    // MARK: - Compact Input Bubble  (avatar-only mode)

    /// Small white speech bubble below Bob that grows as the user types.
    /// Tail points down toward the primary monitor's bottom-centre (where
    /// a keyboard would roughly be) via `inputTailDX`. Honors the
    /// translucency slider like every other surface.
    private var compactInputBubble: some View {
        ZStack {
            ComicBubbleShape(tailDX: inputTailDX)
                .fill(Color.white.opacity(surfaceOpacity))
            ComicBubbleShape(tailDX: inputTailDX)
                .stroke(Color.black.opacity(surfaceOpacity), lineWidth: 3)

            HStack(alignment: .center, spacing: 6) {
                TextField("Ask Bob\u{2026}", text: $session.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(textOpacity))
                    .focused($inputFocused)
                    .onSubmit { sendWithSound() }

                Button(action: { sendWithSound() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(textOpacity))
                }
                .buttonStyle(.plain)
                .disabled(session.inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.25 * surfaceOpacity), radius: 0, x: 2, y: 2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 160, idealWidth: 230, maxWidth: 290)
        .background(InputBubbleTailTracker(tailDX: $inputTailDX))
    }

    // MARK: - Speech Bubble

    private var speechBubbleView: some View {
        let rawText = latestAssistantLine ?? ""
        let display = rawText.count > 140
            ? String(rawText.prefix(140)) + "\u{2026}"
            : rawText

        return ZStack {
            ComicBubbleShape()
                .fill(Color.white.opacity(surfaceOpacity))
            ComicBubbleShape()
                .stroke(Color.black.opacity(surfaceOpacity), lineWidth: 3)
            Text(display)
                .font(.system(size: 11))
                .foregroundColor(.black.opacity(textOpacity))
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.25 * surfaceOpacity), radius: 0, x: 2, y: 2)
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
