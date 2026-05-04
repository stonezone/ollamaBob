import Foundation
import Combine

/// Singleton store for user preferences, backed by UserDefaults.
/// Consumed by PreferencesView and AvatarWindow to react to live changes.
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()
    nonisolated static let defaultUncensoredModelName = "huihui_ai/qwen3-abliterated:8b"
    nonisolated static let braveAPIKeyKey = "braveAPIKey"
    nonisolated static let jarvisPhoneEnabledKey = "jarvisPhoneEnabled"
    nonisolated static let jarvisAPIKeyKey = "jarvisAPIKey"
    nonisolated static let jarvisOperatorSecretKey = "jarvisOperatorSecret"
    nonisolated static let toolApprovalOverridesKey = "toolApprovalOverrides"
    nonisolated static let useMockedJarvisClientKey = "useMockedJarvisClient"
    nonisolated static let activityTimelineEnabledKey = "activityTimelineEnabled"
    nonisolated static let debugLoggingEnabledKey = "debugLoggingEnabled"

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

    /// Standard-mode model tag. Uncensored conversations use
    /// `uncensoredModelName` instead and keep tools/compaction disabled.
    @Published var standardModelName: String {
        didSet { UserDefaults.standard.set(standardModelName, forKey: Keys.standardModelName) }
    }

    /// Master switch for beta tools (Phase 3.5). Default OFF. When off,
    /// ToolRuntime.isLive returns false for any catalog entry with beta=true,
    /// which hides them from the cheat sheet, tool_help("list"), and the
    /// approval policy stays at .forbidden for them.
    @Published var betaToolsEnabled: Bool {
        didSet { UserDefaults.standard.set(betaToolsEnabled, forKey: Keys.betaToolsEnabled) }
    }

    /// Per-tool approval overrides from Preferences > Tools. Values are
    /// `ToolApprovalSetting.rawValue`; missing keys use the built-in policy.
    @Published var toolApprovalOverrides: [String: String] {
        didSet { UserDefaults.standard.set(toolApprovalOverrides, forKey: Self.toolApprovalOverridesKey) }
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

    /// Master switch for the local activity timeline. Default OFF; when
    /// enabled, Bob records local tool/chat events for later timeline search.
    @Published var activityTimelineEnabled: Bool {
        didSet { UserDefaults.standard.set(activityTimelineEnabled, forKey: Self.activityTimelineEnabledKey) }
    }

    /// Debug logging (v1.0.46). When ON, every Ollama request/response,
    /// tool dispatch, guard fire, and timeout is appended to a session
    /// log file under `~/Library/Logs/OllamaBob/`. Default OFF — turn on
    /// only while reproducing a bug, then ship the log file.
    @Published var debugLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(debugLoggingEnabled, forKey: Self.debugLoggingEnabledKey)
            DebugLog.enabled = debugLoggingEnabled
            if debugLoggingEnabled {
                DebugLog.startNewSession()
                DebugLog.log(.agent, "debug-logging enabled by user")
            }
        }
    }

    /// When true, Bob's Desk renders only the avatar + an input bubble +
    /// Bob's speech bubble — the transcript, status line, and tool trace
    /// are all hidden. The user still drives a real conversation; the only
    /// thing removed is the "terminal" surface.
    @Published var avatarOnlyMode: Bool {
        didSet { UserDefaults.standard.set(avatarOnlyMode, forKey: Keys.avatarOnlyMode) }
    }

    /// Last-seen window frame in full mode. Restored when the user flips
    /// back from avatar-only. Stored as `NSStringFromRect` so NSWindow can
    /// round-trip it.
    @Published var fullModeWindowFrame: String {
        didSet { UserDefaults.standard.set(fullModeWindowFrame, forKey: Keys.fullModeWindowFrame) }
    }

    /// Last-seen window frame in avatar-only mode. Separate from full mode
    /// so the user can park each layout in its own spot on the screen.
    @Published var avatarModeWindowFrame: String {
        didSet { UserDefaults.standard.set(avatarModeWindowFrame, forKey: Keys.avatarModeWindowFrame) }
    }

    /// Last-seen frame for the floating HUD scene. HUD persists separately
    /// from the chat window so users can park it on a different display
    /// or screen edge without disturbing Bob's Desk.
    @Published var hudWindowFrame: String {
        didSet { UserDefaults.standard.set(hudWindowFrame, forKey: Keys.hudWindowFrame) }
    }

    /// HUD always-on-top toggle. When true, the HUD sits above all
    /// non-fullscreen windows even after losing focus.
    @Published var hudAlwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(hudAlwaysOnTop, forKey: Keys.hudAlwaysOnTop) }
    }

    /// Global hotkey for summoning the floating HUD anywhere in macOS.
    /// Default ON so ⌘⇧Space summons Bob out of the box; users where this
    /// collides with Spotlight Finder Search can flip it off in Preferences.
    @Published var hudSummonHotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(hudSummonHotkeyEnabled, forKey: Keys.hudSummonHotkeyEnabled) }
    }

    /// Human-readable chord (`cmd+shift+space` style) for the HUD summon
    /// hotkey.
    @Published var hudSummonHotkeyChord: String {
        didSet { UserDefaults.standard.set(hudSummonHotkeyChord, forKey: Keys.hudSummonHotkeyChord) }
    }

    /// Default summon chord. ⌘⇧Space matches the original UI plan; users on
    /// stock macOS where this collides with Spotlight Finder Search can
    /// rebind in Preferences.
    static let defaultHUDSummonHotkeyChord = "cmd+shift+space"

    /// Master switch for rich presentation. When disabled, Bob should not
    /// see the `present` tool and chat should hide artifact chips.
    @Published var richPresentationEnabled: Bool {
        didSet { UserDefaults.standard.set(richPresentationEnabled, forKey: Keys.richPresentationEnabled) }
    }

    /// Allow Bob-authored HTML to load remote images/styles. Disabling this
    /// keeps the rich view self-contained.
    @Published var richPresentationRemoteResourcesEnabled: Bool {
        didSet { UserDefaults.standard.set(richPresentationRemoteResourcesEnabled, forKey: Keys.richPresentationRemoteResourcesEnabled) }
    }

    /// Show detected "Open" chips under assistant messages for supported
    /// markdown artifacts. Bob-initiated presentation still works when OFF.
    @Published var richPresentationArtifactChipsEnabled: Bool {
        didSet { UserDefaults.standard.set(richPresentationArtifactChipsEnabled, forKey: Keys.richPresentationArtifactChipsEnabled) }
    }

    /// Master gate for Naughty Bob UI. When disabled, chat surfaces hide the
    /// per-conversation uncensored toggle and any visible mode badge.
    @Published var uncensoredModeAvailable: Bool {
        didSet { UserDefaults.standard.set(uncensoredModeAvailable, forKey: Keys.uncensoredModeAvailable) }
    }

    /// Configurable Ollama tag for the uncensored model path. The raw string is
    /// preserved as typed so the Preferences text field behaves naturally;
    /// callers that need a usable tag should read `effectiveUncensoredModelName`.
    @Published var uncensoredModelName: String {
        didSet { UserDefaults.standard.set(uncensoredModelName, forKey: Keys.uncensoredModelName) }
    }

    /// Brave Search API key used by the web_search tool. Persisted to the
    /// macOS Keychain; UserDefaults is legacy-only for first-launch migration.
    @Published var braveAPIKey: String {
        didSet { Self.persistSecret(braveAPIKey, secret: .braveAPIKey, legacyKey: Self.braveAPIKeyKey) }
    }

    /// Master switch for the Jarvis phone service integration. When off,
    /// Bob hides the phone settings warning and the future phone tools stay
    /// out of the registry.
    @Published var jarvisPhoneEnabled: Bool {
        didSet { UserDefaults.standard.set(jarvisPhoneEnabled, forKey: Self.jarvisPhoneEnabledKey) }
    }

    /// Shared secret for the local Jarvis daemon. Phase 0c: persists to
    /// the macOS Keychain via `KeychainService`. UserDefaults is no longer
    /// the storage of record but is cleared on write so legacy installs
    /// stop carrying a plaintext copy.
    @Published var jarvisAPIKey: String {
        didSet { Self.persistSecret(jarvisAPIKey, secret: .jarvisAPIKey, legacyKey: Self.jarvisAPIKeyKey) }
    }

    /// When true, JarvisCallClientFactory returns JarvisCallClientMock instead of
    /// JarvisCallClientHTTP. Default: FALSE; DEBUG builds expose a Preferences
    /// override for deterministic local demos/tests.
    /// Only has an effect in DEBUG builds — the factory ignores this flag in release.
    @Published var useMockedJarvisClient: Bool {
        didSet { UserDefaults.standard.set(useMockedJarvisClient, forKey: Self.useMockedJarvisClientKey) }
    }

    /// Outer operator-auth secret required by the Jarvis daemon before the
    /// inner call API key is even checked. See `jarvisAPIKey` for storage.
    @Published var jarvisOperatorSecret: String {
        didSet { Self.persistSecret(jarvisOperatorSecret, secret: .jarvisOperatorSecret, legacyKey: Self.jarvisOperatorSecretKey) }
    }

    private static func persistSecret(_ value: String, secret: KeychainSecretKey, legacyKey: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? KeychainService.current.delete(secret)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        } else {
            try? KeychainService.current.write(trimmed, for: secret)
            // Clear the legacy slot once we've successfully written
            // to the Keychain. UserDefaults no longer carries the secret.
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    // MARK: - Walkie-Talkie push-to-talk settings

    /// Default chord string for the push-to-talk hotkey.
    nonisolated static let defaultPushToTalkKeyChord = "ctrl+opt+space"

    /// Master switch for the push-to-talk walkie-talkie mode. Default OFF.
    @Published var pushToTalkEnabled: Bool {
        didSet { UserDefaults.standard.set(pushToTalkEnabled, forKey: Keys.pushToTalkEnabled) }
    }

    /// Human-readable key chord for the push-to-talk hotkey, e.g. "ctrl+opt+space".
    @Published var pushToTalkKeyChord: String {
        didSet { UserDefaults.standard.set(pushToTalkKeyChord, forKey: Keys.pushToTalkKeyChord) }
    }

    // MARK: - Focus Guardian (Phase 7c)

    /// Master switch for Focus Guardian. Default OFF (must opt-in).
    /// When enabled, FocusService observes the frontmost app and swaps the
    /// active persona when the bundle ID matches a known mapping.
    @Published var focusGuardianEnabled: Bool {
        didSet { UserDefaults.standard.set(focusGuardianEnabled, forKey: Keys.focusGuardianEnabled) }
    }

    // MARK: - Clipboard Cortex (Phase 7d)

    /// Master switch for Clipboard Cortex. Default OFF (must opt-in).
    /// When enabled, ClipboardWatcher polls the clipboard and surfaces a chip
    /// in the menu-bar dropdown when actionable content is detected.
    @Published var clipboardCortexEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardCortexEnabled, forKey: Keys.clipboardCortexEnabled) }
    }

    // MARK: - Daily Briefing (Phase 7e)

    /// Master switch for the Daily Briefing scheduler. Default OFF (must opt-in).
    /// When enabled, `SchedulerService` fires a read-only briefing at the
    /// configured time each day.
    @Published var briefingScheduleEnabled: Bool {
        didSet { UserDefaults.standard.set(briefingScheduleEnabled, forKey: Keys.briefingScheduleEnabled) }
    }

    /// Target time-of-day for the daily briefing expressed as minutes since
    /// midnight (0–1439). Default 420 = 07:00 local time.
    @Published var briefingScheduleMinutes: Int {
        didSet { UserDefaults.standard.set(briefingScheduleMinutes, forKey: Keys.briefingScheduleMinutes) }
    }

    /// User-level overrides for the bundle-ID → persona-ID mapping.
    /// Keys are bundle identifiers; values are persona IDs. An empty value
    /// string removes a built-in default for that bundle ID.
    @Published var focusGuardianOverrides: [String: String] {
        didSet { UserDefaults.standard.set(focusGuardianOverrides, forKey: Keys.focusGuardianOverrides) }
    }

    private enum Keys {
        static let showBob               = "showBob"
        static let chatWindowOpacity     = "chatWindowOpacity"
        static let numCtx                = "numCtx"
        static let standardModelName     = "standardModelName"
        static let betaToolsEnabled      = "betaToolsEnabled"
        static let soundsEnabled         = "soundsEnabled"
        static let bobVoiceEnabled       = "bobVoiceEnabled"
        static let heartbeatEnabled      = "heartbeatEnabled"
        static let avatarOnlyMode        = "avatarOnlyMode"
        static let fullModeWindowFrame   = "fullModeWindowFrame"
        static let avatarModeWindowFrame = "avatarModeWindowFrame"
        static let hudWindowFrame        = "hudWindowFrame"
        static let hudAlwaysOnTop        = "hudAlwaysOnTop"
        static let hudSummonHotkeyEnabled = "hudSummonHotkeyEnabled"
        static let hudSummonHotkeyChord   = "hudSummonHotkeyChord"
        static let richPresentationEnabled = "richPresentationEnabled"
        static let richPresentationRemoteResourcesEnabled = "richPresentationRemoteResourcesEnabled"
        static let richPresentationArtifactChipsEnabled = "richPresentationArtifactChipsEnabled"
        static let uncensoredModeAvailable = "uncensoredModeAvailable"
        static let uncensoredModelName = "uncensoredModelName"
        static let pushToTalkEnabled       = "pushToTalkEnabled"
        static let pushToTalkKeyChord      = "pushToTalkKeyChord"
        static let focusGuardianEnabled    = "focusGuardianEnabled"
        static let focusGuardianOverrides  = "focusGuardianOverrides"
        static let clipboardCortexEnabled    = "clipboardCortexEnabled"
        static let briefingScheduleEnabled   = "briefingScheduleEnabled"
        static let briefingScheduleMinutes   = "briefingScheduleMinutes"
    }

    private static let defaultMockedJarvisClient = false

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
        if defaults.object(forKey: Keys.standardModelName) == nil {
            defaults.set(AppConfig.primaryModel, forKey: Keys.standardModelName)
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
        if defaults.object(forKey: Keys.avatarOnlyMode) == nil {
            defaults.set(false, forKey: Keys.avatarOnlyMode)
        }
        if defaults.object(forKey: Keys.richPresentationEnabled) == nil {
            defaults.set(true, forKey: Keys.richPresentationEnabled)
        }
        if defaults.object(forKey: Keys.richPresentationRemoteResourcesEnabled) == nil {
            defaults.set(true, forKey: Keys.richPresentationRemoteResourcesEnabled)
        }
        if defaults.object(forKey: Keys.richPresentationArtifactChipsEnabled) == nil {
            defaults.set(true, forKey: Keys.richPresentationArtifactChipsEnabled)
        }
        if defaults.object(forKey: Keys.uncensoredModeAvailable) == nil {
            defaults.set(false, forKey: Keys.uncensoredModeAvailable)
        }
        if defaults.object(forKey: Keys.uncensoredModelName) == nil {
            defaults.set(Self.defaultUncensoredModelName, forKey: Keys.uncensoredModelName)
        }
        if defaults.object(forKey: Self.jarvisPhoneEnabledKey) == nil {
            defaults.set(false, forKey: Self.jarvisPhoneEnabledKey)
        }
        if defaults.object(forKey: Self.useMockedJarvisClientKey) == nil {
            defaults.set(Self.defaultMockedJarvisClient, forKey: Self.useMockedJarvisClientKey)
        }
        if defaults.object(forKey: Self.activityTimelineEnabledKey) == nil {
            defaults.set(false, forKey: Self.activityTimelineEnabledKey)
        }
        if defaults.object(forKey: Self.debugLoggingEnabledKey) == nil {
            defaults.set(false, forKey: Self.debugLoggingEnabledKey)
        }
        // Walkie-Talkie push-to-talk: default OFF / default chord.
        if defaults.object(forKey: Keys.pushToTalkEnabled) == nil {
            defaults.set(false, forKey: Keys.pushToTalkEnabled)
        }
        if defaults.object(forKey: Keys.pushToTalkKeyChord) == nil {
            defaults.set(Self.defaultPushToTalkKeyChord, forKey: Keys.pushToTalkKeyChord)
        }
        // Focus Guardian: default OFF (must opt-in), empty overrides dict.
        if defaults.object(forKey: Keys.focusGuardianEnabled) == nil {
            defaults.set(false, forKey: Keys.focusGuardianEnabled)
        }
        if defaults.object(forKey: Keys.focusGuardianOverrides) == nil {
            defaults.set([String: String](), forKey: Keys.focusGuardianOverrides)
        }
        // Clipboard Cortex: default OFF (must opt-in).
        if defaults.object(forKey: Keys.clipboardCortexEnabled) == nil {
            defaults.set(false, forKey: Keys.clipboardCortexEnabled)
        }
        // Daily Briefing: default OFF + 07:00 (must opt-in per spec).
        if defaults.object(forKey: Keys.briefingScheduleEnabled) == nil {
            defaults.set(false, forKey: Keys.briefingScheduleEnabled)
        }
        if defaults.object(forKey: Keys.briefingScheduleMinutes) == nil {
            defaults.set(BriefingSchedule.defaultTimeOfDayMinutes, forKey: Keys.briefingScheduleMinutes)
        }
        // Phase 0c: secrets live in the Keychain. We no longer write the
        // .env value into UserDefaults on first launch (that path is what
        // SecretMigration is migrating *out of*). Tests / CI seed the
        // Keychain directly when needed.

        self.showBob               = defaults.bool(forKey: Keys.showBob)
        self.chatWindowOpacity     = defaults.double(forKey: Keys.chatWindowOpacity)
        self.standardModelName     = defaults.string(forKey: Keys.standardModelName) ?? AppConfig.primaryModel
        self.betaToolsEnabled      = defaults.bool(forKey: Keys.betaToolsEnabled)
        self.toolApprovalOverrides = defaults.dictionary(forKey: Self.toolApprovalOverridesKey) as? [String: String] ?? [:]
        self.soundsEnabled         = defaults.bool(forKey: Keys.soundsEnabled)
        self.bobVoiceEnabled       = defaults.bool(forKey: Keys.bobVoiceEnabled)
        self.heartbeatEnabled      = defaults.bool(forKey: Keys.heartbeatEnabled)
        self.activityTimelineEnabled = defaults.bool(forKey: Self.activityTimelineEnabledKey)
        // `debugLoggingEnabled` initialized here; DebugLog.enabled is
        // mirrored AFTER full self-initialization at the bottom of init
        // (Swift's strict-init forbids `self.x` reads before every
        // stored property has been assigned).
        self.debugLoggingEnabled   = defaults.bool(forKey: Self.debugLoggingEnabledKey)
        self.avatarOnlyMode        = defaults.bool(forKey: Keys.avatarOnlyMode)
        self.fullModeWindowFrame   = defaults.string(forKey: Keys.fullModeWindowFrame) ?? ""
        self.avatarModeWindowFrame = defaults.string(forKey: Keys.avatarModeWindowFrame) ?? ""
        self.hudWindowFrame        = defaults.string(forKey: Keys.hudWindowFrame) ?? ""
        if defaults.object(forKey: Keys.hudAlwaysOnTop) == nil {
            defaults.set(true, forKey: Keys.hudAlwaysOnTop)
        }
        self.hudAlwaysOnTop        = defaults.bool(forKey: Keys.hudAlwaysOnTop)
        if defaults.object(forKey: Keys.hudSummonHotkeyEnabled) == nil {
            // Default ON so ⌘⇧Space summons Bob's HUD out of the box.
            defaults.set(true, forKey: Keys.hudSummonHotkeyEnabled)
        }
        self.hudSummonHotkeyEnabled = defaults.bool(forKey: Keys.hudSummonHotkeyEnabled)
        if defaults.object(forKey: Keys.hudSummonHotkeyChord) == nil {
            defaults.set(Self.defaultHUDSummonHotkeyChord, forKey: Keys.hudSummonHotkeyChord)
        }
        self.hudSummonHotkeyChord  = defaults.string(forKey: Keys.hudSummonHotkeyChord) ?? Self.defaultHUDSummonHotkeyChord
        self.richPresentationEnabled = defaults.bool(forKey: Keys.richPresentationEnabled)
        self.richPresentationRemoteResourcesEnabled = defaults.bool(forKey: Keys.richPresentationRemoteResourcesEnabled)
        self.richPresentationArtifactChipsEnabled = defaults.bool(forKey: Keys.richPresentationArtifactChipsEnabled)
        self.uncensoredModeAvailable = defaults.bool(forKey: Keys.uncensoredModeAvailable)
        self.uncensoredModelName = defaults.string(forKey: Keys.uncensoredModelName) ?? Self.defaultUncensoredModelName
        self.braveAPIKey = KeychainService.current.read(.braveAPIKey)
            ?? defaults.string(forKey: Self.braveAPIKeyKey)
            ?? ""
        self.jarvisPhoneEnabled = defaults.bool(forKey: Self.jarvisPhoneEnabledKey)
        self.useMockedJarvisClient = defaults.bool(forKey: Self.useMockedJarvisClientKey)
        self.pushToTalkEnabled  = defaults.bool(forKey: Keys.pushToTalkEnabled)
        self.pushToTalkKeyChord = defaults.string(forKey: Keys.pushToTalkKeyChord) ?? Self.defaultPushToTalkKeyChord
        self.focusGuardianEnabled   = defaults.bool(forKey: Keys.focusGuardianEnabled)
        self.focusGuardianOverrides = defaults.dictionary(forKey: Keys.focusGuardianOverrides) as? [String: String] ?? [:]
        self.clipboardCortexEnabled = defaults.bool(forKey: Keys.clipboardCortexEnabled)
        self.briefingScheduleEnabled = defaults.bool(forKey: Keys.briefingScheduleEnabled)
        self.briefingScheduleMinutes = {
            let stored = defaults.integer(forKey: Keys.briefingScheduleMinutes)
            // If the key was never set, integer(forKey:) returns 0 which maps to
            // 00:00 — not the 07:00 default. Guard against that here.
            return stored == 0 && defaults.object(forKey: Keys.briefingScheduleMinutes) == nil
                ? BriefingSchedule.defaultTimeOfDayMinutes
                : max(0, min(stored, 1439))
        }()
        // Phase 0c: read Keychain first; fall back to legacy UserDefaults so
        // an un-migrated install still shows the existing key in Preferences.
        self.jarvisAPIKey = KeychainService.current.read(.jarvisAPIKey)
            ?? defaults.string(forKey: Self.jarvisAPIKeyKey)
            ?? ""
        self.jarvisOperatorSecret = KeychainService.current.read(.jarvisOperatorSecret)
            ?? defaults.string(forKey: Self.jarvisOperatorSecretKey)
            ?? ""

        let storedCtx = defaults.integer(forKey: Keys.numCtx)
        self.numCtx = AppConfig.numCtxAllowed.contains(storedCtx) ? storedCtx : AppConfig.numCtx

        // Mirror the persisted toggle into DebugLog so any call site
        // (including those reached during early launch, before the UI
        // has a chance to flip it) is gated correctly. Done at the end
        // of init so all stored properties are guaranteed initialized
        // (Swift's strict-init forbids `self.x` reads before that).
        DebugLog.enabled = self.debugLoggingEnabled
    }

    var effectiveUncensoredModelName: String {
        let trimmed = uncensoredModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultUncensoredModelName : trimmed
    }

    var effectiveStandardModelName: String {
        let trimmed = standardModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppConfig.primaryModel : trimmed
    }

    nonisolated static func storedToolApprovalOverride(for toolName: String) -> ToolApprovalSetting? {
        guard let raw = (UserDefaults.standard.dictionary(forKey: toolApprovalOverridesKey) as? [String: String])?[toolName] else {
            return nil
        }
        return ToolApprovalSetting(rawValue: raw)
    }

    func toolApprovalOverride(for toolName: String) -> ToolApprovalSetting? {
        guard let raw = toolApprovalOverrides[toolName] else { return nil }
        return ToolApprovalSetting(rawValue: raw)
    }

    func setToolApprovalOverride(_ setting: ToolApprovalSetting, for toolName: String) {
        var overrides = toolApprovalOverrides
        overrides[toolName] = setting.rawValue
        toolApprovalOverrides = overrides
    }

    func cycleToolApprovalOverride(for toolName: String, defaultSetting: ToolApprovalSetting) {
        setToolApprovalOverride((toolApprovalOverride(for: toolName) ?? defaultSetting).next, for: toolName)
    }
}
