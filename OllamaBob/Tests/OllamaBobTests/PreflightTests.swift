import XCTest
@testable import OllamaBob

final class PreflightTests: XCTestCase {
    func testRunReturnsInstalledModelStatusWhenReachable() async {
        let status = await Preflight.run(
            clientReachable: { true },
            installedModels: { [AppConfig.fallbackModel] },
            braveKeyPresent: false,
            databaseWritable: { true },
            sandboxDisabled: { true }
        )

        XCTAssertTrue(status.ollamaReachable)
        XCTAssertTrue(status.modelInstalled)
        XCTAssertFalse(status.braveKeyPresent)
        XCTAssertTrue(status.databaseWritable)
        XCTAssertTrue(status.sandboxDisabled)
        XCTAssertTrue(status.canLaunch)
    }

    func testRunSkipsModelCheckWhenClientIsUnavailable() async {
        let status = await Preflight.run(
            clientReachable: { false },
            installedModels: { XCTFail("installedModels should not run when Ollama is unreachable"); return [] },
            braveKeyPresent: true,
            databaseWritable: { true },
            sandboxDisabled: { true }
        )

        XCTAssertFalse(status.ollamaReachable)
        XCTAssertFalse(status.modelInstalled)
        XCTAssertTrue(status.braveKeyPresent)
        XCTAssertFalse(status.canLaunch)
    }

    func testRunFailsLaunchWhenDatabaseOrSandboxChecksFail() async {
        let status = await Preflight.run(
            clientReachable: { true },
            installedModels: { [AppConfig.primaryModel] },
            braveKeyPresent: true,
            databaseWritable: { false },
            sandboxDisabled: { false }
        )

        XCTAssertTrue(status.ollamaReachable)
        XCTAssertTrue(status.modelInstalled)
        XCTAssertFalse(status.databaseWritable)
        XCTAssertFalse(status.sandboxDisabled)
        XCTAssertFalse(status.canLaunch)
    }
}
