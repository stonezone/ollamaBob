import XCTest
@testable import OllamaBob

@MainActor
final class MenuBarMarkTests: XCTestCase {

    func testStatusResolvesIdleWhenAgentIsResting() {
        let status = BobMenuBarMark.Status.resolve(isProcessing: false, hasError: false)
        XCTAssertEqual(status, .idle)
    }

    func testStatusResolvesProcessingWhenAgentIsBusy() {
        let status = BobMenuBarMark.Status.resolve(isProcessing: true, hasError: false)
        XCTAssertEqual(status, .processing)
    }

    func testStatusResolvesErrorWhenErrorIsPresent() {
        // Error wins over both idle and processing — the user needs to see it.
        XCTAssertEqual(BobMenuBarMark.Status.resolve(isProcessing: false, hasError: true), .error)
        XCTAssertEqual(BobMenuBarMark.Status.resolve(isProcessing: true, hasError: true), .error)
    }
}
