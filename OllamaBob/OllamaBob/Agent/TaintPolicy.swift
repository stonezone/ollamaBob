import Combine
import Foundation

enum TaintSource: Equatable, Hashable, Sendable {
    case tool(String)
    case briefing
    case appPrompt(String)
    case unknown

    var displayName: String {
        switch self {
        case .tool(let name):
            return name
        case .briefing:
            return "briefing"
        case .appPrompt(let name):
            return name
        case .unknown:
            return "unknown source"
        }
    }
}

@MainActor
final class TaintPolicy: ObservableObject {
    static let shared = TaintPolicy()

    enum Decision: Equatable {
        case allow
        case blockedBy(TaintSource)
    }

    @Published private var sourcesBySession: [String: TaintSource] = [:]

    private init() {}

    func tainted(forSession sessionID: String) -> Bool {
        sourcesBySession[sessionID] != nil
    }

    func source(forSession sessionID: String) -> TaintSource? {
        sourcesBySession[sessionID]
    }

    func markTainted(forSession sessionID: String, source: TaintSource) {
        sourcesBySession[sessionID] = source
    }

    func markTaintedIfNeeded(afterTool toolName: String, sessionID: String, success: Bool) {
        guard success, let source = Self.source(forToolName: toolName) else { return }
        markTainted(forSession: sessionID, source: source)
    }

    func lift(forSession sessionID: String) {
        sourcesBySession.removeValue(forKey: sessionID)
    }

    func clearOnUserMessage(forSession sessionID: String) {
        lift(forSession: sessionID)
    }

    func noteUserMessage(_ text: String, sessionID: String) {
        if UntrustedWrapper.containsWrappedContent(text) {
            markTainted(forSession: sessionID, source: .appPrompt("untrusted user message"))
        } else {
            clearOnUserMessage(forSession: sessionID)
        }
    }

    func decision(toolName: String, arguments: [String: Any] = [:], sessionID: String) -> Decision {
        guard let source = source(forSession: sessionID), Self.blocksTool(toolName, arguments: arguments) else {
            return .allow
        }
        return .blockedBy(source)
    }

    func deniedResult(toolName: String, arguments: [String: Any] = [:], sessionID: String) -> ToolResult? {
        guard case .blockedBy(let source) = decision(toolName: toolName, arguments: arguments, sessionID: sessionID) else {
            return nil
        }
        return ToolResult.denied(tool: toolName, reason: Self.blockedReason(toolName: toolName, source: source))
    }

    func resetForTests() {
        sourcesBySession.removeAll()
    }

    static func source(forToolName toolName: String) -> TaintSource? {
        switch toolName {
        case "briefing":
            return .briefing
        case "web_search", "screen_ocr", "mail_check", "mail_triage",
             "read_file", "clipboard_read", "youtube_search",
             "active_window", "selected_items", "current_context",
             "project_context", "ocr", "timeline_search", "search_vault":
            return .tool(toolName)
        default:
            return nil
        }
    }

    static func blocksTool(_ toolName: String, arguments: [String: Any] = [:]) -> Bool {
        switch toolName {
        case "shell", "write_file", "move_file", "create_directory",
             "clipboard_write", "image_convert",
             "applescript", "phone_call", "phone_inject",
             "phone_hangup", "enable_dev_mode", "create_skill",
             "delete_skill", "remember", "forget", "mail_triage",
             "run_skill":
            return true
        case "present":
            let kind = (arguments["kind"] as? String)?.lowercased()
            return kind == "file" || kind == "url"
        // v1.0.47: `youtube_download` was previously blocked when tainted,
        // which made the authorized music workflow impossible — `youtube_search`
        // taints the session, so the very next `youtube_download` (the natural
        // sequel) was silently denied. youtube_download already requires
        // modal approval per call (the user sees the URL, format, and
        // destination before each download); the taint guard was redundant
        // belt-and-suspenders defense for this specific tool. yt-dlp does
        // not execute URLs — it downloads videos — so the malicious-URL
        // attack surface is essentially zero. We deliberately allow
        // youtube_download to run even when the session is tainted.
        default:
            return false
        }
    }

    static func blockedReason(toolName: String, source: TaintSource) -> String {
        "Blocked \(toolName) while this turn contains untrusted content from \(source.displayName). Type /lift or send a new message to clear the taint before running write actions."
    }
}
