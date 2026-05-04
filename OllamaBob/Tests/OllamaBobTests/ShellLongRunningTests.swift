import XCTest
@testable import OllamaBob

/// Coverage for the long-running shell hardening landed in v1.0.44:
/// idle-reset timeout, hard cap, output chunk streaming, SIGTERM-resistant
/// kill via SIGKILL escalation, ShellTool argument clamping.
final class ShellLongRunningTests: XCTestCase {

    // MARK: - Idle timeout

    func testProcessRunnerIdleTimeoutResetsOnOutput() async {
        // 6 seconds of activity at 1s intervals with 2s idle timeout — should
        // complete normally because every print resets the idle clock.
        //
        // Use `python3 -u` (forced unbuffered stdio) so each print() reaches
        // the reader as a discrete chunk. zsh block-buffers stdout when piped
        // and would batch all writes at process exit — we want to exercise the
        // idle-timer reset, which only happens on observed chunks.
        let result = await ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: ["python3", "-u", "-c", "import time\nfor i in range(6):\n    print(i)\n    time.sleep(1)"],
            idleTimeout: 2,
            hardCap: 30
        )
        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertNil(result.terminationCause)
        XCTAssertTrue(result.stdout.contains("5"))
    }

    func testProcessRunnerIdleTimeoutFiresOnSilence() async {
        // 5s of silence with 1s idle timeout — must die from idle.
        let result = await ProcessRunner.run(
            executable: "/bin/zsh",
            arguments: ["-c", "sleep 5"],
            idleTimeout: 1,
            hardCap: 30
        )
        XCTAssertTrue(result.idleTimedOut, "expected idle kill, got \(String(describing: result.terminationCause))")
        XCTAssertTrue(result.timedOut, "legacy `timedOut` flag must remain true for any time-based kill")
    }

    // MARK: - Hard cap

    func testProcessRunnerHardCapFiresEvenWhenChatty() async {
        // Constant noise so idle never trips; 2s hard cap must still kill.
        let result = await ProcessRunner.run(
            executable: "/bin/zsh",
            arguments: ["-c", "while true; do echo .; sleep 0.05; done"],
            idleTimeout: 60,
            hardCap: 2
        )
        XCTAssertTrue(result.hardCapped, "expected hard-cap kill, got \(String(describing: result.terminationCause))")
    }

    // MARK: - Streaming

    func testProcessRunnerOnOutputChunkFiresIncrementally() async {
        let queue = DispatchQueue(label: "test.chunk-collector")
        var chunkCount = 0
        let onChunk: ProcessRunner.OutputChunkHandler = { _, _ in
            queue.sync { chunkCount += 1 }
        }
        // python3 -u forces unbuffered stdio so each print arrives as a
        // separate chunk — see note in testProcessRunnerIdleTimeoutResetsOnOutput.
        let result = await ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: ["python3", "-u", "-c", "import time\nfor i in range(3):\n    print(i)\n    time.sleep(0.2)"],
            idleTimeout: 5,
            hardCap: 10,
            onOutputChunk: onChunk
        )
        XCTAssertEqual(result.exitCode, 0)
        let observed = queue.sync { chunkCount }
        XCTAssertGreaterThanOrEqual(observed, 2, "onOutputChunk should fire multiple times for streamed output, got \(observed)")
    }

    // MARK: - SIGTERM-resistant kill

    func testProcessRunnerEscalatesToSIGKILLWhenSIGTERMIgnored() async {
        // `trap '' TERM` ignores SIGTERM. Idle timeout fires SIGTERM, then
        // SIGKILL after the grace window. Total time should be ~ idle + grace.
        let start = Date()
        let result = await ProcessRunner.run(
            executable: "/bin/zsh",
            arguments: ["-c", "trap '' TERM; sleep 30"],
            idleTimeout: 1,
            hardCap: 30,
            killGrace: 1.0
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(result.idleTimedOut, "expected idle cause, got \(String(describing: result.terminationCause))")
        XCTAssertLessThan(elapsed, 6.0, "process should die within idle + grace + slack, took \(elapsed)s")
    }

    // MARK: - External cancel via CancelHandle

    func testProcessRunnerHonorsExternalCancel() async {
        let handle = ProcessRunner.CancelHandle()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            handle.cancel()
        }
        let start = Date()
        let result = await ProcessRunner.run(
            executable: "/bin/zsh",
            arguments: ["-c", "sleep 10"],
            idleTimeout: 30,
            hardCap: 30,
            cancelHandle: handle
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(result.cancelled, "expected cancel cause, got \(String(describing: result.terminationCause))")
        XCTAssertLessThan(elapsed, 4.0, "cancel should be near-immediate, took \(elapsed)s")
    }

    // MARK: - ShellTool clamping

    func testShellToolClampsAbsurdIdleTimeout() async {
        let result = await ShellTool.execute(
            command: "echo ok",
            idleTimeout: 999_999,
            hardCap: 5
        )
        XCTAssertTrue(result.success, result.content)
    }

    func testShellToolReportsIdleTimeoutInError() async {
        // ShellTool clamps idleTimeout to AppConfig.shellIdleTimeoutMin (5s),
        // so we sleep well past that to be sure the idle timer trips.
        let result = await ShellTool.execute(
            command: "sleep 30",
            idleTimeout: 1,
            hardCap: 60
        )
        XCTAssertFalse(result.success)
        XCTAssertTrue(
            result.content.contains("idle"),
            "error should mention idle timeout, got: \(result.content)"
        )
    }

    func testShellToolReportsHardCapInError() async {
        let result = await ShellTool.execute(
            command: "while true; do echo .; sleep 0.05; done",
            idleTimeout: 60,
            hardCap: 2
        )
        XCTAssertFalse(result.success)
        XCTAssertTrue(
            result.content.contains("hard cap"),
            "error should mention hard cap, got: \(result.content)"
        )
    }
}
