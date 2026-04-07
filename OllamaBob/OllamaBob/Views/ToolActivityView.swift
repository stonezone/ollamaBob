import SwiftUI

struct ToolActivityView: View {
    let entries: [AgentLoop.ToolLogEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No tool activity yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(entries.reversed()) { entry in
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
                Text(entry.toolName)
                    .font(.body.bold())
                Spacer()
                Text("\(entry.durationMs)ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input:")
                        .font(.caption.bold())
                    Text(entry.input)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(5)

                    Text("Output:")
                        .font(.caption.bold())
                    Text(entry.output)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(10)

                    HStack {
                        Text("Approval: \(entry.approval.rawValue)")
                        Text("Approved: \(entry.approved ? "Yes" : "No")")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }
}
