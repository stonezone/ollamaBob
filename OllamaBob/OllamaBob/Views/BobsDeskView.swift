import SwiftUI
import AppKit

// MARK: - Window Transparency

enum ChatWindowMetrics {
    static let fullMinSize = NSSize(width: 420, height: 520)
    static let avatarMinSize = NSSize(width: 280, height: 340)
    static let avatarMaxSize = NSSize(width: 420, height: 420)
    static let avatarMinimumVisibleHeight: CGFloat = 240
}

/// Strips all macOS chrome from the chat window: makes the NSWindow non-opaque,
/// hides the title bar visuals and traffic-light buttons, and lets the user
/// drag from any background area. Also walks the titlebar container tree and
/// hides every NSVisualEffectView — macOS's hidden-titlebar style still
/// renders a frosted-glass strip behind the content, and there's no public
/// API to disable it. Tracks window frames per-mode so the user can park
/// full mode and avatar-only mode in separate spots on the screen.
/// Close via Cmd+W.
struct WindowTransparencyConfigurator: NSViewRepresentable {
    let avatarOnly: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(avatarOnly: avatarOnly)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let mode = avatarOnly
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.applyChromelessConfiguration(to: window, avatarOnly: mode)
            context.coordinator.attachIfNeeded(window: window)
            Self.stripBackdrop(under: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if context.coordinator.avatarOnly != avatarOnly {
            let previousMode = context.coordinator.avatarOnly
            let outgoingFrame = window.frame
            context.coordinator.handleModeSwitch(
                window: window,
                from: previousMode,
                to: avatarOnly,
                outgoingFrame: outgoingFrame
            )
        }
        // AppKit re-adds frosted chrome on window state changes (resize,
        // screen move). Re-strip on every update to keep the backdrop clear.
        Self.stripBackdrop(under: window)
    }

