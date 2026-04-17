import SwiftUI

/// First-launch wizard. Shown once, dismissable at any step. Persists a
/// `hasCompletedOnboarding` flag so it never re-appears. Three steps:
///   1. Welcome
///   2. Pick persona
///   3. Quick tour (shortcuts + example prompts)
struct OnboardingView: View {

    // Style constants — match Preferences/Bob's Desk for consistency.
    private static let phosphorGreen = Color(red: 0.22, green: 1.0,  blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)
    private static let textGrey      = Color(white: 0.60)

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var personaStore = PersonaStore.shared
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
                case 2: tourStep
                default: welcomeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().background(Self.phosphorGreen.opacity(0.15))
            footer
        }
        .frame(width: 520, height: 520)
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
            ForEach(0..<3) { i in
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
            Button(step == 2 ? "Get started" : "Next") {
                if step == 2 { finish() } else { step += 1 }
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
                pillRow(icon: "🧠", title: "Remembers what matters", body: "Tell Bob \"remember I prefer tabs\" and he'll carry that forward across every future conversation.")
                pillRow(icon: "🎭", title: "Five personas", body: "Mumbai Bob (with voice!), Terse Engineer, Grumpy Linus, Helpful Assistant, or Blank — pick the voice that fits your mood.")
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
                            "\"remember my GitHub handle is @zackjordan\"",
                         ])

                tourCard(title: "Handy shortcuts",
                         lines: [
                            "⌘N  new conversation",
                            "⌘L  focus the input field",
                            "⌘1–5  swap persona",
                            "⌘,  open preferences",
                         ])

                Text("Anything in Preferences → Help has the full reference. Have fun.")
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
