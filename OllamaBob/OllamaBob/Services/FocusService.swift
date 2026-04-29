import Foundation
import AppKit
import Combine

/// Observes the frontmost application and requests persona swaps when the
/// bundle ID matches a configured mapping.
///
/// Rules:
/// - Default OFF; only active when `AppSettings.focusGuardianEnabled == true`.
/// - Manual lock (`manualLockEnabled`) always wins — no auto-swaps while locked.
/// - Debounce: app switches within `debounceInterval` of each other are ignored
///   to avoid persona thrashing during Cmd-Tab bursts.
/// - Only writes to `PersonaStore.shared.activePersonaID`; no tool or approval
///   side effects.
@MainActor
final class FocusService: ObservableObject {

    // MARK: - Singleton

    static let shared = FocusService()

    // MARK: - Published state

    /// Bundle ID of the most recently seen frontmost application (after
    /// debounce). `nil` until the first qualifying activation event.
    @Published private(set) var lastFrontmostBundleID: String?

    /// When true, auto-persona-swaps are suppressed. The user chose a persona
    /// manually and does not want Focus Guardian to override it.
    @Published private(set) var manualLockEnabled: Bool = false

    /// Human-readable label for the last swap reason, e.g. "Xcode → Terse Engineer".
    @Published private(set) var lastSwapReason: String?

    // MARK: - Configuration

    /// Minimum seconds between accepted app-switch events. Switches arriving
    /// faster than this are discarded (debounce against Cmd-Tab bursts).
    var debounceInterval: TimeInterval = 5.0

    // MARK: - Private

    private var observation: NSObjectProtocol?
    private var lastActivationDate: Date = .distantPast

    /// Injected clock for test overrides. Defaults to `Date()`.
    var now: () -> Date = { Date() }

    // MARK: - Lifecycle

    private init() {}

    /// Begins observing `NSWorkspace.shared.notificationCenter` for app
    /// activation events. No-op if already observing.
    func start() {
        guard observation == nil else { return }
        observation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleActivation(notification)
            }
        }
    }

    /// Stops observing. Safe to call if not started.
    func stop() {
        if let obs = observation {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            observation = nil
        }
    }

    // MARK: - Manual lock

    /// Toggle the manual persona lock. When `on`, no automatic swaps occur.
    func setManualLock(_ on: Bool) {
        manualLockEnabled = on
    }

    // MARK: - Swap (also callable directly for testing)

    /// Evaluates a bundle ID and swaps the active persona if conditions allow.
    ///
    /// Returns the persona ID that was applied, or `nil` if no swap occurred.
    @discardableResult
    func applySwap(for bundleID: String) -> String? {
        // Lock check: manual lock always wins.
        guard !manualLockEnabled else { return nil }

        // Mapping check.
        let overrides = AppSettings.shared.focusGuardianOverrides
        guard let personaID = FocusBundleMapping.personaID(for: bundleID, overrides: overrides) else {
            return nil
        }

        // No-op if already on the target persona.
        guard PersonaStore.shared.activePersonaID != personaID else { return nil }

        PersonaStore.shared.activePersonaID = personaID
        lastFrontmostBundleID = bundleID
        lastSwapReason = "\(bundleID) → \(personaID)"
        return personaID
    }

    // MARK: - Private helpers

    private func handleActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              let bundleID = app.bundleIdentifier
        else { return }

        // Debounce: ignore rapid app switches.
        let currentDate = now()
        let elapsed = currentDate.timeIntervalSince(lastActivationDate)
        guard elapsed >= debounceInterval else { return }

        lastActivationDate = currentDate
        applySwap(for: bundleID)
    }
}
