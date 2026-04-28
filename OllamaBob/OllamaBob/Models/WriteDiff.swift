import Foundation

/// Computes unified diffs between file versions for write_file approval modals.
/// All computation is in-process — no shelling out to external tools.
enum WriteDiff {

    // MARK: - Caps

    /// Maximum combined byte count (before + after) we are willing to diff.
    static let maxCombinedBytes = 200 * 1024  // 200 KB

    /// Maximum combined line count (before + after) we are willing to diff.
    static let maxCombinedLines = 6_000

    // MARK: - Public entry points

    /// Read the existing file at `fileURL`, then produce a unified diff against
    /// `proposedContent`. Returns `nil` when:
    ///   - The file does not exist (new file — no diff to show).
    ///   - The file cannot be read (binary, permission denied, encoding error).
    ///   - Inputs exceed the size cap.
    ///   - The proposed content is identical to the existing content.
    static func computeForWriteFile(at fileURL: URL, proposedContent: String) -> String? {
        // Existence check — not an error, just means new file.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        // Attempt to read as UTF-8; return nil on any failure (binary, perms, etc.)
        guard let existingContent = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }

        return unified(
            beforeContent: existingContent,
            afterContent: proposedContent,
            beforePath: fileURL.path,
            afterPath: fileURL.path
        )
    }

    /// Produce a unified diff string (standard format) between `beforeContent`
    /// and `afterContent`. Returns `nil` when either input exceeds the cap,
    /// or when the two inputs are identical (no hunks to show).
    ///
    /// - Parameters:
    ///   - beforeContent: Original file text.
    ///   - afterContent:  Proposed replacement text.
    ///   - beforePath:    Shown in the `--- path` header line.
    ///   - afterPath:     Shown in the `+++ path` header line.
    ///   - contextLines:  Number of unchanged lines to include around each change.
    static func unified(
        beforeContent: String,
        afterContent: String,
        beforePath: String,
        afterPath: String,
        contextLines: Int = 3
    ) -> String? {
        // Size cap check (bytes)
        let combinedBytes = beforeContent.utf8.count + afterContent.utf8.count
        guard combinedBytes <= maxCombinedBytes else { return nil }

        let beforeLines = splitLines(beforeContent)
        let afterLines  = splitLines(afterContent)

        // Line cap check
        guard beforeLines.count + afterLines.count <= maxCombinedLines else { return nil }

        // Identical content — nothing to show
        guard beforeLines != afterLines else { return nil }

        // Compute edit script via Myers' diff
        let edits = myersDiff(before: beforeLines, after: afterLines)

        // Group edits into hunks
        let hunks = buildHunks(edits: edits, beforeLines: beforeLines, afterLines: afterLines, contextLines: contextLines)
        guard !hunks.isEmpty else { return nil }

        // Render
        var output = "--- \(beforePath)\n+++ \(afterPath)\n"
        for hunk in hunks {
            output += renderHunk(hunk, beforeLines: beforeLines, afterLines: afterLines)
        }
        return output
    }

    // MARK: - LCS / Myers diff

    /// An edit operation in the diff.
    private enum Edit {
        case equal(oldIndex: Int, newIndex: Int)
        case delete(oldIndex: Int)
        case insert(newIndex: Int)
    }

    /// O(ND) Myers' diff algorithm.  Returns the shortest edit script.
    private static func myersDiff(before: [String], after: [String]) -> [Edit] {
        let n = before.count
        let m = after.count

        if n == 0 && m == 0 { return [] }
        if n == 0 { return (0..<m).map { .insert(newIndex: $0) } }
        if m == 0 { return (0..<n).map { .delete(oldIndex: $0) } }

        let max = n + m
        // v[k + max] = x-coordinate of the furthest-reaching D-path along diagonal k
        var v = [Int](repeating: 0, count: 2 * max + 1)

        // trace[d][k+max] = x value for that D/k pair (for backtracking)
        var trace: [[Int]] = []

        outer: for d in 0...max {
            trace.append(v)
            let kRange = stride(from: -d, through: d, by: 2)
            for k in kRange {
                var x: Int
                if k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max]) {
                    x = v[k + 1 + max]   // move down (insert)
                } else {
                    x = v[k - 1 + max] + 1  // move right (delete)
                }
                var y = x - k
                // Follow diagonal (equal lines)
                while x < n && y < m && before[x] == after[y] {
                    x += 1
                    y += 1
                }
                v[k + max] = x
                if x >= n && y >= m {
                    // Reached end — backtrack to build edit list
                    return backtrack(trace: trace, before: before, after: after, max: max)
                }
            }
        }
        // Fallback: replace all (should not happen for finite inputs)
        return (0..<n).map { .delete(oldIndex: $0) } + (0..<m).map { .insert(newIndex: $0) }
    }

    private static func backtrack(trace: [[Int]], before: [String], after: [String], max: Int) -> [Edit] {
        var edits: [Edit] = []
        var x = before.count
        var y = after.count

        for d in stride(from: trace.count - 1, through: 1, by: -1) {
            let v = trace[d]
            let k = x - y
            let prevK: Int
            if k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max]) {
                prevK = k + 1  // came from down (insert)
            } else {
                prevK = k - 1  // came from right (delete)
            }
            let prevX = v[prevK + max]
            let prevY = prevX - prevK

            // Walk diagonal backwards (equal lines)
            while x > prevX && y > prevY {
                x -= 1
                y -= 1
                edits.append(.equal(oldIndex: x, newIndex: y))
            }

            if d > 0 {
                if x == prevX {
                    // Came from down → insert from `after`
                    y -= 1
                    edits.append(.insert(newIndex: y))
                } else {
                    // Came from right → delete from `before`
                    x -= 1
                    edits.append(.delete(oldIndex: x))
                }
            }
        }
        // Handle the initial diagonal from (0,0)
        let v0 = trace[0]
        let k = x - y
        let startX = v0[k + max]
        let startY = startX - k
        while x > startX && y > startY {
            x -= 1
            y -= 1
            edits.append(.equal(oldIndex: x, newIndex: y))
        }

        return edits.reversed()
    }

    // MARK: - Hunk building

    private struct HunkSpan {
        var oldStart: Int   // 0-based
        var oldCount: Int
        var newStart: Int   // 0-based
        var newCount: Int
        var editSlice: ArraySlice<Edit>
    }

    private static func buildHunks(
        edits: [Edit],
        beforeLines: [String],
        afterLines: [String],
        contextLines: Int
    ) -> [HunkSpan] {
        // Identify change positions so we know where hunks begin/end
        var changeIndices: [Int] = []  // indices into `edits` that are non-equal
        for (i, edit) in edits.enumerated() {
            if case .equal = edit { } else { changeIndices.append(i) }
        }
        guard !changeIndices.isEmpty else { return [] }

        // Group change indices into clusters separated by > 2*context equal lines
        var clusters: [[Int]] = []
        var current: [Int] = [changeIndices[0]]
        for idx in changeIndices.dropFirst() {
            // Count equal edits between last cluster element and this one
            let gapStart = current.last! + 1
            let gapEnd   = idx
            var equalCount = 0
            for g in gapStart..<gapEnd {
                if case .equal = edits[g] { equalCount += 1 }
            }
            if equalCount > 2 * contextLines {
                clusters.append(current)
                current = [idx]
            } else {
                current.append(idx)
            }
        }
        clusters.append(current)

        // Build HunkSpan for each cluster
        var hunks: [HunkSpan] = []
        for cluster in clusters {
            let firstEditIdx = cluster.first!
            let lastEditIdx  = cluster.last!

            // Context before
            let ctxBeforeStart = max(0, firstEditIdx - contextLines)
            // Context after
            let ctxAfterEnd    = min(edits.count - 1, lastEditIdx + contextLines)

            var oldStart: Int?
            var newStart: Int?
            var oldCount = 0
            var newCount = 0

            for idx in ctxBeforeStart...ctxAfterEnd {
                let edit = edits[idx]
                switch edit {
                case .equal(let oi, let ni):
                    if oldStart == nil { oldStart = oi; newStart = ni }
                    oldCount += 1; newCount += 1
                case .delete(let oi):
                    if oldStart == nil { oldStart = oi; newStart = newCount == 0 ? (hunks.last.map { $0.newStart + $0.newCount } ?? 0) : newStart }
                    if newStart == nil {
                        // derive newStart from the previous hunk or zero
                        newStart = hunks.last.map { $0.newStart + $0.newCount } ?? 0
                    }
                    oldCount += 1
                case .insert(let ni):
                    if newStart == nil { newStart = ni }
                    if oldStart == nil {
                        oldStart = hunks.last.map { $0.oldStart + $0.oldCount } ?? 0
                    }
                    newCount += 1
                }
            }

            let hunk = HunkSpan(
                oldStart: oldStart ?? 0,
                oldCount: oldCount,
                newStart: newStart ?? 0,
                newCount: newCount,
                editSlice: edits[ctxBeforeStart...ctxAfterEnd]
            )
            hunks.append(hunk)
        }
        return hunks
    }

    // MARK: - Rendering

    private static func renderHunk(_ hunk: HunkSpan, beforeLines: [String], afterLines: [String]) -> String {
        var out = "@@ -\(hunk.oldStart + 1),\(hunk.oldCount) +\(hunk.newStart + 1),\(hunk.newCount) @@\n"
        for edit in hunk.editSlice {
            switch edit {
            case .equal(let oi, _):
                out += " \(beforeLines[oi])\n"
            case .delete(let oi):
                out += "-\(beforeLines[oi])\n"
            case .insert(let ni):
                out += "+\(afterLines[ni])\n"
            }
        }
        return out
    }

    // MARK: - Helpers

    /// Split content into lines, preserving empty trailing line correctly.
    private static func splitLines(_ content: String) -> [String] {
        // `components(separatedBy:)` on "a\nb\n" gives ["a","b",""] —
        // drop the spurious trailing empty element only when the content
        // actually ends with a newline.
        var lines = content.components(separatedBy: "\n")
        if content.hasSuffix("\n") && lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
