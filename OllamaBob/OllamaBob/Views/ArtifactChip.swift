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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
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
    }
}
