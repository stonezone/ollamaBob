import SwiftUI

/// Lightweight in-memory overlay item rendered inline in the transcript.
/// Never persisted to the database.
struct SystemNotice: Identifiable {
    let id = UUID()
    let text: String
    let at: Date
    var isGreeting: Bool = false
}

enum DeskTranscriptItemContent {
    case message(ChatMessage)
    case notice(SystemNotice)
}

struct DeskTranscriptItem: Identifiable {
    let id: String
    let timestamp: Date
    let content: DeskTranscriptItemContent

    static func interleaved(messages: [ChatMessage], notices: [SystemNotice]) -> [DeskTranscriptItem] {
        var items: [DeskTranscriptItem] = []
        items.reserveCapacity(messages.count + notices.count)
        for msg in messages {
            items.append(DeskTranscriptItem(id: msg.id, timestamp: msg.timestamp, content: .message(msg)))
        }
        for notice in notices {
            items.append(DeskTranscriptItem(id: notice.id.uuidString, timestamp: notice.at, content: .notice(notice)))
        }
        return items.sorted { $0.timestamp < $1.timestamp }
    }
}

private struct ScrollContentBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DeskTranscriptView<TopBanner: View, BottomBanner: View>: View {
    @Binding var autoScrollEnabled: Bool
    @Binding var isNearBottom: Bool

    let items: [DeskTranscriptItem]
    let transcriptRevision: Int
    let chatWindowOpacity: Double
    let richPresentationEnabled: Bool
    let richPresentationArtifactChipsEnabled: Bool
    let surfaceOpacity: Double
    let textOpacity: Double
    let bgPanel: Color
    let topBanner: () -> TopBanner
    let bottomBanner: () -> BottomBanner

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { scrollProxy in
                let scrollViewHeight = scrollProxy.size.height
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(items) { item in
                                row(for: item)
                            }
                        }
                        .padding(.vertical, 8)

