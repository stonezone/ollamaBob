import SwiftUI
import AppKit

/// Liquid-Glass menu bar popover. Replaces the legacy menu-style dropdown with
/// a tile that surfaces the same actions in a clearer hierarchy: header (Bob
/// mark + persona + version), modes (toggleable services), windows (open
/// scenes), and a footer (status dot + model + quit).
///
/// Reads `AppState.agentLoop` and `AppSettings.shared` to mirror live state.
/// Action callbacks dispatch through the same `AppState` update methods the
/// legacy menu used so the underlying behavior stays untouched.
struct BobMenuBarPopover: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject private var personaRegistry = BobPersonaRegistry.shared

    @Environment(\.openWindow) private var openWindow
    @State private var quickInput: String = ""
    @FocusState private var quickInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            quickInputRow
            Divider().opacity(0.4)
            modesSection
            Divider().opacity(0.4)
            windowsSection
            Divider().opacity(0.4)
            footer
        }
        .padding(BobSpacing.md)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BobRadii.lg, style: .continuous))
        .onAppear { quickInputFocused = true }
    }

    // MARK: - Quick Input

    private var quickInputRow: some View {
        HStack(spacing: BobSpacing.sm) {
            Image(systemName: "text.bubble")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Ask Bob…", text: $quickInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($quickInputFocused)
                .onSubmit { sendQuickPrompt() }

            Button {
                sendQuickPrompt()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(quickInput.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? Color.secondary
                                     : BobColors.Accent.bobBlue)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(quickInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, BobSpacing.xs + 2)
        .padding(.vertical, 6)
        .background(BobColors.Glass.fill, in: RoundedRectangle(cornerRadius: BobRadii.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BobRadii.md, style: .continuous)
                .stroke(BobColors.Glass.strokeOutline, lineWidth: 0.5)
        )
        .padding(.bottom, BobSpacing.sm)
    }

    private func sendQuickPrompt() {
        let trimmed = quickInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DeskPromptInbox.shared.enqueue(trimmed)
        quickInput = ""
        openWindow(id: "chat")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: BobSpacing.sm) {
            BobMenuBarMark(status: markStatus)
                .frame(width: 22, height: 22)
                .padding(4)
                .background(BobColors.Glass.fill, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(personaRegistry.active.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text("OllamaBob \(AppConfig.appVersion)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                openWindow(id: "chat")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .help("Open Bob's Desk")
        }
        .padding(.bottom, BobSpacing.sm)
    }

    // MARK: - Modes

    private var modesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Modes")

            modeToggle(
                title: "Walkie-Talkie",
                systemImage: "mic.circle",
                isOn: settings.pushToTalkEnabled,
                toggle: { settings.pushToTalkEnabled.toggle(); appState.updateWalkieTalkie() }
            )
            modeToggle(
                title: "Focus Guardian",
                systemImage: "lock.shield",
                isOn: settings.focusGuardianEnabled,
                toggle: { settings.focusGuardianEnabled.toggle(); appState.updateFocusGuardian() }
            )
            modeToggle(
                title: "Clipboard Cortex",
                systemImage: "doc.on.clipboard",
                isOn: settings.clipboardCortexEnabled,
                toggle: { settings.clipboardCortexEnabled.toggle(); appState.updateClipboardCortex() }
            )
            modeToggle(
                title: "Daily Briefing",
                systemImage: "alarm",
                isOn: settings.briefingScheduleEnabled,
                toggle: { settings.briefingScheduleEnabled.toggle(); appState.updateBriefingScheduler() }
            )
            modeToggle(
                title: "Avatar-only Mode",
                systemImage: "rectangle.compress.vertical",
                isOn: settings.avatarOnlyMode,
                toggle: { settings.avatarOnlyMode.toggle() }
            )
        }
        .padding(.vertical, BobSpacing.xs)
    }

    private func modeToggle(title: String, systemImage: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: BobSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isOn ? BobColors.Accent.bobBlue : Color.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)

                Spacer()

                Circle()
                    .fill(isOn ? BobColors.Signal.success : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, BobSpacing.xs + 2)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Windows

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Open")
            windowRow(title: "Floating HUD", systemImage: "rectangle.on.rectangle") { openWindow(id: "hud") }
            windowRow(title: "Tool Activity", systemImage: "wrench.and.screwdriver") { openWindow(id: "tool-activity") }
            windowRow(title: "Live Call", systemImage: "phone.bubble") { openWindow(id: "live-call") }
            windowRow(title: "Briefing History", systemImage: "calendar") { openWindow(id: "briefing-history") }
            windowRow(title: "Preferences", systemImage: "gearshape") { openWindow(id: "preferences") }
            windowRow(title: "Welcome / Tour", systemImage: "questionmark.circle") { openWindow(id: "onboarding") }
        }
        .padding(.vertical, BobSpacing.xs)
    }

    private func windowRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: BobSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, BobSpacing.xs + 2)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: BobSpacing.sm) {
            Circle()
                .fill(footerStatusColor)
                .frame(width: 8, height: 8)

            Text(appState.agentLoop.currentModel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
        .padding(.top, BobSpacing.sm)
    }

    private var footerStatusColor: Color {
        switch markStatus {
        case .idle:         return BobColors.Signal.success
        case .processing:   return BobColors.Signal.processing
        case .error:        return BobColors.Signal.danger
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, BobSpacing.xs + 2)
            .padding(.bottom, 4)
    }

    private var markStatus: BobMenuBarMark.Status {
        BobMenuBarMark.Status.resolve(
            isProcessing: appState.agentLoop.isProcessing,
            hasError: false
        )
    }
}
