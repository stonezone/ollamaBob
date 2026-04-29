import XCTest
@testable import OllamaBob

@MainActor
final class HUDStateTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Clear any prior state from earlier tests so each case runs against
        // a known-empty bus.
        HUDState.shared.publishAssistantSnippet(nil)
    }

    func testTruncateLeavesShortStringsUnchanged() {
        XCTAssertEqual(HUDState.truncate("hi", to: 10), "hi")
    }

    func testTruncateAppendsEllipsisWhenOverCap() {
        let raw = String(repeating: "a", count: 50)
        let trimmed = HUDState.truncate(raw, to: 10)
        XCTAssertEqual(trimmed.count, 11) // 10 + "…"
        XCTAssertTrue(trimmed.hasSuffix("…"))
    }

    func testTruncateAtExactCapDoesNotAppendEllipsis() {
        let raw = String(repeating: "a", count: 10)
        XCTAssertEqual(HUDState.truncate(raw, to: 10), raw)
    }

    func testPublishAssistantSnippetTrimsWhitespace() {
        HUDState.shared.publishAssistantSnippet("   hello world   ")
        XCTAssertEqual(HUDState.shared.latestAssistantSnippet, "hello world")
    }

    func testPublishAssistantSnippetCapsLongStrings() {
        let raw = String(repeating: "x", count: 500)
        HUDState.shared.publishAssistantSnippet(raw)
        XCTAssertEqual(HUDState.shared.latestAssistantSnippet.count, HUDState.snippetCap + 1) // cap + ellipsis
    }

    func testPublishNilClearsExistingSnippet() {
        HUDState.shared.publishAssistantSnippet("seed")
        XCTAssertEqual(HUDState.shared.latestAssistantSnippet, "seed")
        HUDState.shared.publishAssistantSnippet(nil)
        XCTAssertEqual(HUDState.shared.latestAssistantSnippet, "")
    }

    func testRepublishingSameSnippetIsIdempotent() {
        HUDState.shared.publishAssistantSnippet("same")
        HUDState.shared.publishAssistantSnippet("same")
        XCTAssertEqual(HUDState.shared.latestAssistantSnippet, "same")
    }
}
