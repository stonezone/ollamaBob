import Foundation

// MARK: - ListSkillsTool
//
// Phase 7a — Skill Capsules.
// Returns a compact list of all stored skills (name, description, step count).
// Approval: .none — read-only.

@MainActor
enum ListSkillsTool {
    static func execute() -> ToolResult {
        let skills: [Skill]
        do {
            skills = try DatabaseManager.shared.listSkills()
        } catch {
            return .failure(tool: "list_skills", error: error.localizedDescription, durationMs: 0)
        }

        if skills.isEmpty {
            return .success(
                tool: "list_skills",
                content: "No skills saved yet. Use create_skill to define one.",
                durationMs: 0
            )
        }

        let lines = skills.map { skill in
            "\(skill.name) (\(skill.steps.count) step\(skill.steps.count == 1 ? "" : "s")): \(skill.description)"
        }
        return .success(
            tool: "list_skills",
            content: lines.joined(separator: "\n"),
            durationMs: 0
        )
    }
}
