import Foundation

/// File-backed spillout for tool outputs too large to inline in the
/// conversation history.
///
/// Why: Gemma4/Qwen3 work best when their context isn't flooded with
/// repeated long stdout dumps. Instead of sending a 10K-char shell output
/// directly into the message list, we write it to disk under
/// `~/Library/Application Support/OllamaBob/spillout/<convId>/<id>.txt`
/// and leave a short pointer in the inline message. Bob can then
/// re-fetch slices on demand via the `read_tool_output` meta-tool.
///
/// Design:
/// - Integer ids only (Gemma4 mangles complex string tokens).
/// - Scoped per conversation — a fresh conv starts counting from 1.
/// - Counter is derived from the directory contents, so ids survive
///   app restart without a separate counter file.
/// - `clearConversation` wipes the conversation's spillout dir.
actor ToolOutputStore {

    static let shared = ToolOutputStore()

    private let rootDir: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        rootDir = appSupport
            .appendingPathComponent("OllamaBob", isDirectory: true)
            .appendingPathComponent("spillout", isDirectory: true)
        try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Writes the given content to a new spillout file for the conversation
    /// and returns the integer id the model can use to fetch it back.
    func write(content: String, conversationId: String) throws -> Int {
        let dir = try ensureConversationDir(conversationId)
        let nextId = nextIdInDir(dir)
        let file = dir.appendingPathComponent("\(nextId).txt")
        try content.write(to: file, atomically: true, encoding: .utf8)
        return nextId
    }

    /// Reads a previously-stored tool output by its integer id. If `range`
    /// is provided in the form `"start-end"` (either side optional), the
    /// returned string is a character-offset slice of the file.
    func read(id: Int, conversationId: String, range: String? = nil) throws -> String {
        let dir = conversationDir(conversationId)
        let file = dir.appendingPathComponent("\(id).txt")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ToolOutputStoreError.notFound(id: id)
        }
        let content = try String(contentsOf: file, encoding: .utf8)
        if let range, let sliced = Self.slice(content, range: range) {
            return sliced
        }
        return content
    }

    /// Removes the entire spillout directory for a conversation. Called
    /// from `/clear`, `/new`, or when a conversation is deleted.
    func clearConversation(_ conversationId: String) {
        let dir = conversationDir(conversationId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Private

    private func conversationDir(_ conversationId: String) -> URL {
        rootDir.appendingPathComponent(conversationId, isDirectory: true)
    }

    private func ensureConversationDir(_ conversationId: String) throws -> URL {
        let dir = conversationDir(conversationId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Walks the directory for files of the form `<int>.txt` and returns
    /// (max + 1), or 1 if the dir is empty. This makes ids survive restarts.
    private func nextIdInDir(_ dir: URL) -> Int {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        let ids = contents.compactMap { name -> Int? in
            guard name.hasSuffix(".txt") else { return nil }
            return Int(name.dropLast(4))
        }
        return (ids.max() ?? 0) + 1
    }

    /// Parse a `"start-end"` range string and return the corresponding
    /// character slice of `content`. Either side may be omitted:
    /// `"0-2000"`, `"500-"`, `"-1000"`. Out-of-bounds values are clamped.
    /// Returns nil if the range string is not parseable.
    private static func slice(_ content: String, range: String) -> String? {
        let trimmed = range.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return nil }
        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }

        let total = content.count
        let start: Int
        if parts[0].isEmpty {
            start = 0
        } else if let n = Int(parts[0]) {
            start = n
        } else {
            return nil
        }

        let end: Int
        if parts[1].isEmpty {
            end = total
        } else if let n = Int(parts[1]) {
            end = n
        } else {
            return nil
        }

        let lo = max(0, min(start, total))
        let hi = max(lo, min(end, total))
        let startIdx = content.index(content.startIndex, offsetBy: lo)
        let endIdx   = content.index(content.startIndex, offsetBy: hi)
        return String(content[startIdx..<endIdx])
    }
}

enum ToolOutputStoreError: Error, LocalizedError {
    case notFound(id: Int)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "No stored tool output with id \(id) in this conversation"
        }
    }
}
