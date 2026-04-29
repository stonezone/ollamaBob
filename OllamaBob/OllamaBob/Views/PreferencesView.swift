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
    @ObservedObject var personaRegistry = BobPersonaRegistry.shared
    @ObservedObject var automationProbe = AutomationProbe.shared
    @ObservedObject var scheduler = SchedulerService.shared
    @State private var selectedTab = 0
    @State private var facts: [FactRecord] = []
    @State private var factsError: String?
    @State private var editingFactID: String?
    @State private var editingContent: String = ""
    @State private var jarvisHealthState = JarvisHealthState()
    @State private var briefingRunState = BriefingRunState()

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(PreferencesView.phosphorGreen.opacity(0.3))
            tabBar
            Divider().background(PreferencesView.phosphorGreen.opacity(0.15))
            // Wrap every tab in a scroll view so the window can't clip the
            // last row even at minimum height. Individual tabs that already
            // had internal ScrollViews are fine — nested scrolls still work.
            ScrollView {
                Group {
                    switch selectedTab {
                    case 0:  generalTab
                    case 1:  toolsTab
                    case 2:  personasTab
                    case 3:  memoryTab
                    case 4:  shortcutsTab
                    case 5:  appearanceTab
                    case 6:  privacyTab
                    case 7:  helpTab
                    default: generalTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(minWidth: 520, idealWidth: 520, minHeight: 520, idealHeight: 640)
        .background(PreferencesView.bgBlack)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton("General", index: 0)
            tabButton("Tools", index: 1)
            tabButton("Persona", index: 2)
            tabButton("Memory", index: 3)
            tabButton("Keys", index: 4)
            tabButton("Look", index: 5)
            tabButton("Privacy", index: 6)
            tabButton("Help", index: 7)
            Spacer()
        }
        .padding(.horizontal, 16)
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
        VStack(alignment: .leading, spacing: 0) {
            toggleRows

            Divider()
                .background(PreferencesView.phosphorGreen.opacity(0.2))
                .padding(.horizontal, 24)
                .padding(.top, 12)

            standardModelSection

            Divider()
                .background(PreferencesView.phosphorGreen.opacity(0.2))
                .padding(.horizontal, 24)
                .padding(.top, 12)

            webSearchSection

            Divider()
                .background(PreferencesView.phosphorGreen.opacity(0.2))
                .padding(.horizontal, 24)
                .padding(.top, 12)

            dailyBriefingSection

            Divider()
                .background(PreferencesView.phosphorGreen.opacity(0.2))
                .padding(.horizontal, 24)
                .padding(.top, 12)

            uncensoredModeSection

            Divider()
                .background(PreferencesView.phosphorGreen.opacity(0.2))
                .padding(.horizontal, 24)
                .padding(.top, 12)

            jarvisPhoneServiceSection
        }
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
            toggleRow(
                title: "Activity Timeline (local)",
                subtitle: "Record local tool calls and chat messages so Bob can answer what you were doing. Stays on your Mac. Default OFF.",
                isOn: $settings.activityTimelineEnabled,
                dimmed: false
            )
            hudSummonHotkeyRow
            numCtxRow
        }
        .padding(.top, 8)
    }

    private var hudSummonHotkeyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("HUD summon hotkey")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Text("Global key chord that brings up Bob's floating HUD anywhere in macOS. Default ⌘⇧Space; collides with Spotlight Finder Search on stock macOS.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
            }
            HStack(spacing: 12) {
                Toggle(isOn: $settings.hudSummonHotkeyEnabled) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(PreferencesView.phosphorGreen)

                TextField(
                    "cmd+shift+space",
                    text: $settings.hudSummonHotkeyChord
                )
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(PreferencesView.phosphorGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.35))
                .cornerRadius(4)
                .disabled(!settings.hudSummonHotkeyEnabled)

                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
        .onChange(of: settings.hudSummonHotkeyEnabled) { restartHotkey() }
        .onChange(of: settings.hudSummonHotkeyChord) { restartHotkey() }
    }

    private func restartHotkey() {
        // Looking up AppState through the SwiftUI environment would mean
        // threading a reference all the way down PreferencesView. Reaching
        // through NSApplication.delegate isn't an option since the app uses
        // pure SwiftUI scenes; the existing toggle pattern (Walkie-Talkie)
        // posts a Notification that AppState observes. We do the same.
        NotificationCenter.default.post(name: .bobHUDSummonHotkeyChanged, object: nil)
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

    private var briefingHour: Int {
        settings.briefingScheduleMinutes / 60
    }

    private var briefingMinute: Int {
        min(55, max(0, (settings.briefingScheduleMinutes % 60) / 5 * 5))
    }

    private var briefingHourBinding: Binding<Int> {
        Binding(
            get: { briefingHour },
            set: { setBriefingTime(hour: $0) }
        )
    }

    private var briefingMinuteBinding: Binding<Int> {
        Binding(
            get: { briefingMinute },
            set: { setBriefingTime(minute: $0) }
        )
    }

    private var formattedBriefingTime: String {
        let suffix = briefingHour >= 12 ? "PM" : "AM"
        let displayHour = briefingHour % 12 == 0 ? 12 : briefingHour % 12
        return "\(displayHour):\(String(format: "%02d", briefingMinute)) \(suffix)"
    }

    private var dailyBriefingStatusText: String {
        if let next = scheduler.nextRunAt {
            return "Next run: \(PreferencesView.briefingDateFormatter.string(from: next))."
        }
        return "Enabled. The next run will be scheduled shortly."
    }

    private static let briefingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func setBriefingTime(hour: Int? = nil, minute: Int? = nil) {
        let nextHour = min(23, max(0, hour ?? briefingHour))
        let nextMinute = min(55, max(0, minute ?? briefingMinute))
        settings.briefingScheduleMinutes = nextHour * 60 + nextMinute
        updateBriefingScheduler()
    }

    private func updateBriefingScheduler() {
        if settings.briefingScheduleEnabled {
            SchedulerService.shared.stop()
            SchedulerService.shared.start()
        } else {
            SchedulerService.shared.stop()
        }
    }

    private func runBriefingNowFromPreferences() async {
        briefingRunState = BriefingRunState(isRunning: true, isError: false, message: nil)
        await SchedulerService.shared.runBriefingNow()
        if let result = SchedulerService.shared.lastRunResult {
            briefingRunState = BriefingRunState(
                isRunning: false,
                isError: !result.success,
                message: result.success ? "Briefing saved." : "Briefing failed."
            )
        } else {
            briefingRunState = BriefingRunState(isRunning: false, isError: true, message: "No briefing result.")
        }
    }

    private var standardModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("STANDARD MODEL")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen)
                Text("Used for normal Bob conversations. Uncensored mode has its own separate model below.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            Picker("Standard model", selection: $settings.standardModelName) {
                ForEach(AppConfig.standardModelOptions) { option in
                    Text(option.title).tag(option.tag)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(PreferencesView.phosphorGreen)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let option = AppConfig.standardModelOptions.first(where: { $0.tag == settings.effectiveStandardModelName }) {
                Text("\(option.tag) — \(option.subtitle)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(settings.effectiveStandardModelName)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
    }

    private var webSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WEB SEARCH")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen)
                Text("Optional Brave Search key for Bob's web_search tool. Stored in the macOS Keychain.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            SecureField("Brave API key", text: $settings.braveAPIKey)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PreferencesView.bgBlack)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(PreferencesView.phosphorGreen.opacity(0.35), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button("Import from .env") {
                    if let result = SecretMigration.importFromEnvironment(.braveAPIKey),
                       result.success,
                       let imported = KeychainService.current.read(.braveAPIKey) {
                        settings.braveAPIKey = imported
                    }
                }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(PreferencesView.phosphorGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

                Text("Restart Bob after changing this key to refresh the registered web_search tool.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
    }

    private var uncensoredModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("UNCENSORED MODE")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen)
                Text("Master-enable Naughty Bob UI and choose the Ollama tag reserved for uncensored conversations.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable uncensored mode")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.white)
                    Text("When off, chat hides the per-conversation uncensored toggle and badge.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $settings.uncensoredModeAvailable)
                    .toggleStyle(.switch)
                    .tint(.orange)
                    .labelsHidden()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(PreferencesView.bgPanel)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Uncensored model tag")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.white)
                    Text("Used by uncensored conversations when the chat is in that mode.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField(AppSettings.defaultUncensoredModelName, text: $settings.uncensoredModelName)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(PreferencesView.bgBlack)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PreferencesView.phosphorGreen.opacity(0.35), lineWidth: 1)
                    )

                Text("Tools are disabled in uncensored mode in V1. Approval and path safety still apply.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)

                Text("If you still need the model locally, pull it with: `ollama pull \(settings.effectiveUncensoredModelName)`")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(PreferencesView.bgPanel)
        }
    }

    // MARK: - Tools Tab

    private var toolsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // Built-in (first-class Swift) tools always come first — they
                // don't depend on PATH probing and they're the core of what
                // Bob can do out of the box.
                builtinToolsHeader
                ForEach(BuiltinToolsCatalog.categoryOrder, id: \.self) { category in
                    builtinToolCategorySection(category)
                }

                Divider()
                    .background(PreferencesView.phosphorGreen.opacity(0.2))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                richPresentationSection

                Divider()
                    .background(PreferencesView.phosphorGreen.opacity(0.2))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                // Mac app automation (TCC) — controls whether Bob can drive
                // Mail / Calendar / Finder / etc. via AppleScript.
                macAppPermissionsSection

                Divider()
                    .background(PreferencesView.phosphorGreen.opacity(0.2))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                // External CLI tools (jq, rg, yt-dlp, ffmpeg, …) probed at launch.
                externalToolsHeader

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

    private var builtinToolsHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("BUILT-IN TOOLS")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(PreferencesView.phosphorGreen)
            Text("Native Swift tools Bob can call. Click a permission badge to cycle Auto / Ask / Deny. Non-bypassable floors still apply for sensitive actions like Mail, AppleScript, and phone calls.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(PreferencesView.textGrey)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var externalToolsHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("EXTERNAL CLI TOOLS")
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundColor(PreferencesView.phosphorGreen)
            Text("Detected on $PATH. Bob can call these via the shell tool.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(PreferencesView.textGrey)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var richPresentationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("RICH PRESENTATION")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen)
                Text("Control Bob's HTML companion window and the assistant-message artifact chips that route through the same presentation pipeline.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            VStack(spacing: 1) {
                richPresentationToggleRow(
                    title: "Enable rich presentation",
                    subtitle: "Registers Bob's `present` tool and allows rich HTML, URL, and file presentation.",
                    isOn: $settings.richPresentationEnabled,
                    dimmed: false
                )
                richPresentationToggleRow(
                    title: "Allow remote resources in HTML",
                    subtitle: "Permit external images and stylesheets when Bob opens rich HTML in the companion window.",
                    isOn: $settings.richPresentationRemoteResourcesEnabled,
                    dimmed: !settings.richPresentationEnabled
                )
                richPresentationToggleRow(
                    title: "Show artifact chips in chat",
                    subtitle: "Show Open chips for supported assistant-generated links and markdown images below chat bubbles.",
                    isOn: $settings.richPresentationArtifactChipsEnabled,
                    dimmed: !settings.richPresentationEnabled
                )
            }
        }
    }

    private var dailyBriefingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("DAILY BRIEFING")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen)
                Text("Run Bob's read-only morning briefing on a schedule. Uses Mail summaries, weather, and memory facts.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable Daily Briefing")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.white)
                    Text(settings.briefingScheduleEnabled ? dailyBriefingStatusText : "Off. Run now is still available for a manual briefing.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.briefingScheduleEnabled },
                    set: { enabled in
                        settings.briefingScheduleEnabled = enabled
                        updateBriefingScheduler()
                    }
                ))
                .toggleStyle(.switch)
                .tint(.orange)
                .labelsHidden()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(PreferencesView.bgPanel)

            HStack(spacing: 14) {
                Stepper(value: briefingHourBinding, in: 0...23) {
                    Text("Hour \(briefingHour)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(width: 150)

                Stepper(value: briefingMinuteBinding, in: 0...55, step: 5) {
                    Text("Minute \(String(format: "%02d", briefingMinute))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(width: 170)

                Text("Runs at \(formattedBriefingTime)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.phosphorGreen)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(PreferencesView.bgPanel)

            HStack(spacing: 10) {
                Button(briefingRunState.isRunning ? "Running..." : "Run now") {
                    Task { await runBriefingNowFromPreferences() }
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PreferencesView.phosphorGreen.opacity(briefingRunState.isRunning ? 0.5 : 0.95))
                )
                .disabled(briefingRunState.isRunning)

                if let message = briefingRunState.message {
                    HStack(spacing: 6) {
                        Image(systemName: briefingRunState.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(briefingRunState.isError ? .red : PreferencesView.phosphorGreen)
                        Text(message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(briefingRunState.isError ? Color(red: 1.0, green: 0.45, blue: 0.35) : PreferencesView.textGrey)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(PreferencesView.bgPanel)
        }
    }

    private var jarvisPhoneServiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("JARVIS PHONE SERVICE")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen)
                Text("Connect Bob to the local Jarvis daemon for phone actions. The integration stays off until you enable it.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable Jarvis phone service")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.white)
                    Text("Bob exposes phone tools when this is on and both Jarvis secrets are configured.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $settings.jarvisPhoneEnabled)
                    .toggleStyle(.switch)
                    .tint(.orange)
                    .labelsHidden()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(PreferencesView.bgPanel)

            #if DEBUG
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Use mocked call supervision client")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.white)
                    Text("Debug builds only. Off uses the live Jarvis HTTP routes; on uses the canned local fixture.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $settings.useMockedJarvisClient)
                    .toggleStyle(.switch)
                    .tint(.orange)
                    .labelsHidden()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(PreferencesView.bgPanel)
            #endif

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Jarvis API key")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.white)
                    Text("Inner call API key sent to the local daemon as X-Jarvis-Key. Stored in the macOS Keychain.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("API key", text: $settings.jarvisAPIKey)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(PreferencesView.bgBlack)
                    )

                Button("Import from .env") {
                    if let result = SecretMigration.importFromEnvironment(.jarvisAPIKey),
                       result.success,
                       let imported = KeychainService.current.read(.jarvisAPIKey) {
                        settings.jarvisAPIKey = imported
                    }
                }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(PreferencesView.phosphorGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Operator secret")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.white)
                    Text("Outer operator-auth secret sent as x-operator-secret. Jarvis call routes currently require both this and the Jarvis API key. Stored in the macOS Keychain.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("Operator secret", text: $settings.jarvisOperatorSecret)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(PreferencesView.bgBlack)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PreferencesView.phosphorGreen.opacity(0.35), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PreferencesView.phosphorGreen.opacity(0.35), lineWidth: 1)
                    )

                Button("Import from .env") {
                    if let result = SecretMigration.importFromEnvironment(.jarvisOperatorSecret),
                       result.success,
                       let imported = KeychainService.current.read(.jarvisOperatorSecret) {
                        settings.jarvisOperatorSecret = imported
                    }
                }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(PreferencesView.phosphorGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)

                HStack(spacing: 8) {
                    Button(jarvisHealthState.isChecking ? "Checking…" : "Test connection") {
                        Task { await testJarvisConnection() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(PreferencesView.phosphorGreen.opacity(jarvisHealthState.isChecking ? 0.5 : 0.95))
                    )
                    .disabled(jarvisHealthState.isChecking)

                    if let message = jarvisHealthState.message {
                        HStack(spacing: 6) {
                            Image(systemName: jarvisHealthState.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(jarvisHealthState.isError ? .red : PreferencesView.phosphorGreen)
                            Text(message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(jarvisHealthState.isError ? Color(red: 1.0, green: 0.45, blue: 0.35) : PreferencesView.textGrey)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text("Health checks read GET \(AppConfig.jarvisBaseURL)/health and do not validate the Jarvis API key or operator secret. Call routes currently require both.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(PreferencesView.bgPanel)
        }
    }

    private var macAppPermissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MAC APP PERMISSIONS")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen)
                Text("macOS Automation (TCC) grants for apps Bob can drive via AppleScript. This is separate from Bob's Auto / Ask / Deny tool policy. If \"denied\" appears, open System Settings → Privacy & Security → Automation and toggle OllamaBob back on.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            HStack(spacing: 8) {
                Button(automationProbe.isProbing ? "Prompting…" : "Re-run prompts") {
                    Task { await automationProbe.probeAll() }
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PreferencesView.phosphorGreen.opacity(automationProbe.isProbing ? 0.5 : 0.95))
                )
                .disabled(automationProbe.isProbing)

                Button("Open System Settings") {
                    AutomationProbe.openSystemSettings()
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(PreferencesView.phosphorGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(PreferencesView.phosphorGreen.opacity(0.5), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)

            VStack(spacing: 4) {
                ForEach(AutomationProbe.targets) { target in
                    macAppPermissionRow(target: target)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
    }

    private func richPresentationToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        dimmed: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(PreferencesView.phosphorGreen)
                .labelsHidden()
                .disabled(dimmed)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(PreferencesView.bgPanel)
        .opacity(dimmed ? 0.4 : 1.0)
    }

    private func macAppPermissionRow(target: AutomationTarget) -> some View {
        let status = automationProbe.statuses[target.id] ?? .unknown
        let isCurrent = automationProbe.currentTargetID == target.id
        let (label, color): (String, Color) = {
            switch status {
            case .unknown: return ("not asked", PreferencesView.textGrey)
            case .granted: return ("granted",   PreferencesView.phosphorGreen)
            case .denied:  return ("denied",    Color(red: 1.0, green: 0.45, blue: 0.35))
            case .missing: return ("not installed", PreferencesView.textGrey.opacity(0.7))
            case .error:   return ("error",     Color(red: 1.0, green: 0.45, blue: 0.35))
            }
        }()
        return HStack(spacing: 10) {
            Text(target.emoji)
            Text(target.displayName)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            if isCurrent {
                ProgressView().controlSize(.mini).tint(PreferencesView.phosphorGreen)
            }
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced).weight(.bold))
                .foregroundColor(color)
            Button("check") {
                Task { _ = await automationProbe.probe(target) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(PreferencesView.phosphorGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(PreferencesView.phosphorGreen.opacity(0.4), lineWidth: 1)
            )
            .disabled(automationProbe.isProbing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(PreferencesView.bgPanel)
        )
    }

    private func builtinToolCategorySection(_ category: String) -> some View {
        let entries = BuiltinToolsCatalog.entries(for: category)
        return VStack(alignment: .leading, spacing: 1) {
            if !entries.isEmpty {
                Text(category.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen.opacity(0.6))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                ForEach(entries, id: \.name) { entry in
                    builtinToolRow(entry)
                }
            }
        }
    }

    private func builtinToolRow(_ entry: BuiltinToolsCatalog.Entry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(builtinDotColor(for: entry.posture))
                .frame(width: 6, height: 6)

            Text(entry.name)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(.white)

            Button {
                settings.setToolApprovalOverride(nextToolApprovalSetting(for: entry), for: entry.name)
            } label: {
                Text(toolApprovalBadge(for: entry))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(toolApprovalBadgeColor(for: entry))
                    .cornerRadius(2)
            }
            .buttonStyle(.plain)
            .help("Click to cycle Auto / Ask / Deny for \(entry.name)")

            Spacer()

            Text(entry.description)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(PreferencesView.textGrey)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 5)
        .background(PreferencesView.bgPanel)
    }

    private func builtinDotColor(for posture: BuiltinToolsCatalog.ApprovalPosture) -> Color {
        switch posture {
        case .none:    return PreferencesView.phosphorGreen
        case .modal:   return .orange
        case .dynamic: return .yellow
        }
    }

    private func postureBadge(for posture: BuiltinToolsCatalog.ApprovalPosture) -> String {
        switch posture {
        case .none:    return "AUTO"
        case .modal:   return "ASK"
        case .dynamic: return "DYN"
        }
    }

    private func defaultToolApprovalSetting(for posture: BuiltinToolsCatalog.ApprovalPosture) -> ToolApprovalSetting {
        switch posture {
        case .none:    return .auto
        case .modal:   return .ask
        case .dynamic: return .auto
        }
    }

    private func toolApprovalBadge(for entry: BuiltinToolsCatalog.Entry) -> String {
        if let override = settings.toolApprovalOverride(for: entry.name) {
            return override.badgeLabel
        }
        return postureBadge(for: entry.posture)
    }

    private func toolApprovalBadgeColor(for entry: BuiltinToolsCatalog.Entry) -> Color {
        if let override = settings.toolApprovalOverride(for: entry.name) {
            return color(for: override)
        }
        return builtinDotColor(for: entry.posture)
    }

    private func nextToolApprovalSetting(for entry: BuiltinToolsCatalog.Entry) -> ToolApprovalSetting {
        if let override = settings.toolApprovalOverride(for: entry.name) {
            return override.next
        }
        if entry.posture == .dynamic {
            return .auto
        }
        return defaultToolApprovalSetting(for: entry.posture).next
    }

    private func color(for setting: ToolApprovalSetting) -> Color {
        switch setting {
        case .auto: return PreferencesView.phosphorGreen
        case .ask:  return .orange
        case .deny: return Color(red: 1.0, green: 0.45, blue: 0.35)
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
        Text("v\(AppConfig.appVersion)  \u{2022}  localhost:11434")
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
                        ("⌘⇧A", "Toggle avatar-only mode"),
                        ("⌘,",  "Open Preferences"),
                        ("⌘W",  "Close window"),
                        ("⌘Q",  "Quit OllamaBob"),
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

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pick Bob's look. Each persona is rendered live in SwiftUI — the thumbnails below are the same renderer Bob's Desk uses.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                avatarOnlyToggle

                Text("VISUAL PERSONA")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundColor(PreferencesView.phosphorGreen.opacity(0.6))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(personaRegistry.personas, id: \.id) { persona in
                    bobPersonaRow(persona)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var avatarOnlyToggle: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Avatar-only mode")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Text("Hide the terminal and type into a small bubble below Bob. Toggle with ⌘⇧A or the menu bar item.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
            }
            Spacer()
            Toggle("", isOn: $settings.avatarOnlyMode)
                .toggleStyle(.switch)
                .tint(PreferencesView.phosphorGreen)
                .labelsHidden()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
    }

    private func bobPersonaRow(_ persona: any BobPersona) -> some View {
        let isActive = persona.id == personaRegistry.activeID
        return Button(action: {
            personaRegistry.setActive(persona.id)
        }) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(PreferencesView.bgBlack)
                        .frame(width: 64, height: 64)
                    persona.character(
                        expression: BobPersonaExpression(.idle),
                        gaze: nil,
                        size: 50
                    )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? PreferencesView.phosphorGreen : Color.white.opacity(0.08),
                                lineWidth: isActive ? 1.5 : 0.5)
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(persona.displayName)
                            .font(.system(.caption, design: .monospaced).weight(.medium))
                            .foregroundColor(isActive ? .white : PreferencesView.textGrey)
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(PreferencesView.bgBlack)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(PreferencesView.phosphorGreen)
                                .cornerRadius(2)
                        }
                    }
                    Text(persona.summary)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(PreferencesView.textGrey.opacity(0.8))
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

    // MARK: - Help Tab

    private var privacyTab: some View {
        PrivacyLedgerView()
    }

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
                    • Current handoff: docs/CURRENT_HANDOFF.md
                    • Operator QA: docs/OPERATOR_QA.md
                    • Historical plans: archive/
                    • Agent guide: AGENTS.md
                    • Claude guide: CLAUDE.md
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

    @MainActor
    private func testJarvisConnection() async {
        jarvisHealthState = JarvisHealthState(isChecking: true, isError: false, message: nil)

        defer {
            jarvisHealthState.isChecking = false
        }

        guard let url = URL(string: "\(AppConfig.jarvisBaseURL)/health") else {
            jarvisHealthState = JarvisHealthState(isChecking: false, isError: true, message: "Invalid Jarvis URL")
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                jarvisHealthState = JarvisHealthState(isChecking: false, isError: true, message: "Jarvis returned an invalid response")
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""
                let suffix = body.isEmpty ? "" : ": \(body.prefix(120))"
                jarvisHealthState = JarvisHealthState(
                    isChecking: false,
                    isError: true,
                    message: "Jarvis error \(httpResponse.statusCode)\(suffix)"
                )
                return
            }

            let version = Self.jarvisDaemonVersion(from: data)
            jarvisHealthState = JarvisHealthState(
                isChecking: false,
                isError: false,
                message: version.map { "Healthy • v\($0)" } ?? "Healthy"
            )
        } catch {
            jarvisHealthState = JarvisHealthState(
                isChecking: false,
                isError: true,
                message: "Jarvis unreachable at \(AppConfig.jarvisBaseURL)"
            )
        }
    }

    private static func jarvisDaemonVersion(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let dictionary = object as? [String: Any] {
            for key in ["version", "daemonVersion", "serviceVersion", "buildVersion"] {
                if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if let nested = dictionary["data"] as? [String: Any] {
                for key in ["version", "daemonVersion", "serviceVersion", "buildVersion"] {
                    if let value = nested[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        if let raw = String(data: data, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }
}

private struct JarvisHealthState {
    var isChecking = false
    var isError = false
    var message: String?
}

private struct BriefingRunState {
    var isRunning = false
    var isError = false
    var message: String?
}
