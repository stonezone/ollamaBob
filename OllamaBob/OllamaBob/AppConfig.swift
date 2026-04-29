import Foundation

struct AppConfig {
    struct StandardModelOption: Identifiable, Equatable {
        let tag: String
        let title: String
        let subtitle: String

        var id: String { tag }
    }

    // MARK: - App Version
    static let appVersion = "1.0.24"
    static let appBuild = "124"

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
    static let batchAudioAgentLoopMaxIterations = 160
    static let batchAudioAgentLoopTimeoutSeconds: TimeInterval = 3_600
    static let batchAudioContinuationNudgeMax = 64

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
