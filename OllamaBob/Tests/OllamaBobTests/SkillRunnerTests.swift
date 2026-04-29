import XCTest
@testable import OllamaBob

/// Tests for SkillRunner static helpers.
///
/// The `run(skill:parameters:agentLoop:)` path requires a live AgentLoop with
/// an approval handler and dispatches real tool calls, so those are covered by
/// testing the pre-flight helpers (firstUnknownTool, firstMissingPlaceholder)
/// and the substitution engine directly. The SkillStorageTests cover the full
/// persistence round-trip; CreateSkillTool tests cover the create-time validator.
@MainActor
final class SkillRunnerTests: XCTestCase {

    // MARK: - Helpers

    private func makeStep(tool: String, args: [String: JSONValue] = [:]) -> SkillStep {
        SkillStep(tool: tool, args: args)
    }

    private func knownTools() -> Set<String> {
        ["web_search", "read_file", "write_file", "shell", "list_directory"]
    }

    // MARK: - Test 1: All known tools — firstUnknownTool returns nil

    func testValidStepsPassToolNameCheck() {
        let steps = [
            makeStep(tool: "web_search"),
            makeStep(tool: "read_file")
        ]
        let result = SkillRunner.firstUnknownTool(in: steps, knownToolNames: knownTools())
        XCTAssertNil(result, "All tools are known — should return nil")
    }

    // MARK: - Test 2: Unknown tool name fails at create time

    func testUnknownToolNameIsDetected() {
        let steps = [
            makeStep(tool: "web_search"),
            makeStep(tool: "nonexistent_tool_xyz")
        ]
        let unknown = SkillRunner.firstUnknownTool(in: steps, knownToolNames: knownTools())
        XCTAssertEqual(unknown, "nonexistent_tool_xyz")
    }

    // MARK: - Test 3: Parameter substitution for a single {{key}}

    func testParameterSubstitutionSingleKey() {
        let result = SkillRunner.substitute(template: "search for {{topic}}", parameters: ["topic": "swift concurrency"])
        XCTAssertEqual(result, "search for swift concurrency")
    }

    func testParameterSubstitutionMultipleKeys() {
        let result = SkillRunner.substitute(
            template: "{{greeting}} {{name}}!",
            parameters: ["greeting": "Hello", "name": "Bob"]
        )
        XCTAssertEqual(result, "Hello Bob!")
    }

    func testParameterSubstitutionNoPlaceholders() {
        let result = SkillRunner.substitute(template: "static text", parameters: ["key": "val"])
        XCTAssertEqual(result, "static text")
    }

    func testParameterSubstitutionOnJSONValueString() {
        let value = JSONValue.string("find {{term}} in {{location}}")
        let substituted = SkillRunner.substituteValue(value, parameters: ["term": "errors", "location": "/var/log"])
        if case .string(let s) = substituted {
            XCTAssertEqual(s, "find errors in /var/log")
        } else {
            XCTFail("Expected a string JSONValue after substitution")
        }
    }

    func testParameterSubstitutionLeavesNonStringValuesUntouched() {
        let value = JSONValue.number(42)
        let substituted = SkillRunner.substituteValue(value, parameters: ["key": "ignored"])
        XCTAssertEqual(substituted, value)
    }

    // MARK: - Test 4: Missing parameter aborts before any step runs

    func testMissingParameterIsDetectedBeforeRun() {
        let steps = [
            makeStep(tool: "web_search", args: ["query": .string("{{missing_key}}")]),
            makeStep(tool: "read_file",  args: ["path": .string("/tmp/file.txt")])
        ]
        let result = SkillRunner.firstMissingPlaceholder(in: steps, parameters: [:])
        XCTAssertNotNil(result, "Should detect missing placeholder")
        XCTAssertEqual(result?.placeholder, "missing_key")
        XCTAssertEqual(result?.stepIndex, 0)
    }

