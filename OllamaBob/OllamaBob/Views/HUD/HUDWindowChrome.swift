import SwiftUI
import AppKit

/// Window chrome configurator for the floating HUD scene. Strips title bar
/// and chrome, keeps the window borderless + transparent, restores the
/// last-known frame from `AppSettings.hudWindowFrame`, and toggles the
/// always-on-top window level based on `AppSettings.hudAlwaysOnTop`.
///
/// HUD persists across spaces (`.canJoinAllSpaces`) so summoning Bob doesn't
/// trap him on the workspace where he was last seen.
struct HUDWindowChrome: NSViewRepresentable {
    let alwaysOnTop: Bool

    private static let minSize = NSSize(width: 220, height: 280)
    private static let defaultSize = NSSize(width: 240, height: 320)

    func makeCoordinator() -> Coordinator {
        Coordinator(alwaysOnTop: alwaysOnTop)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let pinned = alwaysOnTop
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.applyChromelessConfiguration(to: window, alwaysOnTop: pinned)
            context.coordinator.attachIfNeeded(window: window)
            Self.stripBackdrop(under: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if context.coordinator.alwaysOnTop != alwaysOnTop {
            context.coordinator.alwaysOnTop = alwaysOnTop
            Self.applyChromelessConfiguration(to: window, alwaysOnTop: alwaysOnTop)
        }
        Self.stripBackdrop(under: window)
    }

    private static func applyChromelessConfiguration(to window: NSWindow, alwaysOnTop: Bool) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.remove(.titled)
        window.styleMask.insert(.resizable)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.minSize = Self.minSize
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.level = alwaysOnTop ? .floating : .normal
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
        var alwaysOnTop: Bool
        private weak var window: NSWindow?
        private var moveObs: NSObjectProtocol?
        private var resizeObs: NSObjectProtocol?

        init(alwaysOnTop: Bool) { self.alwaysOnTop = alwaysOnTop }

        func attachIfNeeded(window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            applySavedFrame(window: window)
            startObserving(window: window)
        }

        private func applySavedFrame(window: NSWindow) {
            let raw = AppSettings.shared.hudWindowFrame
            guard !raw.isEmpty else { return }
            let rect = NSRectFromString(raw)
            guard rect.width >= 180, rect.height >= 220 else { return }
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
                    AppSettings.shared.hudWindowFrame = NSStringFromRect(window.frame)
                }
            }
            resizeObs = center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    AppSettings.shared.hudWindowFrame = NSStringFromRect(window.frame)
                }
            }
        }

        deinit {
            if let o = moveObs { NotificationCenter.default.removeObserver(o) }
            if let o = resizeObs { NotificationCenter.default.removeObserver(o) }
        }
    }
}
