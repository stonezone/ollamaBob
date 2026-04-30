import SwiftUI
import AppKit

/// Liquid-Glass-friendly window chrome configurator for Bob's Desk.
///
/// Replaces the legacy `WindowTransparencyConfigurator`. Behavior is preserved:
/// chromeless titlebar, transparent background so vibrancy materials in the
/// content view show through, per-mode (full / avatar-only) frame persistence,
/// movable-by-background, and minimum-size enforcement. macOS strips its own
/// backdrop NSVisualEffectView so design-system surfaces fully control the look.
struct DeskWindowChrome: NSViewRepresentable {
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
        // Keep `.titled` in both modes. A borderless NSWindow returns
        // false from `canBecomeKey` by default, which means TextFields
        // inside the window can't receive keyboard focus — that's why
        // the avatar-only input was unusable when we previously toggled
        // `.titled` off. With `titlebarAppearsTransparent` + hidden
        // visibility + hidden traffic-light buttons, the window still
        // looks chrome-less while remaining a real key window.
        window.styleMask.insert(.titled)
        window.styleMask.insert(.fullSizeContentView)
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
