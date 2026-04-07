import SwiftUI
import AppKit

/// Manages the floating Bob avatar window. The avatar shows Bob's current mood
/// sprite (cross-faded on changes) and floats above other windows. Whether it
/// joins all Spaces is controlled by a setting.
@MainActor
final class AvatarWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AvatarView>?

    func show(agentLoop: AgentLoop, persistAcrossSpaces: Bool, toggleChat: @escaping () -> Void) {
        guard panel == nil else {
            applyCollectionBehavior(persistAcrossSpaces: persistAcrossSpaces)
            panel?.orderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true

        let view = AvatarView(agentLoop: agentLoop, onTap: toggleChat)
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        self.hostingView = hosting

        // Top-right of main screen
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 110
            let y = screen.visibleFrame.maxY - 140
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
        applyCollectionBehavior(persistAcrossSpaces: persistAcrossSpaces)
        panel.orderFront(nil)
    }

    func hide() {
        panel?.close()
        panel = nil
        hostingView = nil
    }

    func setPersistAcrossSpaces(_ persist: Bool) {
        applyCollectionBehavior(persistAcrossSpaces: persist)
    }

    private func applyCollectionBehavior(persistAcrossSpaces: Bool) {
        guard let panel else { return }
        if persistAcrossSpaces {
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        } else {
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
}

/// Floating Bob view. Loads the mood-specific sprite and cross-fades on change.
struct AvatarView: View {
    @ObservedObject var agentLoop: AgentLoop
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        let mood = agentLoop.bobMood
        let imageName = "bob_\(mood.rawValue)"

        ZStack {
            if let nsImage = NSImage(named: imageName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let url = Bundle.module.url(forResource: imageName, withExtension: "png"),
                      let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback if sprite missing
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Image(systemName: "bubble.left.fill")
                            .foregroundColor(.accentColor)
                    )
            }
        }
        .id(mood)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: mood)
        .frame(width: 96, height: 120)
        .scaleEffect(isHovering ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onTap)
        .help("Click to open Bob's Desk")
    }
}
