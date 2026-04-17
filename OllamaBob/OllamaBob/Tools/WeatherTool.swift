import Foundation

/// One-line weather lookup via wttr.in.
enum WeatherTool {
    static func execute(location: String) async -> ToolResult {
        let start = Date()
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "weather", error: "Location is empty.", durationMs: durationMs)
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://wttr.in/\(encoded)?format=3") else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "weather", error: "Invalid location.", durationMs: durationMs)
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            guard let http = response as? HTTPURLResponse else {
                return .failure(tool: "weather", error: "Invalid response.", durationMs: durationMs)
            }
            guard http.statusCode == 200 else {
                return .failure(tool: "weather", error: "HTTP \(http.statusCode)", durationMs: durationMs)
            }

            let body = String(data: data, encoding: .utf8) ?? ""
            return .success(
                tool: "weather",
                content: body.trimmingCharacters(in: .whitespacesAndNewlines),
                durationMs: durationMs
            )
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "weather", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