                        GeometryReader { contentProxy in
                            Color.clear
                                .preference(
                                    key: ScrollContentBottomKey.self,
                                    value: contentProxy.frame(in: .named("transcriptScroll")).maxY
                                )
                        }
                        .frame(height: 0)
                    }
                    .coordinateSpace(name: "transcriptScroll")
                    .onPreferenceChange(ScrollContentBottomKey.self) { contentBottom in
                        let newIsNearBottom = contentBottom <= scrollViewHeight + 50
                        if !newIsNearBottom && isNearBottom {
                            autoScrollEnabled = false
                        }
                        isNearBottom = newIsNearBottom
                    }
                    .onChange(of: transcriptRevision) {
                        guard autoScrollEnabled && isNearBottom else { return }
                        withAnimation {
                            if let lastID = items.last?.id {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }

                    if autoScrollEnabled == false {
                        Button {
                            autoScrollEnabled = true
                            withAnimation {
                                if let lastID = items.last?.id {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        } label: {
                            Label("Jump to latest", systemImage: "arrow.down.circle.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(bgPanel.opacity(surfaceOpacity * 0.95))
                                .clipShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .safeAreaInset(edge: .top, spacing: 0) {
            topBanner()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBanner()
        }
    }

    @ViewBuilder
    private func row(for item: DeskTranscriptItem) -> some View {
        switch item.content {
        case .message(let msg):
            if Self.shouldShowInTranscript(msg) {
                ChatBubble(
                    message: msg,
                    chatWindowOpacity: chatWindowOpacity,
                    richPresentationEnabled: richPresentationEnabled,
                    richPresentationArtifactChipsEnabled: richPresentationArtifactChipsEnabled
                )
                .id(msg.id)
            }
        case .notice(let notice):
            systemNoticeRow(notice)
                .id(notice.id.uuidString)
        }
    }

    @ViewBuilder
    private func systemNoticeRow(_ notice: SystemNotice) -> some View {
        if notice.isGreeting {
            HStack {
                Spacer(minLength: 0)
                Text(notice.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85 * textOpacity))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(bgPanel.opacity(surfaceOpacity))
                    )
                Spacer(minLength: 0)
            }
        } else {
            HStack {
                Spacer()
                Text(notice.text)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(Color.white.opacity(0.30 * textOpacity))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                Spacer()
            }
        }
    }

    /// Pure tool-invocation wrappers (assistant turn with only tool_calls, no
    /// visible body) live in the thoughts overlay. Everything else stays visible.
    static func shouldShowInTranscript(_ msg: ChatMessage) -> Bool {
        switch msg.role {
        case .system: return false
        case .tool: return true
        case .user: return true
        case .assistant:
            let body = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty, let calls = msg.toolCalls, !calls.isEmpty {
                return false
            }
            return true
        }
    }
}

struct DeskHistoryOverlay: View {
    @Binding var isPresented: Bool

    let items: [DeskTranscriptItem]
    let chatWindowOpacity: Double
    let richPresentationEnabled: Bool
    let richPresentationArtifactChipsEnabled: Bool
    let surfaceOpacity: Double
    let textOpacity: Double
    let bgPanel: Color
    let speechBubbleFill: Color
    let speechBubbleStroke: Color

    var body: some View {
        ZStack(alignment: .center) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text("History")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.black.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Divider()
                    .background(speechBubbleStroke)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            row(for: item)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: 340, maxHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(speechBubbleFill.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(speechBubbleStroke, lineWidth: 0.9)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 5)
            .padding(.horizontal, 16)

            Button("") { isPresented = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func row(for item: DeskTranscriptItem) -> some View {
        switch item.content {
        case .message(let msg):
            if DeskTranscriptView<EmptyView, EmptyView>.shouldShowInTranscript(msg) {
                ChatBubble(
                    message: msg,
                    chatWindowOpacity: chatWindowOpacity,
                    richPresentationEnabled: richPresentationEnabled,
                    richPresentationArtifactChipsEnabled: richPresentationArtifactChipsEnabled
                )
                .id(msg.id)
            }
        case .notice(let notice):
            systemNoticeRow(notice)
                .id(notice.id.uuidString)
        }
    }

    @ViewBuilder
    private func systemNoticeRow(_ notice: SystemNotice) -> some View {
        if notice.isGreeting {
            HStack {
                Spacer(minLength: 0)
                Text(notice.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85 * textOpacity))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(bgPanel.opacity(surfaceOpacity))
                    )
                Spacer(minLength: 0)
            }
        } else {
            HStack {
                Spacer()
                Text(notice.text)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(Color.white.opacity(0.30 * textOpacity))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                Spacer()
            }
        }
    }
}

struct DeskHistoryToggleButton: View {
    let bubbleVisible: Bool
    let isProcessing: Bool
    let textOpacity: Double
    let speechBubbleFill: Color
    let speechBubbleStroke: Color
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.black.opacity(0.45 * textOpacity))
                .padding(5)
                .background(
                    Circle()
                        .fill(speechBubbleFill)
                        .overlay(Circle().stroke(speechBubbleStroke, lineWidth: 0.6))
                )
        }
        .buttonStyle(.plain)
        .opacity(bubbleVisible || isProcessing ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: bubbleVisible)
        .help("Show conversation history")
    }
}

struct DeskThoughtsOverlay: View {
    let toolActivity: [AgentLoop.ToolLogEntry]
    let isProcessing: Bool
    let textOpacity: Double
    let phosphorGreen: Color

    var body: some View {
        let lines = currentThoughtLines
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                let ageRatio = Double(idx) / Double(max(lines.count - 1, 1))
                let opacity = 0.25 + 0.55 * ageRatio
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(phosphorGreen.opacity(opacity * textOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isProcessing ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isProcessing)
        .animation(.easeInOut(duration: 0.25), value: lines)
    }

    private var currentThoughtLines: [String] {
        let recent = toolActivity
            .filter { $0.toolName != "compaction" && $0.toolName != "prompt_compose" }
            .suffix(3)
        var lines = recent.map { entry in
            let input = entry.input.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = input.isEmpty ? "" : " \(input)"
            let line = "⚡ \(entry.toolName)\(summary)"
            return line.count > 80 ? String(line.prefix(80)) + "…" : line
        }
        if isProcessing && lines.isEmpty {
            lines = ["⚡ thinking…"]
        }
        return lines
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                dot(phase: t * 1.6)
                dot(phase: t * 1.6 + 0.25)
                dot(phase: t * 1.6 + 0.5)
            }
        }
    }

    private func dot(phase: Double) -> some View {
        let cycle = phase.truncatingRemainder(dividingBy: 1.0)
        let wave = 0.5 + 0.5 * sin(cycle * 2 * .pi)
        let scale = 0.65 + 0.35 * wave
        let opacity = 0.35 + 0.65 * wave
        return Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.35),
                        Color.black
                    ]),
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 1,
                    endRadius: 8
                )
            )
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 3, height: 3)
                    .offset(x: -1.5, y: -1.5)
            )
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

