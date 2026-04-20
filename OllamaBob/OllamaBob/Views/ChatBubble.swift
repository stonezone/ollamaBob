import SwiftUI
import AppKit

@MainActor
enum ChatBubbleRendering {
    enum Block {
        case markdown(AttributedString)
        case code(language: String?, content: String)
    }

    struct TranscriptPreview {
        let text: String
        let isTruncated: Bool
    }

    private final class BlockBox: NSObject {
        let blocks: [Block]

        init(blocks: [Block]) {
            self.blocks = blocks
        }
    }

    private static let blockCache: NSCache<NSString, BlockBox> = {
        let cache = NSCache<NSString, BlockBox>()
        cache.countLimit = 512
        return cache
    }()

    static func blocks(for content: String) -> [Block] {
        let cacheKey = content as NSString
        if let cached = blockCache.object(forKey: cacheKey) {
            return cached.blocks
        }

        let parsed = parseBlocks(from: content)
        blockCache.setObject(BlockBox(blocks: parsed), forKey: cacheKey)
        return parsed
    }

    static func shouldShowAssistantBody(content: String, toolCalls: [OllamaToolCall]?) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }

        guard let toolCalls, toolCalls.isEmpty == false else {
            return true
        }

        let lower = trimmed.lowercased()
        let containsRenderedHTMLPayload = lower.contains("<!doctype html") || lower.contains("<html") || lower.contains("<body")
        if containsRenderedHTMLPayload,
           toolCalls.contains(where: {
               $0.function.name == "present" &&
               (($0.function.parsedArguments["kind"] as? String)?.lowercased() == "html")
           }) {
            return false
        }

        return true
    }

    static func avatarBubblePreviewText(for content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        if containsMarkdownImageSyntax(trimmed) {
            return trimmed
        }

        let bubbleBlocks = blocks(for: trimmed)
        let fragments = bubbleBlocks.compactMap { block -> String? in
            switch block {
            case .markdown(let attributed):
                let text = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            case .code(let language, let content):
                let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard body.isEmpty == false else { return nil }
                if let language, language.isEmpty == false {
                    return "\(language)\n\(body)"
                }
                return body
            }
        }

        let joined = fragments.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? trimmed : joined
    }

    static func toolCallSummary(_ call: OllamaToolCall) -> String {
        let args = call.function.parsedArguments
        switch call.function.name {
        case "shell":
            return (args["command"] as? String) ?? ""
        case "read_file", "write_file", "list_directory":
            return (args["path"] as? String) ?? ""
        case "move_file":
            return [args["source"] as? String, args["destination"] as? String]
                .compactMap { $0 }
                .joined(separator: " -> ")
        case "search_files":
            return (args["pattern"] as? String) ?? ""
        case "web_search":
            return (args["query"] as? String) ?? ""
        case "git_status":
            return "repo status"
        case "git_diff":
            return ((args["path"] as? String).flatMap { $0.isEmpty ? nil : $0 }) ?? "repo diff"
        case "present":
            let kind = (args["kind"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
            let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawContent = (args["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let preview: String
            if kind == "html" {
                preview = title?.isEmpty == false ? title! : "rich view"
            } else {
                preview = rawContent
            }
            return "\(kind): \(preview)"
        default:
            return ""
        }
    }

    static func shortTimeString(for timestamp: Date) -> String {
        timestamp.formatted(date: .omitted, time: .shortened)
    }

    static func transcriptPreview(
        for content: String,
        expanded: Bool,
        maxLines: Int = 12,
        maxCharacters: Int = 1400
    ) -> TranscriptPreview {
        guard expanded == false else {
            return TranscriptPreview(text: content, isTruncated: false)
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let exceedsLines = lines.count > maxLines
        let exceedsCharacters = content.count > maxCharacters
        guard exceedsLines || exceedsCharacters else {
            return TranscriptPreview(text: content, isTruncated: false)
        }

        let limitedByLines = lines.prefix(maxLines).joined(separator: "\n")
        let limitedText = String(limitedByLines.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptPreview(text: limitedText + "\n…", isTruncated: true)
    }

    private static func parseBlocks(from content: String) -> [Block] {
        var blocks: [Block] = []
        var textLines: [String] = []
        var codeLines: [String] = []
        var inFence = false
        var codeLanguage: String?

        func flushText() {
            let joined = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard joined.isEmpty == false else {
                textLines.removeAll(keepingCapacity: true)
                return
            }
            blocks.append(.markdown(attributedString(from: joined)))
            textLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            let joined = codeLines.joined(separator: "\n")
            blocks.append(.code(language: codeLanguage, content: joined))
            codeLines.removeAll(keepingCapacity: true)
            codeLanguage = nil
        }

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let string = String(line)
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence {
                    flushCode()
                } else {
                    flushText()
                    codeLanguage = parseFenceLanguage(from: trimmed)
                }
                inFence.toggle()
                continue
            }

            if inFence {
                codeLines.append(string)
            } else {
                textLines.append(string)
            }
        }

        if inFence {
            flushCode()
        } else {
            flushText()
        }

        if blocks.isEmpty {
            return [.markdown(attributedString(from: content))]
        }

        return blocks
    }

    private static func parseFenceLanguage(from fenceLine: String) -> String? {
        let language = fenceLine.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        return language.isEmpty ? nil : language
    }

    private static func attributedString(from markdown: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            return attributed
        }
        return AttributedString(markdown)
    }

    private static func containsMarkdownImageSyntax(_ content: String) -> Bool {
        content.range(of: #"\!\[[^\]]*\]\([^)]+\)"#, options: .regularExpression) != nil
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    @ObservedObject private var settings = AppSettings.shared

    @State private var isToolPanelExpanded = false
    @State private var isThinkingPanelExpanded = false

    var body: some View {
        let artifacts = resolvedArtifacts
        let assistantCalls = message.role == .assistant ? (message.toolCalls ?? []) : []
        let showAssistantText = message.role == .assistant
            ? ChatBubbleRendering.shouldShowAssistantBody(content: message.content, toolCalls: message.toolCalls)
            : message.role != .tool

        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .tool {
                    toolBubble
                } else {
                    if showAssistantText {
                        textBubble
                    }
                    if assistantCalls.isEmpty == false {
                        toolCallBubble(calls: assistantCalls)
                    }
                }

                if shouldShowArtifactChips(artifacts) {
                    artifactChipRow(artifacts: artifacts)
                }

                Text(ChatBubbleRendering.shortTimeString(for: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(textOpacity))
            }

            if message.role != .user { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var textBubble: some View {
        Group {
            if message.role == .assistant {
                assistantTextContent
            } else {
                Text(message.content)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(bubbleColor)
        .foregroundColor(message.role == .user ? .white.opacity(textOpacity) : .primary.opacity(textOpacity))
        .cornerRadius(12)
        .textSelection(.enabled)
    }

    private var assistantTextContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ChatBubbleRendering.blocks(for: message.content).enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let attributed):
                    if String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text(attributed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tint(.accentColor)
                    }
                case .code(let language, let content):
                    VStack(alignment: .leading, spacing: 4) {
                        if let language, language.isEmpty == false {
                            Text(language)
                                .font(.caption2.bold())
                                .foregroundColor(.secondary.opacity(textOpacity))
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(content)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .background(Color.black.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Distinct rendering for an assistant turn that is about to run a tool.
    /// Using a gear icon + the actual command preview (not a generic "Using X…"
    /// string) prevents collisions with literal text the model might emit.
    private func toolCallBubble(calls: [OllamaToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(calls.indices, id: \.self) { i in
                let call = calls[i]
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(call.function.name)
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                    Text(ChatBubbleRendering.toolCallSummary(call))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary.opacity(textOpacity))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let thinking = sanitizedThinking, thinking.isEmpty == false {
                transcriptPanel(title: "thinking", content: thinking, isExpanded: $isThinkingPanelExpanded)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(surfaceOpacity * 0.75))
        .cornerRadius(8)
    }

    private var toolBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "wrench.fill")
                    .font(.caption)
                Text(message.toolName ?? "tool")
                    .font(.caption.bold())
            }
            .foregroundColor(.secondary.opacity(textOpacity))

            transcriptPanel(title: nil, content: sanitizedToolContent, isExpanded: $isToolPanelExpanded)
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: return .accentColor.opacity(surfaceOpacity)
        case .assistant: return Color(.controlBackgroundColor).opacity(surfaceOpacity)
        case .tool: return Color(.controlBackgroundColor).opacity(surfaceOpacity)
        case .system: return .clear
        }
    }

    private var surfaceOpacity: Double {
        settings.chatWindowOpacity
    }

    private var textOpacity: Double {
        min(1.0, settings.chatWindowOpacity + 0.1)
    }

    private var sanitizedThinking: String? {
        let trimmed = message.thinking?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private var resolvedArtifacts: [DetectedArtifact] {
        guard message.role == .assistant,
              settings.richPresentationEnabled,
              settings.richPresentationArtifactChipsEnabled else {
            return []
        }

        return ArtifactDetector.detect(in: message.content)
    }

    private func shouldShowArtifactChips(_ artifacts: [DetectedArtifact]) -> Bool {
        artifacts.isEmpty == false
    }

    private func artifactChipRow(artifacts: [DetectedArtifact]) -> some View {
        WrappingChipLayout(spacing: 6) {
            ForEach(artifacts) { artifact in
                ArtifactChip(artifact: artifact) {
                    openArtifact(artifact)
                }
            }
        }
    }

    private var sanitizedToolContent: String {
        message.content
            .replacingOccurrences(of: "<untrusted>", with: "")
            .replacingOccurrences(of: "</untrusted>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openArtifact(_ artifact: DetectedArtifact) {
        do {
            try PresentationService.shared.present(kind: artifact.kind, content: artifact.content, title: artifact.title)
        } catch {
            NSSound.beep()
            print("[ArtifactChip] \(error.localizedDescription)")
        }
    }

    private func transcriptPanel(title: String?, content: String, isExpanded: Binding<Bool>) -> some View {
        let preview = ChatBubbleRendering.transcriptPreview(for: content, expanded: isExpanded.wrappedValue)

        return VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundColor(.secondary.opacity(textOpacity))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(preview.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary.opacity(textOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor).opacity(surfaceOpacity * 0.9))
            .cornerRadius(8)

            if preview.isTruncated {
                HStack {
                    Spacer()
                    Button(isExpanded.wrappedValue ? "Collapse" : "Expand") {
                        isExpanded.wrappedValue.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.bold())
                    .foregroundColor(.accentColor)
                    .accessibilityLabel(isExpanded.wrappedValue ? "Collapse transcript" : "Expand transcript")
                }
            } else if isExpanded.wrappedValue {
                HStack {
                    Spacer()
                    Button("Collapse") {
                        isExpanded.wrappedValue = false
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.bold())
                    .foregroundColor(.accentColor)
                    .accessibilityLabel("Collapse transcript")
                }
            }
        }
    }
}

private struct WrappingChipLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        _WrappingChipFlowLayout(spacing: spacing) {
            content
        }
    }
}

private struct _WrappingChipFlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let originX: CGFloat = 0
        var x = originX
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > originX, x + size.width > maxWidth {
                x = originX
                y += rowHeight + spacing
                rowHeight = 0
            }

            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: usedWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
