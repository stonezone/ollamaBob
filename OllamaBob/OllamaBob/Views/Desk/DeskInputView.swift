import SwiftUI
import AppKit

// MARK: - Window Transparency

struct WindowTransparencyConfigurator: NSViewRepresentable {
    let avatarOnly: Bool

    private static let fullMinSize = NSSize(width: 420, height: 520)
    private static let avatarMinSize = NSSize(width: 280, height: 340)

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
            context.coordinator.avatarOnly = avatarOnly
            Self.applyChromelessConfiguration(to: window, avatarOnly: avatarOnly)
            context.coordinator.handleModeSwitch(window: window, from: previousMode)
        }
        Self.stripBackdrop(under: window)
    }

    private static func applyChromelessConfiguration(to window: NSWindow, avatarOnly: Bool) {
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
        window.isMovableByWindowBackground = true
        window.minSize = avatarOnly ? Self.avatarMinSize : Self.fullMinSize
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = nil
            contentView.layer?.isOpaque = false
        }
    }

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
                layer.backgroundColor = nil
                layer.isOpaque = false
            }
        }
    }

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

struct WindowDragHandle: NSViewRepresentable {
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

enum BubbleTailDirection {
    case down, up
}

struct ComicBubbleShape: Shape {
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
        let baseCenter = rect.minX + rect.width * clampedAnchor
        let tailLeft = baseCenter - tailWidth / 2
        let tailRight = baseCenter + tailWidth / 2
        let tipX = baseCenter + tailDX

        path.move(to: CGPoint(x: tailLeft, y: tailBaseY))
        path.addLine(to: CGPoint(x: tipX, y: tipY))
        path.addLine(to: CGPoint(x: tailRight, y: tailBaseY))
        path.closeSubpath()

        return path
    }
}

struct DeskInputView: View {
    enum Style {
        case full
        case compact
    }

    let style: Style
    @Binding var inputText: String
    @FocusState.Binding var inputFocused: Bool
    let isProcessing: Bool
    let uncensoredModeAvailable: Bool
    let uncensoredModeEnabled: Bool
    let uncensoredModeToggleDisabled: Bool
    let uncensoredModeHelpText: String
    let surfaceOpacity: Double
    let textOpacity: Double
    let phosphorGreen: Color
    let bgPanel: Color
    let bubbleFill: Color
    let bubbleStroke: Color
    let onToggleUncensoredMode: () -> Void
    let onSend: () -> Void

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespaces)
    }

    private var canSend: Bool {
        !trimmedInput.isEmpty && !isProcessing
    }

    var body: some View {
        switch style {
        case .full:
            fullInput
        case .compact:
            compactInput
        }
    }

    private var fullInput: some View {
        HStack(spacing: 8) {
            TextField("Ask Bob\u{2026}", text: $inputText)
                .textFieldStyle(.plain)
                .foregroundColor(.white.opacity(textOpacity))
                .font(.system(size: 13))
                .onSubmit { onSend() }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .focused($inputFocused)

            uncensoredTogglePill()

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(phosphorGreen.opacity(textOpacity))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityHint(canSend
                ? "Sends the current chat input."
                : "Enter a message to enable sending.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Button("") { inputFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    private var compactInput: some View {
        let shape = ComicBubbleShape(
            tailAnchorX: 0.28,
            cornerRadius: 20,
            tailWidth: 12,
            tailHeight: 10,
            tailDirection: .up
        )

        return HStack(alignment: .center, spacing: 8) {
            TextField("Ask Bob\u{2026}", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .font(.system(size: 12))
                .foregroundColor(.black.opacity(0.85 * textOpacity))
                .tint(.black.opacity(0.6))
                .focused($inputFocused)
                .onSubmit { onSend() }

            uncensoredTogglePill(compact: true, darkText: true)

            Button(action: onSend) {
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
        .padding(.top, 19)
        .padding(.bottom, 9)
        .background(shape.fill(bubbleFill.opacity(surfaceOpacity)))
        .overlay(shape.stroke(bubbleStroke.opacity(surfaceOpacity), lineWidth: 0.6))
        .compositingGroup()
        .shadow(color: .black.opacity(0.15 * surfaceOpacity), radius: 8, x: 0, y: 3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
    }

    @ViewBuilder
    private func uncensoredTogglePill(compact: Bool = false, darkText: Bool = false) -> some View {
        if uncensoredModeAvailable {
            let active = uncensoredModeEnabled
            let foreground = darkText
                ? Color.black.opacity(active ? 0.82 : 0.62)
                : (active ? Color.black.opacity(0.82) : phosphorGreen.opacity(textOpacity))
            let stroke = darkText
                ? Color.black.opacity(active ? 0.12 : 0.20)
                : phosphorGreen.opacity(active ? 0.15 : 0.30)

            Button(action: onToggleUncensoredMode) {
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
                        .fill(active
                            ? Color(red: 1.0, green: 0.60, blue: 0.22)
                            : (darkText ? Color.white.opacity(0.16) : bgPanel.opacity(surfaceOpacity)))
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
}
