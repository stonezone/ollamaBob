import SwiftUI
import AppKit

@main
struct OllamaBobApp: App {
    @NSApplicationDelegateAdaptor(OllamaBobAppDelegate.self) private var appDelegate
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var settings = AppSettings.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        let _ = configureWindowRouting()

        MenuBarExtra("OllamaBob", systemImage: "bubble.left.fill") {
            Button("Open Chat") {
                ChatWindowController.shared.showChatWindow()
            }
            .keyboardShortcut("o")

            Button(settings.avatarOnlyMode ? "Show Full Chat" : "Avatar-only Mode") {
                settings.avatarOnlyMode.toggle()
            }

            Button("Tool Activity") {
                AppWindowRouter.shared.open(id: AppWindowRouter.toolActivityID)
            }

            Button("Preferences…") {
                AppWindowRouter.shared.open(id: AppWindowRouter.preferencesID)
            }
            .keyboardShortcut(",")

            Button("Welcome / Tour…") {
                AppWindowRouter.shared.open(id: AppWindowRouter.onboardingID)
            }

            Divider()

            HStack {
                Circle()
                    .fill(appState.agentLoop.isProcessing ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(appState.agentLoop.currentModel)
                    .font(.caption)
            }

            Text("Version \(AppConfig.appVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Button("Quit OllamaBob") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Window("Tool Activity", id: "tool-activity") {
            ToolActivityView(agentLoop: appState.agentLoop)
        }
        .defaultSize(width: 450, height: 400)
        .commands {
            CommandMenu("Chat") {
                Button("Open Chat") {
                    ChatWindowController.shared.showChatWindow()
                }
                .keyboardShortcut("o")

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

        Window("Bob's View", id: "rich-html") {
            RichHTMLView(state: PresentationService.shared.richHTMLState)
        }
        .defaultSize(width: 760, height: 560)

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

    @MainActor
    private func configureWindowRouting() {
        AppWindowRouter.shared.register { id in
            openWindow(id: id)
        }
        PresentationService.shared.registerOpenRichHTMLWindow {
            AppWindowRouter.shared.open(id: AppWindowRouter.richHTMLID)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var agentLoop = AgentLoop()
    @Published var preflightStatus: PreflightStatus?
    @Published var preflightPassed = false

    private init() {
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
