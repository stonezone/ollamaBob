import Foundation

// MARK: - CreateSkillTool
//
// Phase 7a — Skill Capsules.
//
// Parses the `steps_json` string, validates every step references a known tool,
// then persists the skill via DatabaseManager. Fails at create time if any step
// names an unknown tool so bad recipes are never stored.
//
// Approval: .modal — saving a skill is session-policy state (same tier as
//           enable_dev_mode). Listed in AgentLoop.isSideEffectingTool.

@MainActor
enum CreateSkillTool {

    /// Execute the `create_skill` tool.
    ///
    /// - Parameters:
    ///   - name: Unique skill name (used as the key for `run_skill`/`inspect_skill`).
    ///   - description: Human-readable description of what the skill does.
    ///   - stepsJson: JSON-encoded array of `{tool, args}` objects.
    ///   - knownToolNames: The set of registered tool names from `ToolRegistry`.
    static func execute(
        name: String,
        description: String,
        stepsJson: String,
        knownToolNames: Set<String>
    ) -> ToolResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure(tool: "create_skill", error: "Skill name must not be empty.", durationMs: 0)
        }

        // Parse steps_json.
        guard let data = stepsJson.data(using: .utf8) else {
            return .failure(tool: "create_skill", error: "steps_json is not valid UTF-8.", durationMs: 0)
        }
        let steps: [SkillStep]
        do {
            steps = try JSONDecoder().decode([SkillStep].self, from: data)
        } catch {
            return .failure(
                tool: "create_skill",
                error: "steps_json parse error: \(error.localizedDescription). "
                     + "Expected a JSON array of {\"tool\": \"<name>\", \"args\": {...}} objects.",
                durationMs: 0
            )
        }

        guard !steps.isEmpty else {
            return .failure(tool: "create_skill", error: "A skill must have at least one step.", durationMs: 0)
        }

        // Validate all tool names exist.
        if let unknown = SkillRunner.firstUnknownTool(in: steps, knownToolNames: knownToolNames) {
            return .failure(
                tool: "create_skill",
                error: "Step references unknown tool '\(unknown)'. Known tools: \(knownToolNames.sorted().joined(separator: ", "))",
                durationMs: 0
            )
        }

        // Persist.
        do {
            let skill = try DatabaseManager.shared.createSkill(
                name: trimmedName,
                description: description,
                steps: steps
            )
            return .success(
                tool: "create_skill",
                content: "Skill '\(skill.name)' saved with \(steps.count) step(s). "
                       + "Run it with run_skill(name: \"\(skill.name)\").",
                durationMs: 0
            )
        } catch {
            return .failure(
                tool: "create_skill",
                error: "Failed to save skill: \(error.localizedDescription)",
                durationMs: 0
            )
        }
    }
}
