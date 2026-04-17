import Foundation

/// macOS text-to-speech wrapper around `/usr/bin/say`.
enum SayTool {
    private static let maxChars = 2_000

    static func execute(text: String, voice: String?) async -> ToolResult {
        let start = Date()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "speak", error: "Text is empty.", durationMs: durationMs)
        }

        let count = trimmed.count
        guard count <= maxChars else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "speak", error: "Text too long: \(count) chars (max 2000).", durationMs: durationMs)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        let selectedVoice = voice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if selectedVoice.isEmpty {
            process.arguments = [trimmed]
        } else {
            process.arguments = ["-v", selectedVoice, trimmed]
        }

        do {
            try process.run()
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(tool: "speak", content: "Spoke \(count) chars.", durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "speak", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
