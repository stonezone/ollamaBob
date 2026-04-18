import SwiftUI
import AppKit

@main
struct OllamaBobApp: App {
    @StateObject private var appState = AppState()
    @ObservedObject private var settings = AppSettings.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("OllamaBob", systemImage: "bubble.left.fill") {
            Button("Open Chat") {
                openWindow(id: "chat")
            }
            .keyboardShortcut("o")

            Button(settings.avatarOnlyMode ? "Show Full Chat" : "Avatar-only Mode") {
                settings.avatarOnlyMode.toggle()
            }

            Button("Tool Activity") {
                openWindow(id: "tool-activity")
            }

            Button("Preferences…") {
                openWindow(id: "preferences")
            }
            .keyboardShortcut(",")

            Button("Welcome / Tour…") {
                openWindow(id: "onboarding")
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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // F5 — keyboard shortcuts for chat actions and persona switching
            CommandMenu("Chat") {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .bobNewChat, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Clear Chat") {
                    NotificationCenter.default.post(name: .bobNewChat, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button(settings.avatarOnlyMode ? "Show Full Chat" : "Avatar-only Mode") {
                    settings.avatarOnlyMode.toggle()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Divider()

                Button("Switch to Mumbai Bob") {
                    PersonaStore.shared.activePersonaID = BuiltinPersonas.mumbaiBobID
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Switch to Terse Engineer") {
                    PersonaStore.shared.activePersonaID = BuiltinPersonas.terseEngineerID
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Switch to Grumpy Linus") {
                    PersonaStore.shared.activePersonaID = BuiltinPersonas.grumpyLinusID
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Switch to Helpful Assistant") {
                    PersonaStore.shared.activePersonaID = BuiltinPersonas.helpfulAssistID
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Switch to Blank") {
                    PersonaStore.shared.activePersonaID = BuiltinPersonas.blankID
                }
                .keyboardShortcut("5", modifiers: .command)
            }
        }

        Window("Tool Activity", id: "tool-activity") {
            ToolActivityView(agentLoop: appState.agentLoop)
        }
        .defaultSize(width: 450, height: 400)

        Window("Preferences", id: "preferences") {
            PreferencesView()
        }
        .defaultSize(width: 520, height: 640)
        .windowResizability(.contentMinSize)

        Window("Welcome to OllamaBob", id: "onboarding") {
            OnboardingView()
        }
        .defaultSize(width: 520, height: 520)
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var agentLoop = AgentLoop()
    @Published var preflightStatus: PreflightStatus?
    @Published var preflightPassed = false

    init() {
        initDatabase()
        setupApprovalHandler()
        runPreflight()
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
