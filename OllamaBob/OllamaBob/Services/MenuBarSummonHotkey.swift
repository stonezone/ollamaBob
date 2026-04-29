import Foundation
import AppKit

extension Notification.Name {
    /// Posted when Preferences toggles or rebinds the HUD summon hotkey.
    /// `AppState` observes this to restart its `MenuBarSummonHotkey` listener.
    static let bobHUDSummonHotkeyChanged = Notification.Name("bobHUDSummonHotkeyChanged")
}

/// Global hotkey listener that summons the floating HUD from anywhere in
/// macOS. Unlike `PushToTalkHotkey`, this one fires once on key-down (tap
/// semantics, not hold) and dispatches a single action callback on the
/// main thread.
///
/// Reuses `PushToTalkChord` for chord parsing so the syntax (`ctrl+opt+space`,
/// `cmd+shift+space`, etc.) stays consistent across the two hotkey surfaces.
@MainActor
final class MenuBarSummonHotkey {

    // MARK: State

    private(set) var chord: PushToTalkChord?
    private var monitorDown: Any?

    /// Action invoked on key-down. Set by the owner before calling `start()`.
    var onSummon: (() -> Void)?

    // MARK: Init

    init(chordString: String) {
        self.chord = PushToTalkChord.parse(chordString)
    }

    deinit {
        if let d = monitorDown { NSEvent.removeMonitor(d) }
    }

    // MARK: Activation

    /// Install the global event monitor. Safe to call more than once
    /// (re-installs cleanly).
    func start() {
        stop()
        guard chord != nil else { return }

        monitorDown = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    /// Remove the global event monitor.
    func stop() {
        if let d = monitorDown { NSEvent.removeMonitor(d); monitorDown = nil }
    }

    /// Replace the chord at runtime. Caller must `stop()` and `start()`
    /// around this if the listener is currently active and the chord
    /// string actually changed.
    func updateChord(_ chordString: String) {
        chord = PushToTalkChord.parse(chordString)
    }

    // MARK: - Key event handling

    private func handleKeyDown(_ event: NSEvent) {
        guard let chord else { return }
        guard event.keyCode == chord.keyCode else { return }
        guard event.modifierFlags.intersection(chord.modifiers) == chord.modifiers else { return }

        // Dispatch onto the main actor explicitly even though the monitor
        // already delivers on the main queue — keeps the contract obvious
        // for callers that bind UI from this closure.
        Task { @MainActor in
            self.onSummon?()
        }
    }
}
