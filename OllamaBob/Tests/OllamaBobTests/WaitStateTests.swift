import XCTest
@testable import OllamaBob

/// Coverage for `AgentLoop.WaitState` display formatting + the
/// pre-flight context-pressure threshold (v1.0.52).
///
/// Why these matter: WaitState is the only signal the user gets
/// during the long blank window of a `stream: false` Ollama
/// generation. If its `displayText` is wrong, the user can't tell
/// "Bob is processing 166 msgs (3m12s)" from "thinking…" — both
/// are invisible-to-them states and the wedge problem returns.
@MainActor
final class WaitStateTests: XCTestCase {

    func testIdleStateRendersEmpty() {
        XCTAssertEqual(AgentLoop.WaitState.idle.displayText, "")
    }

    func testThinkingStateShowsElapsedSeconds() {
        let s = AgentLoop.WaitState.thinking(elapsedSec: 3).displayText
        XCTAssertTrue(s.contains("thinking"), s)
        XCTAssertTrue(s.contains("3s"), s)
    }

    func testProcessingStateShowsElapsedAndMessageCount() {
        let s = AgentLoop.WaitState.processing(elapsedSec: 45, messageCount: 12).displayText
        XCTAssertTrue(s.contains("processing"), s)
        XCTAssertTrue(s.contains("45s"), s)
    }

    func testProcessingStateAddsContextWarningOnHighMsgCount() {
        // The 166-msg wedge case from production. UI must surface
        // "this is a lot of context" so the user understands the
        // wait is self-inflicted (long chat history) and can /clear.
        let s = AgentLoop.WaitState.processing(elapsedSec: 192, messageCount: 166).displayText
        XCTAssertTrue(s.contains("166 msgs"), s)
        XCTAssertTrue(s.contains("a lot of context"), s)
        // Elapsed should format as "3m12s" not "192s" once over 60.
        XCTAssertTrue(s.contains("3m12s"), s)
    }

    func testProcessingStateOmitsContextWarningOnSmallMsgCount() {
        // Healthy 10-msg chat shouldn't get the alarm-bell phrasing.
        let s = AgentLoop.WaitState.processing(elapsedSec: 30, messageCount: 10).displayText
        XCTAssertTrue(s.contains("processing"), s)
        XCTAssertFalse(s.contains("a lot of context"), s)
    }

    func testModelDroppedStateMentionsRetry() {
        // The recovery hint matters here — without it the user just
        // sees "Ollama dropped the connection" and doesn't know
        // they should hit ⌘. and try again.
        let s = AgentLoop.WaitState.modelDropped(elapsedSec: 75).displayText
        XCTAssertTrue(s.contains("dropped"), s)
        XCTAssertTrue(s.contains("⌘."), s)
        XCTAssertTrue(s.contains("retry"), s)
    }

    func testExceededHardCapStateMentionsAutoCancel() {
        let s = AgentLoop.WaitState.exceededHardCap(elapsedSec: 600).displayText
        XCTAssertTrue(s.contains("exceeded"), s)
        XCTAssertTrue(s.contains("auto-cancel"), s)
    }

    func testElapsedFormatsBelow60SecondsAsBareSeconds() {
        // Avoid "0m45s" awkwardness for short waits.
        let s = AgentLoop.WaitState.processing(elapsedSec: 45, messageCount: 10).displayText
        XCTAssertTrue(s.contains("45s"), s)
        XCTAssertFalse(s.contains("0m45s"), s)
    }

    // MARK: - HeartbeatSample shape

    func testHeartbeatSampleDetectsModelDropped() {
        // Constructor sanity: the dropped-mid-request flag is a
        // strict requirement (was-loaded → not-loaded). Negative
        // case: still loaded → not dropped.
        let stillUp = OllamaHeartbeat.HeartbeatSample(
            elapsedSeconds: 30,
            requestedModelLoaded: true,
            requestedModelDroppedMidRequest: false,
            loadedModels: []
        )
        XCTAssertFalse(stillUp.requestedModelDroppedMidRequest)

        let dropped = OllamaHeartbeat.HeartbeatSample(
            elapsedSeconds: 60,
            requestedModelLoaded: false,
            requestedModelDroppedMidRequest: true,
            loadedModels: []
        )
        XCTAssertTrue(dropped.requestedModelDroppedMidRequest)
    }

    // MARK: - Context-pressure threshold

    func testContextPressureWarningFractionIsConservative() {
        // Document the chosen threshold so a future tweak forces
        // an explicit decision rather than a silent regression.
        // 0.6 (60%) is the empirical sweet spot for gemma4:e4b on
        // M-series — it gets noticeably sluggish past this even
        // though numCtx still has headroom.
        XCTAssertEqual(AppConfig.chatContextPressureWarningFraction, 0.6, accuracy: 0.0001)
    }

    func testWallClockCapIsHigherThanHTTPIdleTimeout() {
        // The wall-clock cap exists BECAUSE the HTTP idle timeout
        // doesn't fire when Ollama keeps the TCP alive while doing
        // nothing. They serve different purposes; the wall-clock
        // should be >= the HTTP timeout so we don't double-fire.
        XCTAssertGreaterThanOrEqual(
            AppConfig.ollamaSingleRequestWallClockCapSeconds,
            AppConfig.ollamaHTTPRequestTimeoutSeconds
        )
    }

    func testHeartbeatIntervalIsInGoldilocksRange() {
        // Document: 5s is fast enough to detect mid-request unload
        // within a glance, slow enough that 12 GETs/min on a local
        // Ollama is trivially cheap. If someone tries to set this
        // sub-1s or above 30s, they should think hard.
        XCTAssertGreaterThanOrEqual(AppConfig.ollamaHeartbeatIntervalSeconds, 1.0)
        XCTAssertLessThanOrEqual(AppConfig.ollamaHeartbeatIntervalSeconds, 30.0)
    }
}
