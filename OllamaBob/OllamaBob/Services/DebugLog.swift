import Foundation

/// Centralized debug logger for runtime troubleshooting (v1.0.46).
///
/// Default OFF. When the user enables `AppSettings.debugLoggingEnabled`,
/// every Ollama request/response, tool dispatch, guard fire, and timeout
/// gets appended to a session-scoped log file under
/// `~/Library/Logs/OllamaBob/debug-YYYYMMDD-HHmmss.log`.
///
/// Why a file (not just `print`):
/// - The user can grep the log without opening Xcode.
/// - We can ship the file with a bug report.
/// - Stdout is noisy and gets truncated by Console.app at high volume.
///
/// What we DON'T log: Keychain values, raw user passwords, or the entire
/// content of <untrusted> blocks (those can be huge). Tool inputs and
/// outputs are truncated at `maxFieldChars` (default 4 KB per field).
///
/// Threading: writes funnel through a serial DispatchQueue. Logging from
/// any actor or thread is safe; ordering across writers is preserved.
enum DebugLog {
    /// Per-field truncation. A 4-KB cap per field still produces logs in
    /// the low-megabyte range for an hour-long session, which is fine.
    static let maxFieldChars = 4_096

    /// Set by AppSettings on launch and any subsequent toggle. Reads are
    /// lock-free; writes are extremely rare (UI checkbox flips), so a
    /// plain stored property is sufficient. `nonisolated(unsafe)` is the
    /// minimum-overhead choice — the true source of truth is AppSettings,
    /// this is just a hot-path mirror so log calls don't have to hop to
    /// MainActor.
    nonisolated(unsafe) static var enabled: Bool = false

    private static let queue = DispatchQueue(label: "com.ollamabob.debuglog", qos: .utility)
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Lazily-resolved log file URL. Created on first write of the
    /// session. nil if the directory cannot be created (e.g. sandbox
    /// denial) — in that case we silently no-op rather than crash.
    nonisolated(unsafe) private static var logFileURL: URL?
    nonisolated(unsafe) private static var sessionStartedAt: Date?

    /// Categories let `grep '\[ollama\]'` and similar queries pull just
    /// the lines you care about. Keep these short and stable.
    enum Category: String {
        case ollama   = "ollama"   // every /api/chat request + response
        case agent    = "agent"    // loop iteration boundaries, model swaps, cancels
        case tool     = "tool"     // tool dispatch + result + duration
        case shell    = "shell"    // shell tool stdin/stdout/stderr/exit/termination
        case guardx   = "guard"    // continuation / batch-audio / shell-recovery guard fires
        case prompt   = "prompt"   // composed system-prompt segment sizes
        case error    = "error"    // anything thrown or otherwise unhappy
        case timeout  = "timeout"  // any timeout firing (HTTP, idle, hard cap)
    }

    /// Public entry point. No-op when `enabled` is false. Truncates
    /// each field of `details` to `maxFieldChars`.
    static func log(
        _ category: Category,
        _ event: String,
        _ details: [String: String] = [:]
    ) {
        guard enabled else { return }
        let now = Date()
        let stamp = formatter.string(from: now)
        var line = "[\(stamp)] [\(category.rawValue)] \(event)"
        if !details.isEmpty {
            let sorted = details.sorted { $0.key < $1.key }
            let pairs = sorted.map { "\($0.key)=\(truncate($0.value))" }
            line += " {" + pairs.joined(separator: " ") + "}"
        }
        line += "\n"
        queue.async {
            ensureFileExists()
            guard let url = logFileURL,
                  let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }

    /// Convenience for one-off short events without a details dict.
    static func log(_ category: Category, _ event: String) {
        log(category, event, [:])
    }

    /// User-facing accessor for "where is the log file?" — surfaces in
    /// the Preferences pane.
    static var currentLogFilePath: String? {
        queue.sync { logFileURL?.path }
    }

    /// Close the current session log and start a new one. Useful when
    /// the user toggles the setting back on after a long quiet period.
    static func startNewSession() {
        queue.async {
            sessionStartedAt = nil
            logFileURL = nil
            ensureFileExists()
        }
    }

    // MARK: - Private

    private static func truncate(_ s: String) -> String {
        guard s.count > maxFieldChars else { return s.replacingOccurrences(of: "\n", with: "\\n") }
        let head = s.prefix(maxFieldChars)
        return "\(head)…[+\(s.count - maxFieldChars)ch]"
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func ensureFileExists() {
        if logFileURL != nil { return }
        let fm = FileManager.default
        let logsDir = (try? fm.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("OllamaBob", isDirectory: true)
        guard let logsDir else { return }
        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let started = Date()
        sessionStartedAt = started
        let nameFmt = DateFormatter()
        nameFmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = logsDir.appendingPathComponent("debug-\(nameFmt.string(from: started)).log")
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        logFileURL = url

        // Header: identifies the build for cross-referencing crash logs.
        let header = """
        === OllamaBob debug log ===
        version: \(AppConfig.appVersion) (build \(AppConfig.appBuild))
        started: \(started)
        host:    \(ProcessInfo.processInfo.hostName)
        pid:     \(ProcessInfo.processInfo.processIdentifier)
        ============================

        """
        if let data = header.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
