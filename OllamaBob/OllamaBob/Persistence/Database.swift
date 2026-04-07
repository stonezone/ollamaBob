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
