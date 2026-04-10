import Foundation

enum OllamaError: Error, LocalizedError {
    case connectionRefused
    case httpError(Int)
    case decodingError(String)
    case timeout
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .connectionRefused: return "Cannot connect to Ollama at localhost:11434. Is it running?"
        case .httpError(let code): return "Ollama returned HTTP \(code)"
        case .decodingError(let msg): return "Failed to parse Ollama response: \(msg)"
        case .timeout: return "Ollama request timed out"
        case .invalidURL: return "Invalid Ollama URL"
        }
    }
}

actor OllamaClient {
    private let session: URLSession
    private let baseURL: String

    init(baseURL: String = AppConfig.ollamaBaseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfig.agentLoopTimeoutSeconds
        self.session = URLSession(configuration: config)
    }

    /// Send a chat request to /api/chat and return the parsed response.
    /// `numCtx` is passed through to Ollama's `options.num_ctx` — callers
    /// should read the live value from `AppSettings.shared.numCtx` so user
    /// changes take effect on the next turn without restarting the client.
    func chat(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaToolDef]? = nil,
        numCtx: Int = AppConfig.numCtx,
        keepAlive: String? = nil
    ) async throws -> OllamaChatResponse {
        guard let url = URL(string: baseURL + AppConfig.ollamaChatEndpoint) else {
            throw OllamaError.invalidURL
        }

        let request = OllamaChatRequest(
            model: model,
            messages: messages,
            tools: tools,
            options: .init(numCtx: numCtx),
            stream: false,
            keepAlive: keepAlive
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cannotConnectToHost
            || error.code == .networkConnectionLost {
            throw OllamaError.connectionRefused
        } catch let error as URLError where error.code == .timedOut {
            throw OllamaError.timeout
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw OllamaError.httpError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        } catch {
            throw OllamaError.decodingError(error.localizedDescription)
        }
    }

    /// Check if Ollama is reachable by hitting /api/tags
    func isReachable() async -> Bool {
        guard let url = URL(string: baseURL + AppConfig.ollamaTagsEndpoint) else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Fetch installed model names
    func installedModels() async -> [String] {
        guard let url = URL(string: baseURL + AppConfig.ollamaTagsEndpoint) else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return tags.models.map { $0.name }
        } catch {
            return []
        }
    }
}

// Response from /api/tags
private struct OllamaTagsResponse: Codable {
    let models: [OllamaModelInfo]
}

private struct OllamaModelInfo: Codable {
    let name: String
}
