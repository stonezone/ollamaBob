import SwiftUI

struct ToolActivityView: View {
    // Must observe the AgentLoop directly — passing a value-type snapshot of
    // `toolActivity` at scene-creation time leaves the window frozen, since
    // SwiftUI has no signal to re-render when the @Published array mutates.
    @ObservedObject var agentLoop: AgentLoop

    var body: some View {
        List {
            if agentLoop.toolActivity.isEmpty {
                Text("No tool activity yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(agentLoop.toolActivity.reversed()) { entry in
                    ToolActivityRow(entry: entry)
                }
            }
        }
        .frame(minWidth: 350, minHeight: 300)
    }
}

struct ToolActivityRow: View {
    let entry: AgentLoop.ToolLogEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .accessibilityHidden(true)
                Text(entry.toolName)
                    .font(.body.bold())
                Spacer()
                Text("\(entry.durationMs)ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(
                        isExpanded ? "Hide Details" : "Show Details",
                        systemImage: isExpanded ? "chevron.up.circle" : "chevron.down.circle"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide tool details" : "Show tool details")
                .accessibilityHint("Reveals the tool input, output, and approval details")
            }
            VStack(alignment: .leading, spacing: 6) {
                ActivityPreviewField(
                    title: "Input",
                    content: entry.input,
                    lineLimit: isExpanded ? 3 : 1
                )
                ActivityPreviewField(
                    title: "Output",
                    content: entry.output,
                    lineLimit: isExpanded ? 4 : 2
                )
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ActivityExpandedField(title: "Input", content: entry.input, maxHeight: 120)
                    ActivityExpandedField(title: "Output", content: entry.output, maxHeight: 180)

                    HStack {
                        Text("Tool policy: \(entry.approval.rawValue)")
                        Text("Tool execution allowed: \(entry.approved ? "Yes" : "No")")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Tool policy \(entry.approval.rawValue). Tool execution allowed \(entry.approved ? "yes" : "no"). This is separate from macOS Automation permissions.")
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        if !entry.approved && entry.approval == .forbidden { return "xmark.octagon.fill" }
        if !entry.approved { return "hand.raised.fill" }
        return "checkmark.circle.fill"
    }

    private var iconColor: Color {
        if !entry.approved && entry.approval == .forbidden { return .red }
        if !entry.approved { return .orange }
        return .green
    }
    private var timeString: String {
        entry.timestamp.formatted(date: .omitted, time: .shortened)
    }
}

private struct ActivityPreviewField: View {
    let title: String
    let content: String
    let lineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(trimmedContent)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
                .accessibilityLabel("\(title) preview")
                .accessibilityValue(trimmedContent)
        }
    }

    private var trimmedContent: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No \(title.lowercased())" : trimmed
    }
}

private struct ActivityExpandedField: View {
    let title: String
    let content: String
    let maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
            ScrollView(.vertical, showsIndicators: true) {
                Text(trimmedContent)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: maxHeight)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(title)
            .accessibilityValue(trimmedContent)
        }
    }

    private var trimmedContent: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No \(title.lowercased())" : trimmed
    }
}
