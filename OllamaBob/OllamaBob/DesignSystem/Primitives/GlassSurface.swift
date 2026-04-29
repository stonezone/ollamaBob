import SwiftUI

/// Liquid Glass container. On macOS 26+ (Tahoe) uses the native `glassEffect`
/// modifier; falls back to SwiftUI `Material` on macOS 14/15. Honors Reduce
/// Transparency by collapsing to a solid surface token.
///
/// Apply this AFTER any layout modifiers on the wrapped content.
struct GlassSurface<Content: View>: View {
    let role: BobMaterial.Role
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        role: BobMaterial.Role,
        cornerRadius: CGFloat = BobRadii.lg,
        tint: Color? = nil,
        interactive: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.role = role
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.interactive = interactive
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content()
            .background {
                if reduceTransparency {
                    shape.fill(BobMaterial.reducedTransparencyFill(for: role))
                } else {
                    glassBackground(shape: shape)
                }
            }
            .overlay {
                shape
                    .strokeBorder(BobColors.Glass.strokeOutline, lineWidth: 0.5)
            }
            .overlay(alignment: .top) {
                shape
                    .trim(from: 0, to: 0.5)
                    .stroke(BobColors.Glass.topRimHighlight, lineWidth: 1)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .opacity(reduceTransparency ? 0 : 1)
            }
            .clipShape(shape)
    }

    @ViewBuilder
    private func glassBackground(shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(
                    glassEffectStyle(),
                    in: shape
                )
        } else {
            shape
                .fill(BobColors.Glass.fill)
                .background(BobMaterial.legacyMaterial(for: role), in: shape)
        }
    }

    @available(macOS 26.0, *)
    private func glassEffectStyle() -> Glass {
        var style: Glass = .regular
        if let tint { style = style.tint(tint) }
        if interactive { style = style.interactive() }
        return style
    }
}
