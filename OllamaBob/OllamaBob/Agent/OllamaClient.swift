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

// MARK: - Chat-provider protocol seam (v1.0.57)
//
// Test seam for `AgentLoop.process()` and `ConversationCompactor`. Both
// previously held a concrete `OllamaClient` actor, which made every
// integration path require a real localhost daemon — the four guards
// (BatchContinuation, BatchAudit, GenericContinuation, ShellRecovery)
// were unit-tested only at the static-helper level, with the wiring
// inside `process()` "tested" by code review.
//
// Now: callers that only need to send chat requests take
// `any OllamaChatProviding`. Tests inject a `MockOllamaChatProvider`
// that scripts a response sequence. `OllamaClient` itself still owns
// the additional surface (`isReachable`, `installedModels`) that
// Preflight uses; that path stays on the concrete actor.
protocol OllamaChatProviding: Sendable {
    func chat(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaToolDef]?,
        numCtx: Int,
        keepAlive: String?
    ) async throws -> OllamaChatResponse
}

actor OllamaClient: OllamaChatProviding {
    private let session: URLSession
    private let baseURL: String

    init(baseURL: String = AppConfig.ollamaBaseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        // v1.0.46: HTTP idle timeout decoupled from agent-loop timeout.
        // The 120s value (= agentLoopTimeoutSeconds) was firing on large
        // models (qwen3.6:27b, gemma4:26b, gpt-oss:20b) during normal
        // generation, and on batch-audio loops that legitimately need
        // multi-minute model responses. URLSession's
        // `timeoutIntervalForRequest` is the inter-byte idle timeout —
        // with `stream: false`, no bytes arrive until generation is
        // done, so the value must accommodate the longest acceptable
        // model response. 600s (10 min) covers cold-start + long
        // generation for any current model on M-series Macs without
        // letting a genuinely wedged connection hang forever.
        // Per-call overrides via `chat(requestTimeoutSeconds:)` let
        // callers tighten this for lighter turns.
        config.timeoutIntervalForRequest = AppConfig.ollamaHTTPRequestTimeoutSeconds
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

        let lastUserOrToolPreview: String = {
            // Most useful debug field is the last non-system message —
            // that's what the model is actually reacting to.
            for msg in messages.reversed() where msg.role != "system" {
                return msg.content.replacingOccurrences(of: "\n", with: " ")
            }
            return ""
        }()
        let requestStartedAt = Date()
        DebugLog.log(.ollama, "request", [
            "model": model,
            "msgs": "\(messages.count)",
            "tools": "\(tools?.count ?? 0)",
            "numCtx": "\(numCtx)",
            "lastMsgPreview": String(lastUserOrToolPreview.prefix(200))
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cannotConnectToHost
            || error.code == .networkConnectionLost {
            DebugLog.log(.error, "ollama-connection-refused", ["model": model])
            throw OllamaError.connectionRefused
        } catch let error as URLError where error.code == .timedOut {
            let elapsed = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            DebugLog.log(.timeout, "ollama-http-timeout", [
                "model": model,
                "elapsedMs": "\(elapsed)",
                "configuredCapMs": "\(Int(AppConfig.ollamaHTTPRequestTimeoutSeconds * 1000))"
            ])
            throw OllamaError.timeout
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            DebugLog.log(.error, "ollama-http-error", [
                "model": model,
                "status": "\(httpResponse.statusCode)"
            ])
            throw OllamaError.httpError(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
            let elapsed = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            DebugLog.log(.ollama, "response", [
                "model": model,
                "elapsedMs": "\(elapsed)",
                "contentLen": "\(decoded.message.content.count)",
                "toolCalls": "\(decoded.message.toolCalls?.count ?? 0)",
                "thinkingLen": "\(decoded.message.thinking?.count ?? 0)"
            ])
            return decoded
        } catch {
            DebugLog.log(.error, "ollama-decode-failed", [
                "model": model,
                "error": error.localizedDescription
            ])
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
