import SwiftUI

struct PreferencesView: View {

    // MARK: Style Constants

    private static let phosphorGreen = Color(red: 0.22, green: 1.0,  blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)
    private static let textGrey      = Color(white: 0.50)

    // MARK: State

    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var toolRuntime = ToolRuntime.shared
    @ObservedObject var personaStore = PersonaStore.shared
    @State private var selectedTab = 0
    @State private var facts: [FactRecord] = []
    @State private var factsError: String?
    @State private var editingFactID: String?
    @State private var editingContent: String = ""

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(PreferencesView.phosphorGreen.opacity(0.3))
            tabBar
            Divider().background(PreferencesView.phosphorGreen.opacity(0.15))
            Group {
                switch selectedTab {
                case 0:  generalTab
                case 1:  toolsTab
                case 2:  personasTab
                case 3:  memoryTab
                case 4:  shortcutsTab
                case 5:  helpTab
                default: generalTab
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 480, height: 460)
        .background(PreferencesView.bgBlack)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("General", index: 0)
            tabButton("Tools", index: 1)
            tabButton("Persona", index: 2)
            tabButton("Memory", index: 3)
            tabButton("Shortcuts", index: 4)
            tabButton("Help", index: 5)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    private func tabButton(_ label: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            Text(label)
                .font(.system(.caption, design: .monospaced).weight(selectedTab == index ? .bold : .regular))
                .foregroundColor(selectedTab == index ? PreferencesView.phosphorGreen : PreferencesView.textGrey)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    selectedTab == index
                        ? PreferencesView.phosphorGreen.opacity(0.12)
                        : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private var generalTab: some View {
        toggleRows
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OllamaBob Preferences")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundColor(PreferencesView.phosphorGreen)
            Text("Configure your local Bob assistant")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(PreferencesView.textGrey)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var toggleRows: some View {
        VStack(spacing: 1) {
            toggleRow(
                title: "Show Bob",
                subtitle: "Display Bob and his speech bubbles at the top of the chat",
                isOn: $settings.showBob,
                dimmed: false
            )
            toggleRow(
                title: "Play sounds",
                subtitle: "Subtle sound effects when you send a message and when Bob replies",
                isOn: $settings.soundsEnabled,
                dimmed: false
            )
            toggleRow(
                title: "Bob speaks",
                subtitle: "Play pre-recorded voice lines on greetings and completions (Mumbai Bob only)",
                isOn: $settings.bobVoiceEnabled,
                dimmed: !settings.soundsEnabled
            )
            toggleRow(
                title: "Heartbeat",
                subtitle: "Bob pipes up every 10–20 minutes when idle so he feels alive (Mumbai Bob only)",
                isOn: $settings.heartbeatEnabled,
                dimmed: !settings.soundsEnabled || !settings.bobVoiceEnabled
            )
            sliderRow(
                title: "Chat window transparency",
                subtitle: "Lower values let your desktop show through",
                value: $settings.chatWindowOpacity,
                range: 0.4...1.0
            )
            numCtxRow
        }
        .padding(.top, 8)
    }

    private var numCtxRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Context window")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Text("Tokens Bob can hold in memory per turn. Larger = longer conversations before truncation.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
            }
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { Double(settings.numCtx) },
                        set: { newValue in
                            let snapped = PreferencesView.snapNumCtx(newValue)
                            if snapped != settings.numCtx { settings.numCtx = snapped }
                        }
                    ),
                    in: 8192...32768,
                    step: 8192
                )
                .tint(PreferencesView.phosphorGreen)
                Text(PreferencesView.formatNumCtx(settings.numCtx))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.phosphorGreen)
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
    }

    private static func snapNumCtx(_ raw: Double) -> Int {
        let candidates = AppConfig.numCtxAllowed
        return candidates.min(by: { abs(Double($0) - raw) < abs(Double($1) - raw) }) ?? AppConfig.numCtx
    }

    private static func formatNumCtx(_ value: Int) -> String {
        "\(value / 1024)K"
    }

    // MARK: - Tools Tab

    private var toolsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if toolRuntime.isProbing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("Probing tools...")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(PreferencesView.textGrey)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }

                // Beta tools toggle
                betaToolsToggle

                let categories = orderedCategories()
                ForEach(categories, id: \.self) { category in
                    toolCategorySection(category)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var betaToolsToggle: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Beta tools")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundColor(.white)
                Text("Enable tools that may confuse the model or have security implications.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
            }
            Spacer()
            Toggle("", isOn: $settings.betaToolsEnabled)
                .toggleStyle(.switch)
                .tint(.orange)
                .labelsHidden()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(PreferencesView.bgPanel)
    }

    private func orderedCategories() -> [String] {
        let cats = Set(toolRuntime.catalog.tools.map(\.category))
        return cats.sorted()
    }

    private func toolCategorySection(_ category: String) -> some View {
        let tools = toolRuntime.catalog.tools.filter { $0.category == category }
        return VStack(alignment: .leading, spacing: 1) {
            Text(category.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(PreferencesView.phosphorGreen.opacity(0.6))
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(tools) { entry in
                toolRow(entry)
            }
        }
    }

    private func toolRow(_ entry: ToolCatalogEntry) -> some View {
        let state = toolRuntime.states[entry.name]
        let isLive = toolRuntime.isLive(entry.name)

        return HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(dotColor(for: state))
                .frame(width: 6, height: 6)

            // Tool name
            Text(entry.name)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(isLive ? .white : PreferencesView.textGrey)

            if entry.beta {
                Text("BETA")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .cornerRadius(2)
            }

            if entry.bundled {
                Text("BUNDLED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(PreferencesView.phosphorGreen.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(PreferencesView.phosphorGreen.opacity(0.15))
                    .cornerRadius(2)
            }

            Spacer()

            // Version or status text
            Text(statusText(for: state))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(isLive ? PreferencesView.phosphorGreen.opacity(0.7) : PreferencesView.textGrey.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 5)
        .background(PreferencesView.bgPanel)
    }

    private func dotColor(for state: ToolState?) -> Color {
        switch state {
        case .homebrewDetected: return PreferencesView.phosphorGreen
        case .bundled:          return .blue
        case .missing:          return PreferencesView.textGrey.opacity(0.4)
        case .none:             return PreferencesView.textGrey.opacity(0.2)
        }
    }

    private func statusText(for state: ToolState?) -> String {
        switch state {
        case .homebrewDetected(_, let version):
            return version ?? "detected"
        case .bundled(let version):
            return version ?? "bundled"
        case .missing(let reason):
            return String(reason.prefix(40))
        case .none:
            return "unknown"
        }
    }

    // MARK: - Personas Tab

    private var personasTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose Bob's voice and personality. The active persona controls tone — safety rules always apply regardless.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)

                ForEach(personaStore.personas) { persona in
                    personaRow(persona)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func personaRow(_ persona: Persona) -> some View {
        let isActive = persona.id == personaStore.activePersonaID
        return Button(action: { personaStore.activePersonaID = persona.id }) {
            HStack(alignment: .top, spacing: 10) {
                // Radio dot
                Circle()
                    .strokeBorder(isActive ? PreferencesView.phosphorGreen : PreferencesView.textGrey, lineWidth: 1.5)
                    .background(Circle().fill(isActive ? PreferencesView.phosphorGreen : Color.clear))
                    .frame(width: 12, height: 12)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(persona.name)
                            .font(.system(.caption, design: .monospaced).weight(.medium))
                            .foregroundColor(isActive ? .white : PreferencesView.textGrey)

                        if persona.isBuiltin {
                            Text("PRESET")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(PreferencesView.phosphorGreen.opacity(0.7))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(PreferencesView.phosphorGreen.opacity(0.12))
                                .cornerRadius(2)
                        }
                    }

                    // Preview: first 120 chars of the system prompt
                    let preview = String(persona.systemPromptMarkdown.prefix(120))
                        .replacingOccurrences(of: "\n", with: " ")
                    Text(preview + (persona.systemPromptMarkdown.count > 120 ? "..." : ""))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(isActive ? PreferencesView.phosphorGreen.opacity(0.06) : PreferencesView.bgPanel)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Memory Tab

    private var memoryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                MemoryIOPanel(onImportComplete: loadFacts)

                HStack {
                    Text("Facts Bob remembers about you")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(facts.count) fact\(facts.count == 1 ? "" : "s")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                if let error = factsError {
                    Text(error)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 24)
                }

                if facts.isEmpty {
                    Text("No facts stored yet. Tell Bob \"remember that I prefer dark mode\" and it'll show up here.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                } else {
                    let grouped = Dictionary(grouping: facts, by: \.category)
                    let categories = grouped.keys.sorted()
                    ForEach(categories, id: \.self) { category in
                        factCategorySection(category, facts: grouped[category] ?? [])
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear { loadFacts() }
    }

    private func factCategorySection(_ category: String, facts: [FactRecord]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(category.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(PreferencesView.phosphorGreen.opacity(0.6))
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 2)

            ForEach(facts, id: \.id) { fact in
                factRow(fact)
            }
        }
    }

    private func factRow(_ fact: FactRecord) -> some View {
        let isEditing = editingFactID == fact.id
        return VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                TextEditor(text: $editingContent)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minHeight: 56)
                    .scrollContentBackground(.hidden)
                    .background(PreferencesView.bgBlack)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(PreferencesView.phosphorGreen.opacity(0.4), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button("Save") {
                        saveFact(id: fact.id)
                    }
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.bgBlack)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PreferencesView.phosphorGreen)
                    .cornerRadius(3)
                    .buttonStyle(.plain)

                    Button("Cancel") {
                        editingFactID = nil
                        editingContent = ""
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .buttonStyle(.plain)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Text(fact.content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(3)

                    Spacer()

                    Button(action: {
                        editingFactID = fact.id
                        editingContent = fact.content
                    }) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundColor(PreferencesView.textGrey.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Edit this fact")

                    Button(action: { deleteFact(fact) }) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(PreferencesView.textGrey.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Delete this fact")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .background(PreferencesView.bgPanel)
    }

    private func saveFact(id: String) {
        let trimmed = editingContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try DatabaseManager.shared.updateFact(id: id, content: trimmed)
            editingFactID = nil
            editingContent = ""
            loadFacts()
        } catch {
            factsError = error.localizedDescription
        }
    }

    private func loadFacts() {
        do {
            facts = try DatabaseManager.shared.fetchFacts()
            factsError = nil
        } catch {
            factsError = error.localizedDescription
        }
    }

    private func deleteFact(_ fact: FactRecord) {
        do {
            _ = try DatabaseManager.shared.deleteFact(id: fact.id)
            facts.removeAll { $0.id == fact.id }
        } catch {
            factsError = error.localizedDescription
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text("v1.0.2  \u{2022}  localhost:11434")
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(PreferencesView.phosphorGreen.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 14)
    }

    // MARK: Row Builder

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        dimmed: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(PreferencesView.phosphorGreen)
                .labelsHidden()
                .disabled(dimmed)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
        .opacity(dimmed ? 0.4 : 1.0)
    }

    private func sliderRow(
        title: String,
        subtitle: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
            }
            HStack(spacing: 12) {
                Slider(value: value, in: range)
                    .tint(PreferencesView.phosphorGreen)
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.phosphorGreen)
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                shortcutSection(
                    title: "Chat",
                    items: [
                        ("⌘N", "New conversation"),
                        ("⌘L", "Focus the input field"),
                        ("⌘K", "Focus the input field (same as ⌘L)"),
                        ("⏎",  "Send message"),
                        ("⇧⏎", "New line in message"),
                    ]
                )
                shortcutSection(
                    title: "Persona",
                    items: [
                        ("⌘1", "Switch to Mumbai Bob"),
                        ("⌘2", "Switch to Terse Engineer"),
                        ("⌘3", "Switch to Grumpy Linus"),
                        ("⌘4", "Switch to Helpful Assistant"),
                        ("⌘5", "Switch to Blank"),
                    ]
                )
                shortcutSection(
                    title: "App",
                    items: [
                        ("⌘,", "Open Preferences"),
                        ("⌘W", "Close window"),
                        ("⌘Q", "Quit OllamaBob"),
                    ]
                )
                Text("Tip: Bob responds to ⌘-shortcuts anywhere in the app, even with the sprite visible but no message focused.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
    }

    private func shortcutSection(title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(PreferencesView.phosphorGreen)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 6)

            VStack(spacing: 1) {
                ForEach(items, id: \.0) { key, label in
                    HStack(spacing: 12) {
                        shortcutKey(key)
                        Text(label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(PreferencesView.bgPanel)
                }
            }
        }
    }

    private func shortcutKey(_ key: String) -> some View {
        Text(key)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundColor(PreferencesView.phosphorGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: 44)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PreferencesView.phosphorGreen.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(PreferencesView.phosphorGreen.opacity(0.5), lineWidth: 0.5)
            )
    }

    // MARK: - Help Tab

    private var helpTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                helpSection(title: "What is Bob?", body: """
                    Bob is a local-first AI assistant that runs entirely on your \
                    Mac. He talks to Ollama at localhost:11434, owns his own \
                    agent loop, and executes tools (shell, file read, file \
                    search, web search, file write) with native approval \
                    dialogs before any risky action. No cloud, no data leaves \
                    your machine (except web searches, which use Brave).
                    """)

                helpSection(title: "What can Bob do?", body: """
                    Everyday things you can ask:
                    • Inspect your filesystem — "what's in ~/Downloads sorted \
                    by size?"
                    • Read a file — "show me my .zshrc"
                    • Search across files — "find every TODO in this repo"
                    • Search the web — "what's new with Swift 6 concurrency?"
                    • Run commands — "which version of ffmpeg do I have?"
                    • Write files — "save this snippet to \
                    ~/Desktop/note.md" (asks for approval first)
                    • Use your clipboard — "summarize what I just copied" \
                    or "put this command on my clipboard"
                    • Drive Mac apps via AppleScript — "add 'milk' to my \
                    Reminders" or "create a note titled 'meeting' in Notes"
                    • Remember things — tell Bob to "remember I prefer tabs \
                    over spaces" and he will carry that across sessions
                    """)

                helpSection(title: "Example prompts", body: """
                    • "List the 10 largest files in my Downloads."
                    • "Read ~/.gitconfig and explain my aliases."
                    • "Find every Swift file that imports SwiftUI."
                    • "What's the current version of Ollama?"
                    • "Save a README stub to ~/Desktop/readme.md."
                    • "Summarize what I just copied." (reads clipboard)
                    • "Copy a sample curl command to my clipboard."
                    • "Add 'call dentist' to my Reminders." (AppleScript)
                    • "What songs are in my Music library right now?" \
                    (AppleScript)
                    • "Remember that my GitHub is @zackjordan."
                    • "What did we talk about last Tuesday?" (searches past \
                    conversations)
                    """)

                helpSection(title: "Personas", body: """
                    Bob has five voices. Switch with ⌘1–5 or from the \
                    persona menu in the status line:
                    • Mumbai Bob — earnest, eager, "sir" everywhere (default, \
                    the only persona with voice lines)
                    • Terse Engineer — short, technical, no fluff
                    • Grumpy Linus — prickly, opinionated, direct
                    • Helpful Assistant — cheerful, balanced, neutral
                    • Blank — no persona voice, pure tool-use

                    Switching persona changes the system prompt and Bob's \
                    tone; the underlying capabilities stay the same.
                    """)

                helpSection(title: "Memory", body: """
                    Bob remembers facts you tell him across sessions. \
                    Anything like "remember X" or "my name is Y" is saved \
                    as a fact and re-injected into future prompts.

                    • Max ~400 chars per fact.
                    • Oldest facts get trimmed after 30 days, except \
                    identity facts (name, role, preferences).
                    • View, edit, delete, export, or import facts in the \
                    Memory tab.
                    """)

                helpSection(title: "Approvals", body: """
                    Bob never auto-approves writes. Anytime he asks to run \
                    a command that modifies your system — rm, mv, brew \
                    install, write_file, chmod, clipboard_write, \
                    applescript, etc. — a native approval dialog blocks \
                    until you OK it. Reads in your home, Downloads, \
                    Desktop, and Documents don't need approval.

                    Some commands are always forbidden (sudo, rm -rf /, \
                    mkfs, curl | sh, AppleScript with shell-escape or \
                    synthetic keystrokes). Bob tells the model those \
                    aren't allowed and moves on.
                    """)

                helpSection(title: "Sounds & voice", body: """
                    Three audio features, each with its own toggle:
                    • Play sounds — subtle Tink/Pop on send & receive
                    • Bob speaks — pre-recorded Mumbai Bob lines on \
                    greetings, completions, and idle-returns (50 clips \
                    bundled, zero API calls at runtime)
                    • Heartbeat — Bob pipes up every 10–20 minutes when \
                    idle so he feels alive (off by default)

                    All three are Mumbai-Bob-only — other personas stay \
                    silent so the voice doesn't clash.
                    """)

                helpSection(title: "Troubleshooting", body: """
                    • "Ollama not running" — start it with `ollama serve` \
                    or run `brew services start ollama`.
                    • "Tool failing repeatedly" — Bob falls back from \
                    gemma4:e4b to qwen3:14b after 3 parse failures. Check \
                    the bubble for a model-switch notification.
                    • "Chat feels sluggish" — reduce the num_ctx slider in \
                    General; smaller context means faster turns on lower \
                    memory.
                    • "I don't hear Bob's voice" — check General → "Bob \
                    speaks" is on, and you're on Mumbai Bob persona.
                    """)

                helpSection(title: "Learn more", body: """
                    • Project plan: docs/OLLAMABOB_V1.1_PLAN.md
                    • V2 status: OLLAMA_CLAUDE.md
                    • Your memory is in ~/Library/Application \
                    Support/OllamaBob/ollamabob.sqlite
                    • Issues or feedback? Drop a note in the repo.
                    """)
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    private func helpSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(PreferencesView.phosphorGreen)
            Text(body)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}
