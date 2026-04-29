import SwiftUI
import AppKit

@main
struct OllamaBobApp: App {
    @StateObject private var appState = AppState()
    @ObservedObject private var settings = AppSettings.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            BobMenuBarPopover(appState: appState, settings: settings)
        } label: {
            BobMenuBarMark(
                status: BobMenuBarMark.Status.resolve(
                    isProcessing: appState.agentLoop.isProcessing,
                    hasError: false
                )
            )
        }
        .menuBarExtraStyle(.window)

        Window("Bob's Desk", id: "chat") {
            ZStack {
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

                PresentationWindowBinder(appState: appState)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
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

        Window("Live Call", id: "live-call") {
            LiveCallView()
                .allowsHitTesting(true)
        }
        .defaultSize(width: 520, height: 520)

        Window("Briefing History", id: "briefing-history") {
            BriefingHistoryView()
        }
        .defaultSize(width: 520, height: 520)

        Window("Bob's View", id: "rich-html") {
            RichHTMLView(state: PresentationService.shared.richHTMLState)
        }
        .defaultSize(width: 760, height: 560)

        Window("Preferences", id: "preferences") {
            PreferencesView()
        }
        .defaultSize(width: 520, height: 640)
        .windowResizability(.contentMinSize)

        Window("Bob HUD", id: "hud") {
            BobHUDScene(agentLoop: appState.agentLoop)
        }
        .defaultSize(width: 240, height: 320)
        .windowStyle(.hiddenTitleBar)
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

    // Walkie-talkie push-to-talk hotkey listener (nil when disabled).
    private var pushToTalkHotkey: PushToTalkHotkey?

    // Global HUD summon hotkey listener (nil when disabled).
    private var hudSummonHotkey: MenuBarSummonHotkey?

    /// Closure registered by the SwiftUI scene that knows how to open the
    /// HUD window. `nil` until the scene mounts. Driven via the same pattern
    /// as `PresentationService.registerOpenRichHTMLWindow`.
    var openHUDWindow: (() -> Void)?

    init() {
        initDatabase()
        registerBuiltinPersonas()
        setupApprovalHandler()
        runSecretMigrationIfNeeded()
        runPreflight()
        setupWalkieTalkie()
        setupFocusGuardian()
        setupClipboardCortex()
        setupBriefingScheduler()
        setupHUDSummonHotkey()
    }

    /// Register the visual personas the app ships with. Future personas slot
    /// into this list; nothing else needs to change to add or remove one.
    private func registerBuiltinPersonas() {
        let registry = BobPersonaRegistry.shared
        registry.register(MumbaiBobPersona())
        registry.register(ClassicRobotPersona())
    }

    /// Start or stop the push-to-talk hotkey depending on current settings.
    func updateWalkieTalkie() {
        let settings = AppSettings.shared
        if settings.pushToTalkEnabled {
            let hotkey = PushToTalkHotkey(chordString: settings.pushToTalkKeyChord)
            hotkey.start()
            pushToTalkHotkey = hotkey
            // Ensure the transcript bridge is alive.
            _ = WalkieTalkieController.shared
        } else {
            pushToTalkHotkey?.stop()
            pushToTalkHotkey = nil
        }
    }

    private func setupWalkieTalkie() {
        if AppSettings.shared.pushToTalkEnabled {
            updateWalkieTalkie()
        }
    }

    /// Start or stop the global HUD summon hotkey based on current settings.
    func updateHUDSummonHotkey() {
        let settings = AppSettings.shared
        if settings.hudSummonHotkeyEnabled {
            let hotkey = MenuBarSummonHotkey(chordString: settings.hudSummonHotkeyChord)
            hotkey.onSummon = { [weak self] in
                guard let self else { return }
                self.openHUDWindow?()
                NSApp.activate(ignoringOtherApps: true)
            }
            hotkey.start()
            hudSummonHotkey = hotkey
        } else {
            hudSummonHotkey?.stop()
            hudSummonHotkey = nil
        }
    }

    private func setupHUDSummonHotkey() {
        // Preferences edits the toggle / chord directly on AppSettings;
        // observe a notification so we can restart the listener when those
        // changes land.
        NotificationCenter.default.addObserver(
            forName: .bobHUDSummonHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHUDSummonHotkey()
            }
        }

        if AppSettings.shared.hudSummonHotkeyEnabled {
            updateHUDSummonHotkey()
        }
    }

    /// Start or stop Focus Guardian depending on current settings.
    func updateFocusGuardian() {
        if AppSettings.shared.focusGuardianEnabled {
            FocusService.shared.start()
        } else {
            FocusService.shared.stop()
        }
    }

    private func setupFocusGuardian() {
        if AppSettings.shared.focusGuardianEnabled {
            FocusService.shared.start()
        }
    }

    /// Start or stop Clipboard Cortex watcher depending on current settings.
    func updateClipboardCortex() {
        if AppSettings.shared.clipboardCortexEnabled {
            ClipboardWatcher.shared.start()
        } else {
            ClipboardWatcher.shared.stop()
        }
    }

    private func setupClipboardCortex() {
        if AppSettings.shared.clipboardCortexEnabled {
            ClipboardWatcher.shared.start()
        }
    }

    /// Start or stop the Daily Briefing scheduler depending on current settings.
    func updateBriefingScheduler() {
        if AppSettings.shared.briefingScheduleEnabled {
            SchedulerService.shared.start()
        } else {
            SchedulerService.shared.stop()
        }
    }

    private func setupBriefingScheduler() {
        if AppSettings.shared.briefingScheduleEnabled {
            SchedulerService.shared.start()
        }
    }

    /// Phase 0c: one-time prompt to move legacy UserDefaults secrets into the
    /// Keychain. Runs at launch; declines are quiet (re-prompt next launch).
    private func runSecretMigrationIfNeeded() {
        // Defer to the next runloop turn so the SwiftUI scene has time to
        // mount before we surface a modal NSAlert.
        DispatchQueue.main.async {
            _ = SecretMigration.runIfNeeded()
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
        let standardModelName = AppSettings.shared.effectiveStandardModelName
        Task {
            let status = await Preflight.run(standardModelName: standardModelName)
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

private struct PresentationWindowBinder: View {
    @Environment(\.openWindow) private var openWindow
    let appState: AppState

    var body: some View {
        Color.clear
            .onAppear {
                PresentationService.shared.registerOpenRichHTMLWindow {
                    openWindow(id: "rich-html")
                }
                appState.openHUDWindow = {
                    openWindow(id: "hud")
                }
            }
    }
}
