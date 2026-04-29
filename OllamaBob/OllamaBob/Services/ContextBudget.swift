import Foundation

enum ContextBudget {
    static let qwenAbliteratedDefaultNumCtx = AppConfig.numCtx
    static let warningThreshold = 0.85

    struct Snapshot: Equatable {
        let approxTokens: Int
        let numCtx: Int
        let percent: Double

        var shouldWarn: Bool {
            percent >= ContextBudget.warningThreshold
        }
    }

    static func snapshot(
        messages: [OllamaMessage],
        numCtx: Int = qwenAbliteratedDefaultNumCtx
    ) -> Snapshot {
        let tokens = approxTokens(messages)
        let percent = numCtx > 0 ? min(1.0, Double(tokens) / Double(numCtx)) : 0
        return Snapshot(approxTokens: tokens, numCtx: numCtx, percent: percent)
    }

    static func snapshot(
        messages: [ChatMessage],
        numCtx: Int = qwenAbliteratedDefaultNumCtx
    ) -> Snapshot {
        let tokens = approxTokens(messages)
        let percent = numCtx > 0 ? min(1.0, Double(tokens) / Double(numCtx)) : 0
        return Snapshot(approxTokens: tokens, numCtx: numCtx, percent: percent)
    }

    static func approxTokens(_ messages: [OllamaMessage]) -> Int {
        let chars = messages.reduce(0) { $0 + approxChars(for: $1) }
        guard chars > 0 else { return 0 }
        return Int((Double(chars) / 3.5).rounded(.up))
    }

    static func approxTokens(_ messages: [ChatMessage]) -> Int {
        let chars = messages.reduce(0) { $0 + approxChars(for: $1) }
        guard chars > 0 else { return 0 }
        return Int((Double(chars) / 3.5).rounded(.up))
    }

    private static func approxChars(for message: OllamaMessage) -> Int {
        var chars = message.role.count + message.content.count
        chars += message.toolName?.count ?? 0
        if let toolCalls = message.toolCalls {
            chars += approxChars(for: toolCalls)
        }
        return chars
    }

    private static func approxChars(for message: ChatMessage) -> Int {
        var chars = message.role.rawValue.count + message.content.count
        chars += message.toolName?.count ?? 0
        if let toolCalls = message.toolCalls {
            chars += approxChars(for: toolCalls)
        }
        return chars
    }

    private static func approxChars(for toolCalls: [OllamaToolCall]) -> Int {
        let encoder = JSONEncoder()
        return toolCalls.reduce(0) { total, call in
            let encodedArgs = (try? encoder.encode(call.function.arguments)).map(\.count)
                ?? String(describing: call.function.parsedArguments).count
            return total
                + (call.id?.count ?? 0)
                + (call.function.index.map(String.init)?.count ?? 0)
                + call.function.name.count
                + encodedArgs
        }
    }
}
