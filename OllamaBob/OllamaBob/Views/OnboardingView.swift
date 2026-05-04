import SwiftUI

/// First-launch wizard. Shown once, dismissable at any step. Persists a
/// `hasCompletedOnboarding` flag so it never re-appears. Four steps:
///   1. Welcome
///   2. Pick persona
///   3. Grant Mac app permissions (Mail, Calendar, etc.)
///   4. Quick tour (shortcuts + example prompts)
struct OnboardingView: View {

    // Style constants — match Preferences/Bob's Desk for consistency.
    private static let phosphorGreen = Color(red: 0.22, green: 1.0,  blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)
    private static let textGrey      = Color(white: 0.60)

    private static let stepCount = 4

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var personaStore = PersonaStore.shared
    @ObservedObject private var automationProbe = AutomationProbe.shared
    @State private var step = 0

    static let completionKey = "hasCompletedOnboarding"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Self.phosphorGreen.opacity(0.25))
            Group {
                switch step {
                case 0: welcomeStep
                case 1: personaStep
                case 2: permissionsStep
                case 3: tourStep
                default: welcomeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().background(Self.phosphorGreen.opacity(0.15))
            footer
        }
        .frame(width: 520, height: 560)
        .background(Self.bgBlack)
    }

    // MARK: - Header / Footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Welcome to OllamaBob")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundColor(Self.phosphorGreen)
                Spacer()
                stepDots
            }
            Text("Your local AI assistant, running entirely on this Mac.")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Self.textGrey)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.stepCount, id: \.self) { i in
                Circle()
                    .fill(i == step ? Self.phosphorGreen : Self.phosphorGreen.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip") { finish() }
                .buttonStyle(.plain)
                .foregroundColor(Self.textGrey)
                .font(.system(.caption, design: .monospaced))

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(phosphorSecondaryStyle())
            }
            Button(step == Self.stepCount - 1 ? "Get started" : "Next") {
                if step == Self.stepCount - 1 { finish() } else { step += 1 }
            }
            .buttonStyle(phosphorPrimaryStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pillRow(icon: "🔒", title: "Private by default", body: "Everything runs locally through Ollama. Your conversations never leave your machine (except opt-in web searches).")
                pillRow(icon: "🛠", title: "Real tools, not just chat", body: "Bob can inspect your filesystem, run shell commands, read files, search the web, and write files — with your approval.")
                pillRow(icon: "⌨️", title: "Summon Bob from anywhere", body: "Press ⌘⇧Space to bring up Bob's floating HUD — ask a question and the chat opens with the prompt already sent. Rebind in Preferences if it conflicts with Spotlight.")
                pillRow(icon: "📋", title: "Menu bar quick-ask", body: "Click Bob in the menu bar for a glass popover with a quick-input field, mode toggles, and shortcuts to all of Bob's surfaces.")
                pillRow(icon: "📞", title: "Phone calls when you want them", body: "Enable Jarvis in Preferences → Tools and Bob can place real outbound calls. The Live Call window lets you compose, supervise transcripts, inject mid-call messages, and hang up. Post-call action items appear in chat — tap one to hand it straight back to Bob as a new task.")
                pillRow(icon: "⏱", title: "Long-running shell commands work", body: "Bob uses a login zsh shell, so Homebrew and other PATH tools are always available. Commands like 'brew upgrade' run to completion. Press ⌘. or the Cancel button to stop a running turn at any time.")
                pillRow(icon: "🖼", title: "Rich presentation", body: "Bob can open formatted HTML pages, URLs, and local files in real macOS windows instead of dumping everything into chat.")
                pillRow(icon: "🧠", title: "Remembers what matters", body: "Tell Bob \"remember I prefer tabs\" and he'll carry that forward across every future conversation.")
                pillRow(icon: "🎭", title: "Five personas + uncensored mode", body: "Pick the voice that fits the moment, then optionally enable the per-conversation UNCENSORED pill later in Preferences → Models.")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
    }

    private var personaStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick a starting persona")
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundColor(Self.phosphorGreen)

                Text("You can switch any time with ⌘1–5 or from the status line.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Self.textGrey)
                    .padding(.bottom, 4)

                personaRow(id: BuiltinPersonas.mumbaiBobID,
                           title: "Mumbai Bob",
                           subtitle: "Eager, earnest, \"sir\" everywhere — with voice lines.",
                           badge: "recommended")
                personaRow(id: BuiltinPersonas.terseEngineerID,
                           title: "Terse Engineer",
                           subtitle: "Short, technical, no fluff.")
                personaRow(id: BuiltinPersonas.grumpyLinusID,
                           title: "Grumpy Linus",
                           subtitle: "Prickly, opinionated, direct.")
                personaRow(id: BuiltinPersonas.helpfulAssistID,
                           title: "Helpful Assistant",
                           subtitle: "Cheerful, balanced, neutral.")
                personaRow(id: BuiltinPersonas.blankID,
                           title: "Blank",
                           subtitle: "No persona flavor — just the tools.")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
    }

    private var permissionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Let Bob drive your Mac apps")
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundColor(Self.phosphorGreen)

                Text("macOS requires your permission before Bob can talk to apps like Mail or Calendar. Click \"Grant all\" to get the prompts out of the way now — you can approve or skip each one. This step is only for macOS Automation permissions, not every runtime tool approval.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Self.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .padding(.bottom, 4)

                HStack(spacing: 8) {
                    Button(automationProbe.isProbing ? "Prompting…" : "Grant all") {
                        Task { await automationProbe.probeAll() }
                    }
                    .buttonStyle(phosphorPrimaryStyle())
                    .disabled(automationProbe.isProbing)

                    Button("Open System Settings") {
                        AutomationProbe.openSystemSettings()
                    }
                    .buttonStyle(phosphorSecondaryStyle())
                }
                .padding(.bottom, 6)

                ForEach(AutomationProbe.targets) { target in
                    permissionRow(target: target)
                }

                Text("Denied one by accident? Open System Settings → Privacy & Security → Automation and toggle \"OllamaBob\" back on. File writes, AppleScript, phone calls, downloads, and other ASK tools still prompt at runtime.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Self.textGrey.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
    }

    private func permissionRow(target: AutomationTarget) -> some View {
        let status = automationProbe.statuses[target.id] ?? .unknown
        let isCurrent = automationProbe.currentTargetID == target.id
        return HStack(spacing: 12) {
            Text(target.emoji).font(.title3)
            Text(target.displayName)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(.white)
            Spacer()
            statusBadge(status: status, isCurrent: isCurrent)
            Button(buttonLabel(for: status)) {
                Task { _ = await automationProbe.probe(target) }
            }
            .buttonStyle(phosphorSecondaryStyle())
            .disabled(automationProbe.isProbing)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.bgPanel)
        )
    }

    @ViewBuilder
    private func statusBadge(status: AutomationStatus, isCurrent: Bool) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .unknown: return ("not asked", Self.textGrey)
            case .granted: return ("granted", Self.phosphorGreen)
            case .denied:  return ("denied",  Color(red: 1.0, green: 0.45, blue: 0.35))
            case .missing: return ("not installed", Self.textGrey.opacity(0.7))
            case .error:   return ("error", Color(red: 1.0, green: 0.45, blue: 0.35))
            }
        }()
        HStack(spacing: 4) {
            if isCurrent {
                ProgressView().controlSize(.mini).tint(Self.phosphorGreen)
            }
            Text(text.uppercased())
                .font(.system(size: 9, design: .monospaced).weight(.bold))
                .foregroundColor(color)
        }
    }

    private func buttonLabel(for status: AutomationStatus) -> String {
        switch status {
        case .unknown, .error: return "Grant"
        case .granted:          return "Recheck"
        case .denied:           return "Retry"
        case .missing:          return "Skip"
        }
    }

    private var tourStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Quick tour")
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundColor(Self.phosphorGreen)

                tourCard(title: "Try these first",
                         lines: [
                            "\"list the 10 largest files in my Downloads\"",
                            "\"what's in my ~/.zshrc?\"",
                            "\"find every TODO comment in this project\"",
                            "\"give me a formatted page of today's top world news\"",
                            "\"call me and tell me dinner is ready\"",
                            "\"remember my GitHub handle is @zackjordan\"",
                         ])

                tourCard(title: "Handy shortcuts",
                         lines: [
                            "⌘N  new conversation",
                            "⌘L  focus the input field",
                            "⌘1–5  swap persona",
                            "⌘,  open preferences",
                         ])

                tourCard(title: "Worth enabling in Preferences",
                         lines: [
                            "Tools → Rich Presentation  for HTML pages, URLs, and file opens",
                            "Tools → Jarvis Phone Service  for phone_call / phone_status / phone_hangup",
                            "Models → Enable Uncensored Mode  to show the per-chat UNCENSORED pill",
                            "Create jarvis-address-book.local.json  if you want aliases like me or wife",
                         ])

                Text("Anything in Preferences → Help and the README has the fuller reference, including Jarvis calling rules and local address-book shortcuts.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Self.textGrey)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
    }

    // MARK: - Row helpers

    private func pillRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon).font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.bgPanel)
        )
    }

    private func personaRow(id: String, title: String, subtitle: String, badge: String? = nil) -> some View {
        let selected = personaStore.activePersonaID == id
        return Button(action: { personaStore.activePersonaID = id }) {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(Self.phosphorGreen.opacity(selected ? 1.0 : 0.35), lineWidth: 1.5)
                    .background(
                        Circle()
                            .fill(Self.phosphorGreen.opacity(selected ? 0.6 : 0))
                    )
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(.white)
                        if let badge {
                            Text(badge.uppercased())
                                .font(.system(size: 9, design: .monospaced).weight(.bold))
                                .foregroundColor(Self.phosphorGreen)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(Self.phosphorGreen.opacity(0.5), lineWidth: 0.5)
                                )
                        }
                    }
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Self.phosphorGreen.opacity(0.12) : Self.bgPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? Self.phosphorGreen.opacity(0.6) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func tourCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(Self.phosphorGreen)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.bgPanel)
        )
    }

    // MARK: - Finish

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completionKey)
        dismiss()
    }
}

// MARK: - Button styles (phosphor themed)

private struct phosphorPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let green = Color(red: 0.22, green: 1.0, blue: 0.08)
        return configuration.label
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(green.opacity(configuration.isPressed ? 0.7 : 0.95))
            )
    }
}

private struct phosphorSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let green = Color(red: 0.22, green: 1.0, blue: 0.08)
        return configuration.label
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(green)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(green.opacity(configuration.isPressed ? 1.0 : 0.5), lineWidth: 1)
            )
    }
}
