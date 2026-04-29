import SwiftUI

struct DeskStatusStrip: View {
    @ObservedObject private var macContextStore = MacContextStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var devModeStore = DevModeStore.shared
    @ObservedObject private var speechService = SpeechService.shared
    @ObservedObject private var focusService = FocusService.shared

    let accent: Color

    var body: some View {
        if shouldShow {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 8) {
                    ContextChipView()
                        .tint(accent)
                    DevModeIndicator()
                    WalkieTalkieIndicator()

                    if settings.focusGuardianEnabled || focusService.manualLockEnabled {
                        FocusGuardianIndicator()
                            .frame(width: 260)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var shouldShow: Bool {
        Self.shouldShow(
            macContextStore: macContextStore,
            devModeStore: devModeStore,
            speechService: speechService,
            settings: settings,
            focusService: focusService
        )
    }

    static func shouldShow(macContextStore: MacContextStore, devModeStore: DevModeStore, speechService: SpeechService, settings: AppSettings, focusService: FocusService) -> Bool {
        macContextStore.lastContext != nil
            || devModeStore.repoRoot != nil
            || speechService.state != .idle
            || settings.focusGuardianEnabled
            || focusService.manualLockEnabled
    }
}

struct DeskUncensoredConversationBadge: View {
    let helpText: String

    var body: some View {
        Text("UNCENSORED")
            .font(.system(size: 9, design: .monospaced).weight(.bold))
            .foregroundColor(.black.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 1.0, green: 0.60, blue: 0.22))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.15), lineWidth: 0.6)
            )
            .fixedSize()
            .help(helpText)
    }
}

struct DeskStatusLine: View {
    let currentModel: String
    let statusWord: String
    let totalMemoryLabel: String
    let factCount: Int
    let contextFraction: Double
    let contextColor: Color
    let textOpacity: Double
    let phosphorGreen: Color
    let uncensoredModeEnabled: Bool
    let uncensoredHelpText: String
    let session: ChatSessionController
    let onOpenPreferences: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(">_ ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(phosphorGreen.opacity(textOpacity))
            Text(currentModel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(phosphorGreen.opacity(textOpacity))
            if uncensoredModeEnabled {
                Text("  ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(phosphorGreen.opacity(textOpacity))
                DeskUncensoredConversationBadge(helpText: uncensoredHelpText)
            }
            Text("  \u{2022}  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(phosphorGreen.opacity(textOpacity))
            Text("ram \(totalMemoryLabel)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(phosphorGreen.opacity(textOpacity))
                .help("Combined resident memory of the Bob app and the Ollama server")
            Text("  \u{2022}  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(phosphorGreen.opacity(textOpacity))
            Text(statusWord)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(phosphorGreen.opacity(textOpacity))

            Text("  \u{2022}  ")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(phosphorGreen.opacity(textOpacity))
            Button(action: onOpenPreferences) {
                Text("\u{1F9E0} \(factCount) facts")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(phosphorGreen.opacity(textOpacity))
            }
            .buttonStyle(.plain)

            Spacer()

            PersonaQuickSwapMenu()
                .opacity(textOpacity)
                .padding(.trailing, 6)

            ConversationManagerView(session: session)
                .foregroundColor(phosphorGreen)
                .opacity(textOpacity)
                .padding(.trailing, 10)

            Text("ctx \(Int(contextFraction * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(contextColor.opacity(textOpacity))
                .padding(.trailing, 10)
        }
    }
}
