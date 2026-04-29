import Foundation
import GRDB

// MARK: - GRDB Record

/// Raw GRDB record for the `briefing` table. Internal to the persistence layer.
/// Property names match the column names in the schema exactly (snake_case).
struct BriefingRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "briefing"

    // Coding keys map Swift property names to the exact column names.
    enum CodingKeys: String, CodingKey {
        case id
        case run_at
        case summary
        case tool_results_json
        case success
    }

    var id: Int64?
    var run_at: Double              // TimeInterval since Unix epoch
    var summary: String
    var tool_results_json: String   // JSON-encoded [String]
    var success: Int                // 0 or 1

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - BriefingStorage

/// CRUD for the `briefing` table.
///
/// Design follows the `execution_log` pattern in `DatabaseManager` but is kept
/// separate so the briefing feature can be understood and tested in isolation.
enum BriefingStorage {

    // MARK: - Append

    /// Persist a new briefing result and return it stamped with its row id.
    @discardableResult
    static func append(_ result: BriefingResult, in queue: DatabaseQueue) throws -> BriefingResult {
        let encoder = JSONEncoder()
        let data = try encoder.encode(result.toolResults)
        guard let json = String(data: data, encoding: .utf8) else {
            throw BriefingStorageError.encodingFailed
        }

        var record = BriefingRecord(
            id: nil,
            run_at: result.runAt.timeIntervalSince1970,
            summary: result.summary,
            tool_results_json: json,
            success: result.success ? 1 : 0
        )
        try queue.write { db in
            try record.insert(db)
        }
        guard let rowID = record.id else {
            throw BriefingStorageError.insertFailed
        }
        return result.withID(rowID)
    }

    // MARK: - Fetch recent

    /// Return the most recent `limit` briefings, newest first.
    static func fetchRecent(limit: Int = 50, in queue: DatabaseQueue) throws -> [BriefingResult] {
        let cap = max(1, limit)
        return try queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM briefing ORDER BY run_at DESC LIMIT ?",
                arguments: [cap]
            )
            return rows.compactMap { row -> BriefingResult? in
                rowToResult(row)
            }
        }
    }

    // MARK: - Fetch by date range

    /// Return briefings whose `run_at` falls within `[since, until]`.
    /// Pass `nil` for an open-ended range.
    static func fetch(
        since: Date? = nil,
        until: Date? = nil,
        limit: Int = 100,
        in queue: DatabaseQueue
    ) throws -> [BriefingResult] {
        var conditions: [String] = []
        var args: [DatabaseValue] = []

        if let s = since {
            conditions.append("run_at >= ?")
            args.append(s.timeIntervalSince1970.databaseValue)
        }
        if let u = until {
            conditions.append("run_at <= ?")
            args.append(u.timeIntervalSince1970.databaseValue)
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = "SELECT * FROM briefing \(whereClause) ORDER BY run_at DESC LIMIT ?"
        args.append(max(1, limit).databaseValue)

        return try queue.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.compactMap { rowToResult($0) }
        }
    }

    // MARK: - Private helpers

    private static func rowToResult(_ row: Row) -> BriefingResult? {
        guard
            let id: Int64 = row["id"],
            let runAtRaw: Double = row["run_at"],
            let summary: String = row["summary"],
            let toolResultsJson: String = row["tool_results_json"],
            let successInt: Int = row["success"]
        else {
            return nil
        }

        guard
            let data = toolResultsJson.data(using: .utf8),
            let toolResults = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }

        return BriefingResult(
            id: id,
            runAt: Date(timeIntervalSince1970: runAtRaw),
            summary: summary,
            toolResults: toolResults,
            success: successInt != 0
        )
    }
}

// MARK: - Errors

enum BriefingStorageError: LocalizedError {
    case encodingFailed
    case insertFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "BriefingStorage: failed to encode tool results as JSON."
        case .insertFailed:   return "BriefingStorage: insert did not return a row ID."
        }
    }
}
