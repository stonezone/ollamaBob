import AppKit
import Combine
import Foundation

/// Ambient "heartbeat" so Bob feels alive even when the user isn't chatting.
/// Fires a filler/boast voice clip + optional system notice every 10–20 minutes
/// when all of these are true:
///   • heartbeatEnabled, bobVoiceEnabled, and soundsEnabled are on,
///   • the active persona is Mumbai Bob,
///   • the agent isn't currently processing,
///   • the Bob window is key (user hasn't switched away),
///   • at least `minIdleSeconds` have passed since the last user activity.
///
/// Callbacks are dispatched on the main actor. The view layer provides the
/// "what are you working on right now" signal via `registerActivity()` so
/// the heartbeat respects the conversation.
@MainActor
final class Heartbeat: ObservableObject {

    static let shared = Heartbeat()

    /// Published one-liner a view can consume for an inline notice.
    @Published private(set) var lastNoticeText: String?
    @Published private(set) var lastNoticeAt: Date?

    private var timer: Timer?
    private var lastActivity: Date = .init()
    private var observers: [NSObjectProtocol] = []

    // Bounds — deliberately long so Bob doesn't get annoying.
    private let minIntervalSeconds: TimeInterval = 600   // 10 min
    private let maxIntervalSeconds: TimeInterval = 1200  // 20 min
    private let minIdleSeconds: TimeInterval     = 300   // don't interrupt within 5 min of last user input
    private let checkCadenceSeconds: TimeInterval = 60   // poll every minute

    private init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Treat app-deactivation as activity so the timer doesn't fire
            // the instant the user comes back.
            Task { @MainActor in self?.registerActivity() }
        })
    }

    deinit {
        for obs in observers { NotificationCenter.default.removeObserver(obs) }
    }

    /// Called by the chat view any time the user sends, types, or opens
    /// a new conversation. Resets the idle clock and schedules the next beat.
    func registerActivity() {
        lastActivity = Date()
        reschedule()
    }

    /// Start the heartbeat loop. Safe to call multiple times; idempotent.
    func start(agentIsProcessing: @escaping () -> Bool) {
        stop()
        let next = nextInterval()
        timer = Timer.scheduledTimer(withTimeInterval: checkCadenceSeconds,
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(targetInterval: next, agentIsProcessing: agentIsProcessing)
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func reschedule() {
        guard timer != nil else { return }
        // Letting the existing timer keep polling is fine; tick() reads the
        // interval on every check, so updating `lastActivity` is enough.
    }

    private func nextInterval() -> TimeInterval {
        TimeInterval.random(in: minIntervalSeconds...maxIntervalSeconds)
    }

    private func tick(targetInterval: TimeInterval,
                      agentIsProcessing: () -> Bool) {
        let settings = AppSettings.shared
        guard settings.soundsEnabled,
              settings.bobVoiceEnabled,
              settings.heartbeatEnabled else { return }
        guard PersonaStore.shared.activePersonaID == BuiltinPersonas.mumbaiBobID else { return }
        guard NSApp.isActive else { return }
        guard !agentIsProcessing() else { return }

        let idleFor = Date().timeIntervalSince(lastActivity)
        guard idleFor >= max(minIdleSeconds, targetInterval) else { return }

        // Pick a category: 50% working (fits "I'm still here"), 35% boast,
        // 15% greeting (covers the "just peeking in" vibe).
        let roll = Double.random(in: 0...1)
        let category: BobSayings.Category
        let noticeText: String
        switch roll {
        case ..<0.50:
            category = .working
            noticeText = "Bob is here sir, just working working."
        case ..<0.85:
            category = .boast
            noticeText = "Bob is employee of the month sir. Just reminding."
        default:
            category = .greeting
            noticeText = "Sir, Bob is still here, most loyal."
        }

        BobSayings.play(category)
        lastNoticeText = noticeText
        lastNoticeAt = Date()

        // Reset so the next beat is at least another random interval away.
        lastActivity = Date()
    }
}
