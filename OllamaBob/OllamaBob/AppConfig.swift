import Foundation

struct AppConfig {
    struct StandardModelOption: Identifiable, Equatable {
        let tag: String
        let title: String
        let subtitle: String

        var id: String { tag }
    }

    // MARK: - App Version
    static let appVersion = "1.0.53"
    static let appBuild = "153"

    // MARK: - HTML Sanitizer
    /// Bumped whenever PresentationService's HTML allowlist or
    /// rule set changes. Used as metadata for tracking which
    /// rule generation produced sanitized output (defense-in-depth
    /// hardening, Phase 0b — replaced regex pass with SwiftSoup).
    static let htmlSanitizerVersion = 1

    // MARK: - Models
    static let primaryModel = "gemma4:e4b"
    static let fallbackModel = "qwen3:14b"
    static let standardModelOptions: [StandardModelOption] = [
        StandardModelOption(
            tag: primaryModel,
            title: "Gemma 4 E4B",
            subtitle: "Fast default for everyday Bob turns"
        ),
        StandardModelOption(
            tag: "gemma4:26b",
            title: "Gemma 4 26B",
            subtitle: "Higher quality local generalist"
        ),
        StandardModelOption(
            tag: "qwen3.6:27b",
            title: "Qwen 3.6 27B",
            subtitle: "Deeper reasoning and coding"
        ),
        StandardModelOption(
            tag: "gpt-oss:20b",
            title: "gpt-oss 20B",
            subtitle: "OpenAI open-weight reasoning model"
        )
    ]
    /// Model used for conversation compaction (Phase 5). qwen3:14b is
    /// more reliable at structured extraction than gemma4:e4b. Uses
    /// keep_alive=0 so it unloads immediately after compaction.
    static let compactionModel = "qwen3:14b"
    static let maxConsecutiveFailures = 3
    static let notifyOnModelSwitch = true

    // MARK: - Ollama
    static let ollamaBaseURL = "http://localhost:11434"
    static let ollamaChatEndpoint = "/api/chat"
    static let ollamaTagsEndpoint = "/api/tags"

    // MARK: - Jarvis Phone Service
    static let jarvisBaseURL = "http://127.0.0.1:3100"

    /// Default context window size. Raised from 8192 to 32768 after Phase 0
    /// Investigation A proved zero per-turn latency penalty at idle on both
    /// gemma4:e4b and qwen3:14b (baseline TTFT ~250ms flat across 8K/16K/32K).
    /// Users can override via Preferences; allowed snap points are:
    /// 8192 (8K), 16384 (16K), 24576 (24K), 32768 (32K).
    static let numCtx = 32768
    static let numCtxAllowed: [Int] = [8192, 16384, 24576, 32768]

    // MARK: - Tool Output Limits
    static let shellStdoutMax = 10_000
    static let shellStderrMax = 2_000
    static let fileReadMax = 100 * 1024  // 100 KB
    static let searchResultsMax = 5
    static let searchSnippetMax = 200
    static let fileSearchResultsMax = 20
    /// Max chars of a tool result that will be inlined into the model's
    /// message history. Anything larger is written to the ToolOutputStore
    /// and replaced inline with a short pointer the model can resolve
    /// via the `read_tool_output` meta-tool. Keeps Bob's context clean
    /// when a shell command or file read spits out 10K+ chars.
    static let toolInlineMax = 2_000

