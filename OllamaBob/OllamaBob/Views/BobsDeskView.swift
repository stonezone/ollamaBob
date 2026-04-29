import SwiftUI

struct BobsDeskView: View {

    private static let phosphorGreen = Color(red: 0.22, green: 1.0, blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)

    private static let bubbleFill         = Color.white.opacity(0.48)
    private static let bubbleStroke       = Color.black.opacity(0.18)
    private static let speechBubbleFill   = Color.white.opacity(0.64)
    private static let speechBubbleStroke = Color.black.opacity(0.28)
    private static let avatarBubbleTailAnchorX: CGFloat = 0.56

    static let phosphorGreenPublic = Color(red: 0.22, green: 1.0, blue: 0.08)

    @ObservedObject var agentLoop: AgentLoop
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var personaStore = PersonaStore.shared
    @ObservedObject private var avatarStore = AvatarStore.shared
    @ObservedObject private var taintPolicy = TaintPolicy.shared
    @StateObject private var session: ChatSessionController
    @StateObject private var viewModel: DeskViewModel

    @State private var hasGreeted = false

    @State private var factCount = 0
    @State private var memoryRefreshTimer: Timer?
    @State private var totalMemoryLabel = "--"
    @State private var processMemoryTimer: Timer?

    @State private var systemNotices: [SystemNotice] = []
    @State private var interleavedItemsCache: [DeskTranscriptItem] = []
    @State private var lastSeenToolActivityIndex = 0

    @FocusState private var inputFocused: Bool

    @State private var autoScrollEnabled = true
    @State private var isNearBottom = true
    @State private var cachedContextTokensUsed = 0

    @State private var hasProcessed = false

    @State private var turnStartedAt: Date? = nil
    @State private var turnStartingToolCount: Int = 0

    @State private var lastSendAt: Date? = nil

    @Environment(\.openWindow) private var openWindow

    init(agentLoop: AgentLoop) {
        self.agentLoop = agentLoop
        let session = ChatSessionController(agentLoop: agentLoop)
        _session = StateObject(wrappedValue: session)
        _viewModel = StateObject(wrappedValue: DeskViewModel(
            session: session,
            agent: agentLoop,
            sendsViaExternalHandler: true
        ))
    }

