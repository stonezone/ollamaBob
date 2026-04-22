import XCTest
import AppKit
@testable import OllamaBob

final class WindowFrameRecoveryTests: XCTestCase {
    func testClampedFramePullsWeaklyIntersectingRestoreFullyOnScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = NSRect(x: 1320, y: 120, width: 420, height: 520)

        let clamped = WindowFrameRecovery.clampedFrame(
            saved,
            minimumSize: NSSize(width: 420, height: 520),
            visibleFrames: [visible]
        )

        guard let clamped else {
            return XCTFail("Expected a clamped frame")
        }

        XCTAssertEqual(clamped.origin.x, 1020, accuracy: 0.001)
        XCTAssertEqual(clamped.origin.y, 120, accuracy: 0.001)
        XCTAssertEqual(clamped.size.width, 420, accuracy: 0.001)
        XCTAssertEqual(clamped.size.height, 520, accuracy: 0.001)
    }

    func testClampedFrameUsesNearestVisibleScreenWhenSavedDisplayIsGone() {
        let left = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let right = NSRect(x: 1440, y: 0, width: 1440, height: 900)
        let saved = NSRect(x: 3200, y: 80, width: 420, height: 520)

        let clamped = WindowFrameRecovery.clampedFrame(
            saved,
            minimumSize: NSSize(width: 420, height: 520),
            visibleFrames: [left, right]
        )

        guard let clamped else {
            return XCTFail("Expected a clamped frame")
        }

        XCTAssertEqual(clamped.origin.x, 2460, accuracy: 0.001)
        XCTAssertEqual(clamped.origin.y, 80, accuracy: 0.001)
        XCTAssertEqual(clamped.size.width, 420, accuracy: 0.001)
        XCTAssertEqual(clamped.size.height, 520, accuracy: 0.001)
    }

    func testClampedFrameRespectsMinimumSizeButCapsToVisibleBounds() {
        let visible = NSRect(x: 0, y: 0, width: 300, height: 350)
        let saved = NSRect(x: -40, y: -60, width: 100, height: 100)

        let clamped = WindowFrameRecovery.clampedFrame(
            saved,
            minimumSize: NSSize(width: 280, height: 340),
            visibleFrames: [visible]
        )

        guard let clamped else {
            return XCTFail("Expected a clamped frame")
        }

        XCTAssertEqual(clamped.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(clamped.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(clamped.size.width, 280, accuracy: 0.001)
        XCTAssertEqual(clamped.size.height, 340, accuracy: 0.001)
    }

    func testClampedFrameReturnsNilWithoutVisibleScreens() {
        let saved = NSRect(x: 100, y: 100, width: 420, height: 520)

        XCTAssertNil(
            WindowFrameRecovery.clampedFrame(
                saved,
                minimumSize: NSSize(width: 420, height: 520),
                visibleFrames: []
            )
        )
    }
}
