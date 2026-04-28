import XCTest
@testable import OllamaBob

@MainActor
final class StandardModelSettingsTests: XCTestCase {
    func testStandardModelOptionsIncludeGptOssAndRecommendedLocalModels() {
        let tags = AppConfig.standardModelOptions.map(\.tag)

        XCTAssertEqual(tags.first, AppConfig.primaryModel)
        XCTAssertTrue(tags.contains("gemma4:26b"))
        XCTAssertTrue(tags.contains("qwen3.6:27b"))
        XCTAssertTrue(tags.contains("gpt-oss:20b"))
    }

    func testEffectiveStandardModelNameFallsBackToPrimaryWhenBlank() {
        let settings = AppSettings.shared
        let originalModelName = settings.standardModelName

        defer { settings.standardModelName = originalModelName }

        settings.standardModelName = "   "
        XCTAssertEqual(settings.effectiveStandardModelName, AppConfig.primaryModel)

        settings.standardModelName = " gpt-oss:20b "
        XCTAssertEqual(settings.effectiveStandardModelName, "gpt-oss:20b")
    }
}
