import Foundation

struct AppConfig {
    // MARK: - Models
    static let primaryModel = "gemma4:e4b"
    static let fallbackModel = "qwen3:14b"
    static let maxConsecutiveFailures = 3
    static let notifyOnModelSwitch = true

    // MARK: - Ollama
    static let ollamaBaseURL = "http://localhost:11434"
    static let ollamaChatEndpoint = "/api/chat"
    static let ollamaTagsEndpoint = "/api/tags"
    static let numCtx = 8192

    // MARK: - Tool Output Limits
    static let shellStdoutMax = 10_000
    static let shellStderrMax = 2_000
    static let fileReadMax = 100 * 1024  // 100 KB
    static let searchResultsMax = 5
    static let searchSnippetMax = 200
    static let fileSearchResultsMax = 20

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
