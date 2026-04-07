import SwiftUI
import AppKit

/// Manages the floating avatar window
final class AvatarWindowController {
    private var panel: NSPanel?

    func show(toggleChat: @escaping () -> Void) {
        guard panel == nil else {
            panel?.orderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: AvatarView(onTap: toggleChat))
        panel.contentView = hostingView

        // Position at top-right
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 80
            let y = screen.visibleFrame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
    }

    var isVisible: Bool { panel?.isVisible ?? false }
}

struct AvatarView: View {
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 56, height: 56)

            Image(systemName: "bubble.left.fill")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
        }
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onTap)
        .frame(width: 64, height: 64)
    }
}
