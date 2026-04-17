import Foundation
import AppKit

/// macOS pasteboard read/write. Read is free (user put it there themselves);
/// write is modal-gated in ApprovalPolicy because it silently replaces
/// whatever else the user had copied.
enum ClipboardTool {

    /// Soft cap on what Bob can pull off the clipboard in one go. Matches
    /// fileReadMax so a giant copy-paste doesn't blow the context window.
    private static let maxReadBytes = 100_000

    /// Hard cap on what Bob can put *onto* the clipboard. Well under the
    /// read cap — the model shouldn't be dumping huge blobs into the user's
    /// paste buffer.
    private static let maxWriteBytes = 50_000

    static func read() async -> ToolResult {
        let start = Date()
        let pb = NSPasteboard.general

        guard let text = pb.string(forType: .string) else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(
                tool: "clipboard_read",
                content: "(clipboard is empty or contains non-text content)",
                durationMs: durationMs
            )
        }

        let byteCount = text.utf8.count
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        if byteCount > maxReadBytes {
            let truncated = String(text.prefix(maxReadBytes))
            let note = "\n\n... [TRUNCATED: \(byteCount) total bytes, showing first \(maxReadBytes)] ..."
            return .success(tool: "clipboard_read", content: truncated + note, durationMs: durationMs)
        }
        return .success(tool: "clipboard_read", content: text, durationMs: durationMs)
    }

    static func write(content: String) async -> ToolResult {
        let start = Date()
        let byteCount = content.utf8.count
        if byteCount > maxWriteBytes {
            return .failure(
                tool: "clipboard_write",
                error: "Content too large: \(byteCount) bytes (max \(maxWriteBytes))",
                durationMs: 0
            )
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.setString(content, forType: .string)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        if !ok {
            return .failure(tool: "clipboard_write", error: "Pasteboard refused the write.", durationMs: durationMs)
        }
        return .success(
            tool: "clipboard_write",
            content: "Copied \(byteCount) bytes to clipboard.",
            durationMs: durationMs
        )
    }
}
