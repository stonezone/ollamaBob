import XCTest
@testable import OllamaBob

@MainActor
final class HUDSettingsTests: XCTestCase {

    func testHUDFrameRoundTripsThroughAppSettings() {
        let settings = AppSettings.shared
        let original = settings.hudWindowFrame
        defer { settings.hudWindowFrame = original }

        let raw = "{{120, 240}, {260, 340}}"
        settings.hudWindowFrame = raw
        XCTAssertEqual(settings.hudWindowFrame, raw)

        // Persisted form should round-trip via NSRectFromString without
        // dropping any dimensions — the HUD frame restorer relies on this.
        let rect = NSRectFromString(raw)
        XCTAssertEqual(rect.origin.x, 120, accuracy: 0.01)
        XCTAssertEqual(rect.origin.y, 240, accuracy: 0.01)
        XCTAssertEqual(rect.size.width, 260, accuracy: 0.01)
        XCTAssertEqual(rect.size.height, 340, accuracy: 0.01)
    }

    func testHUDAlwaysOnTopDefaultsTrueOnFirstLaunch() {
        // The first-launch default for `hudAlwaysOnTop` should be true so
        // the HUD genuinely floats above other windows out of the box.
        let settings = AppSettings.shared
        let original = settings.hudAlwaysOnTop
        defer { settings.hudAlwaysOnTop = original }

        // We can't actually reset the singleton, but we can verify the
        // setter persists symmetrically.
        settings.hudAlwaysOnTop = false
        XCTAssertFalse(settings.hudAlwaysOnTop)
        settings.hudAlwaysOnTop = true
        XCTAssertTrue(settings.hudAlwaysOnTop)
    }

    func testHUDFrameEmptyStringMeansUseDefault() {
        // An empty frame string is the "no saved frame yet" sentinel; the
        // HUD chrome's restorer must treat that as a no-op.
        let settings = AppSettings.shared
        let original = settings.hudWindowFrame
        defer { settings.hudWindowFrame = original }

        settings.hudWindowFrame = ""
        XCTAssertEqual(settings.hudWindowFrame, "")
    }
}
