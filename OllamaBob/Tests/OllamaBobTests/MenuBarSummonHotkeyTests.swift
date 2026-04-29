import XCTest
@testable import OllamaBob

@MainActor
final class MenuBarSummonHotkeyTests: XCTestCase {

    // MARK: - Chord parsing

    func testHotkeyAcceptsDefaultChord() {
        let hotkey = MenuBarSummonHotkey(chordString: AppSettings.defaultHUDSummonHotkeyChord)
        XCTAssertNotNil(hotkey.chord)
    }

    func testHotkeyParsesAlternateChord() {
        let hotkey = MenuBarSummonHotkey(chordString: "cmd+shift+space")
        XCTAssertNotNil(hotkey.chord)
        XCTAssertEqual(hotkey.chord?.modifiers, [.command, .shift])
    }

    func testHotkeyRejectsUnparseableChord() {
        // No modifiers — chord parser requires at least one to avoid stomping
        // on bare keystrokes.
        let hotkey = MenuBarSummonHotkey(chordString: "space")
        XCTAssertNil(hotkey.chord)
    }

    func testHotkeyRejectsUnknownToken() {
        let hotkey = MenuBarSummonHotkey(chordString: "ctrl+opt+wat")
        XCTAssertNil(hotkey.chord)
    }

    // MARK: - Update lifecycle

    func testHotkeyUpdateChordReplacesParsedChord() {
        let hotkey = MenuBarSummonHotkey(chordString: "ctrl+opt+space")
        XCTAssertEqual(hotkey.chord?.modifiers, [.control, .option])

        hotkey.updateChord("cmd+shift+space")
        XCTAssertEqual(hotkey.chord?.modifiers, [.command, .shift])
    }

    func testHotkeyUpdateChordToInvalidClearsChord() {
        let hotkey = MenuBarSummonHotkey(chordString: "ctrl+opt+space")
        XCTAssertNotNil(hotkey.chord)

        hotkey.updateChord("not a real chord")
        XCTAssertNil(hotkey.chord)
    }

    // MARK: - Start/stop is idempotent

    func testHotkeyStartStopIsIdempotent() {
        let hotkey = MenuBarSummonHotkey(chordString: "ctrl+opt+space")
        // Should not crash or leak even called repeatedly.
        hotkey.start()
        hotkey.start()
        hotkey.stop()
        hotkey.stop()
        // No assertion — surviving without crashing is the contract.
    }

    // MARK: - Settings round-trip

    func testHUDSummonHotkeySettingsRoundTrip() {
        let settings = AppSettings.shared
        let originalEnabled = settings.hudSummonHotkeyEnabled
        let originalChord = settings.hudSummonHotkeyChord
        defer {
            settings.hudSummonHotkeyEnabled = originalEnabled
            settings.hudSummonHotkeyChord = originalChord
        }

        settings.hudSummonHotkeyEnabled = true
        settings.hudSummonHotkeyChord = "cmd+shift+b"
        XCTAssertTrue(settings.hudSummonHotkeyEnabled)
        XCTAssertEqual(settings.hudSummonHotkeyChord, "cmd+shift+b")
    }

    func testDefaultHUDSummonHotkeyChordParsesCleanly() {
        // Sanity-check the shipped default actually parses, otherwise users
        // who flip the toggle on get a silent no-op.
        XCTAssertNotNil(PushToTalkChord.parse(AppSettings.defaultHUDSummonHotkeyChord))
    }
}
