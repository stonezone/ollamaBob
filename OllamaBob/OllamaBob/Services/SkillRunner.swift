import Foundation

// MARK: - SkillRunner
//
// Phase 7a — Skill Capsules replay engine.
//
// SkillRunner executes a Skill's steps by dispatching each one through
// AgentLoop.executeToolCall so that ApprovalPolicy + PathPolicy + the
// execution_log all apply automatically. There are NO approval bypasses here.
//
// Parameter substitution rules (Phase 7a scope):
//   - Only `{{key}}` → `parameters["key"]` replacement in string arg values.
//   - No expressions, no nesting, no escaping.
//   - If a step references `{{foo}}` but `parameters["foo"]` is absent, the
//     whole skill fails BEFORE any step runs (pre-flight check).
//   - Substitution is performed only on .string(_) JSONValue leaves.

enum SkillRunnerError: LocalizedError {
    case unknownTool(String)
    case missingParameter(placeholder: String, step: Int)
    case stepFailed(stepIndex: Int, tool: String, error: String)
    case forbiddenStep(stepIndex: Int, tool: String)
    case deniedStep(stepIndex: Int, tool: String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Skill references unknown tool '\(name)'. The skill was not saved."
        case .missingParameter(let placeholder, let step):
            return "Skill step \(step + 1) references {{\(placeholder)}} but that key was not provided."
        case .stepFailed(let idx, let tool, let err):
            return "Skill stopped at step \(idx + 1) (\(tool)): \(err)"
        case .forbiddenStep(let idx, let tool):
            return "Skill stopped at step \(idx + 1) (\(tool)): action is forbidden by policy."
        case .deniedStep(let idx, let tool):
            return "Skill stopped at step \(idx + 1) (\(tool)): user denied the action."
        }
    }
}

/// Result of a skill run: which steps succeeded/failed and the final output.
struct SkillRunResult {
    let stepsCompleted: Int
    let totalSteps: Int
    let stoppedAt: Int?          // nil = all steps ran
    let output: String           // last successful step content or error description
    let success: Bool
}

@MainActor
enum SkillRunner {

    // MARK: - Validation (create-time)

    /// Validate that all tool names in a skill exist in `knownToolNames`.
    /// Returns the first unknown tool name, or nil if all are valid.
    static func firstUnknownTool(in steps: [SkillStep], knownToolNames: Set<String>) -> String? {
        steps.first(where: { !knownToolNames.contains($0.tool) })?.tool
    }

    // MARK: - Parameter Substitution

    /// Check that every `{{key}}` placeholder across all steps is satisfied by `parameters`.
    /// Returns the first missing key (and which step it was found in), or nil if all satisfied.
    static func firstMissingPlaceholder(
        in steps: [SkillStep],
        parameters: [String: String]
    ) -> (placeholder: String, stepIndex: Int)? {
        for (stepIndex, step) in steps.enumerated() {
            for (_, value) in step.args {
                if case .string(let s) = value {
                    if let missing = firstMissingKey(in: s, parameters: parameters) {
                        return (missing, stepIndex)
                    }
                }
            }
        }
        return nil
    }

