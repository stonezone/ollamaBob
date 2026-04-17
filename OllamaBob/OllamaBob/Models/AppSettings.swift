import Foundation
import Combine

/// Singleton store for user preferences, backed by UserDefaults.
/// Consumed by PreferencesView and AvatarWindow to react to live changes.
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    @Published var showBob: Bool {
        didSet { UserDefaults.standard.set(showBob, forKey: Keys.showBob) }
    }

    @Published var chatWindowOpacity: Double {
        didSet { UserDefaults.standard.set(chatWindowOpacity, forKey: Keys.chatWindowOpacity) }
    }

    /// Context window size passed to Ollama as `options.num_ctx`. Must be one
    /// of `AppConfig.numCtxAllowed`. Invalid stored values are snapped back
    /// to the default on load.
    @Published var numCtx: Int {
        didSet { UserDefaults.standard.set(numCtx, forKey: Keys.numCtx) }
    }

    /// Master switch for beta tools (Phase 3.5). Default OFF. When off,
    /// ToolRuntime.isLive returns false for any catalog entry with beta=true,
    /// which hides them from the cheat sheet, tool_help("list"), and the
    /// approval policy stays at .forbidden for them.
    @Published var betaToolsEnabled: Bool {
        didSet { UserDefaults.standard.set(betaToolsEnabled, forKey: Keys.betaToolsEnabled) }
    }

    @Published var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: Keys.soundsEnabled) }
    }

    /// Play pre-rendered ElevenLabs Bob voice lines on greetings, celebrations,
    /// and idle-returns. Mumbai Bob persona only (the voice doesn't match the
    /// others). Separate from soundsEnabled because voice is more obtrusive
    /// than a Tink; some users will want UI sounds on but voice off.
    @Published var bobVoiceEnabled: Bool {
        didSet { UserDefaults.standard.set(bobVoiceEnabled, forKey: Keys.bobVoiceEnabled) }
    }

    /// Occasional "heartbeat" pings: when Bob has been idle for a while and the
    /// app is frontmost, he plays a filler/boast clip and appends a one-line
    /// system notice — so he feels alive even when the user isn't actively
    /// chatting. Defaults OFF because it's the most intrusive auto-behavior.
    @Published var heartbeatEnabled: Bool {
        didSet { UserDefaults.standard.set(heartbeatEnabled, forKey: Keys.heartbeatEnabled) }
    }

    private enum Keys {
        static let showBob           = "showBob"
        static let chatWindowOpacity = "chatWindowOpacity"
        static let numCtx            = "numCtx"
        static let betaToolsEnabled  = "betaToolsEnabled"
        static let soundsEnabled     = "soundsEnabled"
        static let bobVoiceEnabled   = "bobVoiceEnabled"
        static let heartbeatEnabled  = "heartbeatEnabled"
    }

    private init() {
        let defaults = UserDefaults.standard

        // Write first-launch defaults only when no value exists yet.
        if defaults.object(forKey: Keys.showBob) == nil {
            defaults.set(true, forKey: Keys.showBob)
        }
        if defaults.object(forKey: Keys.chatWindowOpacity) == nil {
            defaults.set(1.0, forKey: Keys.chatWindowOpacity)
        }
        if defaults.object(forKey: Keys.numCtx) == nil {
            defaults.set(AppConfig.numCtx, forKey: Keys.numCtx)
        }
        // Beta tools default OFF per V2 plan §3.5.
        if defaults.object(forKey: Keys.betaToolsEnabled) == nil {
            defaults.set(false, forKey: Keys.betaToolsEnabled)
        }
        if defaults.object(forKey: Keys.soundsEnabled) == nil {
            defaults.set(true, forKey: Keys.soundsEnabled)
        }
        if defaults.object(forKey: Keys.bobVoiceEnabled) == nil {
            defaults.set(true, forKey: Keys.bobVoiceEnabled)
        }
        if defaults.object(forKey: Keys.heartbeatEnabled) == nil {
            defaults.set(false, forKey: Keys.heartbeatEnabled)
        }

        self.showBob           = defaults.bool(forKey: Keys.showBob)
        self.chatWindowOpacity = defaults.double(forKey: Keys.chatWindowOpacity)
        self.betaToolsEnabled  = defaults.bool(forKey: Keys.betaToolsEnabled)
        self.soundsEnabled     = defaults.bool(forKey: Keys.soundsEnabled)
        self.bobVoiceEnabled   = defaults.bool(forKey: Keys.bobVoiceEnabled)
        self.heartbeatEnabled  = defaults.bool(forKey: Keys.heartbeatEnabled)

        let storedCtx = defaults.integer(forKey: Keys.numCtx)
        self.numCtx = AppConfig.numCtxAllowed.contains(storedCtx) ? storedCtx : AppConfig.numCtx
    }
}
