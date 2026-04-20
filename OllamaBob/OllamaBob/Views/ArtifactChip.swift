import SwiftUI

struct ArtifactChip: View {
    let artifact: DetectedArtifact
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: artifact.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(artifact.label)
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isLink)
    }

    private var accessibilityLabel: String {
        artifact.title ?? artifact.label
    }

    private var accessibilityHint: String {
        switch artifact.kind {
        case .file:
            return "Opens the file in its default macOS app."
        case .url:
            return "Opens the link in your default browser."
        case .html:
            return "Opens Bob's rich view window."
        }
    }

    private var helpText: String {
        switch artifact.kind {
        case .file:
            if let title = artifact.title, title.isEmpty == false {
                return "Open \(title) in its default macOS app."
            }
            return "Open this file in its default macOS app."
        case .url:
            if let title = artifact.title, title.isEmpty == false {
                return "Open \(title) in your default browser."
            }
            return "Open this link in your default browser."
        case .html:
            if let title = artifact.title, title.isEmpty == false {
                return "Reopen \(title) in Bob's rich view window."
            }
            return "Reopen Bob's rich view window."
        }
    }
}
