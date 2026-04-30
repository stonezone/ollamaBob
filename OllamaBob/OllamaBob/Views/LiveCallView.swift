import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Live Call window: outbound-only call composition + supervision.
///
/// Sections:
/// 1. Compose — pick persona, destination (alias or raw number), purpose,
///    optional context (typed or imported from a `.txt` file), max duration.
/// 2. Active calls — picker + summary row + hangup button.
/// 3. Transcript — design-system styled bubbles, auto-scrolling, refreshes
///    every 5s while a call is selected.
/// 4. Inject — free-form text field plus three quick-suggestion chips. Same
///    approval policy as `phone_inject` tool dispatch.
struct LiveCallView: View {
    // Calls + transcript state
    @State private var calls: [JarvisCallSummary] = []
    @State private var selectedCallID: String? = nil
    @State private var transcript: JarvisTranscript? = nil
    @State private var statusMessage: String = "Loading calls…"
    @State private var isRefreshing = false
    @State private var transcriptRefreshTask: Task<Void, Never>?

    // Post-call action items state. Populated once the selected call has
    // reached `ended` and the daemon's GET /call/action-items/:id returns.
    // Keyed by callID so switching between recent ended calls doesn't
    // reset the data each time.
    @State private var actionItemsByCallID: [String: JarvisCallActionItems] = [:]
    @State private var actionItemsLoadingForCallID: String? = nil

    // Compose state
    @State private var composePersona: String = "bob"
    @State private var composeAlias: String = ""              // selected alias from picker
    @State private var composeNumber: String = ""              // free-form number override
    @State private var composePurpose: String = ""
    @State private var composeContext: String = ""
    @State private var composeMaxMinutes: Int = 10
    @State private var composeIsBusy = false
    @State private var composeIsExpanded = true
    @State private var composeError: String?

    // Inject state
    @State private var injectText: String = ""
    @State private var injectIsBusy = false
    @State private var lastInjectionFeedback: InjectionFeedback?
    @State private var injectionFeedbackHideTask: Task<Void, Never>?

    private struct InjectionFeedback {
        let text: String
        let success: Bool
        let detail: String?
    }

    // Hangup state
    @State private var hangupIsBusy = false

    private let suggestedInjections = [
        "Got it, thanks.",
        "Can you say more about that?",
        "Let me check and get back to you."
    ]

