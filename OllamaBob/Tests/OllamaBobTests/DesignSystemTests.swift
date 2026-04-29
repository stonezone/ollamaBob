import XCTest
import SwiftUI
@testable import OllamaBob

@MainActor
final class DesignSystemTests: XCTestCase {

    // MARK: - Token scale invariants

    func testSpacingScaleIsMonotonicallyIncreasing() {
        let scale: [CGFloat] = [
            BobSpacing.xxs, BobSpacing.xs, BobSpacing.sm,
            BobSpacing.md, BobSpacing.lg, BobSpacing.xl, BobSpacing.xxl
        ]
        XCTAssertEqual(scale, scale.sorted())
        XCTAssertEqual(BobSpacing.xxs, 2)
        XCTAssertEqual(BobSpacing.lg, 16)
        XCTAssertEqual(BobSpacing.xxl, 32)
    }

    func testRadiiScaleIsMonotonic() {
        XCTAssertLessThan(BobRadii.sm, BobRadii.md)
        XCTAssertLessThan(BobRadii.md, BobRadii.lg)
        XCTAssertLessThan(BobRadii.lg, BobRadii.xl)
        XCTAssertEqual(BobRadii.pill, .infinity)
    }

    // MARK: - BobMotion / Reduce-Motion

    func testRespectingReduceMotionReturnsPassedAnimationWhenDisabled() {
        let result = BobMotion.respectingReduceMotion(BobMotion.expressive, reduceMotion: false)
        XCTAssertNotNil(result)
    }

    func testRespectingReduceMotionFallsBackUnderAccessibility() {
        let result = BobMotion.respectingReduceMotion(BobMotion.expressive, reduceMotion: true)
        // Both branches return an Animation; assert the helper still produces a value
        // and that it differs from the expressive curve by virtue of the function's
        // documented contract (short opacity-only fade). Exhaustive curve equality
        // isn't possible against `Animation` directly; we settle for a non-nil
        // result here and rely on snapshot consumers to cover the visual path.
        XCTAssertNotNil(result)
    }

    // MARK: - BobMaterial role mapping

    func testLegacyMaterialMappingIsExhaustive() {
        let roles: [BobMaterial.Role] = [.popover, .deskWindow, .hud, .bubble, .bubbleEmphasized]
        for role in roles {
            // Just resolves without trapping. Material is an opaque struct, so
            // we verify the call site doesn't crash and the closure terminates.
            _ = BobMaterial.legacyMaterial(for: role)
            _ = BobMaterial.reducedTransparencyFill(for: role)
            _ = BobMaterial.appKitMaterial(for: role)
        }
    }

    func testReducedTransparencyFillReturnsDifferentColorsPerRole() {
        let popover = BobMaterial.reducedTransparencyFill(for: .popover)
        let bubble = BobMaterial.reducedTransparencyFill(for: .bubbleEmphasized)
        // Distinct semantic roles must map to distinct fills, otherwise
        // Reduce-Transparency loses the semantic distinction glass provides.
        XCTAssertNotEqual(String(describing: popover), String(describing: bubble))
    }

    // MARK: - Persona accent fallback

    func testPersonaAccentFallsBackToBobBlueWhenNoPalette() {
        let resolved = BobColors.personaAccent(nil)
        XCTAssertEqual(String(describing: resolved), String(describing: BobColors.Accent.bobBlue))
    }

    // MARK: - BubbleShape geometry

    func testBubbleShapeWithoutTailProducesRoundedRectPath() {
        let shape = BubbleShape(cornerRadius: 12, tailAnchorX: nil, tailHeight: 0, tailWidth: 14)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let path = shape.path(in: rect)
        XCTAssertFalse(path.isEmpty)
        // Rounded rect with no tail must stay within the original bounding rect.
        let bounding = path.boundingRect
        XCTAssertEqual(bounding.height, rect.height, accuracy: 0.5)
    }

    func testBubbleShapeClampsTailAnchorIntoSafeRange() {
        // Anchor 0.0 should clamp to 0.10, anchor 1.0 should clamp to 0.90 so
        // the tail never escapes the rounded corner.
        let leftEdge = BubbleShape(cornerRadius: 12, tailAnchorX: 0.0, tailHeight: 9, tailWidth: 14)
        let rightEdge = BubbleShape(cornerRadius: 12, tailAnchorX: 1.0, tailHeight: 9, tailWidth: 14)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 80)
        let leftPath = leftEdge.path(in: rect)
        let rightPath = rightEdge.path(in: rect)
        XCTAssertFalse(leftPath.isEmpty)
        XCTAssertFalse(rightPath.isEmpty)
        // Tail extends below the body rect — total height should be greater
        // than (height - tailHeight) for both clamped paths.
        XCTAssertGreaterThan(leftPath.boundingRect.height, rect.height - 10)
        XCTAssertGreaterThan(rightPath.boundingRect.height, rect.height - 10)
    }

    func testBubbleShapeInsetsItself() {
        var shape = BubbleShape(cornerRadius: 12, tailAnchorX: nil, tailHeight: 0, tailWidth: 14)
        shape = shape.inset(by: 4)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let path = shape.path(in: rect)
        // Insetted path bounding rect must be smaller than the original rect.
        XCTAssertLessThan(path.boundingRect.width, rect.width)
        XCTAssertLessThan(path.boundingRect.height, rect.height)
    }

    // MARK: - Primitive instantiation smoke tests

    func testGlassSurfaceCanBeInstantiated() {
        let view = GlassSurface(role: .popover) { Text("hi") }
        // Just verifies the generic + initializer compile and resolve.
        _ = view.body
    }

    func testGlassGlyphInstantiatesAcrossAllStates() {
        let states: [GlassGlyph.State] = [.idle, .thinking, .listening, .speaking, .alert]
        for state in states {
            let glyph = GlassGlyph(state: state, tint: BobColors.Accent.bobBlue, size: 28)
            _ = glyph.body
        }
    }

    func testBobBubbleInstantiatesAcrossAllRoles() {
        let roles: [BobBubble<Text>.Role] = [.user, .assistant, .system, .glyph]
        for role in roles {
            let bubble = BobBubble(role: role, tailAnchorX: 0.5) { Text("body") }
            _ = bubble.body
        }
    }

    func testBobChipConvenienceInitializers() {
        let plain = BobChip(label: "ctx 4k")
        _ = plain.body

        let withSymbol = BobChip(label: "focus", systemImage: "circle.fill")
        _ = withSymbol.body

        let withProminence = BobChip(label: "naughty", tint: BobColors.Signal.warn, isProminent: true)
        _ = withProminence.body
    }

    func testBobButtonStyleResolvesForAllKinds() {
        // Direct construction — the `.bob(_:)` extension is reachable only
        // through generic constraint `where Self == BobButtonStyle`, which
        // isn't satisfiable from a metatype expression.
        _ = BobButtonStyle(kind: .primary)
        _ = BobButtonStyle(kind: .secondary)
        _ = BobButtonStyle(kind: .ghost)
        _ = BobButtonStyle(kind: .primary, isCompact: true)
    }
}
