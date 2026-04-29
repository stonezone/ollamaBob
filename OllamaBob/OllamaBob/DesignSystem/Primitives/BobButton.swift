import SwiftUI

/// Primary / secondary / ghost button styles. Applies the design system's
/// glass material, accent color, typography, and motion curves consistently.
struct BobButtonStyle: ButtonStyle {
    enum Kind {
        case primary    // accent-tinted, prominent — main CTA
        case secondary  // glass surface, neutral text
        case ghost      // transparent, hover-only fill
    }

    let kind: Kind
    let isCompact: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(kind: Kind, isCompact: Bool = false) {
        self.kind = kind
        self.isCompact = isCompact
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let pressed = configuration.isPressed

        configuration.label
            .font(isCompact ? BobTypography.caption : BobTypography.bodyEmphasized)
            .foregroundStyle(textColor)
            .padding(.horizontal, isCompact ? BobSpacing.md : BobSpacing.lg)
            .padding(.vertical, isCompact ? BobSpacing.xs + 1 : BobSpacing.sm)
            .background {
                background(in: shape, isPressed: pressed)
            }
            .overlay {
                shape.strokeBorder(strokeColor(isPressed: pressed), lineWidth: 0.6)
            }
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(BobMotion.responsive, value: pressed)
            .contentShape(shape)
    }

    @ViewBuilder
    private func background(in shape: Capsule, isPressed: Bool) -> some View {
        switch kind {
        case .primary:
            if reduceTransparency {
                shape.fill(BobColors.Accent.bobBlue.opacity(isPressed ? 0.85 : 0.95))
            } else if #available(macOS 26.0, *) {
                shape.fill(.clear)
                    .glassEffect(.regular.tint(BobColors.Accent.bobBlue.opacity(isPressed ? 0.75 : 0.60)), in: shape)
            } else {
                shape.fill(BobColors.Accent.bobBlue.opacity(isPressed ? 0.65 : 0.50))
                    .background(.thickMaterial, in: shape)
            }
        case .secondary:
            if reduceTransparency {
                shape.fill(BobColors.Surface.raised.opacity(isPressed ? 0.92 : 0.78))
            } else if #available(macOS 26.0, *) {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            } else {
                shape.fill(.regularMaterial)
            }
        case .ghost:
            shape.fill(isPressed ? Color.white.opacity(0.10) : Color.clear)
        }
    }

    private var textColor: Color {
        switch kind {
        case .primary:      return .white
        case .secondary:    return BobColors.Text.onGlass
        case .ghost:        return BobColors.Text.onGlassSecondary
        }
    }

    private func strokeColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:      return BobColors.Accent.bobBlue.opacity(isPressed ? 0.6 : 0.4)
        case .secondary:    return BobColors.Glass.strokeHighlight
        case .ghost:        return .clear
        }
    }
}

extension ButtonStyle where Self == BobButtonStyle {
    static func bob(_ kind: BobButtonStyle.Kind, isCompact: Bool = false) -> BobButtonStyle {
        BobButtonStyle(kind: kind, isCompact: isCompact)
    }
}