    /// Apply the same transparency baseline to the NSWindow in both modes:
    /// non-opaque, clear backgroundColor, no titlebar, hidden traffic-lights,
    /// resizable, and background dragging only where AppKit's default window
    /// constraints are acceptable. Shadow is kept ON for the full chat
    /// surface (discoverable resize edges) and dropped in avatar-only mode
    /// (no visible chrome at all per the design target).
    ///
    /// `.titled` styleMask is removed in avatar-only mode — that dissolves
    /// NSThemeFrame, which macOS 14 backs with a system material even when
    /// `backgroundColor = .clear`. The borderless styleMask still draws
    /// SwiftUI content and honours resize (because `.resizable` is kept).
    static func applyChromelessConfiguration(to window: NSWindow, avatarOnly: Bool) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = !avatarOnly
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if avatarOnly {
            window.styleMask.remove(.titled)
            window.styleMask.remove(.fullSizeContentView)
        } else {
            window.styleMask.insert(.titled)
            window.styleMask.insert(.fullSizeContentView)
        }
        window.styleMask.insert(.resizable)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = !avatarOnly
        window.minSize = avatarOnly ? ChatWindowMetrics.avatarMinSize : ChatWindowMetrics.fullMinSize
        window.maxSize = avatarOnly
            ? ChatWindowMetrics.avatarMaxSize
            : NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = nil
            contentView.layer?.isOpaque = false
        }
    }

    /// Strip every source of window backdrop so the desktop reads through.
    /// Three things paint an opaque fill that would otherwise remain:
    /// 1. `NSVisualEffectView` — AppKit adds one under the titlebar for the
    ///    "hidden titlebar" style; hiding doesn't unwind the compositor
    ///    material, so we detach it outright.
    /// 2. Layer `backgroundColor` — NSThemeFrame, NSHostingView, and their
    ///    intermediate backing views default to a grey fill on macOS 14.
    ///    Force every layer to a clear CGColor.
    /// 3. Layer `isOpaque` — even with a clear `backgroundColor`, an opaque
    ///    layer asks the compositor to pre-fill a rect before SwiftUI
    ///    draws into it. Flip to non-opaque so the compositor blends.
    /// SwiftUI content paints via Core Graphics into the layer display
    /// context rather than via `layer.backgroundColor`, so no rendered
    /// content is lost by this walk.
    private static func stripBackdrop(under window: NSWindow) {
        guard let rootView = window.contentView?.superview ?? window.contentView else { return }
        var queue: [NSView] = [rootView]
        while let current = queue.popLast() {
            queue.append(contentsOf: current.subviews)
            if current is NSVisualEffectView {
                current.removeFromSuperview()
                continue
            }
            if let layer = current.layer {
                // Set to `nil` (not `.clear`) so SwiftUI's reconciler
                // doesn't see a "configured" color and revert to its
                // default material on the next redraw.
                layer.backgroundColor = nil
                layer.isOpaque = false
            }
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
        private var screenParamsObs: NSObjectProtocol?

        init(avatarOnly: Bool) { self.avatarOnly = avatarOnly }

        func attachIfNeeded(window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            applySavedFrame(window: window)
            startObserving(window: window)
            revalidateWindowFrame(window: window, persistIfAdjusted: true)
        }

        func handleModeSwitch(window: NSWindow, from previous: Bool, to next: Bool, outgoingFrame: NSRect) {
            // Save the frame before changing style masks or size constraints,
            // then restore the destination mode with its own bounds.
            saveFrame(mode: previous, frame: normalizedFrame(outgoingFrame, avatarOnly: previous) ?? outgoingFrame)
            avatarOnly = next
            WindowTransparencyConfigurator.applyChromelessConfiguration(to: window, avatarOnly: next)
            applySavedFrame(window: window)
            revalidateWindowFrame(window: window, persistIfAdjusted: true)
        }

        private func applySavedFrame(window: NSWindow) {
            let raw = avatarOnly
                ? AppSettings.shared.avatarModeWindowFrame
                : AppSettings.shared.fullModeWindowFrame
            guard !raw.isEmpty else { return }
            let rect = NSRectFromString(raw)
            guard rect.width >= 200, rect.height >= 200 else { return }
            let visibleFrames = NSScreen.screens.map(\.visibleFrame)
            guard let clamped = WindowFrameRecovery.clampedFrame(
                rect,
                minimumSize: minimumWindowSize,
                maximumSize: maximumWindowSize,
                minimumVisibleHeight: minimumVisibleHeight,
                visibleFrames: visibleFrames
            ) else {
                return
            }
            if window.frame.equalTo(clamped) == false {
                window.setFrame(clamped, display: true, animate: false)
            }
            saveFrame(mode: avatarOnly, frame: clamped)
        }

        private func startObserving(window: NSWindow) {
            let center = NotificationCenter.default
            moveObs.map { center.removeObserver($0) }
            resizeObs.map { center.removeObserver($0) }
            screenParamsObs.map { center.removeObserver($0) }
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
            screenParamsObs = center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.revalidateWindowFrame(window: window, persistIfAdjusted: true)
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

        private var minimumWindowSize: NSSize {
            avatarOnly ? ChatWindowMetrics.avatarMinSize : ChatWindowMetrics.fullMinSize
        }

        private var maximumWindowSize: NSSize? {
            avatarOnly ? ChatWindowMetrics.avatarMaxSize : nil
        }

        private var minimumVisibleHeight: CGFloat? {
            avatarOnly ? ChatWindowMetrics.avatarMinimumVisibleHeight : nil
        }

        private func revalidateWindowFrame(window: NSWindow, persistIfAdjusted: Bool) {
            let visibleFrames = NSScreen.screens.map(\.visibleFrame)
            guard let clamped = WindowFrameRecovery.clampedFrame(
                window.frame,
                minimumSize: minimumWindowSize,
                maximumSize: maximumWindowSize,
                minimumVisibleHeight: minimumVisibleHeight,
                visibleFrames: visibleFrames
            ) else {
                return
            }

            let adjusted = window.frame.equalTo(clamped) == false
            if adjusted {
                window.setFrame(clamped, display: true, animate: false)
            }

            if persistIfAdjusted && adjusted {
                saveFrame(mode: avatarOnly, frame: clamped)
            }
        }

        private func normalizedFrame(_ frame: NSRect, avatarOnly: Bool) -> NSRect? {
            WindowFrameRecovery.clampedFrame(
                frame,
                minimumSize: avatarOnly
                    ? ChatWindowMetrics.avatarMinSize
                    : ChatWindowMetrics.fullMinSize,
                maximumSize: avatarOnly
                    ? ChatWindowMetrics.avatarMaxSize
                    : nil,
                minimumVisibleHeight: avatarOnly
                    ? ChatWindowMetrics.avatarMinimumVisibleHeight
                    : nil,
                visibleFrames: NSScreen.screens.map(\.visibleFrame)
            )
        }

        deinit {
            if let o = moveObs { NotificationCenter.default.removeObserver(o) }
            if let o = resizeObs { NotificationCenter.default.removeObserver(o) }
            if let o = screenParamsObs { NotificationCenter.default.removeObserver(o) }
        }
    }
}

enum WindowFrameRecovery {
    static func clampedFrame(
        _ frame: NSRect,
        minimumSize: NSSize,
        maximumSize: NSSize? = nil,
        minimumVisibleHeight: CGFloat? = nil,
        visibleFrames: [NSRect]
    ) -> NSRect? {
        let cleanedFrames = visibleFrames.filter { $0.width > 0 && $0.height > 0 }
        guard cleanedFrames.isEmpty == false else { return nil }

        let target = preferredVisibleFrame(for: frame, visibleFrames: cleanedFrames)
        let cappedWidth = min(frame.width, maximumSize?.width ?? frame.width)
        let cappedHeight = min(frame.height, maximumSize?.height ?? frame.height)
        let width = min(target.width, max(cappedWidth, minimumSize.width))
        let height = min(target.height, max(cappedHeight, minimumSize.height))
        let requiredVisibleHeight = min(height, max(minimumVisibleHeight ?? height, 1))

        let minX = target.minX
        let maxX = target.maxX - width
        let minY = target.minY
        let maxY = target.maxY - requiredVisibleHeight

        let originX = min(max(frame.minX, minX), maxX)
        let originY = min(max(frame.minY, minY), maxY)

        return NSRect(
            x: originX,
            y: originY,
            width: width,
            height: height
        )
    }

    private static func preferredVisibleFrame(for frame: NSRect, visibleFrames: [NSRect]) -> NSRect {
        let bestIntersection = visibleFrames.max { lhs, rhs in
            lhs.intersection(frame).area < rhs.intersection(frame).area
        }

        if let bestIntersection, bestIntersection.intersection(frame).area > 0 {
            return bestIntersection
        }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return visibleFrames.min { lhs, rhs in
            distanceSquared(from: center, to: lhs) < distanceSquared(from: center, to: rhs)
        } ?? visibleFrames[0]
    }

    private static func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }
}

private extension NSRect {
    var area: CGFloat {
        width * height
    }
}

// MARK: - Drag Handle

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

/// Rounded speech bubble with a slim triangular tail at the bottom. The
/// tail's base position along the bottom edge is controlled by
/// `tailAnchorX` (0 = left edge, 0.5 = centred, 1 = right edge); `tailDX`
/// shifts the tip horizontally from that base. Used for Bob's response
/// bubble, the thinking-dots bubble, and (optionally) the input bubble.
enum BubbleTailDirection {
    case down, up
}

