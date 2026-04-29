import XCTest
import AppKit
@testable import OllamaBob

/// Tests for PushToTalkChord parsing and PushToTalkHotkey lifecycle.
/// No actual event monitors are needed — parsing is pure logic.
final class PushToTalkHotkeyTests: XCTestCase {

    // MARK: - Chord parsing — valid chords

    func testParseDefaultChordCtrlOptSpace() {
        let chord = PushToTalkChord.parse("ctrl+opt+space")
        XCTAssertNotNil(chord, "Default chord must parse successfully")
        XCTAssertEqual(chord?.keyCode, PushToTalkChord.spaceKeyCode)
        XCTAssertTrue(chord?.modifiers.contains(.control) ?? false)
        XCTAssertTrue(chord?.modifiers.contains(.option) ?? false)
    }

    func testParseControlOptionSpaceFullWords() {
        let chord = PushToTalkChord.parse("control+option+space")
        XCTAssertNotNil(chord)
        XCTAssertEqual(chord?.keyCode, PushToTalkChord.spaceKeyCode)
        XCTAssertTrue(chord?.modifiers.contains(.control) ?? false)
        XCTAssertTrue(chord?.modifiers.contains(.option) ?? false)
    }

    func testParseShiftCmdSpace() {
        let chord = PushToTalkChord.parse("shift+cmd+space")
        XCTAssertNotNil(chord)
        XCTAssertEqual(chord?.keyCode, PushToTalkChord.spaceKeyCode)
        XCTAssertTrue(chord?.modifiers.contains(.shift) ?? false)
        XCTAssertTrue(chord?.modifiers.contains(.command) ?? false)
    }

    func testParseSingleModifierPlusSpace() {
        let chord = PushToTalkChord.parse("ctrl+space")
        XCTAssertNotNil(chord)
        XCTAssertEqual(chord?.keyCode, PushToTalkChord.spaceKeyCode)
        XCTAssertTrue(chord?.modifiers.contains(.control) ?? false)
    }

    func testParseCaseInsensitive() {
        let chord = PushToTalkChord.parse("CTRL+OPT+SPACE")
        XCTAssertNotNil(chord, "Chord parsing must be case-insensitive")
    }

    func testParseMixedCase() {
        let chord = PushToTalkChord.parse("Ctrl+Opt+Space")
        XCTAssertNotNil(chord)
    }

    // MARK: - Chord parsing — invalid chords

    func testParseEmptyStringReturnsNil() {
        XCTAssertNil(PushToTalkChord.parse(""))
    }

    func testParseUnknownTokenReturnsNil() {
        // "meta" is not a recognised modifier.
        XCTAssertNil(PushToTalkChord.parse("meta+space"))
    }

    func testParseNoKeyTokenReturnsNil() {
        // "ctrl+opt" has modifiers but no key.
        XCTAssertNil(PushToTalkChord.parse("ctrl+opt"))
    }

    func testParseOnlySpaceNoModifierReturnsNil() {
        // Key-only without a modifier must be rejected.
        XCTAssertNil(PushToTalkChord.parse("space"))
    }

    func testParseGibberishReturnsNil() {
        XCTAssertNil(PushToTalkChord.parse("xyzzy+zap+wham"))
    }

    // MARK: - Hotkey lifecycle (no TCC needed)

    @MainActor
    func testHotkeyInitWithValidChordDoesNotCrash() {
        // Constructing a hotkey with a valid chord must not crash.
        let hotkey = PushToTalkHotkey(chordString: "ctrl+opt+space")
        XCTAssertNotNil(hotkey)
    }

    @MainActor
    func testHotkeyInitWithInvalidChordDoesNotCrash() {
        // Constructing a hotkey with an invalid chord must not crash;
        // the chord is simply nil and start() is a no-op.
        let hotkey = PushToTalkHotkey(chordString: "totally-invalid")
        XCTAssertNotNil(hotkey)
    }

    @MainActor
    func testHotkeyStartStopDoesNotCrash() {
        // Installing then immediately removing a global monitor must not crash.
        // (Note: without Accessibility/Input Monitoring permission the monitor
        //  may be nil; the code handles that gracefully.)
        let hotkey = PushToTalkHotkey(chordString: "ctrl+opt+space")
        hotkey.start()
        hotkey.stop()
    }

    @MainActor
    func testHotkeyDeinitDoesNotCrash() {
        // Deallocation must be safe even if the monitor was never started.
        var hotkey: PushToTalkHotkey? = PushToTalkHotkey(chordString: "ctrl+opt+space")
        hotkey = nil
        XCTAssertNil(hotkey)
    }

    // MARK: - Space key code constant

    func testSpaceKeyCodeIs49() {
        XCTAssertEqual(PushToTalkChord.spaceKeyCode, 49,
            "Virtual key code for Space must be 49 on macOS")
    }

    // MARK: - AppSettings round-trip

    @MainActor
    func testPushToTalkKeyChordPersists() {
        let settings = AppSettings.shared
        let original = settings.pushToTalkKeyChord
        defer { settings.pushToTalkKeyChord = original }

        settings.pushToTalkKeyChord = "shift+cmd+space"
        XCTAssertEqual(settings.pushToTalkKeyChord, "shift+cmd+space")
    }
}
