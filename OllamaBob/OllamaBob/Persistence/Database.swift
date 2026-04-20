import Foundation
import GRDB

enum DatabaseManagerError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database is not initialized."
        }
    }
}

// GRDB record types
struct ConversationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversations"
    var id: String
    var title: String
    var isPinned: Bool
    var uncensoredMode: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"
    var id: String
    var conversationId: String
    var role: String
    var content: String?
    var thinking: String?
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
        let dbURL = appSupport
            .appendingPathComponent("OllamaBob", isDirectory: true)
            .appendingPathComponent("ollamabob.sqlite", isDirectory: false)
        try setup(at: dbURL)
    }

    func setup(at dbURL: URL) throws {
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let queue = try DatabaseQueue(path: dbURL.path)
        try queue.write { db in
            try AppDatabase.createTables(db)
            try Self.ensureConversationColumns(in: db)
            try Self.ensureMessageColumns(in: db)
        }
        dbQueue = queue
    }

    func resetForTesting() {
        dbQueue = nil
    }

    func canWrite() -> Bool {
        do {
            let queue = try requireQueue()
            try queue.write { db in
                try db.execute(sql: "SELECT 1")
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Conversations

    func createConversation(title: String = "New Chat", uncensoredMode: Bool = false) throws -> ConversationRecord {
        let queue = try requireQueue()
        let record = ConversationRecord(
            id: UUID().uuidString,
            title: title,
            isPinned: false,
            uncensoredMode: uncensoredMode,
            createdAt: Date(),
            updatedAt: Date()
        )
        try queue.write { db in
            try record.insert(db)
        }
        return record
    }

    func currentConversation() throws -> ConversationRecord? {
        let queue = try requireQueue()
        return try queue.read { db in
            try ConversationRecord
                .order(Column("updatedAt").desc)
                .fetchOne(db)
        }
    }

    func listConversations() throws -> [ConversationSummary] {
        let queue = try requireQueue()
        return try queue.read { db in
            let records = try ConversationRecord
                .order(Column("isPinned").desc, Column("updatedAt").desc, Column("createdAt").desc)
                .fetchAll(db)
            return records.map {
                ConversationSummary(
                    id: $0.id,
                    title: $0.title,
                    isPinned: $0.isPinned,
                    uncensoredMode: $0.uncensoredMode,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        }
    }

    func loadConversation(id: String) throws -> ConversationSnapshot? {
        let queue = try requireQueue()
        return try queue.read { db in
            guard let record = try ConversationRecord.fetchOne(db, key: id) else {
                return nil
            }

            return ConversationSnapshot(
                id: record.id,
                title: record.title,
                isPinned: record.isPinned,
                uncensoredMode: record.uncensoredMode,
                messages: try loadMessages(in: db, conversationId: id),
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
        }
    }

    func renameConversation(id: String, title: String) throws -> ConversationSummary? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConversationStoreError.invalidTitle
        }

        let queue = try requireQueue()
        return try queue.write { db in
            guard let record = try ConversationRecord.fetchOne(db, key: id) else {
                return nil
            }
            if record.title == trimmed {
                return ConversationSummary(
                    id: record.id,
                    title: record.title,
                    isPinned: record.isPinned,
                    uncensoredMode: record.uncensoredMode,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
            }

            let now = Date()
            try db.execute(
                sql: "UPDATE conversations SET title = ?, updatedAt = ? WHERE id = ?",
                arguments: [trimmed, now, id]
            )

            return try ConversationRecord.fetchOne(db, key: id).map {
                ConversationSummary(
                    id: $0.id,
                    title: $0.title,
                    isPinned: $0.isPinned,
                    uncensoredMode: $0.uncensoredMode,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        }
    }

    func setConversationPinned(id: String, isPinned: Bool) throws -> ConversationSummary? {
        let queue = try requireQueue()
        return try queue.write { db in
            guard try ConversationRecord.fetchOne(db, key: id) != nil else {
                return nil
            }

            try db.execute(
                sql: "UPDATE conversations SET isPinned = ?, updatedAt = ? WHERE id = ?",
                arguments: [isPinned, Date(), id]
            )

            return try ConversationRecord.fetchOne(db, key: id).map {
                ConversationSummary(
                    id: $0.id,
                    title: $0.title,
                    isPinned: $0.isPinned,
                    uncensoredMode: $0.uncensoredMode,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        }
    }

    func setConversationUncensoredMode(id: String, isEnabled: Bool) throws -> ConversationSummary? {
        let queue = try requireQueue()
        return try queue.write { db in
            guard try ConversationRecord.fetchOne(db, key: id) != nil else {
                return nil
            }

            try db.execute(
                sql: "UPDATE conversations SET uncensoredMode = ?, updatedAt = ? WHERE id = ?",
                arguments: [isEnabled, Date(), id]
            )

            return try ConversationRecord.fetchOne(db, key: id).map {
                ConversationSummary(
                    id: $0.id,
                    title: $0.title,
                    isPinned: $0.isPinned,
                    uncensoredMode: $0.uncensoredMode,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        }
    }

    func deleteConversation(id: String) throws -> Bool {
        let queue = try requireQueue()
        return try queue.write { db in
            try db.execute(sql: "DELETE FROM toolLog WHERE conversationId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM messages WHERE conversationId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM conversations WHERE id = ?", arguments: [id])
            return db.changesCount > 0
        }
    }

    func updateConversationTimestamp(_ id: String) throws {
        let queue = try requireQueue()
        try queue.write { db in
            try db.execute(
                sql: "UPDATE conversations SET updatedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    // MARK: - Messages

    func saveMessage(_ msg: ChatMessage, conversationId: String) throws {
        let queue = try requireQueue()
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
            thinking: msg.thinking,
            toolCallsJson: toolCallsJson,
            toolName: msg.toolName,
            createdAt: msg.timestamp
        )
        let updatedAt = Date()
        try queue.write { db in
            try record.insert(db)
            try db.execute(
                sql: "UPDATE conversations SET updatedAt = ? WHERE id = ?",
                arguments: [updatedAt, conversationId]
            )
        }
    }

    func loadMessages(conversationId: String) throws -> [ChatMessage] {
        let queue = try requireQueue()
        return try queue.read { db in
            try loadMessages(in: db, conversationId: conversationId)
        }
    }

    // MARK: - Facts (Phase 4 sticky memory)

    func saveFact(category: String, content: String, source: String = "user-explicit") throws -> FactRecord {
        let queue = try requireQueue()
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
        try queue.write { db in
            try record.insert(db)
        }
        return record
    }

    func deleteFact(id: String) throws -> Bool {
        let queue = try requireQueue()
        let deleted = try queue.write { db -> Int in
            try db.execute(sql: "DELETE FROM facts WHERE id = ?", arguments: [id])
            return db.changesCount
        }
        return deleted > 0
    }

    func fetchFacts(category: String? = nil) throws -> [FactRecord] {
        let queue = try requireQueue()
        return try queue.read { db in
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
        }
    }

    /// Fetch facts for prompt injection per V2 plan §4.3:
    /// all facts where lastUsedAt > 30 days ago OR category = 'identity'.
    func fetchActiveFacts() throws -> [FactRecord] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let queue = try requireQueue()
        return try queue.read { db in
            try FactRecord
                .filter(Column("category") == "identity" || Column("lastUsedAt") > thirtyDaysAgo)
                .order(Column("category").asc, Column("lastUsedAt").desc)
                .fetchAll(db)
        }
    }

    /// Touch lastUsedAt for a batch of fact ids (called once per turn
    /// after PromptComposer injects them into the system prompt).
    func touchFacts(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let queue = try requireQueue()
        try queue.write { db in
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
        let queue = try requireQueue()
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
        try queue.write { db in
            try record.insert(db)
        }
    }

    private func requireQueue() throws -> DatabaseQueue {
        guard let dbQueue else {
            throw DatabaseManagerError.notInitialized
        }
        return dbQueue
    }

    private static func ensureConversationColumns(in db: Database) throws {
        let columns = try db.columns(in: "conversations").map(\.name)
        if columns.contains("isPinned") == false {
            try db.execute(sql: "ALTER TABLE conversations ADD COLUMN isPinned BOOLEAN NOT NULL DEFAULT 0")
        }
        if columns.contains("uncensoredMode") == false {
            try db.execute(sql: "ALTER TABLE conversations ADD COLUMN uncensoredMode BOOLEAN NOT NULL DEFAULT 0")
        }
    }

    private static func ensureMessageColumns(in db: Database) throws {
        let columns = try db.columns(in: "messages").map(\.name)
        if columns.contains("thinking") == false {
            try db.execute(sql: "ALTER TABLE messages ADD COLUMN thinking TEXT")
        }
    }

    private func loadMessageRecords(in db: Database, conversationId: String) throws -> [MessageRecord] {
        try MessageRecord
            .filter(Column("conversationId") == conversationId)
            .order(Column("createdAt").asc)
            .fetchAll(db)
    }

    private func loadMessages(in db: Database, conversationId: String) throws -> [ChatMessage] {
        let records = try loadMessageRecords(in: db, conversationId: conversationId)
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
                thinking: record.thinking,
                toolCalls: toolCalls,
                toolName: record.toolName,
                timestamp: record.createdAt
            )
        }
    }

    // MARK: - V2.5 search & memory I/O

    /// One hit in a full-text search. conversationId + title locate the thread;
    /// snippet is the matching message content trimmed to 160 chars.
    struct MessageSearchHit: Identifiable {
        let id: String
        let conversationId: String
        let conversationTitle: String
        let role: String
        let snippet: String
        let createdAt: Date
    }

    /// Cheap LIKE search across every message body. Good enough for a few
    /// thousand chats; swap to FTS5 later if it gets slow.
    func searchMessages(query: String, limit: Int = 50) throws -> [MessageSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let queue = try requireQueue()
        let pattern = "%\(trimmed)%"
        return try queue.read { db in
            let sql = """
                SELECT m.id, m.conversationId, c.title, m.role, m.content, m.createdAt
                FROM messages m
                JOIN conversations c ON c.id = m.conversationId
                WHERE m.content LIKE ? COLLATE NOCASE
                ORDER BY m.createdAt DESC
                LIMIT ?
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [pattern, limit])
            return rows.map { row -> MessageSearchHit in
                let raw: String = row["content"] ?? ""
                let snippet = String(raw.prefix(160))
                return MessageSearchHit(
                    id: row["id"],
                    conversationId: row["conversationId"],
                    conversationTitle: row["title"] ?? "Untitled",
                    role: row["role"] ?? "assistant",
                    snippet: snippet,
                    createdAt: row["createdAt"]
                )
            }
        }
    }

    /// Replace the content of an existing fact. Bumps updatedAt + lastUsedAt
    /// so the edit doesn't get immediately LRU-trimmed.
    func updateFact(id: String, content: String) throws -> Bool {
        let queue = try requireQueue()
        let now = Date()
        let capped = String(content.prefix(400))
        let changed = try queue.write { db -> Int in
            try db.execute(
                sql: "UPDATE facts SET content = ?, updatedAt = ?, lastUsedAt = ? WHERE id = ?",
                arguments: [capped, now, now, id]
            )
            return db.changesCount
        }
        return changed > 0
    }

    /// Serialize every fact to a portable markdown document. Categories become
    /// H2 headers; each fact is a bullet. Round-trip stable with importFactsMarkdown.
    func exportFactsMarkdown() throws -> String {
        let facts = try fetchFacts()
        guard !facts.isEmpty else {
            return "# OllamaBob memory export\n\n_(empty)_\n"
        }
        let grouped = Dictionary(grouping: facts, by: { $0.category })
        let categories = grouped.keys.sorted()
        var out = "# OllamaBob memory export\n\n"
        let formatter = ISO8601DateFormatter()
        out += "_exported \(formatter.string(from: Date()))_\n\n"
        for cat in categories {
            out += "## \(cat)\n\n"
            for fact in grouped[cat, default: []] {
                let content = fact.content.replacingOccurrences(of: "\n", with: " ")
                out += "- \(content)\n"
            }
            out += "\n"
        }
        return out
    }

    /// Parse a markdown document in the exportFactsMarkdown format and insert
    /// new facts. Existing facts are left alone (import is additive). Returns
    /// the count of newly-inserted rows.
    @discardableResult
    func importFactsMarkdown(_ text: String) throws -> Int {
        var currentCategory = "general"
        var inserted = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                currentCategory = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if currentCategory.isEmpty { currentCategory = "general" }
                continue
            }
            if line.hasPrefix("- ") {
                let body = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { continue }
                _ = try saveFact(category: currentCategory, content: body, source: "import")
                inserted += 1
            }
        }
        return inserted
    }
}
