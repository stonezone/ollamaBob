import Foundation

/// Represents a tool call from Ollama's /api/chat response.
/// Handles the wire format: { "id": "...", "function": { "index": 0, "name": "...", "arguments": {...} } }
struct OllamaToolCall: Codable, Sendable {
    let id: String?
    let function: FunctionCall

    struct FunctionCall: Codable, Sendable {
        let index: Int?
        let name: String
        let arguments: JSONValue

        /// Normalize arguments to a dictionary, handling both object and string formats.
        var parsedArguments: [String: Any] {
            arguments.asDictionary
        }

        func stringArg(_ key: String) -> String? {
            parsedArguments[key] as? String
        }
    }
}

/// Tool definition sent to Ollama in the request
struct OllamaToolDef: Codable, Sendable {
    let type: String
    let function: FunctionDef

    struct FunctionDef: Codable, Sendable {
        let name: String
        let description: String
        let parameters: ParametersDef
    }

    struct ParametersDef: Codable, Sendable {
        let type: String
        let properties: [String: PropertyDef]
        let required: [String]
    }

    struct PropertyDef: Codable, Sendable {
        let type: String
        let description: String
    }

    static func tool(
        name: String,
        description: String,
        properties: [String: (type: String, description: String)],
        required: [String]
    ) -> OllamaToolDef {
        OllamaToolDef(
            type: "function",
            function: FunctionDef(
                name: name,
                description: description,
                parameters: ParametersDef(
                    type: "object",
                    properties: properties.mapValues { PropertyDef(type: $0.type, description: $0.description) },
                    required: required
                )
            )
        )
    }
}
