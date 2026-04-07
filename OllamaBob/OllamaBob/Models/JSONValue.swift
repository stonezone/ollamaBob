import Foundation

/// Flexible JSON value that handles Ollama's inconsistent argument formats.
/// In multi-turn conversations, arguments may be a JSON object OR a JSON string.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    /// Extract as a plain [String: Any] dictionary, handling both object and string-encoded arguments.
    var asDictionary: [String: Any] {
        switch self {
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = val.asAny
            }
            return result
        case .string(let str):
            // Multi-turn bug: arguments came as a string — try to parse as JSON
            guard let data = str.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return obj
        default:
            return [:]
        }
    }

    var asAny: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .object(let o): return o.mapValues { $0.asAny }
        case .array(let a): return a.map { $0.asAny }
        case .null: return NSNull()
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
