import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

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
                    .foregroundColor(.secondary)
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
            .foregroundColor(message.role == .user ? .white : .primary)
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
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }

    private func toolCallSummary(_ call: OllamaToolCall) -> String {
        let args = call.function.parsedArguments
        switch call.function.name {
        case "shell":     return (args["command"] as? String) ?? ""
        case "read_file": return (args["path"] as? String) ?? ""
        case "search_files": return (args["pattern"] as? String) ?? ""
        case "web_search":   return (args["query"] as? String) ?? ""
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
            .foregroundColor(.secondary)

            Text(message.content)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(8)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: return .accentColor
        case .assistant: return Color(.controlBackgroundColor)
        case .tool: return Color(.controlBackgroundColor)
        case .system: return .clear
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
