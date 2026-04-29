import XCTest
@testable import OllamaBob

final class SkillStorageTests: XCTestCase {

    override func tearDown() {
        DatabaseManager.shared.resetForTesting()
        super.tearDown()
    }

    // MARK: - Helper

    private func withTemporaryDatabase(_ body: (DatabaseManager) throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbURL = tempDir.appendingPathComponent("skill_storage_test.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try DatabaseManager.shared.setup(at: dbURL)
        try body(DatabaseManager.shared)
        DatabaseManager.shared.resetForTesting()
    }

    private func makeSteps(_ tools: [String]) -> [SkillStep] {
        tools.map { SkillStep(tool: $0, args: ["query": .string("hello")]) }
    }

    // MARK: - Test 1: Create + fetch round-trip

    func testCreateAndFetchRoundTrip() throws {
        try withTemporaryDatabase { db in
            let steps = makeSteps(["web_search"])
            let skill = try db.createSkill(
                name: "my_search",
                description: "Run a web search",
                steps: steps
            )

            XCTAssertGreaterThan(skill.id, 0)
            XCTAssertEqual(skill.name, "my_search")
            XCTAssertEqual(skill.description, "Run a web search")
            XCTAssertEqual(skill.steps.count, 1)
            XCTAssertEqual(skill.steps[0].tool, "web_search")

            // Fetch by name and verify equality of fields.
            let fetched = try db.fetchSkill(named: "my_search")
            XCTAssertNotNil(fetched)
            XCTAssertEqual(fetched?.name, "my_search")
            XCTAssertEqual(fetched?.steps.count, 1)
            XCTAssertEqual(fetched?.steps[0].tool, "web_search")
        }
    }

    // MARK: - Test 2: Unique name constraint is enforced

    func testUniqueNameConstraintEnforced() throws {
        try withTemporaryDatabase { db in
            let steps = makeSteps(["read_file"])
            _ = try db.createSkill(name: "dupe", description: "first", steps: steps)

            XCTAssertThrowsError(
                try db.createSkill(name: "dupe", description: "second", steps: steps)
            ) { error in
                // GRDB throws a DatabaseError for UNIQUE constraint violations.
                let desc = error.localizedDescription
                XCTAssertTrue(
                    desc.localizedCaseInsensitiveContains("unique") ||
                    desc.localizedCaseInsensitiveContains("UNIQUE") ||
                    desc.localizedCaseInsensitiveContains("already exists"),
                    "Expected unique-constraint error, got: \(desc)"
                )
            }
        }
    }

    // MARK: - Test 3: List is ordered by name ascending

    func testListOrderedByName() throws {
        try withTemporaryDatabase { db in
            let steps = makeSteps(["shell"])
            _ = try db.createSkill(name: "zzz_last",  description: "z", steps: steps)
            _ = try db.createSkill(name: "aaa_first", description: "a", steps: steps)
            _ = try db.createSkill(name: "mmm_mid",   description: "m", steps: steps)

            let list = try db.listSkills()
            XCTAssertEqual(list.count, 3)
            XCTAssertEqual(list[0].name, "aaa_first")
            XCTAssertEqual(list[1].name, "mmm_mid")
            XCTAssertEqual(list[2].name, "zzz_last")
        }
    }

    // MARK: - Test 4: Delete by name

    func testDeleteByName() throws {
        try withTemporaryDatabase { db in
            let steps = makeSteps(["list_directory"])
            _ = try db.createSkill(name: "to_delete", description: "gone soon", steps: steps)

            // Confirm it exists.
            let before = try db.fetchSkill(named: "to_delete")
            XCTAssertNotNil(before)

            // Delete it.
            let deleted = try db.deleteSkill(named: "to_delete")
            XCTAssertTrue(deleted, "deleteSkill should return true when a row was removed")

            // Confirm it's gone.
            let after = try db.fetchSkill(named: "to_delete")
            XCTAssertNil(after)

            // Second delete returns false.
            let deletedAgain = try db.deleteSkill(named: "to_delete")
            XCTAssertFalse(deletedAgain, "deleteSkill should return false when no row matches")
        }
    }

    // MARK: - Test 5: Multi-step round-trip preserves args

    func testMultiStepRoundTrip() throws {
        try withTemporaryDatabase { db in
            let steps: [SkillStep] = [
                SkillStep(tool: "web_search", args: ["query": .string("{{topic}}")]),
                SkillStep(tool: "read_file",  args: ["path": .string("/tmp/result.txt")])
            ]
            _ = try db.createSkill(name: "multi", description: "two steps", steps: steps)

            let fetched = try db.fetchSkill(named: "multi")
            XCTAssertEqual(fetched?.steps.count, 2)
            XCTAssertEqual(fetched?.steps[0].tool, "web_search")
            if case .string(let v) = fetched?.steps[0].args["query"] {
                XCTAssertEqual(v, "{{topic}}")
            } else {
                XCTFail("Expected string arg for query")
            }
            XCTAssertEqual(fetched?.steps[1].tool, "read_file")
        }
    }
}
