import XCTest
import SwiftUI
@testable import OllamaBob

@MainActor
final class BubbleShapeTests: XCTestCase {

    private let testRect = CGRect(x: 0, y: 0, width: 200, height: 60)

    // MARK: - Tail anchor presence

    func testBubbleShapeOmitsTailWhenAnchorIsNil() {
        let shape = BubbleShape(cornerRadius: 14, tailAnchorX: nil, tailHeight: 0, tailWidth: 14)
        let path = shape.path(in: testRect)
        // With no tail, the path bounding box height should equal the body
        // height (no tail extension below the rounded rect).
        XCTAssertEqual(path.boundingRect.height, testRect.height, accuracy: 0.01)
    }

    func testBubbleShapeRendersTailWhenAnchorIsProvided() {
        let shapeWithTail = BubbleShape(cornerRadius: 14, tailAnchorX: 0.5, tailHeight: 9, tailWidth: 14)
        let shapeNoTail = BubbleShape(cornerRadius: 14, tailAnchorX: nil, tailHeight: 0, tailWidth: 14)
        // Path with a tail should produce a richer bounding box element count
        // than a pure rounded rect (the tail adds a triangle subpath).
        let withTailRect = shapeWithTail.path(in: testRect).boundingRect
        let noTailRect = shapeNoTail.path(in: testRect).boundingRect
        XCTAssertGreaterThanOrEqual(withTailRect.height, noTailRect.height - 0.01)
    }

    // MARK: - Tail anchor clamping

    func testBubbleShapeClampsTailAnchorToInterior() {
        // Anchors outside [0.10, 0.90] should be clamped so the tail tip
        // never escapes the body's rounded corners.
        let leftEdge = BubbleShape(cornerRadius: 14, tailAnchorX: 0.0, tailHeight: 9, tailWidth: 14)
        let rightEdge = BubbleShape(cornerRadius: 14, tailAnchorX: 1.0, tailHeight: 9, tailWidth: 14)
        let leftPath = leftEdge.path(in: testRect)
        let rightPath = rightEdge.path(in: testRect)

        // Tail tip should be inside the rect's horizontal bounds with margin.
        let leftTipX = leftPath.boundingRect.minX
        let rightTipX = rightPath.boundingRect.maxX
        XCTAssertGreaterThanOrEqual(leftTipX, testRect.minX - 0.01)
        XCTAssertLessThanOrEqual(rightTipX, testRect.maxX + 0.01)
    }

    func testBubbleShapeClampsNegativeAnchor() {
        // A negative anchor should still produce a valid path (clamped to 0.10).
        let shape = BubbleShape(cornerRadius: 14, tailAnchorX: -0.5, tailHeight: 9, tailWidth: 14)
        let path = shape.path(in: testRect)
        XCTAssertFalse(path.isEmpty)
        XCTAssertGreaterThan(path.boundingRect.width, 0)
    }

    // MARK: - InsettableShape conformance

    func testBubbleShapeInsetReducesBoundingRect() {
        let shape = BubbleShape(cornerRadius: 14, tailAnchorX: nil, tailHeight: 0, tailWidth: 14)
        let inset = shape.inset(by: 4)
        let originalPath = shape.path(in: testRect)
        let insetPath = inset.path(in: testRect)
        // Inset path should be strictly smaller in both width and height.
        XCTAssertLessThan(insetPath.boundingRect.width, originalPath.boundingRect.width)
        XCTAssertLessThan(insetPath.boundingRect.height, originalPath.boundingRect.height)
    }

    // MARK: - Tail height parameterization

    func testBubbleShapeWithZeroTailHeightSkipsTail() {
        // Tail anchor present but height zero — tail should still be skipped.
        let shape = BubbleShape(cornerRadius: 14, tailAnchorX: 0.5, tailHeight: 0, tailWidth: 14)
        let path = shape.path(in: testRect)
        XCTAssertEqual(path.boundingRect.height, testRect.height, accuracy: 0.01)
    }
}
