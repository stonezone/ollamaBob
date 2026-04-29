import SwiftUI

/// Capsule status chip. Replaces today's monospace status indicators
/// (context, walkie-talkie, focus guardian, persona, model, trust state).
struct BobChip<Leading: View>: View {
    let label: String
    let tint: Color
    let isProminent: Bool
    @ViewBuilder let leading: () -> Leading

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        label: String,
        tint: Color = BobColors.Text.onGlassSecondary,
        isProminent: Bool = false,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() }
    ) {
        self.label = label
        self.tint = tint
        self.isProminent = isProminent
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: BobSpacing.xs) {
            leading()
            Text(label)
                .font(BobTypography.captionMono)
                .foregroundStyle(isProminent ? BobColors.Text.onGlass : tint)
                .lineLimit(1)
        }
        .padding(.horizontal, BobSpacing.sm + 2)
        .padding(.vertical, BobSpacing.xs)
        .background {
            Capsule(style: .continuous)
                .fill(reduceTransparency
                      ? tint.opacity(isProminent ? 0.30 : 0.16)
                      : tint.opacity(isProminent ? 0.22 : 0.10))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(isProminent ? 0.55 : 0.30), lineWidth: 0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

extension BobChip where Leading == EmptyView {
    init(label: String, tint: Color = BobColors.Text.onGlassSecondary, isProminent: Bool = false) {
        self.init(label: label, tint: tint, isProminent: isProminent) { EmptyView() }
    }
}

/// Convenience constructor for the common SF-Symbol-leading shape.
extension BobChip where Leading == Image {
    init(
        label: String,
        systemImage: String,
        tint: Color = BobColors.Text.onGlassSecondary,
        isProminent: Bool = false
    ) {
        self.init(label: label, tint: tint, isProminent: isProminent) {
            Image(systemName: systemImage)
        }
    }
}
