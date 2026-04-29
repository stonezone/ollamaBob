import Foundation
import GRDB

enum AppDatabase {
    static func createTables(_ db: Database) throws {
        try db.create(table: "conversations", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text)
            t.column("isPinned", .boolean).notNull().defaults(to: false)
            t.column("uncensoredMode", .boolean).notNull().defaults(to: false)
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        try db.create(table: "messages", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("conversationId", .text).notNull()
                .references("conversations", onDelete: .cascade)
            t.column("role", .text).notNull()
            t.column("content", .text)
            t.column("thinking", .text)
            t.column("toolCallsJson", .text)
            t.column("toolName", .text)
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }
        try db.create(index: "idx_messages_conv", on: "messages", columns: ["conversationId", "createdAt"], ifNotExists: true)

        try db.create(table: "toolLog", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("conversationId", .text).notNull()
                .references("conversations")
            t.column("toolName", .text).notNull()
            t.column("inputJson", .text).notNull()
            t.column("outputText", .text)
            t.column("approvalLevel", .text)
            t.column("approved", .boolean)
            t.column("durationMs", .integer)
            t.column("executedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        // Per V1.1 plan §schema: simple key/value store reserved for v2 memory
        // features. Created in v1 so we don't need a migration later.
        try db.create(table: "memory", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("key", .text).notNull().unique()
            t.column("value", .text).notNull()
            t.column("category", .text).defaults(to: "general")
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        // Phase 4 — sticky facts memory. Separate from the v1 `memory`
        // table which used a flat key/value scheme. This table follows
        // V2 plan §4.1 with category, source tracking, and lastUsedAt
        // for LRU trimming during prompt injection.
        try db.create(table: "facts", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("category", .text).notNull()          // identity, preference, project, reference, other
            t.column("content", .text).notNull()            // the fact itself, ≤ 400 chars
            t.column("source", .text).notNull()             // user-explicit, user-implicit, imported
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            t.column("lastUsedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }
        try db.create(index: "idx_facts_category", on: "facts", columns: ["category"], ifNotExists: true)

        // Phase 1b — Privacy Ledger. Logs approved side-effecting tool
        // executions only (writes, moves, downloads, calls). Read-only
        // tool calls are never recorded here.
        try db.create(table: "execution_log", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("timestamp", .double).notNull()         // TimeInterval since Unix epoch
            t.column("tool_name", .text).notNull()
            t.column("approval_level", .text).notNull()      // raw value of ApprovalLevel
            t.column("summary", .text).notNull()             // ≤ 500 chars, no secrets
            t.column("success", .integer).notNull()          // 0 or 1
            t.column("duration_ms", .integer).notNull()
        }
        try db.create(index: "idx_execution_log_timestamp", on: "execution_log", columns: ["timestamp"], ifNotExists: true)

        // Phase 7a — Skill Capsules. Stores user-defined named recipes that
        // replay a sequence of first-party tools via the existing approval gate.
        // Schema is additive only; no existing tables are altered.
        try db.create(table: "skill", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull().unique()
            t.column("description", .text).notNull()
            t.column("steps_json", .text).notNull()   // JSON array of {tool: string, args: object}
            t.column("created_at", .double).notNull()  // TimeInterval since Unix epoch
            t.column("updated_at", .double).notNull()
        }
        try db.create(index: "idx_skill_name", on: "skill", columns: ["name"], ifNotExists: true)
    }
}