    private var latestAssistantMessage: ChatMessage? {
        session.messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })
    }

    private var latestAssistantPreview: ChatBubbleRendering.AvatarPreview? {
        latestAssistantMessage.map { ChatBubbleRendering.avatarBubblePreview(for: $0.content) }
    }

    private var latestGreetingLine: String? {
        systemNotices.first(where: { $0.isGreeting })?.text
    }

    private var shouldShowBubble: Bool {
        if let last = session.messages.last(where: { $0.role != .system }) {
            return last.role == .assistant && !last.content.isEmpty
        }
        return systemNotices.contains(where: { $0.isGreeting })
    }

    private var statusWord: String {
        agentLoop.isProcessing ? agentLoop.bobMood.rawValue : "idle"
    }

    private var surfaceOpacity: Double {
        settings.chatWindowOpacity
    }

    private var textOpacity: Double {
        min(1.0, settings.chatWindowOpacity + 0.1)
    }

    private var transcriptRefreshToken: String {
        let lastMessageToken = session.messages.last.map { "\($0.id)|\($0.content.count)|\($0.timestamp.timeIntervalSince1970)" } ?? "none"
        let lastNoticeToken = systemNotices.last.map { "\($0.id.uuidString)|\($0.text.count)|\($0.at.timeIntervalSince1970)" } ?? "none"
        return "\(session.conversationId ?? "nil")|\(session.messages.count)|\(lastMessageToken)|\(systemNotices.count)|\(lastNoticeToken)"
    }

    private var uncensoredModeEnabled: Bool {
        settings.uncensoredModeAvailable && session.conversationUncensoredMode
    }

    private var uncensoredModeToggleDisabled: Bool {
        agentLoop.isProcessing
    }

    private var isTaintActive: Bool { session.conversationId.map { taintPolicy.tainted(forSession: $0) } ?? false }

    private var uncensoredModeHelpText: String {
        if session.conversationId == nil {
            return "Toggle uncensored mode for the next conversation. Configured tag: \(settings.effectiveUncensoredModelName)"
        }
        let action = uncensoredModeEnabled ? "Turn off" : "Turn on"
        return "\(action) uncensored mode for this conversation. Configured tag: \(settings.effectiveUncensoredModelName)"
    }

    private var spriteAccent: Color {
        let rgb = GreetingLines.accentColor(for: personaStore.activePersonaID)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // MARK: - Context Budget

    private func computeContextTokensUsed() -> Int {
        let persona = PersonaStore.shared.activePersona
        var chars = PromptComposer.compose(persona: persona).count
        for msg in session.history where msg.role != "system" {
            chars += msg.content.count
            if let calls = msg.toolCalls {
                for call in calls {
                    chars += call.function.name.count
                    chars += String(describing: call.function.parsedArguments).count
                }
            }
        }
        return chars / 4
    }

    private func refreshContextTokensUsed() {
        cachedContextTokensUsed = computeContextTokensUsed()
    }

    private var contextTokensUsed: Int {
        cachedContextTokensUsed
    }

    private var contextFraction: Double {
        min(1.0, Double(contextTokensUsed) / Double(settings.numCtx))
    }

    private var contextColor: Color {
        switch contextFraction {
        case ..<0.75: return Self.phosphorGreen
        case ..<0.90: return .yellow
        default:      return .red
        }
    }

    private var uncensoredBudgetSnapshot: ContextBudget.Snapshot {
        ContextBudget.snapshot(messages: session.messages, numCtx: settings.numCtx)
    }

    private var shouldShowUncensoredBudgetBanner: Bool {
        uncensoredModeEnabled && uncensoredBudgetSnapshot.shouldWarn
    }

    // MARK: Body

    var body: some View {
        Group {
            if settings.avatarOnlyMode {
                avatarOnlyLayout
                    .frame(minWidth: 300, idealWidth: 360, minHeight: 340, idealHeight: 420)
            } else {
                fullLayout
                    .frame(minWidth: 420, idealWidth: 520, minHeight: 520, idealHeight: 760)
            }
        }
        .background(Color.clear)
        .background(WindowTransparencyConfigurator(avatarOnly: settings.avatarOnlyMode))
        .task {
            session.loadExistingConversationIfNeeded()
            enforceMasterUncensoredSetting()
            rebuildInterleavedItems()
            refreshContextTokensUsed()
        }
        .onChange(of: session.conversationId) {
            resetConversationScopedNoticeState()
            enforceMasterUncensoredSetting()
            rebuildInterleavedItems()
            refreshContextTokensUsed()
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.bubbleVisible = shouldShowBubble
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                maybeGreet()
            }
        }
        .onChange(of: settings.uncensoredModeAvailable) {
            enforceMasterUncensoredSetting()
        }
        .onChange(of: personaStore.activePersonaID) {
            refreshContextTokensUsed()
        }
        .onChange(of: transcriptRefreshToken) {
            rebuildInterleavedItems()
        }
        .onChange(of: session.transcriptRevision) {
            refreshContextTokensUsed()
            viewModel.awaitingTurnTranscript = false
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.bubbleVisible = shouldShowBubble
            }
        }
        .onChange(of: session.errorMessage) {
            guard agentLoop.isProcessing == false else { return }
            viewModel.awaitingTurnTranscript = false
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.bubbleVisible = shouldShowBubble
            }
        }
        .onReceive(agentLoop.$isProcessing) { processing in
            if processing {
                viewModel.awaitingTurnTranscript = true
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.bubbleVisible = true
                }
                turnStartedAt = Date()
                turnStartingToolCount = agentLoop.toolActivity.filter {
                    $0.toolName != "compaction" && $0.toolName != "prompt_compose"
                }.count
            } else {
                if hasProcessed {
                    BobSounds.playReceive()
                }
                if let start = turnStartedAt {
                    let elapsed = Date().timeIntervalSince(start)
                    let endCount = agentLoop.toolActivity.filter {
                        $0.toolName != "compaction" && $0.toolName != "prompt_compose"
                    }.count
                    let delta = endCount - turnStartingToolCount
                    let didRealWork = (delta >= 2) || (delta >= 1 && elapsed >= 15)
                    if didRealWork {
                        let text = GreetingLines.celebrationForPersona(personaStore.activePersonaID)
                        if !text.isEmpty {
                            systemNotices.append(SystemNotice(text: text, at: Date()))
                        }
                        BobSayings.play(Double.random(in: 0...1) < 0.6 ? .boast : .celebration)
                    }
                }
                turnStartedAt = nil
                viewModel.externallyHandledPromptDidFinish()
            }
        }
        .onReceive(agentLoop.$toolActivity) { activity in
            checkForCompaction(in: activity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bobNewChat)) { _ in
            session.startFreshConversation()
            systemNotices.removeAll(where: { $0.isGreeting })
            hasGreeted = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                maybeGreet()
            }
        }
        .onChange(of: viewModel.inputFocusRequestID) {
            inputFocused = true
        }
        .onChange(of: viewModel.chatOpenRequestID) {
            openWindow(id: "chat")
        }
        .onChange(of: viewModel.sendPromptRequestID) {
            if viewModel.prepareNextExternallyHandledPromptForSend() {
                sendWithSound()
            }
        }
        .onAppear {
            viewModel.drainPendingDeskPrompts()
            refreshFactCount()
            startMemoryRefreshTimer()
            refreshProcessMemory()
            startProcessMemoryTimer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                maybeGreet()
                updateBubbleForGreeting()
            }
            Heartbeat.shared.start(agentIsProcessing: { [agentLoop] in
                agentLoop.isProcessing
            })
            if !UserDefaults.standard.bool(forKey: OnboardingView.completionKey) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    openWindow(id: "onboarding")
                }
            }
        }
        .onDisappear {
            memoryRefreshTimer?.invalidate()
            memoryRefreshTimer = nil
            processMemoryTimer?.invalidate()
            processMemoryTimer = nil
            Heartbeat.shared.stop()
        }
        .onReceive(Heartbeat.shared.$lastNoticeAt) { at in
            guard let at, let text = Heartbeat.shared.lastNoticeText else { return }
            systemNotices.append(SystemNotice(text: text, at: at))
        }
    }

    // MARK: - Layouts

    private var fullLayout: some View {
        return VStack(spacing: 0) {
            WindowDragHandle()
                .frame(height: 18)

            if settings.showBob {
                portraitSection
                    .frame(height: 240)
                    .padding(.top, 4)
            }

            chatContainer
        }
    }

    private var avatarOnlyLayout: some View {
        ZStack {
            GeometryReader { proxy in
                let portrait: CGFloat = 160
                let inputSlot: CGFloat = 56
                let gapTop: CGFloat = 10
                let gapBubbleToBob: CGFloat = 10
                let gapBobToInput: CGFloat = 10
                let gapBottom: CGFloat = 12
                let reserved = portrait + inputSlot + gapTop + gapBubbleToBob + gapBobToInput + gapBottom
                let bubbleCap = max(Self.minBubbleHeight, proxy.size.height - reserved)

                VStack(spacing: 0) {
                    Spacer().frame(height: gapTop)

                    ZStack(alignment: .bottom) {
                        speechBubbleView(maxHeight: bubbleCap)
                            .opacity(viewModel.bubbleVisible || agentLoop.isProcessing ? 1 : 0)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.bubbleVisible)
                            .animation(.easeInOut(duration: 0.25), value: agentLoop.isProcessing)

                        historyToggleButton
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 6)
                            .padding(.trailing, 6)
                    }
                    .frame(maxWidth: 360, maxHeight: bubbleCap, alignment: .bottom)
                    .layoutPriority(0)

                    Spacer().frame(height: gapBubbleToBob)

                    draggablePortrait
                        .layoutPriority(2)

                    if uncensoredModeEnabled {
                        uncensoredConversationBadge
                            .padding(.top, 8)
                            .layoutPriority(1)
                    }
                    if isTaintActive { taintBanner.padding(.horizontal, 20).layoutPriority(1) }

                    Spacer().frame(height: gapBobToInput)

                    if shouldShowUncensoredBudgetBanner {
                        UncensoredBudgetBanner(snapshot: uncensoredBudgetSnapshot)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .layoutPriority(1)
                    }

                    compactInputBubble
                        .opacity(agentLoop.isProcessing ? 0.0 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: agentLoop.isProcessing)
                        .padding(.horizontal, 20)
                        .layoutPriority(2)

                    Spacer().frame(height: gapBottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                modelSwitchBanner
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                errorBanner
            }

            if viewModel.showHistoryOverlay {
                historyOverlay
            }
        }
    }

    private var draggablePortrait: some View {
        ZStack {
            bobPortrait
            WindowDragHandle()
        }
        .frame(height: 160)
    }

    // MARK: - Chat Container

    private var chatContainer: some View {
        VStack(spacing: 0) {
            statusLine
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            DeskStatusStrip(accent: Self.phosphorGreen)

            transcriptSection
                .frame(maxHeight: .infinity)

            Divider()
                .background(Self.phosphorGreen.opacity(0.15 * surfaceOpacity))

            if isTaintActive { taintBanner.padding(.horizontal, 16).padding(.vertical, 6) }

            if shouldShowUncensoredBudgetBanner {
                UncensoredBudgetBanner(snapshot: uncensoredBudgetSnapshot)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            inputRow
                .frame(height: 48)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Self.bgBlack.opacity(surfaceOpacity))
                .shadow(color: .black.opacity(0.4 * surfaceOpacity), radius: 12, x: 0, y: 4)
        )
    }

    private var taintBanner: some View {
        Label("Untrusted content in this turn — write actions disabled. Type `/lift` to clear.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.orange.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Portrait Section

    private var portraitSection: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                thoughtsOverlay
                    .allowsHitTesting(false)

                speechBubbleView(maxHeight: Self.portraitBubbleMaxHeight)
                    .opacity(viewModel.bubbleVisible || agentLoop.isProcessing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.bubbleVisible)
                    .animation(.easeInOut(duration: 0.25), value: agentLoop.isProcessing)
            }
            .frame(maxWidth: 360, minHeight: 56, maxHeight: Self.portraitBubbleMaxHeight)
            .padding(.bottom, 6)

            bobPortrait
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 3.5).repeatForever(autoreverses: true)
            ) {
                viewModel.breathPhase = true
            }
        }
    }

    private var bobPortrait: some View {
        let mood = agentLoop.bobMood
        let pack = avatarStore.effectivePack(activePersonaID: personaStore.activePersonaID)
        let tint = pack.id == AvatarPacks.classicRobot.id ? spriteAccent : Color.white

        return ZStack {
            if let nsImage = pack.image(for: mood) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .colorMultiply(tint)
                    .opacity(surfaceOpacity)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.bgPanel.opacity(surfaceOpacity))
                    .frame(width: 140, height: 200)
                    .overlay(
                        Text("\(pack.filePrefix)\(mood.rawValue)")
                            .font(.caption2)
                            .foregroundColor(Self.phosphorGreen.opacity(0.6 * textOpacity))
                    )
            }
        }
        .id(mood)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: mood)
        .scaleEffect(idleBreathScale(mood: mood))
        .animation(
            mood == .idle
                ? .easeInOut(duration: 3.5).repeatForever(autoreverses: true)
                : .easeInOut(duration: 0.25),
            value: viewModel.breathPhase
        )
    }

    private func idleBreathScale(mood: BobMood) -> CGFloat {
        guard mood == .idle else { return 1.0 }
        return viewModel.breathPhase ? 1.015 : 1.0
    }

    // MARK: - Thoughts Overlay

    private var thoughtsOverlay: some View {
        DeskThoughtsOverlay(
            toolActivity: agentLoop.toolActivity,
            isProcessing: agentLoop.isProcessing,
            textOpacity: textOpacity,
            phosphorGreen: Self.phosphorGreen
        )
    }

    // MARK: - Compact Input Bubble  (avatar-only mode)

    private var compactInputBubble: some View {
        DeskInputView(
            style: .compact,
            inputText: $session.inputText,
            inputFocused: $inputFocused,
            isProcessing: agentLoop.isProcessing,
            uncensoredModeAvailable: settings.uncensoredModeAvailable,
            uncensoredModeEnabled: uncensoredModeEnabled,
            uncensoredModeToggleDisabled: uncensoredModeToggleDisabled,
            uncensoredModeHelpText: uncensoredModeHelpText,
            surfaceOpacity: surfaceOpacity,
            textOpacity: textOpacity,
            phosphorGreen: Self.phosphorGreen,
            bgPanel: Self.bgPanel,
            bubbleFill: Self.bubbleFill,
            bubbleStroke: Self.bubbleStroke,
            onToggleUncensoredMode: { session.toggleConversationUncensoredMode() },
            onSend: sendWithSound
        )
    }

    private var uncensoredConversationBadge: some View {
        DeskUncensoredConversationBadge(
            helpText: "This conversation is marked uncensored. Configured tag: \(settings.effectiveUncensoredModelName)"
        )
    }

    // MARK: - History Overlay (Plan 2)

    private var historyToggleButton: some View {
        DeskHistoryToggleButton(
            bubbleVisible: viewModel.bubbleVisible,
            isProcessing: agentLoop.isProcessing,
            textOpacity: textOpacity,
            speechBubbleFill: Self.speechBubbleFill,
            speechBubbleStroke: Self.speechBubbleStroke,
            onToggle: viewModel.toggleHistoryOverlay
        )
    }

    private var historyOverlay: some View {
        DeskHistoryOverlay(
            isPresented: $viewModel.showHistoryOverlay,
            items: interleavedItemsCache,
            chatWindowOpacity: settings.chatWindowOpacity,
            richPresentationEnabled: settings.richPresentationEnabled,
            richPresentationArtifactChipsEnabled: settings.richPresentationArtifactChipsEnabled,
            surfaceOpacity: surfaceOpacity,
            textOpacity: textOpacity,
            bgPanel: Self.bgPanel,
            speechBubbleFill: Self.speechBubbleFill,
            speechBubbleStroke: Self.speechBubbleStroke
        )
    }

    // MARK: - Speech Bubble

    private static let minBubbleHeight: CGFloat = 56
    private static let portraitBubbleMaxHeight: CGFloat = 104

    private func speechBubbleView(maxHeight: CGFloat) -> some View {
        DeskSpeechBubbleView(
            preview: latestAssistantPreview,
            greetingText: latestGreetingLine ?? "",
            isProcessing: agentLoop.isProcessing,
            awaitingTurnTranscript: viewModel.awaitingTurnTranscript,
            bubbleVisible: viewModel.bubbleVisible,
            isAvatarOnly: settings.avatarOnlyMode,
            maxHeight: maxHeight,
            minHeight: Self.minBubbleHeight,
            textOpacity: textOpacity,
            speechBubbleFill: Self.speechBubbleFill,
            speechBubbleStroke: Self.speechBubbleStroke,
            tailAnchorX: Self.avatarBubbleTailAnchorX
        )
    }

    // MARK: - Status Line

    private var statusLine: some View {
        DeskStatusLine(
            currentModel: agentLoop.currentModel,
            statusWord: statusWord,
            totalMemoryLabel: totalMemoryLabel,
            factCount: factCount,
            contextFraction: contextFraction,
            contextColor: contextColor,
            textOpacity: textOpacity,
            phosphorGreen: Self.phosphorGreen,
            uncensoredModeEnabled: uncensoredModeEnabled,
            uncensoredHelpText: "This conversation is marked uncensored. Configured tag: \(settings.effectiveUncensoredModelName)",
            session: session,
            onOpenPreferences: { openWindow(id: "preferences") }
        )
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        DeskTranscriptView(
            autoScrollEnabled: $autoScrollEnabled,
            isNearBottom: $isNearBottom,
            items: interleavedItemsCache,
            transcriptRevision: session.transcriptRevision,
            chatWindowOpacity: settings.chatWindowOpacity,
            richPresentationEnabled: settings.richPresentationEnabled,
            richPresentationArtifactChipsEnabled: settings.richPresentationArtifactChipsEnabled,
            surfaceOpacity: surfaceOpacity,
            textOpacity: textOpacity,
            bgPanel: Self.bgPanel,
            topBanner: { modelSwitchBanner },
            bottomBanner: { errorBanner }
        )
    }

    // MARK: - Interleaving helpers (F1 + F4)

    private func rebuildInterleavedItems() {
        interleavedItemsCache = DeskTranscriptItem.interleaved(messages: session.messages, notices: systemNotices)
    }

    @ViewBuilder
    private var modelSwitchBanner: some View {
        DeskModelSwitchBanner(
            notice: $agentLoop.modelSwitchNotice,
            surfaceOpacity: surfaceOpacity,
            textOpacity: textOpacity,
            bgPanel: Self.bgPanel
        )
    }

    @ViewBuilder
    private var errorBanner: some View {
        DeskErrorBanner(
            errorMessage: session.errorMessage,
            surfaceOpacity: surfaceOpacity,
            textOpacity: textOpacity,
            bgPanel: Self.bgPanel,
            onDismiss: session.dismissError
        )
    }

    // MARK: - Input Row

    private var inputRow: some View {
        DeskInputView(
            style: .full,
            inputText: $session.inputText,
            inputFocused: $inputFocused,
            isProcessing: agentLoop.isProcessing,
            uncensoredModeAvailable: settings.uncensoredModeAvailable,
            uncensoredModeEnabled: uncensoredModeEnabled,
            uncensoredModeToggleDisabled: uncensoredModeToggleDisabled,
            uncensoredModeHelpText: uncensoredModeHelpText,
            surfaceOpacity: surfaceOpacity,
            textOpacity: textOpacity,
            phosphorGreen: Self.phosphorGreen,
            bgPanel: Self.bgPanel,
            bubbleFill: Self.bubbleFill,
            bubbleStroke: Self.bubbleStroke,
            onToggleUncensoredMode: { session.toggleConversationUncensoredMode() },
            onSend: sendWithSound
        )
    }

    private func sendWithSound() {
        let text = session.inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        autoScrollEnabled = true
        let isLocalCommand = text == "/clear" || text == "/new"
        if !isLocalCommand {
            BobSounds.playSend()
            hasProcessed = true
            if let last = lastSendAt, Date().timeIntervalSince(last) > 300 {
                BobSayings.play(.idleReturn)
            }
            lastSendAt = Date()
            Heartbeat.shared.registerActivity()
        }
        session.sendCurrentInput(allowsLocalCommands: true)
    }

    private func enforceMasterUncensoredSetting() {
        guard settings.uncensoredModeAvailable == false, session.conversationUncensoredMode else { return }
        session.setConversationUncensoredMode(false)
    }

    private func resetConversationScopedNoticeState() {
        systemNotices.removeAll()
        hasGreeted = false
        viewModel.awaitingTurnTranscript = false
        lastSeenToolActivityIndex = agentLoop.toolActivity.count
    }

    // MARK: - F1 Greeting

    private func maybeGreet() {
        guard !hasGreeted else { return }
        let hasRealMessages = !session.messages.filter({ $0.role != .system }).isEmpty
        guard !hasRealMessages else {
            hasGreeted = true
            return
        }
        let text = GreetingLines.forPersona(personaStore.activePersonaID)
        guard !text.isEmpty else {
            hasGreeted = true
            return
        }
        let notice = SystemNotice(text: text, at: Date(), isGreeting: true)
        systemNotices.append(notice)
        hasGreeted = true
        BobSayings.play(.greeting)
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.bubbleVisible = true
        }
    }

    private func updateBubbleForGreeting() {
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.bubbleVisible = shouldShowBubble
        }
    }

    // MARK: - F3 Memory count helpers

    private func refreshFactCount() {
        factCount = (try? DatabaseManager.shared.fetchFacts().count) ?? 0
    }

    private func startMemoryRefreshTimer() {
        memoryRefreshTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                self.refreshFactCount()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        memoryRefreshTimer = t
    }

    private func refreshProcessMemory() {
        Task {
            let snapshot = await ProcessMemorySampler.sample()
            await MainActor.run {
                let total: Int64? = {
                    switch (snapshot.bobBytes, snapshot.ollamaBytes) {
                    case let (b?, o?): return b + o
                    case let (b?, nil): return b
                    case let (nil, o?): return o
                    case (nil, nil):   return nil
                    }
                }()
                totalMemoryLabel = ProcessMemorySampler.format(total)
            }
        }
    }

    private func startProcessMemoryTimer() {
        processMemoryTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.refreshProcessMemory()
        }
        RunLoop.main.add(timer, forMode: .common)
        processMemoryTimer = timer
    }

    // MARK: - F4 Compaction detection

    private func checkForCompaction(in activity: [AgentLoop.ToolLogEntry]) {
        guard activity.count > lastSeenToolActivityIndex else { return }
        let newEntries = activity[lastSeenToolActivityIndex...]
        lastSeenToolActivityIndex = activity.count
        for entry in newEntries where entry.toolName == "compaction" {
            let notice = SystemNotice(
                text: "\u{2014} compacted older turns to free up context \u{2014}",
                at: entry.timestamp,
                isGreeting: false
            )
            systemNotices.append(notice)
        }
    }
}

extension Notification.Name {
    static let bobNewChat = Notification.Name("com.ollamabob.newChat")
    static let bobToggleHistoryOverlay = Notification.Name("com.ollamabob.toggleHistoryOverlay")
}
