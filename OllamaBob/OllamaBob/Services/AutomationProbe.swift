import Foundation
import AppKit

/// Current TCC / Automation permission state for a target app.
enum AutomationStatus: Equatable {
    case unknown      // probe hasn't run yet
    case granted      // script succeeded — Automation access is live
    case denied       // -1743 — user said "Don't Allow" (or never prompted + blocked)
    case missing      // -600 / app not found — target app isn't installed or not scriptable
    case error(String)
}

/// One app OllamaBob may need to drive via AppleScript. `probeScript` is a
/// cheap no-op that forces macOS to either show the TCC prompt (first run)
/// or return the saved grant/deny decision.
struct AutomationTarget: Identifiable, Hashable {
    let id: String
    let displayName: String
    let emoji: String
    /// AppleScript body used to trigger/check access. Must be read-only and
    /// return a value so success is unambiguous.
    let probeScript: String
}

/// Pokes macOS's Automation TCC system once per target so the user sees
/// every "OllamaBob wants to control X" prompt up front, instead of
/// discovering them mid-conversation. Driven from Onboarding and from
/// Preferences → Tools → Permissions.
@MainActor
final class AutomationProbe: ObservableObject {

    static let shared = AutomationProbe()

    /// Ordered list of apps OllamaBob commonly talks to. Finder and System
    /// Events are bundled because a lot of casual AppleScript depends on
    /// them; Music is here because "play something relaxing" is a classic
    /// Bob prompt.
    static let targets: [AutomationTarget] = [
        AutomationTarget(id: "mail", displayName: "Mail", emoji: "📧",
                         probeScript: "tell application \"Mail\" to return name"),
        AutomationTarget(id: "calendar", displayName: "Calendar", emoji: "📅",
                         probeScript: "tell application \"Calendar\" to return name"),
        AutomationTarget(id: "reminders", displayName: "Reminders", emoji: "✅",
                         probeScript: "tell application \"Reminders\" to return name"),
        AutomationTarget(id: "contacts", displayName: "Contacts", emoji: "👤",
                         probeScript: "tell application \"Contacts\" to return name"),
        AutomationTarget(id: "music", displayName: "Music", emoji: "🎵",
                         probeScript: "tell application \"Music\" to return name"),
        AutomationTarget(id: "finder", displayName: "Finder", emoji: "🗂",
                         probeScript: "tell application \"Finder\" to return name"),
        AutomationTarget(id: "system_events", displayName: "System Events", emoji: "⚙️",
                         probeScript: "tell application \"System Events\" to return name"),
    ]

    @Published private(set) var statuses: [String: AutomationStatus] = [:]
    @Published private(set) var isProbing: Bool = false
    @Published private(set) var currentTargetID: String?

    private init() {
        for target in Self.targets {
            statuses[target.id] = .unknown
        }
    }

    /// Run the probe against every target in order. Each call may block
    /// the calling actor waiting on a system TCC prompt — that's fine,
    /// the prompt is handled by `tccd` in a separate process.
    func probeAll() async {
        guard !isProbing else { return }
        isProbing = true
        defer {
            isProbing = false
            currentTargetID = nil
        }
        for target in Self.targets {
            currentTargetID = target.id
            statuses[target.id] = await probe(target)
        }
    }

    /// Run the probe against a single target (used by "Grant" row buttons).
    func probe(_ target: AutomationTarget) async -> AutomationStatus {
        currentTargetID = target.id
        let result = Self.runProbeScript(target.probeScript)
        statuses[target.id] = result
        currentTargetID = nil
        return result
    }

    /// Opens System Settings → Privacy & Security → Automation so the user
    /// can flip a previously-denied switch back on (macOS gives no way to
    /// re-prompt once denied — the user must toggle it manually).
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        if let url { NSWorkspace.shared.open(url) }
    }

    private static func runProbeScript(_ script: String) -> AutomationStatus {
        guard let apple = NSAppleScript(source: script) else {
            return .error("Could not parse probe script")
        }
        var errorInfo: NSDictionary?
        _ = apple.executeAndReturnError(&errorInfo)
        if let err = errorInfo as? [String: Any] {
            let number = err["NSAppleScriptErrorNumber"] as? Int ?? 0
            switch number {
            case -1743:
                return .denied
            case -600, -1728:
                // -600: target app isn't running/installed. -1728: "Can't get X"
                // usually means authed but the expected object wasn't found.
                // Treat missing as its own signal; -1728 means the channel
                // is open, so call it granted.
                return number == -600 ? .missing : .granted
            default:
                let message = (err["NSAppleScriptErrorMessage"] as? String)
                    ?? (err["NSAppleScriptErrorBriefMessage"] as? String)
                    ?? "AppleScript error"
                return .error("\(message) (\(number))")
            }
        }
        return .granted
    }
}