    func testAllPlaceholdersPresentReturnsNil() {
        let steps = [
            makeStep(tool: "web_search", args: ["query": .string("{{topic}}")]),
            makeStep(tool: "read_file",  args: ["path": .string("{{file_path}}")])
        ]
        let result = SkillRunner.firstMissingPlaceholder(
            in: steps,
            parameters: ["topic": "AI", "file_path": "/tmp/out.txt"]
        )
        XCTAssertNil(result, "All placeholders provided — should return nil")
    }

    func testMissingPlaceholderInSecondStepReturnsCorrectIndex() {
        let steps = [
            makeStep(tool: "web_search", args: ["query": .string("{{known}}")]),
            makeStep(tool: "read_file",  args: ["path": .string("{{unknown_path}}")])
        ]
        let result = SkillRunner.firstMissingPlaceholder(
            in: steps,
            parameters: ["known": "hello"]   // missing "unknown_path"
        )
        XCTAssertEqual(result?.placeholder, "unknown_path")
        XCTAssertEqual(result?.stepIndex, 1)
    }

    // MARK: - Test 5: resolveArgs converts JSONValue args to [String: Any]

    func testResolveArgsSubstitutesStringValues() {
        let args: [String: JSONValue] = [
            "query": .string("{{q}}"),
            "limit": .number(5)
        ]
        let resolved = SkillRunner.resolveArgs(args, parameters: ["q": "test query"])
        XCTAssertEqual(resolved["query"] as? String, "test query")
        XCTAssertEqual(resolved["limit"] as? Double, 5.0)
    }

    // MARK: - Test 6: CreateSkillTool rejects unknown tool at create time

    func testCreateSkillToolRejectsUnknownTool() {
        let stepsJson = """
        [{"tool": "definitely_not_a_real_tool", "args": {"x": "y"}}]
        """
        let result = CreateSkillTool.execute(
            name: "bad_skill",
            description: "Should fail",
            stepsJson: stepsJson,
            knownToolNames: knownTools()
        )
        XCTAssertFalse(result.success, "create_skill should fail when a step references an unknown tool")
        XCTAssertTrue(result.content.contains("definitely_not_a_real_tool"),
                      "Error should name the unknown tool")
    }

    // MARK: - Test 7: CreateSkillTool rejects empty name

    func testCreateSkillToolRejectsEmptyName() {
        let stepsJson = """
        [{"tool": "web_search", "args": {"query": "test"}}]
        """
        let result = CreateSkillTool.execute(
            name: "   ",
            description: "desc",
            stepsJson: stepsJson,
            knownToolNames: knownTools()
        )
        XCTAssertFalse(result.success)
    }

    // MARK: - Test 8: CreateSkillTool rejects malformed steps_json

    func testCreateSkillToolRejectsMalformedJSON() {
        let result = CreateSkillTool.execute(
            name: "broken",
            description: "desc",
            stepsJson: "not valid json",
            knownToolNames: knownTools()
        )
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.lowercased().contains("error") ||
                      result.content.lowercased().contains("parse"),
                      "Error message should describe the parse failure")
    }

    // MARK: - Test 9: CreateSkillTool rejects empty steps array

    func testCreateSkillToolRejectsEmptyStepsArray() {
        let result = CreateSkillTool.execute(
            name: "empty_skill",
            description: "no steps",
            stepsJson: "[]",
            knownToolNames: knownTools()
        )
        XCTAssertFalse(result.success)
    }

    // MARK: - Test 10: SkillRunnerError descriptions are informative

    func testSkillRunnerErrorDescriptions() {
        let errors: [SkillRunnerError] = [
            .unknownTool("foo_tool"),
            .missingParameter(placeholder: "mykey", step: 2),
            .stepFailed(stepIndex: 1, tool: "shell", error: "timeout"),
            .forbiddenStep(stepIndex: 0, tool: "sudo_thing"),
            .deniedStep(stepIndex: 3, tool: "write_file")
        ]
        for error in errors {
            let desc = error.localizedDescription
            XCTAssertFalse(desc.isEmpty, "Error description should not be empty for \(error)")
        }
    }
}
