import Foundation
import GRDB

// MARK: - SkillRecord (GRDB row type)
//
// Phase 7a — Skill Capsules.
// Encodes / decodes a single row from the `skill` table. The skill CRUD methods
// live in Database.swift (same file as requireQueue) so they can access the
// private `requireQueue()` helper directly.

struct SkillRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "skill"

    var id: Int64?
    var name: String
    var description: String
    var stepsJson: String           // JSON-encoded [SkillStep]
    var createdAt: Double           // TimeInterval since Unix epoch
    var updatedAt: Double

    // Map Swift property names to snake_case column names.
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case stepsJson = "steps_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - SkillStorageError

enum SkillStorageError: LocalizedError {
    case insertFailed
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .insertFailed:   return "Skill insert succeeded but returned no row id."
        case .encodingFailed: return "Failed to encode skill steps to JSON."
        case .decodingFailed: return "Failed to decode skill steps from stored JSON."
        }
    }
}
