import Foundation

/// Best-effort local `.env` reader for developer builds.
///
/// Finder-launched `.app` bundles do not inherit the shell environment, so
/// secrets stored only in a repo-local `.env` would otherwise disappear at
/// runtime. This helper searches ancestor directories of the app bundle and the
/// current working directory for a `.env` file, parses it once, and exposes a
/// small key lookup API. If no repo-local `.env` is present, it simply returns
/// nil and the app falls back to UserDefaults / ProcessInfo.environment.
enum LocalEnv {
    private static let values: [String: String] = loadValues()

    static func value(for key: String) -> String? {
        let trimmed = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func loadValues() -> [String: String] {
        for url in candidateEnvURLs() {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                let parsed = parse(text)
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }
        return [:]
    }

    private static func candidateEnvURLs() -> [URL] {
        var urls: [URL] = []
        var seen: Set<String> = []

        func addAncestors(startingAt url: URL) {
            var current = url.resolvingSymlinksInPath().standardizedFileURL
            let fileManager = FileManager.default
            // Bounded walk — URL.deletingLastPathComponent() has been observed
            // to not converge under xctest for some bundle URLs, causing an
            // unbounded seen-set and >100GB RAM. 64 is deeper than any
            // plausible filesystem we'd walk.
            for _ in 0..<64 {
                let candidate = current.appendingPathComponent(".env")
                let path = candidate.path
                if seen.insert(path).inserted, fileManager.fileExists(atPath: path) {
                    urls.append(candidate)
                }

                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent.path == current.path || current.path == "/" || current.path.isEmpty {
                    break
                }
                current = parent
            }
        }

        addAncestors(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        addAncestors(startingAt: Bundle.main.bundleURL)

        return urls
    }

    private static func parse(_ text: String) -> [String: String] {
        var parsed: [String: String] = [:]

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let pieces = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }

            let key = String(pieces[0]).trimmingCharacters(in: .whitespaces)
            var value = String(pieces[1]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }

            parsed[key] = value
        }

        return parsed
    }
}
