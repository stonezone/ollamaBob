import XCTest
@testable import OllamaBob

final class BobsDeskViewPresentationTests: XCTestCase {
    func testSingleLineMetricsStayNarrowerThanMultiLineReply() {
        let short = AvatarBubblePresentation.metrics(
            lines: ["Done."],
            maxHeight: 180,
            isThinking: false
        )
        let longer = AvatarBubblePresentation.metrics(
            lines: [
                "I tightened the avatar bubble.",
                "Short replies now hug their content more closely."
            ],
            maxHeight: 180,
            isThinking: false
        )

        XCTAssertLessThan(short.width, longer.width)
        XCTAssertFalse(short.useScroll)
    }

    func testOverflowMetricsClampToScrollAndMaxWidth() {
        let metrics = AvatarBubblePresentation.metrics(
            lines: [
                String(repeating: "overflow ", count: 18),
                String(repeating: "details ", count: 18),
                String(repeating: "summary ", count: 18)
            ],
            maxHeight: 72,
            isThinking: false
        )

        XCTAssertTrue(metrics.useScroll)
        XCTAssertLessThanOrEqual(metrics.width, AvatarBubblePresentation.maxWidth)
    }

    func testTailAttachmentChangesWithBubbleWidth() {
        let short = AvatarBubblePresentation.metrics(
            lines: ["Done."],
            maxHeight: 180,
            isThinking: false
        )
        let wide = AvatarBubblePresentation.metrics(
            lines: [
                "I tightened the avatar-only bubble so longer spoken replies can still fit cleanly."
            ],
            maxHeight: 180,
            isThinking: false
        )

        XCTAssertNotEqual(short.tailAnchorX, wide.tailAnchorX, accuracy: 0.0001)
        XCTAssertNotEqual(short.tailDX, wide.tailDX, accuracy: 0.0001)
        XCTAssertNotEqual(short.horizontalOffset, wide.horizontalOffset, accuracy: 0.0001)
    }

    func testThinkingMetricsStayCompact() {
        let metrics = AvatarBubblePresentation.metrics(
            lines: [],
            maxHeight: 200,
            isThinking: true
        )

        XCTAssertEqual(metrics.width, AvatarBubblePresentation.thinkingWidth, accuracy: 0.0001)
        XCTAssertEqual(metrics.minHeight, AvatarBubblePresentation.thinkingMinHeight, accuracy: 0.0001)
        XCTAssertFalse(metrics.useScroll)
    }
}
