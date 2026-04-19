import Foundation

enum PresentTool {
    static func execute(kind: String, content: String, title: String?) async -> ToolResult {
        let start = Date()
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard let kind = PresentationKind(rawValue: normalizedKind) else {
            return .failure(
                tool: "present",
                error: "kind must be one of: html, url, file",
                durationMs: 0
            )
        }

        do {
            let result = try await MainActor.run {
                try PresentationService.shared.present(kind: kind, content: content, title: title)
            }
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(tool: "present", content: result, durationMs: durationMs)
        } catch let error as PresentationError {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "present", error: error.localizedDescription, durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "present", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