    private let personaOptions = ["bob", "buddy", "zack", "glennel"]
    private let durationOptions = [3, 5, 10, 15, 20]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: BobSpacing.md) {
                    Spacer().frame(height: BobSpacing.sm)
                    liveCallHeader
                    composeSection
                    Divider()
                    callHeaderSection
                    if selectedCallID != nil {
                        Divider()
                        transcriptSection
                        actionItemsSection
                    }
                }
                .padding(BobSpacing.md)
            }

            if selectedCallID != nil {
                Divider()
                injectSection
                    .padding(.horizontal, BobSpacing.md)
                    .padding(.vertical, BobSpacing.sm)
                    .background(.ultraThinMaterial)
            }
        }
        .frame(minWidth: 520, minHeight: 520)
        .background(BobColors.Surface.canvas.opacity(0.0))
        .background(LiveCallWindowChrome())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task { await refresh() }
        .onAppear { startTranscriptRefresh() }
        .onDisappear { stopTranscriptRefresh() }
    }

    private var liveCallHeader: some View {
        VStack(alignment: .leading, spacing: BobSpacing.xs) {
            HStack(spacing: BobSpacing.sm) {
                Image(systemName: "phone.connection.fill")
                    .foregroundStyle(BobColors.Signal.success)
                    .font(.system(size: 14))
                Text("Live Call")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BobColors.Text.onGlass)
                Spacer()
            }
            .padding(.horizontal, BobSpacing.xs)

            mockBannerIfActive
        }
    }

    @ViewBuilder
    private var mockBannerIfActive: some View {
        #if DEBUG
        if AppSettings.shared.useMockedJarvisClient {
            HStack(spacing: BobSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BobColors.Signal.warn)
                Text("Mock client is on — calls below are canned fixtures, not real Jarvis calls.")
                    .font(.system(size: 11))
                    .foregroundStyle(BobColors.Text.onGlass)
                Spacer(minLength: 8)
                Button("Switch to live") {
                    AppSettings.shared.useMockedJarvisClient = false
                    Task { await refresh() }
                }
                .buttonStyle(BobButtonStyle(kind: .secondary))
                .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, BobSpacing.sm)
            .padding(.vertical, BobSpacing.xs + 2)
            .background(BobColors.Signal.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: BobRadii.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BobRadii.md, style: .continuous)
                    .stroke(BobColors.Signal.warn.opacity(0.5), lineWidth: 0.6)
            )
        }
        #endif
    }

    // MARK: - Compose

    private var composeSection: some View {
        GlassSurface(role: .bubble, cornerRadius: BobRadii.lg) {
            VStack(alignment: .leading, spacing: BobSpacing.sm) {
                composeHeader
                if composeIsExpanded {
                    composeFields
                }
            }
            .padding(BobSpacing.md)
        }
    }

    private var composeHeader: some View {
        HStack {
            Image(systemName: "phone.arrow.up.right.fill")
                .foregroundStyle(BobColors.Signal.success)
            Text("Place a call")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BobColors.Text.onGlass)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { composeIsExpanded.toggle() }
            } label: {
                Image(systemName: composeIsExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(BobColors.Text.onGlassSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var composeFields: some View {
        VStack(alignment: .leading, spacing: BobSpacing.sm) {
            personaAndDestinationRow
            destinationRow
            purposeRow
            contextRow
            durationAndSubmitRow
            if let composeError {
                Text(composeError)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BobColors.Signal.danger)
            }
        }
    }

    private var personaAndDestinationRow: some View {
        HStack(spacing: BobSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Persona")
                Picker("", selection: $composePersona) {
                    ForEach(personaOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Contact")
                Picker("", selection: $composeAlias) {
                    Text("— Custom number —").tag("")
                    ForEach(LocalAddressBook.allEntries(), id: \.alias) { entry in
                        Text("\(entry.alias) (\(entry.number))").tag(entry.alias)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .onChange(of: composeAlias) {
                    if !composeAlias.isEmpty,
                       let resolved = LocalAddressBook.value(for: composeAlias) {
                        composeNumber = resolved
                    }
                }
            }
        }
    }

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Number")
            TextField("+15551234567 or alias", text: $composeNumber)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var purposeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Purpose (optional)")
            TextField("Defaults to a generic personal call.", text: $composePurpose)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var contextRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                fieldLabel("Context for \(composePersona) (optional)")
                Spacer()
                Button {
                    importContextFromFile()
                } label: {
                    Label("Import .txt", systemImage: "doc.text")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BobColors.Accent.bobBlue)

                if !composeContext.isEmpty {
                    Button("Clear") { composeContext = "" }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(BobColors.Text.onGlassSecondary)
                }
            }
            TextEditor(text: $composeContext)
                .font(.system(size: 12))
                .frame(minHeight: 60, maxHeight: 140)
                .padding(4)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(BobColors.Glass.strokeOutline, lineWidth: 0.5)
                )
            if composeContext.isEmpty {
                Text("Paste anything you want the persona to know — meeting notes, order numbers, prior conversation, etc.")
                    .font(.system(size: 10))
                    .foregroundStyle(BobColors.Text.onGlassSecondary)
            } else {
                Text("\(composeContext.count) chars attached")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BobColors.Text.onGlassSecondary)
            }
        }
    }

    private var durationAndSubmitRow: some View {
        HStack(alignment: .bottom, spacing: BobSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Max duration")
                Picker("", selection: $composeMaxMinutes) {
                    ForEach(durationOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 110)
            }

            Spacer()

            Button {
                Task { await placeCall() }
            } label: {
                HStack(spacing: 6) {
                    if composeIsBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "phone.fill")
                    }
                    Text(composeIsBusy ? "Placing call…" : "Place call")
                }
            }
            .buttonStyle(BobButtonStyle(kind: .primary))
            .disabled(!canPlaceCall || composeIsBusy)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(BobColors.Text.onGlassSecondary)
    }

    private var canPlaceCall: Bool {
        // Number is required; purpose is required by PhoneTool.execute too
        // but if blank we'll fall back to a generic purpose so the user
        // can place a call with just a number + optional context. This
        // mirrors how a phone-app dial pad behaves: hit dial, talk.
        !composeNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var effectivePurpose: String {
        let p = composePurpose.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? "Personal call from \(composePersona)." : p
    }

    private func importContextFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text, .utf8PlainText]
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Append rather than overwrite if there's already context — users
            // may want to combine pasted notes with imported transcripts.
            if composeContext.trimmingCharacters(in: .whitespaces).isEmpty {
                composeContext = text
            } else {
                composeContext += "\n\n--- \(url.lastPathComponent) ---\n\(text)"
            }
        } catch {
            composeError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func placeCall() async {
        composeError = nil
        composeIsBusy = true
        defer { composeIsBusy = false }

        let trimmedContext = composeContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await PhoneTool.execute(
            persona: composePersona,
            to: composeNumber,
            purpose: effectivePurpose,
            maxMinutes: composeMaxMinutes,
            context: trimmedContext.isEmpty ? nil : trimmedContext
        )

        if result.success {
            // Clear ephemeral compose fields so a fresh call starts clean.
            composeNumber = ""
            composeAlias = ""
            composePurpose = ""
            composeContext = ""
            // Refresh active calls list so the new call appears.
            await refresh()
        } else {
            composeError = result.content
        }
    }

    // MARK: - Active Calls Header

    private var callHeaderSection: some View {
        VStack(alignment: .leading, spacing: BobSpacing.sm) {
            HStack {
                Image(systemName: "phone.fill")
                    .foregroundStyle(BobColors.Signal.success)
                Text("Active calls")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BobColors.Text.onGlass)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        .foregroundStyle(BobColors.Text.onGlassSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh active calls")
            }

            if calls.isEmpty {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(BobColors.Text.onGlassSecondary)
            } else {
                Picker("Call", selection: $selectedCallID) {
                    ForEach(calls, id: \.callID) { call in
                        Text("\(call.to) — \(call.status) (\(call.durationSeconds)s)")
                            .tag(Optional(call.callID))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedCallID) {
                    Task { await loadTranscript() }
                }

                if let callID = selectedCallID,
                   let call = calls.first(where: { $0.callID == callID }) {
                    callSummaryRow(call)
                }
            }
        }
    }

    private func callSummaryRow(_ call: JarvisCallSummary) -> some View {
        HStack(spacing: BobSpacing.md) {
            BobChip(
                label: "To: \(call.to)",
                tint: BobColors.Text.onGlassSecondary
            ) { Image(systemName: "person.fill") }

            BobChip(
                label: "Persona: \(call.persona)",
                tint: BobColors.Accent.bobBlue
            ) { Image(systemName: "theatermasks.fill") }

            BobChip(
                label: call.status,
                tint: statusColor(call.status),
                isProminent: true
            ) { Image(systemName: statusIcon(call.status)) }

            Text("\(call.durationSeconds)s")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BobColors.Text.onGlassSecondary)

            Spacer()

            if call.status != "ended" {
                Button {
                    Task { await hangup(callID: call.callID) }
                } label: {
                    HStack(spacing: 4) {
                        if hangupIsBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "phone.down.fill")
                        }
                        Text("Hang up")
                    }
                }
                .buttonStyle(BobButtonStyle(kind: .secondary))
                .disabled(hangupIsBusy)
            }
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if let transcript {
                        ForEach(Array(transcript.lines.enumerated()), id: \.offset) { index, line in
                            transcriptBubble(line)
                                .id(index)
                        }
                    } else {
                        Text(selectedCallID == nil ? "Select a call above" : "No transcript yet.")
                            .foregroundStyle(BobColors.Text.onGlassSecondary)
                            .padding()
                    }
                }
                .padding(.vertical, BobSpacing.xs)
            }
            .frame(minHeight: 200, maxHeight: 320)
            .onChange(of: transcript?.lines.count) {
                if let last = transcript?.lines.indices.last {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func transcriptBubble(_ line: JarvisTranscript.Line) -> some View {
        let isCaller = line.speaker == "caller"
        return HStack {
            if isCaller { Spacer(minLength: 40) }
            BobBubble(role: isCaller ? .user : .assistant, tailAnchorX: nil, cornerRadius: BobRadii.md) {
                Text(line.text)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(maxWidth: 360, alignment: isCaller ? .trailing : .leading)
            if !isCaller { Spacer(minLength: 40) }
        }
    }

    // MARK: - Action Items ("Bob noticed:")

    /// Renders the post-call extraction once the daemon's
    /// `GET /call/action-items/:id` returns. Empty view while the call is
    /// still in flight, while extraction is loading, or when the call
    /// produced no items (too short, voicemail, model returned nothing).
    @ViewBuilder
    private var actionItemsSection: some View {
        if let callID = selectedCallID,
           let call = calls.first(where: { $0.callID == callID }),
           call.status == "ended",
           let items = actionItemsByCallID[callID],
           items.followUps.isEmpty == false || items.outcome.isEmpty == false {
            Divider()
            VStack(alignment: .leading, spacing: BobSpacing.sm) {
                HStack(spacing: BobSpacing.xs + 2) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(BobColors.Signal.warn)
                    Text("Bob noticed:")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BobColors.Text.onGlass)
                }

                if items.outcome.isEmpty == false {
                    Text(items.outcome)
                        .font(.system(size: 12))
                        .foregroundStyle(BobColors.Text.onGlassSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(items.followUps, id: \.self) { item in
                    HStack(alignment: .top, spacing: BobSpacing.xs + 2) {
                        Text("•")
                            .foregroundStyle(BobColors.Signal.success)
                        Text(item)
                            .font(.system(size: 12))
                            .foregroundStyle(BobColors.Text.onGlass)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if items.facts.isEmpty == false {
                    Text("Facts: \(items.facts.joined(separator: " · "))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(BobColors.Text.onGlassSecondary)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, BobSpacing.xs + 2)
            .task(id: callID) { await fetchActionItemsIfNeeded(for: callID) }
        } else if let callID = selectedCallID,
                  let call = calls.first(where: { $0.callID == callID }),
                  call.status == "ended" {
            // Triggers the fetch even when nothing has been cached yet, so
            // a freshly-ended call has its action items loaded the first
            // time the user looks at it.
            Color.clear
                .frame(height: 0)
                .task(id: callID) { await fetchActionItemsIfNeeded(for: callID) }
        }
    }

    private func fetchActionItemsIfNeeded(for callID: String) async {
        if actionItemsByCallID[callID] != nil { return }
        if actionItemsLoadingForCallID == callID { return }
        actionItemsLoadingForCallID = callID
        defer { actionItemsLoadingForCallID = nil }

        let client = JarvisCallClientFactory.current()
        do {
            if let items = try await client.actionItems(callID: callID) {
                await MainActor.run {
                    actionItemsByCallID[callID] = items
                }
            }
        } catch {
            // 404 / not-yet-ready surfaces as nil from the client; other
            // errors are logged but don't block the UI.
        }
    }

    // MARK: - Inject

    private var injectSection: some View {
        VStack(alignment: .leading, spacing: BobSpacing.xs + 2) {
            HStack(spacing: BobSpacing.sm) {
                Text("Inject mid-call")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BobColors.Text.onGlassSecondary)
                Spacer()
                if let feedback = lastInjectionFeedback {
                    HStack(spacing: 4) {
                        Image(systemName: feedback.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(feedback.success ? BobColors.Signal.success : BobColors.Signal.danger)
                        Text(feedback.success ? "Sent: \"\(feedback.text)\"" : "Failed: \(feedback.detail ?? feedback.text)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(feedback.success ? BobColors.Signal.success : BobColors.Signal.danger)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            HStack(spacing: BobSpacing.sm) {
                TextField("Type anything to send mid-call…", text: $injectText, axis: .horizontal)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { handleCustomInjection() }

                Button {
                    handleCustomInjection()
                } label: {
                    HStack(spacing: 4) {
                        if injectIsBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Inject")
                    }
                }
                .buttonStyle(BobButtonStyle(kind: .primary))
                .disabled(injectText.trimmingCharacters(in: .whitespaces).isEmpty || selectedCallID == nil || injectIsBusy)
                .keyboardShortcut(.return, modifiers: [])
            }

            HStack(spacing: 6) {
                Text("Quick:")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BobColors.Text.onGlassSecondary)
                ForEach(suggestedInjections, id: \.self) { suggestion in
                    Button(suggestion) {
                        injectText = suggestion
                        handleCustomInjection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selectedCallID == nil || injectIsBusy)
                }
                Spacer()
            }
        }
    }

    private func handleCustomInjection() {
        let trimmed = injectText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let callID = selectedCallID else { return }

        // The user clicking "Inject" on a call they themselves placed is
        // explicit consent — no modal needed. The blocking NSAlert can land
        // off-screen from a non-frontmost window and lock the app, so we
        // route UI-initiated injections through the policy without the
        // modal step. Tool-dispatched `phone_inject` from Bob's agent loop
        // still goes through the full ApprovalAlert path elsewhere.
        let args: [String: Any] = ["call_id": callID, "text": trimmed]
        let approval = ApprovalPolicy.check(toolName: "phone_inject", arguments: args)
        if approval == .forbidden {
            recordInjection(text: trimmed, success: false, detail: "Blocked by tool policy.")
            return
        }

        injectIsBusy = true
        Task {
            let result = await PhoneInjectTool.execute(callID: callID, text: trimmed)
            try? DatabaseManager.shared.appendExecutionLog(
                toolName: "phone_inject",
                approvalLevel: approval,
                summary: result.content,
                success: result.success,
                durationMs: result.durationMs
            )

            await MainActor.run {
                injectIsBusy = false
                recordInjection(text: trimmed, success: result.success, detail: result.success ? nil : result.content)
                if result.success {
                    injectText = ""
                }
            }
            if result.success { await loadTranscript() }
        }
    }

    private func recordInjection(text: String, success: Bool, detail: String?) {
        lastInjectionFeedback = InjectionFeedback(text: text, success: success, detail: detail)
        injectionFeedbackHideTask?.cancel()
        injectionFeedbackHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                lastInjectionFeedback = nil
            }
        }
    }

    // MARK: - Hangup

    private func hangup(callID: String) async {
        hangupIsBusy = true
        defer { hangupIsBusy = false }
        let result = await PhoneTool.hangup(callID: callID)
        try? DatabaseManager.shared.appendExecutionLog(
            toolName: "phone_hangup",
            approvalLevel: .none,
            summary: result.content,
            success: result.success,
            durationMs: result.durationMs
        )
        await refresh()
    }

    // MARK: - Refresh

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let client = JarvisCallClientFactory.current()
        do {
            let fetched = try await client.listCalls()
            await MainActor.run {
                calls = fetched
                if fetched.isEmpty {
                    statusMessage = "No active calls. Compose one above."
                    selectedCallID = nil
                    transcript = nil
                } else if selectedCallID == nil ||
                            !fetched.contains(where: { $0.callID == selectedCallID }) {
                    selectedCallID = fetched.first?.callID
                }
            }
            await loadTranscript()
        } catch let error as JarvisCallClientError {
            await MainActor.run { statusMessage = error.localizedDescription }
        } catch {
            await MainActor.run { statusMessage = error.localizedDescription }
        }
    }

    private func loadTranscript() async {
        guard let callID = selectedCallID else { return }
        let client = JarvisCallClientFactory.current()
        do {
            let t = try await client.transcript(callID: callID)
            await MainActor.run { transcript = t }
        } catch {
            await MainActor.run { transcript = nil }
        }
    }

    private func startTranscriptRefresh() {
        transcriptRefreshTask?.cancel()
        transcriptRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch { break }
                guard selectedCallID != nil else { continue }
                await loadTranscript()
            }
        }
    }

    private func stopTranscriptRefresh() {
        transcriptRefreshTask?.cancel()
        transcriptRefreshTask = nil
    }

    private func showInjectionError(_ message: String) {
        let errAlert = NSAlert()
        errAlert.messageText = "Injection failed"
        errAlert.informativeText = message
        errAlert.alertStyle = .warning
        errAlert.runModal()
    }

    // MARK: - Helpers

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "ringing":     return "phone.arrow.up.right"
        case "in_progress": return "phone.fill"
        case "ended":       return "phone.down.fill"
        default:            return "phone"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ringing":     return BobColors.Signal.warn
        case "in_progress": return BobColors.Signal.success
        case "ended":       return BobColors.Text.onGlassSecondary
        default:            return BobColors.Text.onGlassSecondary
        }
    }
}

// MARK: - Window Chrome

/// Strips the Live Call window's titlebar + opaque background so the
/// SwiftUI Liquid-Glass content shows through to the desktop, matching
/// Bob's Desk's chrome-less aesthetic.
private struct LiveCallWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.titled)
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.insert(.resizable)
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
            if let content = window.contentView {
                content.wantsLayer = true
                content.layer?.backgroundColor = nil
                content.layer?.isOpaque = false
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
