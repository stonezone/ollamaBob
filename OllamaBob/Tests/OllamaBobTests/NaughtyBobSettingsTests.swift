import XCTest
@testable import OllamaBob

@MainActor
final class NaughtyBobSettingsTests: XCTestCase {
    func testUncensoredModeAvailabilityFlagIsWritable() {
        let settings = AppSettings.shared
        let originalAvailable = settings.uncensoredModeAvailable

        defer { settings.uncensoredModeAvailable = originalAvailable }

        settings.uncensoredModeAvailable = true
        XCTAssertTrue(settings.uncensoredModeAvailable)

        settings.uncensoredModeAvailable = false
        XCTAssertFalse(settings.uncensoredModeAvailable)
    }

    func testEffectiveUncensoredModelNameFallsBackToDefaultWhenBlank() {
        let settings = AppSettings.shared
        let originalModelName = settings.uncensoredModelName

        defer { settings.uncensoredModelName = originalModelName }

        settings.uncensoredModelName = "   "
        XCTAssertEqual(settings.effectiveUncensoredModelName, AppSettings.defaultUncensoredModelName)

        settings.uncensoredModelName = " custom-model:latest "
        XCTAssertEqual(settings.effectiveUncensoredModelName, "custom-model:latest")
    }
}