    // MARK: - Timeouts & Caps
    static let toolTimeoutSeconds: TimeInterval = 30
    static let agentLoopMaxIterations = 10
    static let agentLoopTimeoutSeconds: TimeInterval = 120
    /// HTTP idle timeout for /api/chat requests. Decoupled from the
    /// agent-loop budget (v1.0.46) — that's the WHOLE TURN budget,
    /// this is per-MODEL-RESPONSE. URLSession's
    /// `timeoutIntervalForRequest` is inter-byte; with `stream: false`
    /// no bytes arrive until generation is done, so this must
    /// accommodate the longest acceptable single-response time.
    /// 600s (10 min) covers cold-load + long generation for 27B
    /// models on M-series hardware. Bob's user-facing Cancel button
    /// (⌘.) is the actual escape hatch for stuck requests.
    static let ollamaHTTPRequestTimeoutSeconds: TimeInterval = 600
    /// Wall-clock cap on a single Ollama request (v1.0.52). Independent
    /// of URLSession's idle-only timeout — that one never fires when
    /// Ollama keeps the TCP socket alive while doing nothing (the
    /// 19-minute wedge the user hit). This is the absolute ceiling
    /// from "request fired" to "force-cancel". 600s gives huge models
    /// (qwen3.6:27b cold-load + long generation) breathing room while
    /// putting a hard floor under wedge cases.
    static let ollamaSingleRequestWallClockCapSeconds: TimeInterval = 600
    /// How often the OllamaHeartbeat polls /api/ps while a chat call
    /// is in flight (v1.0.52). 5s is the Goldilocks zone: fast enough
    /// to detect mid-request model unload within a single avatar
    /// glance, slow enough that 12 GETs/min on a local Ollama is
    /// trivially cheap. Not user-configurable.
    static let ollamaHeartbeatIntervalSeconds: TimeInterval = 5
    /// Pre-flight context-pressure threshold (v1.0.52). When the
    /// estimated prompt tokens for the next chat request would exceed
    /// this fraction of the configured numCtx, surface a soft warning
    /// to the user before sending. 0.6 is conservative — gemma4:e4b
    /// gets sluggish well before 100% context utilization.
    static let chatContextPressureWarningFraction: Double = 0.6
    static let batchAudioAgentLoopMaxIterations = 160
    static let batchAudioAgentLoopTimeoutSeconds: TimeInterval = 3_600
    static let batchAudioContinuationNudgeMax = 64
    /// Generic "announce-and-stop" continuation nudge cap. The agent loop
    /// detects when the assistant ends a non-tool-call turn with future-action
    /// language ("now running X", "let me X", "I'll X") and nudges Bob to
    /// actually call the tool. Capped low: if Bob still emits the same
    /// pattern after one nudge, give up rather than spin — show the user the
    /// broken reply so they can intervene.
    static let continuationNudgeMax = 1
    /// Shell-recovery guard cap (v1.0.46). Mirror of continuationNudgeMax.
    /// Same reasoning: one nudge to diagnose+retry, then surface to user.
    static let shellRecoveryNudgeMax = 1
    static let processOutputMaxBytes = 1_000_000

    // MARK: - Shell Tool Timeouts
    /// Idle timeout for the `shell` tool: kill the command if no stdout/stderr
    /// activity for this many seconds. Resets on each output byte. Default 60s.
    /// Overridable per-call via `idle_timeout_seconds` arg, clamped [5, 600].
    static let shellIdleTimeoutSeconds: TimeInterval = 60
    /// Hard cap for the `shell` tool: kill the command after this many seconds
    /// of total wall time regardless of activity. Default 1800s (30 min).
    /// Overridable per-call via `max_total_seconds` arg, clamped [10, 7200].
    static let shellMaxTotalSeconds: TimeInterval = 1_800
    /// Grace period between SIGTERM and SIGKILL when terminating a child
    /// process. Lets well-behaved processes flush; SIGKILL fires after this
    /// for ones that ignore SIGTERM (e.g. `trap '' TERM`, some brew paths).
    static let processKillGraceSeconds: TimeInterval = 2.0
    /// Clamps for shell-tool overrides. Bob can request larger values for
    /// huge builds, but never beyond these absolute ceilings.
    static let shellIdleTimeoutMin: TimeInterval = 5
    static let shellIdleTimeoutMax: TimeInterval = 600
    static let shellMaxTotalMin: TimeInterval = 10
    static let shellMaxTotalMax: TimeInterval = 7_200

    // MARK: - Brave Search
    /// Read order: Keychain (Phase 0c migration target) -> process env -> UserDefaults legacy.
    /// UserDefaults stays in the chain so an un-migrated install keeps working
    /// until SecretMigration runs.
    static var braveAPIKey: String {
        if let keychain = KeychainService.current.read(.braveAPIKey), !keychain.isEmpty {
            return keychain
        }
        return ProcessInfo.processInfo.environment["BRAVE_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "braveAPIKey")
            ?? ""
    }
    static let braveSearchURL = "https://api.search.brave.com/res/v1/web/search"
}
