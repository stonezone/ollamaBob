import SwiftUI
import AppKit

enum ChatWindowConstraint {
    static func constrainedFrame(_ frame: NSRect, avatarOnly: Bool, screen: NSScreen?) -> NSRect {
        let visibleFrames = screen.map { [$0.visibleFrame] } ?? NSScreen.screens.map(\.visibleFrame)
        return constrainedFrame(frame, avatarOnly: avatarOnly, visibleFrames: visibleFrames)
    }

    static func constrainedFrame(_ frame: NSRect, avatarOnly: Bool, visibleFrames: [NSRect]) -> NSRect {
        guard avatarOnly else { return frame }

        let cleanedFrames = visibleFrames.filter { $0.width > 0 && $0.height > 0 }
        guard let target = preferredVisibleFrame(for: frame, visibleFrames: cleanedFrames) else {
            return frame
        }

        let maxY = target.maxY - min(frame.height, max(ChatWindowMetrics.avatarMinimumVisibleHeight, 1))
        guard frame.minY > maxY else { return frame }

        var adjusted = frame
        adjusted.origin.y = maxY
        return adjusted
    }

    private static func preferredVisibleFrame(for frame: NSRect, visibleFrames: [NSRect]) -> NSRect? {
        let bestIntersection = visibleFrames.max { lhs, rhs in
            intersectionArea(lhs, with: frame) < intersectionArea(rhs, with: frame)
        }

        if let bestIntersection, intersectionArea(bestIntersection, with: frame) > 0 {
            return bestIntersection
        }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return visibleFrames.min { lhs, rhs in
            distanceSquared(from: center, to: lhs) < distanceSquared(from: center, to: rhs)
        }
    }

    private static func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }

    private static func intersectionArea(_ lhs: NSRect, with rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.width * intersection.height
    }
}

@MainActor
final class ChatWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if AppSettings.shared.avatarOnlyMode {
            return ChatWindowConstraint.constrainedFrame(frameRect, avatarOnly: true, screen: screen)
        }
        return super.constrainFrameRect(frameRect, to: screen)
    }
}

@MainActor
final class ChatWindowController: NSWindowController {
    static let shared = ChatWindowController()

    private let hostingController: NSHostingController<ChatRootView>

    private init() {
        hostingController = NSHostingController(rootView: ChatRootView(appState: AppState.shared))

        let window = ChatWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "Bob's Desk"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("BobDeskChatWindow")
        WindowTransparencyConfigurator.applyChromelessConfiguration(
            to: window,
            avatarOnly: AppSettings.shared.avatarOnlyMode
        )

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showChatWindow() {
        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ChatRootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.preflightPassed {
                BobsDeskView(agentLoop: appState.agentLoop)
            } else if let status = appState.preflightStatus {
                PreflightErrorView(status: status, onRetry: { appState.runPreflight() })
            } else {
                ProgressView("Starting up...")
                    .frame(width: 300, height: 200)
            }
        }
    }
}

final class OllamaBobAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            ChatWindowController.shared.showChatWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            ChatWindowController.shared.showChatWindow()
        }
        return true
    }
}