    /// Replace all `{{key}}` occurrences in `template` with `parameters["key"]`.
    /// Caller must have already verified all keys are present.
    static func substitute(template: String, parameters: [String: String]) -> String {
        var result = template
        for (key, value) in parameters {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    /// Resolve a JSONValue by substituting any `{{key}}` placeholders in string leaves.
    static func substituteValue(_ value: JSONValue, parameters: [String: String]) -> JSONValue {
        switch value {
        case .string(let s):
            return .string(substitute(template: s, parameters: parameters))
        case .array(let arr):
            return .array(arr.map { substituteValue($0, parameters: parameters) })
        case .object(let obj):
            return .object(obj.mapValues { substituteValue($0, parameters: parameters) })
        default:
            return value
        }
    }

    /// Resolve a step's args dict, substituting `{{key}}` in string values.
    static func resolveArgs(
        _ args: [String: JSONValue],
        parameters: [String: String]
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in args {
            result[key] = substituteValue(value, parameters: parameters).asAny
        }
        return result
    }

    // MARK: - Run

    /// Execute all steps of `skill` via `agentLoop.executeTool` (after ApprovalPolicy gate).
    ///
    /// Pre-flight checks (before any step runs):
    ///   1. All tool names must exist in the registry.
    ///   2. All `{{key}}` placeholders must have a matching key in `parameters`.
    ///
    /// If any step returns a failure, denied, or forbidden result, the skill
    /// stops immediately and does NOT run subsequent steps.
    static func run(
        skill: Skill,
        parameters: [String: String] = [:],
        agentLoop: AgentLoop
    ) async -> SkillRunResult {
        let steps = skill.steps

        // Pre-flight 1: all tool names must be known.
        let knownNames = Set(agentLoop.registry.toolNames)
        if let unknown = firstUnknownTool(in: steps, knownToolNames: knownNames) {
            return SkillRunResult(
                stepsCompleted: 0,
                totalSteps: steps.count,
                stoppedAt: 0,
                output: SkillRunnerError.unknownTool(unknown).localizedDescription,
                success: false
            )
        }

        // Pre-flight 2: all placeholders must be satisfied.
        if let missing = firstMissingPlaceholder(in: steps, parameters: parameters) {
            let error = SkillRunnerError.missingParameter(
                placeholder: missing.placeholder,
                step: missing.stepIndex
            )
            return SkillRunResult(
                stepsCompleted: 0,
                totalSteps: steps.count,
                stoppedAt: missing.stepIndex,
                output: error.localizedDescription,
                success: false
            )
        }

        // Execute steps sequentially.
        var stepsCompleted = 0
        var lastOutput = ""

        for (index, step) in steps.enumerated() {
            let resolvedArgs = resolveArgs(step.args, parameters: parameters)

            // Run the approval gate with the RESOLVED args (after {{key}} substitution)
            // so path checks and forbidden-shape checks operate on the final values.
            // We replicate the executeToolCall gate here rather than calling
            // executeToolCall directly because we need to supply the substituted
            // args rather than the raw stored args. The gate is NOT skipped.
            let approval = ApprovalPolicy.check(toolName: step.tool, arguments: resolvedArgs)

            if approval == .forbidden {
                let error = SkillRunnerError.forbiddenStep(stepIndex: index, tool: step.tool)
                return SkillRunResult(
                    stepsCompleted: stepsCompleted,
                    totalSteps: steps.count,
                    stoppedAt: index,
                    output: error.localizedDescription,
                    success: false
                )
            }

            if approval == .modal {
                let desc = agentLoop.describeToolCall(name: step.tool, args: resolvedArgs)
                let approved = await agentLoop.requestApproval(
                    command: desc,
                    toolName: step.tool,
                    level: approval
                )
                if !approved {
                    let error = SkillRunnerError.deniedStep(stepIndex: index, tool: step.tool)
                    return SkillRunResult(
                        stepsCompleted: stepsCompleted,
                        totalSteps: steps.count,
                        stoppedAt: index,
                        output: error.localizedDescription,
                        success: false
                    )
                }
            }

            // Execute the tool with resolved args.
            let result = await agentLoop.executeTool(name: step.tool, args: resolvedArgs)

            // Log the tool call (same as executeToolCall does).
            agentLoop.logTool(
                name: step.tool,
                input: "\(resolvedArgs)",
                output: result.content,
                approval: approval,
                approved: true,
                durationMs: result.durationMs
            )

            // Privacy Ledger for side-effecting steps.
            if AgentLoop.isSideEffectingTool(step.tool, args: resolvedArgs) {
                let summary = String(result.content.prefix(500))
                try? DatabaseManager.shared.appendExecutionLog(
                    toolName: step.tool,
                    approvalLevel: approval,
                    summary: summary,
                    success: result.success,
                    durationMs: result.durationMs
                )
            }

            lastOutput = result.content

            if !result.success {
                let error = SkillRunnerError.stepFailed(
                    stepIndex: index,
                    tool: step.tool,
                    error: result.content
                )
                return SkillRunResult(
                    stepsCompleted: stepsCompleted,
                    totalSteps: steps.count,
                    stoppedAt: index,
                    output: error.localizedDescription,
                    success: false
                )
            }

            stepsCompleted += 1
        }

        return SkillRunResult(
            stepsCompleted: stepsCompleted,
            totalSteps: steps.count,
            stoppedAt: nil,
            output: lastOutput,
            success: true
        )
    }

    // MARK: - Private helpers

    private static func firstMissingKey(in template: String, parameters: [String: String]) -> String? {
        // Find all {{...}} placeholders in `template`.
        var searchRange = template.startIndex..<template.endIndex
        while let openRange = template.range(of: "{{", range: searchRange) {
            guard let closeRange = template.range(of: "}}", range: openRange.upperBound..<template.endIndex) else {
                break
            }
            let key = String(template[openRange.upperBound..<closeRange.lowerBound])
            if !key.isEmpty && parameters[key] == nil {
                return key
            }
            searchRange = closeRange.upperBound..<template.endIndex
        }
        return nil
    }
}
