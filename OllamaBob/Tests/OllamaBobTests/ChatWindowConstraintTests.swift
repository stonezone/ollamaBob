import XCTest
@testable import OllamaBob

final class ChatWindowConstraintTests: XCTestCase {
    func testAvatarConstraintAllowsPartialTopTuck() {
        let constrained = ChatWindowConstraint.constrainedFrame(
            NSRect(x: 120, y: 820, width: 420, height: 420),
            avatarOnly: true,
            visibleFrames: [
                NSRect(x: 0, y: 0, width: 1440, height: 982)
            ]
        )

        XCTAssertEqual(constrained.origin.y, 742, accuracy: 0.0001)
        XCTAssertEqual(constrained.origin.x, 120, accuracy: 0.0001)
    }

    func testAvatarConstraintLeavesLowerAndSidePlacementUntouched() {
        let constrained = ChatWindowConstraint.constrainedFrame(
            NSRect(x: -180, y: -96, width: 420, height: 420),
            avatarOnly: true,
            visibleFrames: [
                NSRect(x: 0, y: 0, width: 1440, height: 982)
            ]
        )

        XCTAssertEqual(constrained.origin.x, -180, accuracy: 0.0001)
        XCTAssertEqual(constrained.origin.y, -96, accuracy: 0.0001)
    }
}
