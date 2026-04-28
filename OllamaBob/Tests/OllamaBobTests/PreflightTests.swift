import XCTest
@testable import OllamaBob

final class PreflightTests: XCTestCase {
    func testRunReturnsInstalledModelStatusWhenReachable() async {
        let status = await Preflight.run(
            clientReachable: { true },
            installedModels: { [AppConfig.primaryModel] },
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

    func testRunAcceptsSelectedStandardModelWhenInstalled() async {
        let status = await Preflight.run(
            standardModelName: "gpt-oss:20b",
            clientReachable: { true },
            installedModels: { ["gpt-oss:20b"] },
            braveKeyPresent: false,
            databaseWritable: { true },
            sandboxDisabled: { true }
        )

        XCTAssertTrue(status.modelInstalled)
        XCTAssertEqual(status.requiredModelName, "gpt-oss:20b")
        XCTAssertTrue(status.canLaunch)
    }

    func testRunRejectsMissingSelectedStandardModelEvenWhenFallbackIsInstalled() async {
        let status = await Preflight.run(
            standardModelName: "gpt-oss:20b",
            clientReachable: { true },
            installedModels: { [AppConfig.fallbackModel] },
            braveKeyPresent: false,
            databaseWritable: { true },
            sandboxDisabled: { true }
        )

        XCTAssertFalse(status.modelInstalled)
        XCTAssertEqual(status.requiredModelName, "gpt-oss:20b")
        XCTAssertFalse(status.canLaunch)
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
