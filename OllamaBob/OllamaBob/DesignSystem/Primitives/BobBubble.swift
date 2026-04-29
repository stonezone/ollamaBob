import SwiftUI

/// Modernized comic bubble. Frosted-glass body with optional tail pointing at
/// the rendered persona's on-screen center.
///
/// Tail anchor is a normalized x-coordinate along the bottom edge (0 = left,
/// 1 = right). When `nil`, the tail is omitted (popover thread previews,
/// chrome-less inline bubbles).
struct BobBubble<Content: View>: View {
    enum Role {
        case user
        case assistant
        case system
        case glyph    // small bubble next to a glyph (HUD, popover greetings)
    }

    let role: Role
    let tailAnchorX: CGFloat?
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        role: Role,
        tailAnchorX: CGFloat? = nil,
        cornerRadius: CGFloat = BobRadii.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.role = role
        self.tailAnchorX = tailAnchorX
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        let bubbleShape = BubbleShape(
            cornerRadius: cornerRadius,
            tailAnchorX: tailAnchorX,
            tailHeight: tailAnchorX == nil ? 0 : 9,
            tailWidth: 14
        )

        content()
            .padding(.horizontal, BobSpacing.md)
            .padding(.vertical, BobSpacing.sm)
            .padding(.bottom, tailAnchorX == nil ? 0 : 9)
            .background {
                if reduceTransparency {
                    bubbleShape.fill(BobMaterial.reducedTransparencyFill(for: materialRole))
                } else {
                    glassFill(shape: bubbleShape)
                }
            }
            .overlay {
                bubbleShape.stroke(strokeColor, lineWidth: 0.5)
            }
            .foregroundStyle(textColor)
    }

    private var materialRole: BobMaterial.Role {
        role == .user ? .bubbleEmphasized : .bubble
    }

    private var strokeColor: Color {
        switch role {
        case .user:         return BobColors.Accent.bobBlue.opacity(0.45)
        case .assistant:    return BobColors.Glass.strokeHighlight
        case .system:       return BobColors.Glass.strokeOutline
        case .glyph:        return BobColors.Glass.strokeHighlight
        }
    }

    private var textColor: Color {
        role == .user ? BobColors.Text.onGlass : BobColors.Text.onGlass
    }

    @ViewBuilder
    private func glassFill(shape: BubbleShape) -> some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(glassStyle(), in: shape)
        } else {
            shape
                .fill(role == .user ? BobColors.Accent.bobBlue.opacity(0.30) : BobColors.Glass.fill)
                .background(BobMaterial.legacyMaterial(for: materialRole), in: shape)
        }
    }

    @available(macOS 26.0, *)
    private func glassStyle() -> Glass {
        switch role {
        case .user:         return .regular.tint(BobColors.Accent.bobBlue.opacity(0.55))
        case .assistant:    return .regular
        case .system:       return .regular.tint(BobColors.Signal.warn.opacity(0.20))
        case .glyph:        return .regular
        }
    }
}

/// Rounded-rect bubble with an optional triangular tail along the bottom edge.
/// `tailAnchorX` is a normalized 0...1 position along the bottom.
struct BubbleShape: Shape, InsettableShape {
    var cornerRadius: CGFloat
    var tailAnchorX: CGFloat?
    var tailHeight: CGFloat
    var tailWidth: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> BubbleShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let bodyHeight = r.height - tailHeight
        let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: bodyHeight)
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)

        guard let anchor = tailAnchorX, tailHeight > 0 else { return path }

        let clamped = max(0.10, min(0.90, anchor))
        let tipX = r.minX + r.width * clamped
        let baseY = r.minY + bodyHeight
        let tipY = r.minY + r.height
        let leftX = max(r.minX + cornerRadius + 2, tipX - tailWidth / 2)
        let rightX = min(r.maxX - cornerRadius - 2, tipX + tailWidth / 2)

        path.move(to: CGPoint(x: leftX, y: baseY))
        path.addLine(to: CGPoint(x: tipX, y: tipY))
        path.addLine(to: CGPoint(x: rightX, y: baseY))
        path.closeSubpath()
        return path
    }
}
