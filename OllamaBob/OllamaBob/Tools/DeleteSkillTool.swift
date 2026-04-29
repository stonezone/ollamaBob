import Foundation

// MARK: - DeleteSkillTool
//
// Phase 7a — Skill Capsules.
// Deletes a named skill from the database.
// Approval: .modal — destructive (removes saved skill recipe).
// Listed in AgentLoop.isSideEffectingTool.

@MainActor
enum DeleteSkillTool {
    static func execute(name: String) -> ToolResult {
        do {
            let deleted = try DatabaseManager.shared.deleteSkill(named: name)
            if deleted {
                return .success(
                    tool: "delete_skill",
                    content: "Skill '\(name)' deleted.",
                    durationMs: 0
                )
            } else {
                return .failure(
                    tool: "delete_skill",
                    error: "No skill named '\(name)' found. Use list_skills to see available skills.",
                    durationMs: 0
                )
            }
        } catch {
            return .failure(tool: "delete_skill", error: error.localizedDescription, durationMs: 0)
        }
    }
}
