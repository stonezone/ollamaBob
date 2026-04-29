import Foundation

// MARK: - SkillStep

/// One step in a Skill recipe. References an existing first-party tool by name
/// and a flat dictionary of arguments. Parameter substitution (`{{key}}`) is
/// done at run time by SkillRunner before the step is dispatched.
///
/// Argument values are stored as JSONValue (the same flexible enum used for
/// Ollama tool call arguments) so the JSON round-trip is lossless.
struct SkillStep: Equatable, Sendable, Codable {
    /// The registered tool name (e.g. "web_search", "write_file").
    let tool: String
    /// Flat argument dictionary. Values may contain `{{key}}` placeholders.
    let args: [String: JSONValue]
}

// MARK: - Skill

/// A named, user-defined recipe that replays a sequence of first-party tool
/// calls through the existing ApprovalPolicy + PathPolicy gates.
///
/// Rules:
///   - Every step tool must exist in ToolRegistry at create time.
///   - Replay is strictly sequential. If step N fails the skill stops;
///     subsequent steps are NOT run.
///   - Skills never bypass ApprovalPolicy or PathPolicy.
///   - Parameter substitution is `{{key}}` → `parameters[key]` only.
///     No scripting, no conditionals, no loops.
struct Skill: Equatable, Sendable {
    let id: Int64
    let name: String
    let description: String
    let steps: [SkillStep]
    let createdAt: Date
    let updatedAt: Date
}
