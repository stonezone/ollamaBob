import Foundation
import GRDB

enum AppDatabase {
    static func createTables(_ db: Database) throws {
        try db.create(table: "conversations", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text)
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        try db.create(table: "messages", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("conversationId", .text).notNull()
                .references("conversations", onDelete: .cascade)
            t.column("role", .text).notNull()
            t.column("content", .text)
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
    }
}
