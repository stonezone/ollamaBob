import Foundation
import AppKit

// MARK: - PushToTalkChord

/// A parsed key chord consisting of modifier flags and a virtual key code.
struct PushToTalkChord: Equatable {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: UInt16

    // Virtual key code for the Space bar.
    static let spaceKeyCode: UInt16 = 49
}

// MARK: - Chord parsing

extension PushToTalkChord {

    /// Parse a human-readable chord string such as `"ctrl+opt+space"`.
    ///
    /// Recognised modifier tokens (case-insensitive):
    ///   - `ctrl` / `control`
    ///   - `opt` / `option` / `alt`
    ///   - `shift`
    ///   - `cmd` / `command`
    ///
    /// Key token: only `"space"` is currently supported.
    ///
    /// Returns `nil` if the string cannot be parsed, contains no valid key
    /// token, or specifies no modifier flags.
    static func parse(_ chordString: String) -> PushToTalkChord? {
        let tokens = chordString
            .lowercased()
            .components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var modifiers: NSEvent.ModifierFlags = []
        var keyCode: UInt16?

        for token in tokens {
            switch token {
            case "ctrl", "control":
                modifiers.insert(.control)
            case "opt", "option", "alt":
                modifiers.insert(.option)
            case "shift":
                modifiers.insert(.shift)
            case "cmd", "command":
                modifiers.insert(.command)
            case "space":
                keyCode = PushToTalkChord.spaceKeyCode
            default:
                // Unknown token — reject the whole chord.
                return nil
            }
        }

        // Must have both a recognised key and at least one modifier.
        guard let code = keyCode, !modifiers.isEmpty else { return nil }
        return PushToTalkChord(modifiers: modifiers, keyCode: code)
    }
}

// MARK: - PushToTalkHotkey

/// Installs a global NSEvent monitor for a configurable modifier+space chord.
///
/// Usage:
/// ```swift
/// let hotkey = PushToTalkHotkey(chord: "ctrl+opt+space")
/// hotkey.start()
/// ```
///
/// The listener calls `SpeechService.shared.startRecording()` on key-down and
/// `SpeechService.shared.stopRecording()` on key-up.  Both callbacks are
/// dispatched on the main thread.
///
/// `deinit` removes the global monitor automatically — no crash risk.
@MainActor
final class PushToTalkHotkey {

    // MARK: State

    private(set) var chord: PushToTalkChord?
    private var monitorDown: Any?
    private var monitorUp: Any?
    private var isHeld = false

    // MARK: Init

    /// - Parameter chordString: Human-readable chord, e.g. `"ctrl+opt+space"`.
    ///   Defaults to `AppSettings.defaultPushToTalkKeyChord`.
    init(chordString: String = AppSettings.defaultPushToTalkKeyChord) {
        self.chord = PushToTalkChord.parse(chordString)
    }

    deinit {
        // Remove monitors on whichever thread deinit fires.
        if let d = monitorDown { NSEvent.removeMonitor(d) }
        if let u = monitorUp   { NSEvent.removeMonitor(u) }
    }

    // MARK: Activation

    /// Install the global event monitors.  Safe to call more than once
    /// (re-installs if the monitors were previously removed).
    func start() {
        stop() // Remove any stale monitors first.
        guard chord != nil else { return }

        monitorDown = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        monitorUp = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
        }
    }

    /// Remove the global event monitors.
    func stop() {
        if let d = monitorDown { NSEvent.removeMonitor(d); monitorDown = nil }
        if let u = monitorUp   { NSEvent.removeMonitor(u); monitorUp   = nil }
        isHeld = false
    }

    // MARK: - Key event handling

    private func handleKeyDown(_ event: NSEvent) {
        guard let chord, !isHeld else { return }
        guard event.keyCode == chord.keyCode else { return }
        guard event.modifierFlags.intersection(chord.modifiers) == chord.modifiers else { return }

        isHeld = true
        SpeechService.shared.startRecording()
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard let chord, isHeld else { return }
        guard event.keyCode == chord.keyCode else { return }

        isHeld = false
        SpeechService.shared.stopRecording()
        deliverTranscriptIfReady()
    }

    // MARK: - Transcript delivery

    /// After stopRecording, the transcript arrives asynchronously through
    /// SpeechService.transcriptPublisher.  The WalkieTalkie notification is
    /// posted from there (see WalkieTalkieController subscription below).
    private func deliverTranscriptIfReady() {
        // Transcript delivery is handled by WalkieTalkieController which
        // subscribes to SpeechService.shared.transcriptPublisher.
    }
}

// MARK: - WalkieTalkieController

/// Bridges `SpeechService.transcriptPublisher` → `Notification` so existing
/// chat surfaces can subscribe without coupling to `SpeechService` directly.
@MainActor
final class WalkieTalkieController {

    static let shared = WalkieTalkieController()

    private var cancellable: AnyCancellable?

    private init() {
        cancellable = SpeechService.shared.transcriptPublisher
            .receive(on: RunLoop.main)
            .sink { transcript in
                let notification = Notification(
                    name: .bobWalkieTalkieTranscript,
                    object: nil,
                    userInfo: ["transcript": transcript]
                )
                if let prompt = DeskPromptActions.walkieTalkiePrompt(from: notification) {
                    DeskPromptInbox.shared.enqueue(prompt)
                }
            }
    }
}

// MARK: - Notification name

extension Notification.Name {
    /// Posted when the push-to-talk hotkey releases and speech recognition
    /// has produced a final transcript.
    ///
    /// `userInfo["transcript"]` contains the recognized `String`.
    static let bobWalkieTalkieTranscript = Notification.Name("bobWalkieTalkieTranscript")
}

// MARK: - Combine import shim
// AnyCancellable is in Combine; import at top of file.
import Combine
