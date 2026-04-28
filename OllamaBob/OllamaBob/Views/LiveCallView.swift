import SwiftUI

// MARK: - LiveCallView
// Phase 4a: call supervision window.
// Renders a call summary header, live transcript scroll, and
// suggested-injection buttons (static Phase 4a placeholders).
// Each injection button is approval-gated via the normal tool path.

struct LiveCallView: View {
    @State private var calls: [JarvisCallSummary] = []
    @State private var selectedCallID: String? = nil
    @State private var transcript: JarvisTranscript? = nil
    @State private var statusMessage: String = "Loading calls…"
    @State private var isRefreshing = false

    // Phase 4a static suggested injections — Phase 4b will swap to model-generated
    private let suggestedInjections = [
        "Got it, thanks.",
        "Can you say more about that?",
        "Let me check and get back to you."
    ]

    var body: some View {
        VStack(spacing: 0) {
            callHeaderSection
            Divider()
            transcriptSection
            Divider()
            suggestedInjectionsSection
        }
        .frame(minWidth: 480, minHeight: 420)
        .task { await refresh() }
    }

    // MARK: - Call Header

    private var callHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "phone.fill")
                    .foregroundColor(.green)
                Text("Live Call")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.borderless)
                .help("Refresh calls and transcript")
            }

            if calls.isEmpty {
                Text(statusMessage)
                    .foregroundColor(.secondary)
                    .font(.callout)
            } else {
                Picker("Call", selection: $selectedCallID) {
                    ForEach(calls, id: \.callID) { call in
                        Text("\(call.to) — \(call.status) (\(call.durationSeconds)s)")
                            .tag(Optional(call.callID))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedCallID) { _ in
                    Task { await loadTranscript() }
                }

                if let callID = selectedCallID,
                   let call = calls.first(where: { $0.callID == callID }) {
                    callSummaryRow(call)
                }
            }
        }
        .padding()
    }

    private func callSummaryRow(_ call: JarvisCallSummary) -> some View {
        HStack(spacing: 16) {
            Label("To: \(call.to)", systemImage: "person.fill")
            Label("Persona: \(call.persona)", systemImage: "theatermasks.fill")
            Label(call.status, systemImage: statusIcon(call.status))
                .foregroundColor(statusColor(call.status))
            Text("\(call.durationSeconds)s")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .font(.callout)
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if let transcript = transcript {
                        ForEach(Array(transcript.lines.enumerated()), id: \.offset) { index, line in
                            transcriptBubble(line, id: index)
                                .id(index)
                        }
                    } else {
                        Text(selectedCallID == nil ? "Select a call above" : "No transcript yet.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding()
            }
            .frame(minHeight: 180)
            .onChange(of: transcript?.lines.count) { _ in
                if let last = transcript?.lines.indices.last {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func transcriptBubble(_ line: JarvisTranscript.Line, id: Int) -> some View {
        let isCaller = line.speaker == "caller"
        return HStack {
            if isCaller { Spacer(minLength: 40) }
            Text(line.text)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(isCaller ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isCaller ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
            if !isCaller { Spacer(minLength: 40) }
        }
    }

    // MARK: - Suggested Injections

    private var suggestedInjectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Injections")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            HStack(spacing: 8) {
                ForEach(suggestedInjections, id: \.self) { suggestion in
                    Button(suggestion) {
                        handleSuggestedInjection(suggestion)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedCallID == nil)
                    .font(.callout)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await MainActor.run {
            calls = []
            transcript = nil
            statusMessage = "Loading calls…"
        }

        let client = JarvisCallClientFactory.current()
        do {
            let fetched = try await client.listCalls()
            await MainActor.run {
                calls = fetched
                if fetched.isEmpty {
                    statusMessage = "No active calls."
                } else if selectedCallID == nil {
                    selectedCallID = fetched.first?.callID
                }
            }
            await loadTranscript()
        } catch let error as JarvisCallClientError {
            await MainActor.run {
                statusMessage = error.localizedDescription
            }
        } catch {
            await MainActor.run {
                statusMessage = error.localizedDescription
            }
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

    /// Injection is handled through the approval gate in the normal agent tool path.
    /// In the Live Call window we show an NSAlert to confirm before constructing a
    /// ToolCall — in Phase 4a the button fires a direct client call via the factory
    /// after confirming with a quick alert. The approval modal text mirrors what
    /// the agent would show.
    private func handleSuggestedInjection(_ text: String) {
        guard let callID = selectedCallID,
              let call = calls.first(where: { $0.callID == callID }) else { return }

        let lastLine = transcript?.lines.last?.text ?? "(no transcript yet)"

        let alert = NSAlert()
        alert.messageText = "Inject into active call?"
        alert.informativeText = "Call to: \(call.to)\nLast transcript line: \(lastLine)\n\nInject: \"\(text)\""
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Inject")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        Task {
            let client = JarvisCallClientFactory.current()
            do {
                _ = try await client.inject(callID: callID, text: text)
                await loadTranscript()
            } catch {
                // Surface error quietly for Phase 4a
                await MainActor.run {
                    let errAlert = NSAlert()
                    errAlert.messageText = "Injection failed"
                    errAlert.informativeText = error.localizedDescription
                    errAlert.alertStyle = .warning
                    errAlert.runModal()
                }
            }
        }
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
        case "ringing":     return .orange
        case "in_progress": return .green
        case "ended":       return .secondary
        default:            return .secondary
        }
    }
}
