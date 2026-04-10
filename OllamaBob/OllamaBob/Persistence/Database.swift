import Foundation
import GRDB

// GRDB record types
struct ConversationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversations"
    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
}

struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"
    var id: String
    var conversationId: String
    var role: String
    var content: String?
    var toolCallsJson: String?
    var toolName: String?
    var createdAt: Date
}

struct FactRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "facts"
    var id: String
    var category: String
    var content: String
    var source: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date
}

struct ToolLogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "toolLog"
    var id: String
    var conversationId: String
    var toolName: String
    var inputJson: String
    var outputText: String?
    var approvalLevel: String?
    var approved: Bool?
    var durationMs: Int?
    var executedAt: Date
}

final class DatabaseManager {
    static let shared = DatabaseManager()
    private var dbQueue: DatabaseQueue?

    private init() {}

    func setup() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("OllamaBob")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("ollamabob.sqlite").path

        dbQueue = try DatabaseQueue(path: dbPath)
        try dbQueue?.write { db in
            try AppDatabase.createTables(db)
        }
    }

    func canWrite() -> Bool {
        guard dbQueue != nil else { return false }
        do {
            try dbQueue?.write { db in
                try db.execute(sql: "SELECT 1")
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Conversations

    func createConversation(title: String = "New Chat") throws -> ConversationRecord {
        let record = ConversationRecord(
            id: UUID().uuidString,
            title: title,
            createdAt: Date(),
            updatedAt: Date()
        )
        try dbQueue?.write { db in
            try record.insert(db)
        }
        return record
    }

    func currentConversation() throws -> ConversationRecord? {
        try dbQueue?.read { db in
            try ConversationRecord
                .order(Column("updatedAt").desc)
                .fetchOne(db)
        }
    }

    func updateConversationTimestamp(_ id: String) throws {
        try dbQueue?.write { db in
            try db.execute(
                sql: "UPDATE conversations SET updatedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    // MARK: - Messages

    func saveMessage(_ msg: ChatMessage, conversationId: String) throws {
        var toolCallsJson: String?
        if let calls = msg.toolCalls {
            let data = try JSONEncoder().encode(calls)
            toolCallsJson = String(data: data, encoding: .utf8)
        }

        let record = MessageRecord(
            id: msg.id,
            conversationId: conversationId,
            role: msg.role.rawValue,
            content: msg.content,
            toolCallsJson: toolCallsJson,
            toolName: msg.toolName,
            createdAt: msg.timestamp
        )
        try dbQueue?.write { db in
            try record.insert(db)
        }
        try updateConversationTimestamp(conversationId)
    }

    func loadMessages(conversationId: String) throws -> [ChatMessage] {
        let records = try dbQueue?.read { db in
            try MessageRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        } ?? []

        return records.compactMap { record in
            guard let role = MessageRole(rawValue: record.role) else { return nil }
            var toolCalls: [OllamaToolCall]?
            if let json = record.toolCallsJson, let data = json.data(using: .utf8) {
                toolCalls = try? JSONDecoder().decode([OllamaToolCall].self, from: data)
            }
            return ChatMessage(
                id: record.id,
                role: role,
                content: record.content ?? "",
                toolCalls: toolCalls,
                toolName: record.toolName,
                timestamp: record.createdAt
            )
        }
    }

    // MARK: - Facts (Phase 4 sticky memory)

    func saveFact(category: String, content: String, source: String = "user-explicit") throws -> FactRecord {
        let now = Date()
        var record = FactRecord(
            id: UUID().uuidString,
            category: category,
            content: String(content.prefix(400)),
            source: source,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: now
        )
        try dbQueue?.write { db in
            try record.insert(db)
        }
        return record
    }

    func deleteFact(id: String) throws -> Bool {
        let deleted = try dbQueue?.write { db -> Int in
            try db.execute(sql: "DELETE FROM facts WHERE id = ?", arguments: [id])
            return db.changesCount
        }
        return (deleted ?? 0) > 0
    }

    func fetchFacts(category: String? = nil) throws -> [FactRecord] {
        try dbQueue?.read { db in
            if let cat = category {
                return try FactRecord
                    .filter(Column("category") == cat)
                    .order(Column("updatedAt").desc)
                    .fetchAll(db)
            } else {
                return try FactRecord
                    .order(Column("category").asc, Column("updatedAt").desc)
                    .fetchAll(db)
            }
        } ?? []
    }

    /// Fetch facts for prompt injection per V2 plan §4.3:
    /// all facts where lastUsedAt > 30 days ago OR category = 'identity'.
    func fetchActiveFacts() throws -> [FactRecord] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return try dbQueue?.read { db in
            try FactRecord
                .filter(Column("category") == "identity" || Column("lastUsedAt") > thirtyDaysAgo)
                .order(Column("category").asc, Column("lastUsedAt").desc)
                .fetchAll(db)
        } ?? []
    }

    /// Touch lastUsedAt for a batch of fact ids (called once per turn
    /// after PromptComposer injects them into the system prompt).
    func touchFacts(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue?.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE facts SET lastUsedAt = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments([Date()] + ids)
            )
        }
    }

    // MARK: - Tool Logs

    func saveToolLog(
        conversationId: String,
        toolName: String,
        inputJson: String,
        outputText: String,
        approvalLevel: ApprovalLevel,
        approved: Bool,
        durationMs: Int
    ) throws {
        let record = ToolLogRecord(
            id: UUID().uuidString,
            conversationId: conversationId,
            toolName: toolName,
            inputJson: inputJson,
            outputText: outputText,
            approvalLevel: approvalLevel.rawValue,
            approved: approved,
            durationMs: durationMs,
            executedAt: Date()
        )
        try dbQueue?.write { db in
            try record.insert(db)
        }
    }
}
