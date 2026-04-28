import Foundation

/// Captures the frontmost screen using ScreenCaptureKit, runs Vision OCR,
/// and returns the extracted text. Caps at ~10KB of text. Prefixes the
/// result with "(captured at HH:MM:SS)". Read-only, no approval required.
///
/// IMPORTANT: All output is wrapped in `<untrusted>` tags because screen
/// content is user-controlled data and may contain injection attempts.
///
/// If TCC has denied screen capture permission, or capture fails for any
/// reason, returns a graceful error message rather than throwing.
@MainActor
enum ScreenOCRTool {

    static func execute() async -> ToolResult {
        let start = Date()
        let cal = Calendar.current
        let h   = cal.component(.hour,   from: start)
        let m   = cal.component(.minute, from: start)
        let s   = cal.component(.second, from: start)
        let timestamp = String(format: "%02d:%02d:%02d", h, m, s)

        guard let text = await MacContextService.screenOCR() else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(
                tool: "screen_ocr",
                content: "Screen OCR unavailable (captured at \(timestamp)). Screen capture may not be permitted — grant Screen Recording access to OllamaBob in System Settings > Privacy & Security.",
                durationMs: durationMs
            )
        }

        let header = "(captured at \(timestamp))"
        let full   = "\(header)\n\(text)"
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return .success(
            tool: "screen_ocr",
            content: UntrustedWrapper.wrap(full),
            durationMs: durationMs
        )
    }
}