private struct ComicBubbleShape: Shape {
    var tailDX: CGFloat = 0
    var tailAnchorX: CGFloat = 0.5
    var cornerRadius: CGFloat = 18
    var tailWidth: CGFloat = 14
    var tailHeight: CGFloat = 14
    var tailDirection: BubbleTailDirection = .down

    var animatableData: CGFloat {
        get { tailDX }
        set { tailDX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bodyRect: CGRect
        let tailBaseY: CGFloat
        let tipY: CGFloat
        switch tailDirection {
        case .down:
            bodyRect = CGRect(x: rect.minX, y: rect.minY,
                              width: rect.width, height: rect.height - tailHeight)
            tailBaseY = bodyRect.maxY
            tipY = rect.maxY
        case .up:
            bodyRect = CGRect(x: rect.minX, y: rect.minY + tailHeight,
                              width: rect.width, height: rect.height - tailHeight)
            tailBaseY = bodyRect.minY
            tipY = rect.minY
        }

        var path = Path()
        path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        let clampedAnchor = min(max(tailAnchorX, 0.1), 0.9)
        let baseCenter    = rect.minX + rect.width * clampedAnchor
        let tailLeft      = baseCenter - tailWidth / 2
        let tailRight     = baseCenter + tailWidth / 2
        let tipX          = baseCenter + tailDX

        path.move(to: CGPoint(x: tailLeft, y: tailBaseY))
        path.addLine(to: CGPoint(x: tipX, y: tipY))
        path.addLine(to: CGPoint(x: tailRight, y: tailBaseY))
        path.closeSubpath()

        return path
    }
}

// MARK: - Thinking Dots

/// Three black "3D bubble" circles that scale and fade in sequence. Used
/// inside the avatar-only thinking bubble while Bob is processing, in place
/// of the normal response text.
private struct ThinkingDots: View {
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: 6) {
                    staticDot(opacity: 0.75)
                    staticDot(opacity: 0.9)
                    staticDot(opacity: 0.75)
                }
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 6) {
                        dot(phase: t * 1.6)
                        dot(phase: t * 1.6 + 0.25)
                        dot(phase: t * 1.6 + 0.5)
                    }
                }
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

    private func staticDot(opacity: Double) -> some View {
        Circle()
            .fill(Color.black.opacity(opacity))
            .frame(width: 8, height: 8)
    }
}

struct AvatarBubbleLayoutMetrics: Equatable {
    let width: CGFloat
    let minHeight: CGFloat
    let useScroll: Bool
    let horizontalOffset: CGFloat
    let tailAnchorX: CGFloat
    let tailDX: CGFloat
}

enum AvatarBubblePresentation {
    static let minWidth: CGFloat = 156
    static let maxWidth: CGFloat = 336
    static let shortMinHeight: CGFloat = 44
    static let thinkingWidth: CGFloat = 108
    static let thinkingMinHeight: CGFloat = 48

    static func metrics(lines: [String], maxHeight: CGFloat, isThinking: Bool) -> AvatarBubbleLayoutMetrics {
        if isThinking {
            return AvatarBubbleLayoutMetrics(
                width: thinkingWidth,
                minHeight: thinkingMinHeight,
                useScroll: false,
                horizontalOffset: -24,
                tailAnchorX: 0.72,
                tailDX: 6
            )
        }

        let sanitized = lines
            .map {
                $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.isEmpty == false }

        let effectiveLines = sanitized.isEmpty ? [""] : sanitized
        let maxChars = effectiveLines.map(\.count).max() ?? 0
        let lineCount = effectiveLines.count

        let width = clamp(
            minWidth + CGFloat(min(maxChars, 34)) * 4.4 + CGFloat(max(0, lineCount - 1)) * 8,
            min: minWidth,
            max: maxWidth
        )

        let widthRatio = (width - minWidth) / max(maxWidth - minWidth, 1)
        let charactersPerLine = max(16, Int((width - 48) / 7.0))
        let visualLineCount = effectiveLines.reduce(0) { partialResult, line in
            partialResult + max(1, Int(ceil(Double(max(line.count, 1)) / Double(charactersPerLine))))
        }
        let estimatedHeight = 28 + CGFloat(visualLineCount) * 22 + CGFloat(max(0, lineCount - 1)) * 4
        let useScroll = estimatedHeight > max(maxHeight - 6, shortMinHeight)

        return AvatarBubbleLayoutMetrics(
            width: width,
            minHeight: shortMinHeight,
            useScroll: useScroll,
            horizontalOffset: -22 + 10 * widthRatio,
            tailAnchorX: 0.80 - 0.15 * widthRatio,
            tailDX: 10 - 6 * widthRatio
        )
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
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

private struct ScrollContentBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - BobsDeskView

struct BobsDeskView: View {

    // MARK: Style Constants

    private static let phosphorGreen = Color(red: 0.22, green: 1.0, blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)

    // Avatar-only bubble palette. Soft translucent fill + hair-thin stroke
    // so the desktop reads through the bubble and nothing chromes the
    // window; paired with a diffuse drop-shadow instead of a hard comic
    // offset. Matches the "chat bubble over the backdrop" target look.
    // Alpha is intentionally fixed (not multiplied by chatWindowOpacity) —
    // the slider governs the chat surface chrome in fullLayout; avatar-only
    // bubbles carry their own translucency and must stay legible at any
    // chatWindowOpacity setting.
    private static let bubbleFill         = Color.white.opacity(0.48)
    private static let bubbleStroke       = Color.black.opacity(0.18)
    private static let speechBubbleFill   = Color.white.opacity(0.64)
    private static let speechBubbleStroke = Color.black.opacity(0.28)
    private static let avatarBubbleTailAnchorX: CGFloat = 0.56

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
    @State private var awaitingTurnTranscript = false

    // F1 — greeting (display-only, not persisted)
    @State private var hasGreeted = false

    // F3 — memory count
    @State private var factCount = 0
    @State private var memoryRefreshTimer: Timer?
    @State private var totalMemoryLabel = "--"
    @State private var processMemoryTimer: Timer?

    // F4 — compaction notices (and greeting) rendered inline
    @State private var systemNotices: [SystemNotice] = []
    @State private var interleavedItemsCache: [InterleavedItem] = []
    @State private var lastSeenToolActivityIndex = 0

    // F5 — keyboard focus
    @FocusState private var inputFocused: Bool

    // F6 — real-time tool feedback
    @State private var currentToolName: String? = nil
    @State private var autoScrollEnabled = true
    @State private var isNearBottom = true
    @State private var cachedContextTokensUsed = 0

    // Plan 2 — transient history overlay (avatar-only mode)
    @State private var showHistoryOverlay = false

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(agentLoop: AgentLoop) {
        self.agentLoop = agentLoop
        _session = StateObject(wrappedValue: ChatSessionController(agentLoop: agentLoop))
    }

    // MARK: Computed helpers

    /// The most recent assistant message with non-empty content, for the speech bubble.
    private var latestAssistantMessage: ChatMessage? {
        session.messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })
    }

