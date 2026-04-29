import XCTest
@testable import OllamaBob

// MARK: - Stubs

/// A stub BriefingRunner that records calls and returns a canned result.
@MainActor
final class StubBriefingRunner: BriefingRunnerProtocol {
    var runCallCount = 0
    var stubbedResult: BriefingResult = BriefingResult(
        id: 0,
        runAt: Date(),
        summary: "Stub summary",
        toolResults: ["[mail_check]\n<untrusted>ok</untrusted>"],
        success: true
    )

    func run(
        tools: [(name: String, args: [String: String])],
        runAt: Date
    ) async -> BriefingResult {
        runCallCount += 1
        return stubbedResult
    }
}

// MARK: - BriefingRunnerProtocol

/// Protocol so SchedulerService can accept a stub in tests.
@MainActor
protocol BriefingRunnerProtocol {
    func run(tools: [(name: String, args: [String: String])], runAt: Date) async -> BriefingResult
}

extension BriefingRunner: BriefingRunnerProtocol {}

// MARK: - SchedulerServiceTests

@MainActor
final class SchedulerServiceTests: XCTestCase {

    // Hold the original settings for restoration.
    private var originalEnabled = false
    private var originalMinutes = 0

    override func setUp() async throws {
        try await super.setUp()
        originalEnabled = AppSettings.shared.briefingScheduleEnabled
        originalMinutes = AppSettings.shared.briefingScheduleMinutes
        // Always start from a clean disabled state.
        AppSettings.shared.briefingScheduleEnabled = false
        SchedulerService.shared.stop()
    }

    override func tearDown() async throws {
        SchedulerService.shared.stop()
        AppSettings.shared.briefingScheduleEnabled = originalEnabled
        AppSettings.shared.briefingScheduleMinutes = originalMinutes
        try await super.tearDown()
    }

    // MARK: - Test 1: nextRunAt is correctly computed from settings

    func testNextRunAtComputedFromScheduleMinutes() {
        // Use a controlled reference date: 2026-04-28 08:00 local
        // Schedule at 07:00 (420 min) → already passed today → tomorrow 07:00.
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")

        // Build a reference date at 08:00 today.
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        let refDate = calendar.date(from: comps) ?? Date()

        // 07:00 = 420 minutes since midnight.
        AppSettings.shared.briefingScheduleMinutes = 420
        AppSettings.shared.briefingScheduleEnabled = true

        // Inject the controlled clock.
        SchedulerService.shared.now = { refDate }
        SchedulerService.shared.calendar = calendar

        // scheduleNext should compute 07:00 tomorrow.
        SchedulerService.shared.start()

        // nextRunAt must exist and be after refDate.
        guard let nextRun = SchedulerService.shared.nextRunAt else {
            XCTFail("nextRunAt should not be nil when scheduler is enabled")
            return
        }
        XCTAssertGreaterThan(nextRun, refDate, "nextRunAt should be in the future")

        // The scheduled time should have hour=7, minute=0.
        let fireComps = calendar.dateComponents([.hour, .minute], from: nextRun)
        XCTAssertEqual(fireComps.hour, 7)
        XCTAssertEqual(fireComps.minute, 0)
    }

    // MARK: - Test 2: Disabled state produces nil nextRunAt

    func testDisabledSchedulerHasNilNextRunAt() {
        AppSettings.shared.briefingScheduleEnabled = false
        SchedulerService.shared.stop()
        XCTAssertNil(SchedulerService.shared.nextRunAt,
                     "nextRunAt must be nil when scheduler is disabled")
    }

    // MARK: - Test 3: Scheduler does not fire when disabled

    func testDisabledSchedulerDoesNotFireOnStart() {
        // Even if we call start() when disabled, nextRunAt stays nil.
        AppSettings.shared.briefingScheduleEnabled = false
        SchedulerService.shared.start()
        XCTAssertNil(SchedulerService.shared.nextRunAt)
    }

    // MARK: - Test 4: runBriefingNow persists and sets lastRunResult

    func testRunBriefingNowSetsLastRunResult() async throws {
        // Use a temp database.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbURL = tempDir.appendingPathComponent("briefing_scheduler_test.sqlite")
        defer {
            DatabaseManager.shared.resetForTesting()
            try? FileManager.default.removeItem(at: tempDir)
        }
        try DatabaseManager.shared.setup(at: dbURL)

        // Give the service a stub runner that does NOT hit real tools.
        let stub = StubBriefingRunner()
        SchedulerService.shared.runner = BriefingRunner()
        // We can't inject the stub directly without making the runner property
        // protocol-typed; instead verify via lastRunResult after runBriefingNow.
        // Use the real runner but stub the tool executor.
        let stubExecutor = StubToolExecutor(result: ToolResult.success(
            tool: "mail_check",
            content: "Test ok",
            durationMs: 1
        ))
        let stubSynthesizer = StubBriefingSynthesizer(response: "Short summary.")
        let runner = BriefingRunner(
            toolExecutor: stubExecutor,
            synthesizer: stubSynthesizer,
            synthesizeWithBob: true
        )
        SchedulerService.shared.runner = runner

        await SchedulerService.shared.runBriefingNow()

        let result = SchedulerService.shared.lastRunResult
        XCTAssertNotNil(result, "lastRunResult should be set after runBriefingNow")
        XCTAssertEqual(result?.summary, "Short summary.")
        XCTAssertTrue(result?.success == true)

        _ = stub // suppress unused warning
    }

    // MARK: - Test 5: nextRunAt uses future time when schedule is later today

    func testNextRunAtIsTodayWhenScheduleIsLater() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")

        // Reference: 06:00 today.
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 6
        comps.minute = 0
        comps.second = 0
        let refDate = calendar.date(from: comps) ?? Date()

        // Schedule at 07:00 (still in the future relative to refDate).
        AppSettings.shared.briefingScheduleMinutes = 420
        AppSettings.shared.briefingScheduleEnabled = true

        SchedulerService.shared.now = { refDate }
        SchedulerService.shared.calendar = calendar
        SchedulerService.shared.start()

        guard let nextRun = SchedulerService.shared.nextRunAt else {
            XCTFail("nextRunAt should not be nil")
            return
        }

        // Should be today at 07:00 (not tomorrow).
        let refDay   = calendar.dateComponents([.year, .month, .day], from: refDate)
        let fireDay  = calendar.dateComponents([.year, .month, .day], from: nextRun)
        XCTAssertEqual(refDay.day, fireDay.day, "Fire should be today when target time hasn't passed")

        let fireComps = calendar.dateComponents([.hour, .minute], from: nextRun)
        XCTAssertEqual(fireComps.hour, 7)
        XCTAssertEqual(fireComps.minute, 0)
    }
}

// MARK: - Helper stubs for test 4

@MainActor
struct StubToolExecutor: BriefingToolExecutor, @unchecked Sendable {
    let result: ToolResult
    func executeTool(name: String, args: [String: String]) async -> ToolResult { result }
}

struct StubBriefingSynthesizer: BriefingSynthesizer {
    let response: String?
    func synthesize(prompt: String) async -> String? { response }
}
