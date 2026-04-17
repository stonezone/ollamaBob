import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .tool {
                    toolBubble
                } else if message.role == .assistant,
                          let calls = message.toolCalls, !calls.isEmpty {
                    toolCallBubble(calls: calls)
                } else {
                    textBubble
                }

                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(textOpacity))
            }

            if message.role != .user { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var textBubble: some View {
        Text(message.content)
            .padding(10)
            .background(bubbleColor)
            .foregroundColor(message.role == .user ? .white.opacity(textOpacity) : .primary.opacity(textOpacity))
            .cornerRadius(12)
            .textSelection(.enabled)
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
                    Text(toolCallSummary(call))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary.opacity(textOpacity))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let thinking = sanitizedThinking, thinking.isEmpty == false {
                transcriptPanel(title: "thinking", content: thinking)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(surfaceOpacity * 0.75))
        .cornerRadius(8)
    }

    private func toolCallSummary(_ call: OllamaToolCall) -> String {
        let args = call.function.parsedArguments
        switch call.function.name {
        case "shell":     return (args["command"] as? String) ?? ""
        case "read_file": return (args["path"] as? String) ?? ""
        case "write_file": return (args["path"] as? String) ?? ""
        case "list_directory": return (args["path"] as? String) ?? ""
        case "move_file":
            return [args["source"] as? String, args["destination"] as? String]
                .compactMap { $0 }
                .joined(separator: " -> ")
        case "search_files": return (args["pattern"] as? String) ?? ""
        case "web_search":   return (args["query"] as? String) ?? ""
        case "git_status": return "repo status"
        case "git_diff":
            return ((args["path"] as? String).flatMap { $0.isEmpty ? nil : $0 }) ?? "repo diff"
        default: return ""
        }
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

            transcriptPanel(title: nil, content: sanitizedToolContent)
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

    private var sanitizedToolContent: String {
        message.content
            .replacingOccurrences(of: "<untrusted>", with: "")
            .replacingOccurrences(of: "</untrusted>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcriptPanel(title: String?, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundColor(.secondary.opacity(textOpacity))
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary.opacity(textOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
            .padding(8)
            .background(Color(.controlBackgroundColor).opacity(surfaceOpacity * 0.9))
            .cornerRadius(8)
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
