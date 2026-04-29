import Foundation

// MARK: - InspectSkillTool
//
// Phase 7a — Skill Capsules.
// Returns the full recipe for a named skill so Bob can review it before running.
// Approval: .none — read-only.

@MainActor
enum InspectSkillTool {
    static func execute(name: String) -> ToolResult {
        let skill: Skill?
        do {
            skill = try DatabaseManager.shared.fetchSkill(named: name)
        } catch {
            return .failure(tool: "inspect_skill", error: error.localizedDescription, durationMs: 0)
        }

        guard let skill else {
            return .failure(
                tool: "inspect_skill",
                error: "No skill named '\(name)'. Use list_skills to see available skills.",
                durationMs: 0
            )
        }

        var lines: [String] = [
            "Skill: \(skill.name)",
            "Description: \(skill.description)",
            "Steps (\(skill.steps.count)):"
        ]

        for (index, step) in skill.steps.enumerated() {
            // Pretty-print args as compact JSON.
            let argsJson: String
            if let data = try? JSONEncoder().encode(step.args),
               let str = String(data: data, encoding: .utf8) {
                argsJson = str
            } else {
                argsJson = "(unparseable)"
            }
            lines.append("  \(index + 1). \(step.tool)  args: \(argsJson)")
        }

        return .success(tool: "inspect_skill", content: lines.joined(separator: "\n"), durationMs: 0)
    }
}