struct DeskSpeechBubbleView: View {
    let preview: ChatBubbleRendering.AvatarPreview?
    let greetingText: String
    let isProcessing: Bool
    let awaitingTurnTranscript: Bool
    let bubbleVisible: Bool
    let isAvatarOnly: Bool
    let maxHeight: CGFloat
    let minHeight: CGFloat
    let textOpacity: Double
    let speechBubbleFill: Color
    let speechBubbleStroke: Color
    let tailAnchorX: CGFloat

    var body: some View {
        let shape = ComicBubbleShape(tailAnchorX: tailAnchorX, tailDirection: .down)
        let textFont = Font.system(
            size: isAvatarOnly ? 15 : 13,
            weight: isAvatarOnly ? .semibold : .medium,
            design: .rounded
        )

        return ScrollView(.vertical, showsIndicators: false) {
            Group {
                if isProcessing || awaitingTurnTranscript {
                    ThinkingDots()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let preview, preview.blocks.isEmpty == false {
                    avatarBubblePreviewContent(preview.blocks, textFont: textFont)
                } else {
                    Text(greetingText)
                        .font(textFont)
                        .foregroundColor(.black.opacity(0.9 * textOpacity))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(isAvatarOnly ? 2 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shadow(color: .white.opacity(0.12), radius: 0.4, x: 0, y: 0.4)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, isAvatarOnly ? 18 : 16)
            .padding(.top, isAvatarOnly ? 14 : 12)
            .padding(.bottom, isAvatarOnly ? 24 : 22)
        }
        .background(shape.fill(speechBubbleFill))
        .overlay(shape.stroke(speechBubbleStroke, lineWidth: isAvatarOnly ? 1.2 : 0.9))
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 5)
        .frame(maxWidth: isAvatarOnly ? 360 : 332)
        // Content-driven height: shrinks to a single-line bubble for short
        // replies, grows up to `maxHeight` for long ones, then the inner
        // ScrollView takes over. `fixedSize(vertical: true)` is what makes
        // the bubble hug the text — the outer .frame caps the upper bound.
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: minHeight, maxHeight: (bubbleVisible || isProcessing) ? maxHeight : minHeight, alignment: .bottom)
        .animation(.easeInOut(duration: 0.3), value: bubbleVisible)
        .animation(.easeInOut(duration: 0.25), value: isProcessing)
    }

    @ViewBuilder
    private func avatarBubblePreviewContent(
        _ blocks: [ChatBubbleRendering.Block],
        textFont: Font
    ) -> some View {
        VStack(alignment: .leading, spacing: isAvatarOnly ? 10 : 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let attributed):
                    Text(attributed)
                        .font(textFont)
                        .foregroundColor(.black.opacity(0.9 * textOpacity))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(isAvatarOnly ? 2 : 1)
                        .lineLimit(isAvatarOnly ? 5 : 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tint(.accentColor)
                        .textSelection(.enabled)
                case .code(let language, let content):
                    VStack(alignment: .leading, spacing: 4) {
                        if let language, language.isEmpty == false {
                            Text(language)
                                .font(.system(size: isAvatarOnly ? 11 : 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black.opacity(0.65 * textOpacity))
                        }

                        Text(content)
                            .font(.system(size: isAvatarOnly ? 13 : 11, design: .monospaced))
                            .foregroundColor(.black.opacity(0.9 * textOpacity))
                            .lineSpacing(1)
                            .lineLimit(isAvatarOnly ? 5 : 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeskModelSwitchBanner: View {
    @Binding var notice: AgentLoop.ModelSwitchNotice?
    let surfaceOpacity: Double
    let textOpacity: Double
    let bgPanel: Color

    var body: some View {
        if let notice {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue.opacity(textOpacity))
                Text("Switched model: \(notice.from) \u{2192} \(notice.to)")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(textOpacity))
                Spacer()
                Button("Dismiss") { self.notice = nil }
                    .font(.caption)
            }
            .padding(8)
            .background(bgPanel.opacity(surfaceOpacity))
        }
    }
}

struct DeskErrorBanner: View {
    let errorMessage: String?
    let surfaceOpacity: Double
    let textOpacity: Double
    let bgPanel: Color
    let onDismiss: () -> Void

    var body: some View {
        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange.opacity(textOpacity))
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(textOpacity))
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .font(.caption)
            }
            .padding(8)
            .background(bgPanel.opacity(surfaceOpacity))
        }
    }
}
