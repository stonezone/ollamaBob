import SwiftUI
import AppKit

@main
struct OllamaBobApp: App {
    @StateObject private var appState = AppState()

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("OllamaBob", systemImage: "bubble.left.fill") {
            Button("Open Chat") {
                openWindow(id: "chat")
            }
            .keyboardShortcut("o")

            Button("Toggle Avatar") {
                appState.toggleAvatar {
                    openWindow(id: "chat")
                }
            }

            Button("Tool Activity") {
                openWindow(id: "tool-activity")
            }

            Divider()

            HStack {
                Circle()
                    .fill(appState.agentLoop.isProcessing ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(appState.agentLoop.currentModel)
                    .font(.caption)
            }

            Divider()

            Button("Quit OllamaBob") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Window("Bob's Desk", id: "chat") {
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
        .defaultSize(width: 520, height: 760)

        Window("Tool Activity", id: "tool-activity") {
            ToolActivityView(agentLoop: appState.agentLoop)
        }
        .defaultSize(width: 450, height: 400)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var agentLoop = AgentLoop()
    @Published var preflightStatus: PreflightStatus?
    @Published var preflightPassed = false

    private let avatarController = AvatarWindowController()

    init() {
        initDatabase()
        setupApprovalHandler()
        runPreflight()
    }

    func toggleAvatar(openChat: @escaping () -> Void) {
        if avatarController.isVisible {
            avatarController.hide()
        } else {
            avatarController.show(toggleChat: openChat)
        }
    }

    private func initDatabase() {
        do {
            try DatabaseManager.shared.setup()
        } catch {
            print("Database setup failed: \(error)")
        }
    }

    func runPreflight() {
        Task {
            let status = await Preflight.run()
            preflightStatus = status
            preflightPassed = status.canLaunch
        }
    }

    private func setupApprovalHandler() {
        agentLoop.approvalHandler = { command, toolName, level in
            await MainActor.run {
                ApprovalAlert.show(command: command, toolName: toolName, level: level)
            }
        }

        agentLoop.modelSwitchHandler = { oldModel, newModel in
            print("Model switched from \(oldModel) to \(newModel)")
        }
    }
}
