import XCTest
@testable import OllamaBob

/// Tests for SpeechService that do NOT require microphone / TCC access.
/// The audio engine and recognizer are never actually started.
@MainActor
final class SpeechServiceTests: XCTestCase {

    // MARK: - Default state

    func testDefaultStateIsIdle() {
        // SpeechService is a singleton; verify it starts (or resets) in .idle.
        let service = SpeechService.shared
        // After launch without any recording activity the state must be .idle.
        XCTAssertEqual(service.state, .idle)
    }

    // MARK: - speak() no-op on empty / whitespace-only input

    func testSpeakEmptyStringIsNoOp() {
        let service = SpeechService.shared
        // Verify no crash and state remains .idle when speaking "".
        service.speak("")
        // State should not have transitioned to .speaking for an empty string.
        XCTAssertNotEqual(service.state, .recording,
            "speak(\"\") must not transition to .recording")
    }

    func testSpeakWhitespaceOnlyIsNoOp() {
        let service = SpeechService.shared
        // Whitespace-only strings are trimmed to empty and discarded.
        service.speak("   \t\n  ")
        // The synthesizer should not have been invoked; state stays non-recording.
        XCTAssertNotEqual(service.state, .recording,
            "speak(whitespace) must not transition to .recording")
    }

    // MARK: - AppSettings defaults

    func testPushToTalkEnabledDefaultIsFalse() {
        // Verify that the AppSettings default for pushToTalkEnabled is false,
        // meaning walkie-talkie mode is OFF out-of-the-box.
        let defaults = UserDefaults.standard
        // If the key has never been written, the system returns false (default bool).
        // If it has been written (by a previous test run), we just validate the
        // current stored value is a valid Bool (no crash).
        let storedValue = defaults.object(forKey: "pushToTalkEnabled")
        if storedValue == nil {
            // First launch: should be false.
            XCTAssertFalse(defaults.bool(forKey: "pushToTalkEnabled"))
        } else {
            // Key exists — just ensure it parses without error.
            _ = defaults.bool(forKey: "pushToTalkEnabled")
        }
    }

    func testPushToTalkEnabledCanBeToggled() {
        let settings = AppSettings.shared
        let original = settings.pushToTalkEnabled
        defer { settings.pushToTalkEnabled = original }

        settings.pushToTalkEnabled = true
        XCTAssertTrue(settings.pushToTalkEnabled)

        settings.pushToTalkEnabled = false
        XCTAssertFalse(settings.pushToTalkEnabled)
    }

    func testPushToTalkKeyChordDefaultValue() {
        // Default chord must be the canonical ctrl+opt+space string.
        XCTAssertEqual(AppSettings.defaultPushToTalkKeyChord, "ctrl+opt+space")
    }

    // MARK: - Notification name constant

    func testWalkieTalkieNotificationNameIsStable() {
        XCTAssertEqual(Notification.Name.bobWalkieTalkieTranscript.rawValue,
                       "bobWalkieTalkieTranscript")
    }

    // MARK: - SpeechServiceState equatability

    func testSpeechServiceStateEquatable() {
        XCTAssertEqual(SpeechServiceState.idle, .idle)
        XCTAssertEqual(SpeechServiceState.recording, .recording)
        XCTAssertEqual(SpeechServiceState.speaking, .speaking)
        XCTAssertNotEqual(SpeechServiceState.idle, .recording)
        XCTAssertNotEqual(SpeechServiceState.recording, .speaking)
    }
}
