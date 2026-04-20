import Foundation

struct AppConfig {
    // MARK: - Models
    static let primaryModel = "gemma4:e4b"
    static let fallbackModel = "qwen3:14b"
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

    // MARK: - Brave Search
    static var braveAPIKey: String {
        ProcessInfo.processInfo.environment["BRAVE_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "braveAPIKey")
            ?? ""
    }
    static let braveSearchURL = "https://api.search.brave.com/res/v1/web/search"
}
