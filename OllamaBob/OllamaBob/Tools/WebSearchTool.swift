import Foundation

struct BraveSearchProvider: SearchProvider {
    let apiKey: String

    func search(query: String) async throws -> [SearchResult] {
        guard var components = URLComponents(string: AppConfig.braveSearchURL) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(AppConfig.searchResultsMax))
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let braveResponse = try JSONDecoder().decode(BraveSearchResponse.self, from: data)
        return (braveResponse.web?.results ?? []).prefix(AppConfig.searchResultsMax).map { result in
            SearchResult(
                title: result.title,
                url: result.url,
                snippet: OutputLimits.truncateSnippet(result.description)
            )
        }
    }
}

// Brave Search API response models
private struct BraveSearchResponse: Codable {
    let web: WebResults?
}

private struct WebResults: Codable {
    let results: [WebResult]
}

private struct WebResult: Codable {
    let title: String
    let url: String
    let description: String
}

enum WebSearchTool {
    static func execute(query: String, provider: SearchProvider) async -> ToolResult {
        let start = Date()
        do {
            let results = try await provider.search(query: query)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)

            if results.isEmpty {
                return .success(tool: "web_search", content: "No results found for '\(query)'", durationMs: durationMs)
            }

            let formatted = results.enumerated().map { i, r in
                "\(i + 1). \(r.title)\n   \(r.url)\n   \(r.snippet)"
            }.joined(separator: "\n\n")

            return .success(tool: "web_search", content: formatted, durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "web_search", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
