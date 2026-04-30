import SwiftUI
import AppKit

/// Floating HUD scene: chrome-less glass tile with the active persona's glyph,
/// the latest assistant message snippet (or greeting), and a compact action
/// row. Designed for ambient "always available Bob" use — drag to move,
/// edges to resize, ⌘. dismisses, always-on-top by default.
struct BobHUDScene: View {
    @ObservedObject var agentLoop: AgentLoop
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var personaRegistry = BobPersonaRegistry.shared
    @ObservedObject private var hudState = HUDState.shared

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var hudInput: String = ""
    @FocusState private var hudInputFocused: Bool

    var body: some View {
        ZStack {
            GlassSurface(role: .hud, cornerRadius: BobRadii.xl, tint: personaRegistry.active.palette.accentColor.opacity(0.35)) {
                VStack(spacing: BobSpacing.sm) {
                    glyphPane
                    speechBubble
                    Spacer(minLength: 0)
                    inputRow
                    actionRow
                }
                .padding(BobSpacing.md)
            }
        }
        .frame(minWidth: 240, minHeight: 320)
        .background(HUDWindowChrome(alwaysOnTop: settings.hudAlwaysOnTop))
        .onExitCommand {
            // ⌘. or Esc dismisses the HUD without quitting the app.
            dismissWindow(id: "hud")
        }
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: BobSpacing.xs + 2) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11))
                .foregroundStyle(BobColors.Text.onGlassSecondary)

            TextField("Ask Bob…", text: $hudInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(BobColors.Text.onGlass)
                .focused($hudInputFocused)
                .onSubmit { submitFromHUD() }

            Button(action: submitFromHUD) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(hudInput.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? BobColors.Text.onGlassSecondary
                                     : personaRegistry.active.palette.accentColor)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(hudInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, BobSpacing.sm)
        .padding(.vertical, 6)
        .background(BobColors.Glass.fill, in: RoundedRectangle(cornerRadius: BobRadii.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BobRadii.md, style: .continuous)
                .stroke(BobColors.Glass.strokeOutline, lineWidth: 0.5)
        )
        .onAppear { hudInputFocused = true }
    }

    private func submitFromHUD() {
        let trimmed = hudInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DeskPromptInbox.shared.enqueue(trimmed)
        hudInput = ""
        openWindow(id: "chat")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Glyph Pane

    private var glyphPane: some View {
        let persona = personaRegistry.active
        let glyphState: GlassGlyph.State = {
            switch agentLoop.bobMood {
            case .thinking, .typing:    return .thinking
            case .happy:                return .speaking
            default:                    return agentLoop.isProcessing ? .thinking : .idle
            }
        }()

        return GlassGlyph(
            state: glyphState,
            tint: persona.palette.accentColor,
            size: 96
        )
        .padding(.top, BobSpacing.sm)
    }

    // MARK: - Speech Bubble

    private var speechBubble: some View {
        BobBubble(role: .glyph, tailAnchorX: 0.5, cornerRadius: BobRadii.lg) {
            Text(snippet)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(BobColors.Text.onGlass)
                .lineLimit(4)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .opacity(snippet.isEmpty ? 0 : 1)
    }

    private var snippet: String {
        if agentLoop.isProcessing { return "Working on it…" }
        if hudState.latestAssistantSnippet.isEmpty {
            return "Tap below to open the desk."
        }
        return hudState.latestAssistantSnippet
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: BobSpacing.sm) {
            Button {
                openWindow(id: "chat")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Desk", systemImage: "macwindow")
            }
            .buttonStyle(BobButtonStyle(kind: .primary))

            Button {
                settings.hudAlwaysOnTop.toggle()
            } label: {
                Image(systemName: settings.hudAlwaysOnTop ? "pin.fill" : "pin.slash")
            }
            .buttonStyle(BobButtonStyle(kind: .ghost))
            .help(settings.hudAlwaysOnTop ? "Pinned above other windows" : "Pin above other windows")

            Button {
                dismissWindow(id: "hud")
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(BobButtonStyle(kind: .ghost))
            .help("Dismiss HUD (⌘.)")
        }
    }
}
