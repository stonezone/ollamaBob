import Foundation

// MARK: - RunSkillTool
//
// Phase 7a — Skill Capsules.
//
// Looks up a skill by name, then dispatches every step through SkillRunner
// which calls agentLoop.executeTool + ApprovalPolicy. The `run_skill` tool
// call itself is approval: .none; each individual STEP is gated by its own
// ApprovalPolicy entry just as if the model had called that tool directly.
//
// Optional `parameters_json`: a JSON object whose keys are substituted for
// `{{key}}` placeholders in step arg strings (Phase 7a: string replacement only).

@MainActor
enum RunSkillTool {

    static func execute(
        name: String,
        parametersJson: String?,
        agentLoop: AgentLoop
    ) async -> ToolResult {
        // Fetch skill.
        let skill: Skill?
        do {
            skill = try DatabaseManager.shared.fetchSkill(named: name)
        } catch {
            return .failure(tool: "run_skill", error: error.localizedDescription, durationMs: 0)
        }

        guard let skill else {
            return .failure(
                tool: "run_skill",
                error: "No skill named '\(name)'. Use list_skills to see available skills.",
                durationMs: 0
            )
        }

        // Parse optional parameters.
        var parameters: [String: String] = [:]
        if let json = parametersJson, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(
                    tool: "run_skill",
                    error: "parameters_json must be a JSON object (e.g. {\"key\": \"value\"}).",
                    durationMs: 0
                )
            }
            for (key, value) in dict {
                parameters[key] = "\(value)"
            }
        }

        // Delegate to SkillRunner — approval, logging, and ledger happen there.
        let runResult = await SkillRunner.run(
            skill: skill,
            parameters: parameters,
            agentLoop: agentLoop
        )

        if runResult.success {
            let summary = runResult.stepsCompleted == 1
                ? "Skill '\(name)' completed 1 step."
                : "Skill '\(name)' completed \(runResult.stepsCompleted) of \(runResult.totalSteps) steps."
            let output = runResult.output.isEmpty ? summary : "\(summary)\n\(runResult.output)"
            return .success(tool: "run_skill", content: output, durationMs: 0)
        } else {
            return .failure(tool: "run_skill", error: runResult.output, durationMs: 0)
        }
    }
}
