import XCTest
@testable import OllamaBob

final class VersionConsistencyTests: XCTestCase {
    func testGeneratedBundleVersionMatchesAppConfig() throws {
        let buildScript = try String(
            contentsOf: packageRoot().appendingPathComponent("build.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(
            buildScript.contains("<string>\(AppConfig.appVersion)</string>"),
            "build.sh CFBundleShortVersionString must match AppConfig.appVersion"
        )
        XCTAssertTrue(
            buildScript.contains("<string>\(AppConfig.appBuild)</string>"),
            "build.sh CFBundleVersion must match AppConfig.appBuild"
        )
    }

    private func packageRoot() throws -> URL {
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidates = [
            cwd,
            cwd.appendingPathComponent("OllamaBob")
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate.appendingPathComponent("build.sh").path) {
            return candidate
        }

        throw XCTSkip("Unable to locate OllamaBob package root from \(cwd.path)")
    }
}