    private var latestAssistantPreview: ChatBubbleRendering.AvatarPreview? {
        latestAssistantMessage.map { ChatBubbleRendering.avatarBubblePreview(for: $0.content) }
    }

    private var latestGreetingLine: String? {
        systemNotices.first(where: { $0.isGreeting })?.text
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

    private var transcriptRefreshToken: String {
        let lastMessageToken = session.messages.last.map { "\($0.id)|\($0.content.count)|\($0.timestamp.timeIntervalSince1970)" } ?? "none"
        let lastNoticeToken = systemNotices.last.map { "\($0.id.uuidString)|\($0.text.count)|\($0.at.timeIntervalSince1970)" } ?? "none"
        return "\(session.conversationId ?? "nil")|\(session.messages.count)|\(lastMessageToken)|\(systemNotices.count)|\(lastNoticeToken)"
    }

    private var uncensoredModeEnabled: Bool {
        settings.uncensoredModeAvailable && session.conversationUncensoredMode
    }

    private var uncensoredModeToggleDisabled: Bool {
        agentLoop.isProcessing
    }

    private var uncensoredModeHelpText: String {
        if session.conversationId == nil {
            return "Toggle uncensored mode for the next conversation. Configured tag: \(settings.effectiveUncensoredModelName)"
        }
        let action = uncensoredModeEnabled ? "Turn off" : "Turn on"
        return "\(action) uncensored mode for this conversation. Configured tag: \(settings.effectiveUncensoredModelName)"
    }

    private var avatarSurfaceFill: Color {
        reduceTransparency ? Color.white.opacity(0.94) : Self.bubbleFill.opacity(surfaceOpacity)
    }

    private var avatarSurfaceStroke: Color {
        reduceTransparency ? Color.black.opacity(0.28) : Self.bubbleStroke.opacity(surfaceOpacity)
    }

    private var avatarSpeechFill: Color {
        reduceTransparency ? Color.white.opacity(0.97) : Self.speechBubbleFill
    }

    private var avatarSpeechStroke: Color {
        reduceTransparency ? Color.black.opacity(0.40) : Self.speechBubbleStroke
    }

    private var avatarBubbleShadow: Color {
        Color.black.opacity(reduceTransparency ? 0.16 : 0.22)
    }

    private var avatarVisibilityAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    private var avatarProcessingAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    // F7 — persona sprite tint
    private var spriteAccent: Color {
        let rgb = GreetingLines.accentColor(for: personaStore.activePersonaID)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // MARK: - Context Budget

    private func computeContextTokensUsed() -> Int {
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

    private func refreshContextTokensUsed() {
        cachedContextTokensUsed = computeContextTokensUsed()
    }

    private var contextTokensUsed: Int {
        cachedContextTokensUsed
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
        .task {
            session.loadExistingConversationIfNeeded()
            enforceMasterUncensoredSetting()
            rebuildInterleavedItems()
            refreshContextTokensUsed()
        }
        .onChange(of: session.conversationId) {
            resetConversationScopedNoticeState()
            enforceMasterUncensoredSetting()
            rebuildInterleavedItems()
            refreshContextTokensUsed()
            withAnimation(avatarVisibilityAnimation) {
                bubbleVisible = shouldShowBubble
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                maybeGreet()
            }
        }
        .onChange(of: settings.uncensoredModeAvailable) {
            enforceMasterUncensoredSetting()
        }
        .onChange(of: settings.avatarOnlyMode) { _, avatarOnlyMode in
            if avatarOnlyMode == false {
                showHistoryOverlay = false
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotionEnabled in
            if reduceMotionEnabled {
                breathPhase = false
            }
        }
        .onChange(of: personaStore.activePersonaID) {
            refreshContextTokensUsed()
        }
        .onChange(of: transcriptRefreshToken) {
            rebuildInterleavedItems()
        }
        // Sync bubble visibility whenever the transcript actually changes.
        .onChange(of: session.transcriptRevision) {
            refreshContextTokensUsed()
            withAnimation(avatarVisibilityAnimation) {
                bubbleVisible = shouldShowBubble
            }
        }
        .onChange(of: session.terminalTurnRevision) {
            awaitingTurnTranscript = false
            withAnimation(avatarVisibilityAnimation) {
                bubbleVisible = shouldShowBubble
            }
        }
        .onChange(of: session.errorMessage) {
            guard agentLoop.isProcessing == false else { return }
            withAnimation(avatarVisibilityAnimation) {
                bubbleVisible = shouldShowBubble
            }
        }
        // Also react when a message's content changes (tool result fills in)
        .onReceive(agentLoop.$isProcessing) { processing in
            if processing {
                awaitingTurnTranscript = true
                withAnimation(avatarVisibilityAnimation) {
                    bubbleVisible = true
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
        // F4/F6 — watch toolActivity for compaction events and in-progress tool names
        .onReceive(agentLoop.$toolActivity) { activity in
            checkForCompaction(in: activity)
            if agentLoop.isProcessing, let last = activity.last {
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
        // Plan 2 — toggle history overlay from menu bar shortcut
        .onReceive(NotificationCenter.default.publisher(for: .bobToggleHistoryOverlay)) { _ in
            toggleAvatarHistoryOverlay()
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
                    AppWindowRouter.shared.open(id: AppWindowRouter.onboardingID)
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
        // GeometryReader measures the live window height so the bubble's
        // cap is always `height - Bob - input - gaps`. Bob's 160pt slot and
        // the input pill get `.layoutPriority(2)` so the bubble gives up
        // space first when the window is short. The visible avatar content
        // is top-anchored inside the transparent frame so Bob can sit nearer
        // to the screen edge without relying on offscreen window movement.
        ZStack {
            GeometryReader { proxy in
                let portrait: CGFloat = 160
                let inputSlot: CGFloat = 56   // pill height incl. tail + padding
                let gapTop: CGFloat = 10
                let gapBubbleToBob: CGFloat = 6
                let gapBobToInput: CGFloat = 10
                let gapBottom: CGFloat = 12
                let reserved = portrait + inputSlot + gapTop + gapBubbleToBob + gapBobToInput + gapBottom
                let bubbleCap = max(Self.minBubbleHeight, proxy.size.height - reserved)

                VStack(spacing: 0) {
                    Spacer().frame(height: gapTop)

                    speechBubbleView(maxHeight: bubbleCap)
                        .overlay(alignment: .topTrailing) {
                            historyToggleButton
                                .offset(x: 8, y: -8)
                        }
                        .opacity(bubbleVisible || agentLoop.isProcessing ? 1 : 0)
                        .animation(avatarVisibilityAnimation, value: bubbleVisible)
                        .animation(avatarProcessingAnimation, value: agentLoop.isProcessing)
                        .frame(maxWidth: AvatarBubblePresentation.maxWidth + 24, maxHeight: bubbleCap, alignment: .bottom)
                    .layoutPriority(0)

                    Spacer().frame(height: gapBubbleToBob)

                    draggablePortrait
                        .layoutPriority(2)

                    if uncensoredModeEnabled {
                        uncensoredConversationBadge
                            .padding(.top, 8)
                            .layoutPriority(1)
                    }

                    Spacer().frame(height: gapBobToInput)

                    compactInputBubble
                        .opacity(agentLoop.isProcessing ? 0.0 : 1.0)
                        .animation(avatarVisibilityAnimation, value: agentLoop.isProcessing)
                        .padding(.horizontal, 20)
                        .layoutPriority(2)

                    Spacer().frame(height: gapBottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                modelSwitchBanner
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                errorBanner
            }

            if showHistoryOverlay {
                historyOverlay
            }
        }
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

                speechBubbleView(maxHeight: Self.portraitBubbleMaxHeight)
                    .opacity(bubbleVisible || agentLoop.isProcessing ? 1 : 0)
                    .animation(avatarVisibilityAnimation, value: bubbleVisible)
                    .animation(avatarProcessingAnimation, value: agentLoop.isProcessing)
            }
            .frame(maxWidth: 360, minHeight: 56, maxHeight: Self.portraitBubbleMaxHeight)
            .padding(.bottom, 6)

            bobPortrait
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard reduceMotion == false else {
                breathPhase = false
                return
            }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
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
        let hasArt = pack.image(for: mood) != nil

        return ZStack {
            if let nsImage = pack.image(for: mood) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .colorMultiply(tint)
                    .opacity(surfaceOpacity)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(reduceTransparency ? Color.white.opacity(0.88) : Self.bgPanel.opacity(surfaceOpacity))
                    .frame(width: 140, height: 200)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "person.crop.rectangle")
                                .font(.system(size: 42, weight: .medium))
                                .foregroundColor(.black.opacity(0.42))
                            Text("Bob")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.black.opacity(0.58))
                        }
                    }
            }
        }
        .id(mood)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mood)
        .scaleEffect(idleBreathScale(mood: mood))
        .animation(
            reduceMotion
                ? nil
                : (mood == .idle
                    ? .easeInOut(duration: 3.5).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.25)),
            value: breathPhase
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bob avatar")
        .accessibilityValue(
            hasArt
                ? "\(pack.name), \(accessibleMoodDescription(mood))"
                : "\(accessibleMoodDescription(mood)), using fallback artwork"
        )
    }

    private func idleBreathScale(mood: BobMood) -> CGFloat {
        guard mood == .idle, reduceMotion == false else { return 1.0 }
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

    // MARK: - Compact Input Bubble  (avatar-only mode)

    /// Pill-shaped translucent input below Bob. "Ask Bob…" placeholder on
    /// the left, circular send button on the right. No tail — the input
    /// reads as a discrete control rather than a second speech bubble, so
    /// the view isn't competing with Bob's response balloon above.
    private var compactInputBubble: some View {
        let trimmed = session.inputText.trimmingCharacters(in: .whitespaces)
        let canSend = !trimmed.isEmpty && !agentLoop.isProcessing
        let shape = ComicBubbleShape(
            tailAnchorX: 0.28,
            cornerRadius: 20,
            tailWidth: 12,
            tailHeight: 10,
            tailDirection: .up
        )

        return HStack(alignment: .center, spacing: 8) {
            TextField("Ask Bob\u{2026}", text: $session.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.85 * textOpacity))
                .tint(.black.opacity(0.6))
                .focused($inputFocused)
                .onSubmit { sendWithSound() }

            uncensoredTogglePill(compact: true, darkText: true)

            Button(action: { sendWithSound() }) {
                Image(systemName: canSend ? "arrow.up.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black.opacity(0.55 * textOpacity))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityHint(canSend
                ? "Sends the current chat input."
                : "Enter a message to enable sending.")
        }
        .padding(.horizontal, 14)
        .padding(.top, 9 + 10)   // extra top room so the tail doesn't overlap the field
        .padding(.bottom, 9)
        .background(shape.fill(avatarSurfaceFill))
        .overlay(shape.stroke(avatarSurfaceStroke, lineWidth: reduceTransparency ? 0.9 : 0.6))
        .compositingGroup()
        .shadow(color: .black.opacity(0.15 * surfaceOpacity), radius: 8, x: 0, y: 3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
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

    // MARK: - History Overlay (Plan 2)

    private var historyToggleButton: some View {
        Button(action: { toggleAvatarHistoryOverlay() }) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.black.opacity(0.45 * textOpacity))
                .padding(5)
                .background(
                    Circle()
                        .fill(avatarSpeechFill)
                        .overlay(Circle().stroke(avatarSpeechStroke, lineWidth: 0.8))
                )
        }
        .buttonStyle(.plain)
        .opacity(bubbleVisible || agentLoop.isProcessing ? 1 : 0)
        .animation(avatarVisibilityAnimation, value: bubbleVisible)
        .help("Show conversation history")
        .accessibilityLabel("Show conversation history")
        .accessibilityHint("Opens the transcript overlay for Avatar Mode.")
    }

    private var historyOverlay: some View {
        ZStack(alignment: .center) {
            // Tap outside to dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showHistoryOverlay = false }

            // Panel
            VStack(spacing: 0) {
                HStack {
                    Text("History")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                    Spacer()
                    Button(action: { showHistoryOverlay = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.black.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Divider()
                    .background(Self.speechBubbleStroke)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(interleavedItemsCache) { item in
                            switch item.content {
                            case .message(let msg):
                                if Self.shouldShowInTranscript(msg) {
                                    ChatBubble(
                                        message: msg,
                                        chatWindowOpacity: settings.chatWindowOpacity,
                                        richPresentationEnabled: settings.richPresentationEnabled,
                                        richPresentationArtifactChipsEnabled: settings.richPresentationArtifactChipsEnabled
                                    )
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
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: 340, maxHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(reduceTransparency ? Color.white.opacity(0.98) : avatarSpeechFill.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(avatarSpeechStroke, lineWidth: reduceTransparency ? 1.1 : 0.9)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 5)
            .padding(.horizontal, 16)

            // Esc to dismiss
            Button("") { showHistoryOverlay = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func uncensoredTogglePill(compact: Bool = false, darkText: Bool = false) -> some View {
        if settings.uncensoredModeAvailable {
            let active = uncensoredModeEnabled
            let foreground = darkText
                ? Color.black.opacity(active ? 0.82 : 0.62)
                : (active ? Color.black.opacity(0.82) : Self.phosphorGreen.opacity(textOpacity))
            let stroke = darkText
                ? Color.black.opacity(active ? 0.12 : 0.20)
                : Self.phosphorGreen.opacity(active ? 0.15 : 0.30)

            Button {
                session.toggleConversationUncensoredMode()
            } label: {
                HStack(spacing: compact ? 4 : 5) {
                    Image(systemName: active ? "flame.fill" : "flame")
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    Text("UNCENSORED")
                        .font(.system(size: compact ? 9 : 10, design: .monospaced).weight(.bold))
                }
                .foregroundColor(foreground)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, compact ? 5 : 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            active
                                ? Color(red: 1.0, green: 0.60, blue: 0.22)
                                : (darkText
                                    ? Color.white.opacity(0.16)
                                    : Self.bgPanel.opacity(surfaceOpacity))
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(stroke, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .disabled(uncensoredModeToggleDisabled)
            .opacity(uncensoredModeToggleDisabled ? 0.5 : 1.0)
            .help(uncensoredModeHelpText)
        }
    }

    // MARK: - Speech Bubble

    /// Minimum bubble height when there's no text to show (idle/thinking
    /// slot). When text is present, the bubble caps at the caller's
    /// `maxHeight` and scrolls internally — never grows past the cap. This
    /// keeps Bob's portrait fully visible in avatar-only mode and keeps the
    /// portrait-slot bubble from pushing Bob down in full mode.
    private static let minBubbleHeight: CGFloat = 56
    private static let portraitBubbleMaxHeight: CGFloat = 104

    /// Renders Bob's response inside a translucent speech bubble. The
    /// `maxHeight` cap is supplied by the parent layout (computed from
    /// available window height for avatar-only mode, or a fixed slot
    /// height for portrait mode). Text always scrolls inside so the
    /// bubble's frame is stable as new tokens stream in.
    @ViewBuilder
    private func speechBubbleView(maxHeight: CGFloat) -> some View {
        let preview = latestAssistantPreview
        let greetingText = latestGreetingLine ?? ""
        let isAvatarOnly = settings.avatarOnlyMode
        let textFont = Font.system(
            size: isAvatarOnly ? 15 : 13,
            weight: isAvatarOnly ? .semibold : .medium,
            design: .rounded
        )
        let isThinking = agentLoop.isProcessing || awaitingTurnTranscript

        if isAvatarOnly {
            avatarOnlySpeechBubbleView(
                preview: preview,
                greetingText: greetingText,
                textFont: textFont,
                maxHeight: maxHeight,
                isThinking: isThinking
            )
        } else {
            fullModeSpeechBubbleView(
                preview: preview,
                greetingText: greetingText,
                textFont: textFont,
                maxHeight: maxHeight,
                isThinking: isThinking
            )
        }
    }

    private func avatarOnlySpeechBubbleView(
        preview: ChatBubbleRendering.AvatarPreview?,
        greetingText: String,
        textFont: Font,
        maxHeight: CGFloat,
        isThinking: Bool
    ) -> some View {
        let metrics = AvatarBubblePresentation.metrics(
            lines: avatarSpeechLines(preview: preview, greetingText: greetingText),
            maxHeight: maxHeight,
            isThinking: isThinking
        )
        let shape = ComicBubbleShape(
            tailDX: metrics.tailDX,
            tailAnchorX: metrics.tailAnchorX,
            cornerRadius: 18,
            tailWidth: 18,
            tailHeight: 16,
            tailDirection: .down
        )

        return Group {
            if metrics.useScroll {
                ScrollView(.vertical, showsIndicators: true) {
                    speechBubbleContent(
                        preview: preview,
                        greetingText: greetingText,
                        textFont: textFont,
                        isAvatarOnly: true,
                        expandToFillWidth: true,
                        isThinking: isThinking
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: metrics.width, maxHeight: maxHeight, alignment: .topLeading)
            } else {
                speechBubbleContent(
                    preview: preview,
                    greetingText: greetingText,
                    textFont: textFont,
                    isAvatarOnly: true,
                    expandToFillWidth: false,
                    isThinking: isThinking
                )
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(maxWidth: metrics.width, alignment: .leading)
            }
        }
        .background(shape.fill(avatarSpeechFill))
        .overlay(shape.stroke(avatarSpeechStroke, lineWidth: reduceTransparency ? 1.4 : 1.2))
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: avatarBubbleShadow, radius: reduceTransparency ? 8 : 12, x: 0, y: reduceTransparency ? 3 : 5)
        .offset(x: metrics.horizontalOffset)
        .frame(minHeight: metrics.minHeight, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isThinking ? "Bob is thinking" : "Bob says")
        .accessibilityValue(avatarSpeechAccessibilityValue(preview: preview, greetingText: greetingText, isThinking: isThinking))
    }

    private func fullModeSpeechBubbleView(
        preview: ChatBubbleRendering.AvatarPreview?,
        greetingText: String,
        textFont: Font,
        maxHeight: CGFloat,
        isThinking: Bool
    ) -> some View {
        let shape = ComicBubbleShape(tailAnchorX: Self.avatarBubbleTailAnchorX, tailDirection: .down)

        return ScrollView(.vertical, showsIndicators: false) {
            speechBubbleContent(
                preview: preview,
                greetingText: greetingText,
                textFont: textFont,
                isAvatarOnly: false,
                expandToFillWidth: true,
                isThinking: isThinking
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .background(shape.fill(Self.speechBubbleFill))
        .overlay(shape.stroke(Self.speechBubbleStroke, lineWidth: 0.9))
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 5)
        .frame(maxWidth: 332)
        .frame(minHeight: Self.minBubbleHeight,
               maxHeight: (bubbleVisible || agentLoop.isProcessing) ? maxHeight : Self.minBubbleHeight)
        .animation(avatarVisibilityAnimation, value: bubbleVisible)
        .animation(avatarProcessingAnimation, value: agentLoop.isProcessing)
    }

    @ViewBuilder
    private func speechBubbleContent(
        preview: ChatBubbleRendering.AvatarPreview?,
        greetingText: String,
        textFont: Font,
        isAvatarOnly: Bool,
        expandToFillWidth: Bool,
        isThinking: Bool
    ) -> some View {
        if isThinking {
            ThinkingDots(reduceMotion: reduceMotion)
                .frame(maxWidth: expandToFillWidth ? .infinity : nil, alignment: .leading)
        } else if let preview, preview.blocks.isEmpty == false {
            avatarBubblePreviewContent(
                preview.blocks,
                textFont: textFont,
                isAvatarOnly: isAvatarOnly,
                expandToFillWidth: expandToFillWidth
            )
        } else {
            Text(greetingText)
                .font(textFont)
                .foregroundColor(.black.opacity(0.9 * textOpacity))
                .multilineTextAlignment(.leading)
                .lineSpacing(isAvatarOnly ? 2 : 1)
                .frame(maxWidth: expandToFillWidth ? .infinity : nil, alignment: .leading)
                .shadow(color: .white.opacity(0.12), radius: 0.4, x: 0, y: 0.4)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func avatarBubblePreviewContent(
        _ blocks: [ChatBubbleRendering.Block],
        textFont: Font,
        isAvatarOnly: Bool,
        expandToFillWidth: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: isAvatarOnly ? 10 : 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let attributed):
                    Text(attributed)
                        .font(textFont)
                        .foregroundColor(.black.opacity(0.9 * textOpacity))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(isAvatarOnly ? 2 : 1)
                        .lineLimit(isAvatarOnly ? 5 : 4)
                        .frame(maxWidth: expandToFillWidth ? .infinity : nil, alignment: .leading)
                        .tint(.accentColor)
                        .textSelection(.enabled)
                case .code(let language, let content):
                    VStack(alignment: .leading, spacing: 4) {
                        if let language, language.isEmpty == false {
                            Text(language)
                                .font(.system(size: isAvatarOnly ? 11 : 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black.opacity(0.65 * textOpacity))
                        }

                        Text(content)
                            .font(.system(size: isAvatarOnly ? 13 : 11, design: .monospaced))
                            .foregroundColor(.black.opacity(0.9 * textOpacity))
                            .lineSpacing(1)
                            .lineLimit(isAvatarOnly ? 5 : 4)
                            .frame(maxWidth: expandToFillWidth ? .infinity : nil, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .frame(maxWidth: expandToFillWidth ? .infinity : nil, alignment: .leading)
    }

    private func avatarSpeechLines(
        preview: ChatBubbleRendering.AvatarPreview?,
        greetingText: String
    ) -> [String] {
        if let preview, preview.blocks.isEmpty == false {
            return preview.blocks.compactMap { block in
                switch block {
                case .markdown(let attributed):
                    let text = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : text
                case .code(_, let content):
                    let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : text
                }
            }
        }

        return greetingText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func avatarSpeechAccessibilityValue(
        preview: ChatBubbleRendering.AvatarPreview?,
        greetingText: String,
        isThinking: Bool
    ) -> String {
        guard isThinking == false else { return "Generating a reply." }

        let speech = avatarSpeechLines(preview: preview, greetingText: greetingText).joined(separator: " ")
        return speech.isEmpty ? "No reply yet." : speech
    }

    private func toggleAvatarHistoryOverlay() {
        guard settings.avatarOnlyMode else {
            showHistoryOverlay = false
            return
        }
        showHistoryOverlay.toggle()
    }

    private func accessibleMoodDescription(_ mood: BobMood) -> String {
        switch mood {
        case .idle:
            return "idle"
        case .thinking:
            return "thinking"
        case .typing:
            return "typing"
        case .happy:
            return "happy"
        case .sheepish:
            return "sheepish"
        case .confused:
            return "confused"
        }
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
            if uncensoredModeEnabled {
                Text("  ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
                uncensoredConversationBadge
            }
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
                AppWindowRouter.shared.open(id: AppWindowRouter.preferencesID)
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
            GeometryReader { scrollProxy in
                let scrollViewHeight = scrollProxy.size.height
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(interleavedItemsCache) { item in
                                switch item.content {
                                case .message(let msg):
                                    if Self.shouldShowInTranscript(msg) {
                                        ChatBubble(
                                            message: msg,
                                            chatWindowOpacity: settings.chatWindowOpacity,
                                            richPresentationEnabled: settings.richPresentationEnabled,
                                            richPresentationArtifactChipsEnabled: settings.richPresentationArtifactChipsEnabled
                                        )
                                            .id(msg.id)
                                    }
                                case .notice(let notice):
                                    systemNoticeRow(notice)
                                        .id(notice.id.uuidString)
                                }
                            }
                        }
                        .padding(.vertical, 8)

                        GeometryReader { contentProxy in
                            Color.clear
                                .preference(
                                    key: ScrollContentBottomKey.self,
                                    value: contentProxy.frame(in: .named("transcriptScroll")).maxY
                                )
                        }
                        .frame(height: 0)
                    }
                    .coordinateSpace(name: "transcriptScroll")
                    .onPreferenceChange(ScrollContentBottomKey.self) { contentBottom in
                        let newIsNearBottom = contentBottom <= scrollViewHeight + 50
                        if !newIsNearBottom && isNearBottom {
                            autoScrollEnabled = false
                        }
                        isNearBottom = newIsNearBottom
                    }
                    .onChange(of: session.transcriptRevision) {
                        guard autoScrollEnabled && isNearBottom else { return }
                        withAnimation {
                            if let lastID = interleavedItemsCache.last?.id {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }

                    if autoScrollEnabled == false {
                        Button {
                            autoScrollEnabled = true
                            withAnimation {
                                if let lastID = interleavedItemsCache.last?.id {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        } label: {
                            Label("Jump to latest", systemImage: "arrow.down.circle.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Self.bgPanel.opacity(surfaceOpacity * 0.95))
                                .clipShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                        .padding(.bottom, 12)
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

    private func rebuildInterleavedItems() {
        var items: [InterleavedItem] = []
        items.reserveCapacity(session.messages.count + systemNotices.count)
        for msg in session.messages {
            items.append(InterleavedItem(id: msg.id, timestamp: msg.timestamp, content: .message(msg)))
        }
        for notice in systemNotices {
            items.append(InterleavedItem(id: notice.id.uuidString, timestamp: notice.at, content: .notice(notice)))
        }
        interleavedItemsCache = items.sorted { $0.timestamp < $1.timestamp }
    }

    @ViewBuilder
    private func systemNoticeRow(_ notice: SystemNotice) -> some View {
        if notice.isGreeting {
            // Greeting renders as a speech-bubble-style assistant message row
            HStack {
                Spacer(minLength: 0)
                Text(notice.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85 * textOpacity))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Self.bgPanel.opacity(surfaceOpacity))
                    )
                Spacer(minLength: 0)
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

            uncensoredTogglePill()

            Button(action: { sendWithSound() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(Self.phosphorGreen.opacity(textOpacity))
            }
            .buttonStyle(.plain)
            .disabled(session.inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing)
            .accessibilityLabel("Send message")
            .accessibilityHint(
                session.inputText.trimmingCharacters(in: .whitespaces).isEmpty || agentLoop.isProcessing
                    ? "Enter a message to enable sending."
                    : "Sends the current chat input."
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // F5 — Cmd+K focuses the input field
        .background(
            Button("") { inputFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
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

    private func enforceMasterUncensoredSetting() {
        guard settings.uncensoredModeAvailable == false, session.conversationUncensoredMode else { return }
        session.setConversationUncensoredMode(false)
    }

    private func resetConversationScopedNoticeState() {
        systemNotices.removeAll()
        hasGreeted = false
        awaitingTurnTranscript = false
        lastSeenToolActivityIndex = agentLoop.toolActivity.count
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
        withAnimation(avatarVisibilityAnimation) {
            bubbleVisible = true
        }
    }

    private func updateBubbleForGreeting() {
        withAnimation(avatarVisibilityAnimation) {
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
    static let bobToggleHistoryOverlay = Notification.Name("com.ollamabob.toggleHistoryOverlay")
}
